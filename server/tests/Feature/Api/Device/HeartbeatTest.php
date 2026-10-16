<?php

use App\Services\Devices\DeviceCommands;
use Illuminate\Support\Carbon;

function heartbeat(int $policyVersion, array $status = []): array
{
    return [
        'policyVersion' => $policyVersion,
        'daemonVersion' => '1.1.1',
        'timeZone' => 'Pacific/Auckland',
        'status' => $status + [
            'internetEnabled' => false,
            'action' => 'blocked',
            'activeProfileId' => null,
            'manualOverride' => ['enabled' => false, 'until' => '2026-10-16T19:00:00Z'],
            'override' => null,
        ],
    ];
}

it('records what the device is enforcing', function () {
    Carbon::setTestNow('2026-10-16T18:00:00Z');
    [$device, $token] = enrolledDevice(null, ['last_seen_at' => null]);

    $this->postJson('/api/v1/device/heartbeat', heartbeat($device->policy_version), bearer($token))
        ->assertOk()
        ->assertJson(['policyVersion' => $device->policy_version, 'policyStale' => false, 'pendingEvents' => 0]);

    $device->refresh();
    expect($device->last_seen_at->toIso8601ZuluString())->toBe('2026-10-16T18:00:00Z')
        ->and($device->isOnline())->toBeTrue()
        ->and($device->last_status['internetEnabled'])->toBeFalse()
        ->and($device->last_status['action'])->toBe('blocked')
        ->and($device->last_status['policyVersion'])->toBe($device->policy_version)
        ->and($device->daemon_version)->toBe('1.1.1')
        ->and($device->time_zone)->toBe('Pacific/Auckland');
});

it('flags a stale policy so a device that missed policyChanged catches up', function () {
    [$device, $token] = enrolledDevice(null, ['policy_version' => 7]);

    $this->postJson('/api/v1/device/heartbeat', heartbeat(6), bearer($token))
        ->assertOk()->assertJson(['policyVersion' => 7, 'policyStale' => true]);
});

it('counts events the device has not acknowledged yet', function () {
    [$device, $token] = enrolledDevice();
    app(DeviceCommands::class)->setManualInternet($device, false, 30);
    app(DeviceCommands::class)->clearManualInternet($device);

    $this->postJson('/api/v1/device/heartbeat', heartbeat($device->policy_version), bearer($token))
        ->assertJsonPath('pendingEvents', 2);
});

it('goes offline after the online window', function () {
    [$device] = enrolledDevice();
    Carbon::setTestNow(Carbon::now()->addSeconds(91));

    expect($device->isOnline())->toBeFalse();
});

it('validates the status', function () {
    [, $token] = enrolledDevice();

    $this->postJson('/api/v1/device/heartbeat', ['policyVersion' => 1, 'status' => ['action' => 'party']], bearer($token))
        ->assertStatus(422)
        ->assertJsonStructure(['fields' => ['status.internetEnabled', 'status.action']]);
});
