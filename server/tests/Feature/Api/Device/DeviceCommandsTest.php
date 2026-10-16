<?php

use App\Models\DeviceEvent;
use App\Models\Profile;
use App\Models\Schedule;
use App\Models\User;
use App\Services\Devices\DeviceCommands;
use App\Services\Policy\PolicyPublisher;
use Illuminate\Support\Carbon;

it('sends the manual toggle with an absolute end and mirrors it on the device', function () {
    Carbon::setTestNow('2026-10-16T18:00:00Z');
    [$device] = enrolledDevice();

    app(DeviceCommands::class)->setManualInternet($device, true, 60);

    expect($device->refresh()->activeManualOverride())->toBe(['enabled' => true, 'until' => '2026-10-16T19:00:00Z'])
        ->and($device->events()->sole()->payload)->toBe(['enabled' => true, 'minutes' => 60, 'until' => '2026-10-16T19:00:00Z']);

    Carbon::setTestNow('2026-10-16T19:00:01Z');
    expect($device->refresh()->activeManualOverride())->toBeNull();
});

it('clears the manual toggle', function () {
    [$device] = enrolledDevice();
    app(DeviceCommands::class)->setManualInternet($device, false, 10);
    app(DeviceCommands::class)->clearManualInternet($device);

    expect($device->refresh()->manual_override)->toBeNull()
        ->and($device->events()->latest('id')->first()->type)->toBe(DeviceEvent::CLEAR_MANUAL_INTERNET);
});

it('changes the active profile, bumping the policy version', function () {
    [$device, $token] = enrolledDevice();
    $profile = Profile::factory()->for($device->user)->create();
    $version = $device->refresh()->policy_version;

    app(DeviceCommands::class)->setActiveProfile($device, $profile);

    expect($device->refresh()->active_profile_id)->toBe($profile->id)
        ->and($device->policy_version)->toBe($version + 1)
        ->and($device->events()->latest('id')->first()->only(['type', 'payload']))->toBe([
            'type' => 'activeProfileChanged', 'payload' => ['profileId' => $profile->id],
        ]);
    $this->getJson('/api/v1/device/policy', bearer($token))->assertJsonPath('activeProfileId', $profile->id);
});

it("refuses another parent's profile", function () {
    [$device] = enrolledDevice();

    app(DeviceCommands::class)->setActiveProfile($device, Profile::factory()->create());
})->throws(InvalidArgumentException::class);

it('collapses publishes inside deferred() into one per parent', function () {
    $parent = User::factory()->create();
    [$device] = enrolledDevice($parent);
    $version = $device->policy_version;

    app(PolicyPublisher::class)->deferred(function () use ($parent) {
        Schedule::factory()->for($parent)->count(3)->create();
    });

    expect($device->refresh()->policy_version)->toBe($version + 1)
        ->and($device->events()->where('type', 'policyChanged')->count())->toBe(1);
});

it('does not publish to unenrolled devices', function () {
    $parent = User::factory()->create();
    [$device] = enrolledDevice($parent);
    app(DeviceCommands::class)->revoke($device);
    $version = $device->refresh()->policy_version;

    Schedule::factory()->for($parent)->create();

    expect($device->refresh()->policy_version)->toBe($version);
});
