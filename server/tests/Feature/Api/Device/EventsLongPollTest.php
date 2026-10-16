<?php

use App\Models\DeviceEvent;
use App\Services\Devices\DeviceCommands;
use App\Services\Devices\DeviceEventOutbox;
use Illuminate\Support\Carbon;
use Illuminate\Support\Sleep;

beforeEach(function () {
    // The long-poll sleeps between checks; fake it and move the clock instead.
    Sleep::fake(syncWithCarbon: true);
    Carbon::setTestNow('2026-10-16T18:00:00Z');
});

it('returns immediately with wait=0 and nothing pending', function () {
    [, $token] = enrolledDevice();

    $this->getJson('/api/v1/device/events?cursor=0&wait=0', bearer($token))
        ->assertOk()
        ->assertExactJson(['events' => [], 'nextCursor' => 0, 'serverTime' => '2026-10-16T18:00:00Z']);

    Sleep::assertNeverSlept();
});

it('holds for the requested time, then answers empty', function () {
    [, $token] = enrolledDevice();

    $this->getJson('/api/v1/device/events?cursor=0&wait=5', bearer($token))
        ->assertOk()->assertJsonPath('events', []);

    Sleep::assertSleptTimes(5);
});

it('never holds longer than the configured maximum', function () {
    config(['paco.longpoll.max_seconds' => 3]);
    [, $token] = enrolledDevice();

    $this->getJson('/api/v1/device/events?wait=60', bearer($token))->assertOk();

    Sleep::assertSleptTimes(3);
});

it('returns an event published while the poll is held', function () {
    [$device, $token] = enrolledDevice();
    Sleep::whenFakingSleep(function () use ($device) {
        if ($device->events()->doesntExist()) {
            app(DeviceCommands::class)->setManualInternet($device, false, 10);
        }
        Carbon::setTestNow(Carbon::now()->addSecond());
    });

    $response = $this->getJson('/api/v1/device/events?cursor=0&wait=25', bearer($token))->assertOk();

    expect($response->json('events'))->toHaveCount(1)
        ->and($response->json('events.0.type'))->toBe('setManualInternet')
        ->and($response->json('events.0.payload'))->toBe(['enabled' => false, 'minutes' => 10, 'until' => '2026-10-16T18:10:01Z'])
        ->and($response->json('events.0.createdAt'))->toBeSwiftIsoDate();
    Sleep::assertSleptTimes(1);
});

it('returns events after the cursor, oldest first, and moves the cursor', function () {
    [$device, $token] = enrolledDevice();
    $outbox = app(DeviceEventOutbox::class);
    $first = $outbox->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET);
    $second = $outbox->push($device, DeviceEvent::POLICY_CHANGED, ['version' => 2]);
    $third = $outbox->push($device, DeviceEvent::POLICY_CHANGED, ['version' => 3]);

    $response = $this->getJson("/api/v1/device/events?cursor={$first->id}&wait=0", bearer($token))->assertOk();

    expect(array_column($response->json('events'), 'id'))->toBe([$second->id, $third->id])
        ->and($response->json('nextCursor'))->toBe($third->id)
        ->and($response->json('events.0.payload'))->toBe(['version' => 2]);
});

it('encodes an empty payload as an object', function () {
    [$device, $token] = enrolledDevice();
    app(DeviceEventOutbox::class)->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET);

    $raw = $this->getJson('/api/v1/device/events?wait=0', bearer($token))->getContent();

    expect($raw)->toContain('"payload":{}');
});

it('treats the cursor as an acknowledgement', function () {
    [$device, $token] = enrolledDevice();
    $outbox = app(DeviceEventOutbox::class);
    $first = $outbox->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET);
    $second = $outbox->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET);

    $this->getJson('/api/v1/device/events?cursor=0&wait=0', bearer($token));
    expect($first->fresh()->delivered_at)->not->toBeNull()
        ->and($first->fresh()->acked_at)->toBeNull();

    $this->getJson("/api/v1/device/events?cursor={$first->id}&wait=0", bearer($token));
    expect($first->fresh()->acked_at)->not->toBeNull()
        ->and($second->fresh()->acked_at)->toBeNull();

    $this->postJson('/api/v1/device/events/ack', ['cursor' => $second->id], bearer($token))->assertOk();
    expect($second->fresh()->acked_at)->not->toBeNull();
});

it('caps a batch at the configured size', function () {
    [$device, $token] = enrolledDevice();
    foreach (range(1, 60) as $v) {
        app(DeviceEventOutbox::class)->push($device, DeviceEvent::POLICY_CHANGED, ['version' => $v]);
    }

    $response = $this->getJson('/api/v1/device/events?wait=0', bearer($token));

    expect($response->json('events'))->toHaveCount(50)
        ->and($response->json('events.49.payload.version'))->toBe(50);
});

it("never returns another device's events", function () {
    [$mine, $token] = enrolledDevice();
    [$other] = enrolledDevice();
    app(DeviceEventOutbox::class)->push($other, DeviceEvent::CLEAR_MANUAL_INTERNET);

    $this->getJson('/api/v1/device/events?wait=0', bearer($token))->assertJsonPath('events', []);
});

it('ends an open poll with unenrolled when the device is unenrolled', function () {
    [$device, $token] = enrolledDevice();
    Sleep::whenFakingSleep(function () use ($device) {
        app(DeviceCommands::class)->revoke($device);
        Carbon::setTestNow(Carbon::now()->addSecond());
    });

    $this->getJson('/api/v1/device/events?wait=25', bearer($token))
        ->assertOk()->assertJsonPath('events.0.type', 'unenrolled');

    $this->getJson('/api/v1/device/events?wait=0', bearer($token))->assertUnauthorized();
});

it('answers at once with retryAfter when too many polls are open', function () {
    config(['paco.longpoll.max_concurrent' => 0]);
    [, $token] = enrolledDevice();

    $this->getJson('/api/v1/device/events?wait=25', bearer($token))
        ->assertOk()->assertJson(['events' => [], 'retryAfter' => 5]);

    Sleep::assertNeverSlept();
});
