<?php

use App\Models\User;
use App\Services\Devices\DeviceCommands;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Support\Facades\Notification;
use Illuminate\Support\Facades\RateLimiter;

it('rejects requests without a token', function () {
    $this->getJson('/api/v1/device/policy')->assertUnauthorized()->assertExactJson(['error' => 'invalid_token']);
});

it('rejects malformed and wrong tokens', function (string $token) {
    $this->getJson('/api/v1/device/policy', bearer($token))->assertUnauthorized()->assertJsonPath('error', 'invalid_token');
})->with([
    'no prefix' => 'abc',
    'no secret' => 'pcd_6f1c2a8e-5b7d-4c3e-9a10-2b3c4d5e6f70',
    'not a uuid' => 'pcd_nope.secret',
    'unknown device' => 'pcd_6f1c2a8e-5b7d-4c3e-9a10-2b3c4d5e6f70.secret',
]);

it('rejects a valid device id with the wrong secret', function () {
    [$device] = enrolledDevice();

    $this->getJson('/api/v1/device/policy', bearer("pcd_{$device->id}.wrong"))
        ->assertUnauthorized()->assertJsonPath('error', 'invalid_token');
});

it('answers device_revoked after unenrollment, on every route', function () {
    [$device, $token] = enrolledDevice();
    app(DeviceCommands::class)->revoke($device);

    $this->getJson('/api/v1/device/policy', bearer($token))->assertUnauthorized()->assertExactJson(['error' => 'device_revoked']);
    $this->postJson('/api/v1/device/heartbeat', [], bearer($token))->assertUnauthorized()->assertJsonPath('error', 'device_revoked');
    $this->getJson('/api/v1/device/events?wait=0', bearer($token))->assertUnauthorized()->assertJsonPath('error', 'device_revoked');
});

it('scopes everything to the authenticated device', function () {
    Notification::fake();
    $parent = User::factory()->create();
    [, $myToken] = enrolledDevice($parent);
    [, $otherToken] = enrolledDevice(User::factory()->create());

    $this->postJson('/api/v1/device/extension-requests', [
        'requestId' => '9a7d0e2c-1111-4c3e-9a10-2b3c4d5e6f70', 'requestedMinutes' => 30,
    ], bearer($myToken))->assertCreated();

    // The other device cannot see or withdraw it…
    $this->deleteJson('/api/v1/device/extension-requests/9a7d0e2c-1111-4c3e-9a10-2b3c4d5e6f70', [], bearer($otherToken))
        ->assertNotFound();
    // …nor claim the same id.
    $this->postJson('/api/v1/device/extension-requests', [
        'requestId' => '9a7d0e2c-1111-4c3e-9a10-2b3c4d5e6f70', 'requestedMinutes' => 30,
    ], bearer($otherToken))->assertStatus(409);
});

it('renders unknown API routes as JSON', function () {
    $this->get('/api/v1/nope')->assertNotFound()->assertHeader('Content-Type', 'application/json');
});

it('authenticates before rate limiting, so limits are per device', function () {
    $seen = [];
    RateLimiter::for('device', function ($request) use (&$seen) {
        $seen[] = $request->user()?->getAuthIdentifier();

        return Limit::perMinute(120);
    });
    [$device, $token] = enrolledDevice();

    $this->getJson('/api/v1/device/policy', bearer($token))->assertOk();

    expect($seen)->toBe([$device->id]);
});

it('lets a device unenroll itself', function () {
    [$device, $token] = enrolledDevice();

    $this->postJson('/api/v1/device/unenroll', [], bearer($token))->assertOk()->assertExactJson(['unenrolled' => true]);

    expect($device->refresh()->isRevoked())->toBeTrue();
    $this->getJson('/api/v1/device/policy', bearer($token))->assertUnauthorized()->assertJsonPath('error', 'device_revoked');
});

it('rotates the token, keeping the old one until the new one is used', function () {
    [$device, $old] = enrolledDevice();

    $new = $this->postJson('/api/v1/device/token/rotate', [], bearer($old))
        ->assertOk()->assertJsonStructure(['deviceToken', 'rotatedAt'])->json('deviceToken');
    expect($new)->not->toBe($old)->toStartWith('pcd_'.$device->id.'.');

    // The reply could have been lost: the old token still works…
    $this->getJson('/api/v1/device/policy', bearer($old))->assertOk();
    // …until the new one is used once.
    $this->getJson('/api/v1/device/policy', bearer($new))->assertOk();
    $this->getJson('/api/v1/device/policy', bearer($old))->assertUnauthorized()->assertJsonPath('error', 'invalid_token');
});

it('kills both tokens when a device is unenrolled mid-rotation', function () {
    [$device, $old] = enrolledDevice();
    $new = $this->postJson('/api/v1/device/token/rotate', [], bearer($old))->json('deviceToken');
    app(DeviceCommands::class)->revoke($device->fresh());

    $this->getJson('/api/v1/device/policy', bearer($old))->assertUnauthorized();
    $this->getJson('/api/v1/device/policy', bearer($new))->assertUnauthorized();
});
