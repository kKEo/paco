<?php

use App\Models\ExtensionRequest;
use App\Models\UsageDay;
use App\Models\User;
use App\Services\Devices\DeviceCommands;
use Database\Seeders\PolicyFixtureSeeder;
use Illuminate\Support\Carbon;

dataset('pages', [
    'overview' => ['/dashboard'],
    'macs' => ['/devices'],
    'add a mac' => ['/devices/add'],
    'requests' => ['/requests'],
    'screen time' => ['/screen-time'],
    'activity' => ['/activity'],
    'profiles' => ['/profiles'],
    'schedules' => ['/schedules'],
    'app rules' => ['/app-rules'],
]);

it('sends guests to the login page', function (string $url) {
    $this->get($url)->assertRedirect('/login');
})->with('pages');

it('asks unverified parents to verify their email first', function (string $url) {
    $this->actingAs(User::factory()->unverified()->create())->get($url)->assertRedirect('/verify-email');
})->with('pages');

it('renders every page empty', function (string $url) {
    $this->actingAs(User::factory()->create())->get($url)->assertOk();
})->with('pages');

it('renders every page with a Mac, rules, usage and requests', function (string $url) {
    Carbon::setTestNow('2026-10-16T18:00:00Z');
    $parent = User::factory()->create();
    (new PolicyFixtureSeeder)->run($parent);
    [$device] = enrolledDevice($parent, [
        'active_profile_id' => PolicyFixtureSeeder::PROFILE_ID,
        'last_status' => ['internetEnabled' => false, 'action' => 'gracePeriod', 'graceRemainingSeconds' => 120,
            'override' => ['requestId' => '9a7d0e2c-5b7d-4c3e-9a10-2b3c4d5e6f70', 'grantedUntil' => '2026-10-16T18:30:00Z'], 'policyVersion' => 1],
    ]);
    UsageDay::query()->create([
        'device_id' => $device->id, 'local_date' => '2026-10-16', 'internet_on_seconds' => 3600, 'app_seconds' => 2400,
        'app_entries' => [['bundleIdentifier' => 'com.mojang.minecraft', 'appName' => 'Minecraft', 'duration' => 2400, 'launchCount' => 1]],
        'reported_at' => Carbon::now(),
    ]);
    ExtensionRequest::query()->create([
        'id' => '9a7d0e2c-5b7d-4c3e-9a10-2b3c4d5e6f71', 'user_id' => $parent->id, 'device_id' => $device->id,
        'requested_minutes' => 30, 'reason' => 'Homework', 'status' => 'pending',
    ]);
    app(DeviceCommands::class)->setManualInternet($device, false, 30, $parent);

    $this->actingAs($parent)->get($url)->assertOk()->assertSee("Alex's MacBook");
})->with([
    'overview' => ['/dashboard'],
    'macs' => ['/devices'],
    'requests' => ['/requests'],
    'screen time' => ['/screen-time'],
    'activity' => ['/activity'],
]);

it('shows the number of pending requests in the navigation', function () {
    $parent = User::factory()->create();
    [$device] = enrolledDevice($parent);
    ExtensionRequest::query()->create([
        'id' => '9a7d0e2c-5b7d-4c3e-9a10-2b3c4d5e6f72', 'user_id' => $parent->id, 'device_id' => $device->id,
        'requested_minutes' => 30, 'status' => 'pending',
    ]);

    $this->actingAs($parent)->get('/dashboard')->assertSee('1 request for more time');
});
