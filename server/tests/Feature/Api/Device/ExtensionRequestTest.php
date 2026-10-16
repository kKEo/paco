<?php

use App\Models\DeviceEvent;
use App\Models\ExtensionRequest;
use App\Notifications\ExtensionRequested;
use App\Services\Requests\ExtensionRequestService;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Notification;

const REQUEST_ID = '9A7D0E2C-5B7D-4C3E-9A10-2B3C4D5E6F70'; // Swift sends upper case

function requestPayload(array $extra = []): array
{
    return $extra + [
        'requestId' => REQUEST_ID,
        'childDeviceName' => 'Something the child typed',
        'profileId' => null,
        'requestedMinutes' => 30,
        'reason' => 'Finishing my essay',
    ];
}

beforeEach(fn () => Notification::fake());

it('records a request attributed to the authenticated device and notifies the parent', function () {
    [$device, $token] = enrolledDevice();

    $this->postJson('/api/v1/device/extension-requests', requestPayload(), bearer($token))
        ->assertCreated()
        ->assertJson(['requestId' => strtolower(REQUEST_ID), 'status' => 'pending', 'requestedMinutes' => 30]);

    $request = ExtensionRequest::query()->sole();
    expect($request->id)->toBe(strtolower(REQUEST_ID))
        ->and($request->device_id)->toBe($device->id)
        ->and($request->user_id)->toBe($device->user_id)
        ->and($request->child_device_name)->toBe('Something the child typed')
        ->and($request->reason)->toBe('Finishing my essay');

    Notification::assertSentTo($device->user, ExtensionRequested::class);
});

it('is idempotent on the request id', function () {
    [, $token] = enrolledDevice();

    $this->postJson('/api/v1/device/extension-requests', requestPayload(), bearer($token))->assertCreated();
    $this->postJson('/api/v1/device/extension-requests', requestPayload(['requestedMinutes' => 120]), bearer($token))
        ->assertOk()->assertJsonPath('requestedMinutes', 30);

    expect(ExtensionRequest::count())->toBe(1);
    Notification::assertCount(1);
});

it('lets the child withdraw a pending request', function () {
    [, $token] = enrolledDevice();
    $this->postJson('/api/v1/device/extension-requests', requestPayload(), bearer($token));

    $this->deleteJson('/api/v1/device/extension-requests/'.REQUEST_ID, [], bearer($token))
        ->assertOk()->assertJsonPath('status', 'withdrawn');
});

it('queues approveExtension with an absolute end time', function () {
    Carbon::setTestNow('2026-10-16T18:00:00Z');
    [$device, $token] = enrolledDevice();
    $this->postJson('/api/v1/device/extension-requests', requestPayload(), bearer($token));

    app(ExtensionRequestService::class)->approve(ExtensionRequest::query()->sole(), 45, $device->user);

    $request = ExtensionRequest::query()->sole();
    expect($request->status)->toBe('approved')
        ->and($request->granted_minutes)->toBe(45)
        ->and($request->resolved_by_user_id)->toBe($device->user_id)
        ->and($device->events()->sole()->toWire())->toMatchArray([
            'type' => 'approveExtension',
            'payload' => (object) [
                'requestId' => strtolower(REQUEST_ID),
                'grantedMinutes' => 45,
                'grantedUntil' => '2026-10-16T18:45:00Z',
            ],
        ]);
});

it('queues denyExtension on deny', function () {
    [$device, $token] = enrolledDevice();
    $this->postJson('/api/v1/device/extension-requests', requestPayload(), bearer($token));

    app(ExtensionRequestService::class)->deny(ExtensionRequest::query()->sole());

    expect(ExtensionRequest::query()->sole()->status)->toBe('denied')
        ->and($device->events()->sole()->type)->toBe(DeviceEvent::DENY_EXTENSION);
});

it('refuses to resolve a request twice', function () {
    [, $token] = enrolledDevice();
    $this->postJson('/api/v1/device/extension-requests', requestPayload(), bearer($token));
    $service = app(ExtensionRequestService::class);
    $service->deny(ExtensionRequest::query()->sole());

    $service->approve(ExtensionRequest::query()->sole(), 30);
})->throws(InvalidArgumentException::class);

it('auto-denies requests nobody answered within a day', function () {
    [$device, $token] = enrolledDevice();
    $this->postJson('/api/v1/device/extension-requests', requestPayload(), bearer($token));
    Carbon::setTestNow(Carbon::now()->addHours(25));

    $this->artisan('paco:expire-requests')->assertSuccessful();

    expect(ExtensionRequest::query()->sole()->status)->toBe('expired')
        ->and($device->events()->sole()->type)->toBe(DeviceEvent::DENY_EXTENSION);
});

it('validates the payload', function () {
    [, $token] = enrolledDevice();

    $this->postJson('/api/v1/device/extension-requests', ['requestId' => 'nope', 'requestedMinutes' => 0], bearer($token))
        ->assertStatus(422)->assertJsonStructure(['fields' => ['requestId', 'requestedMinutes']]);
});
