<?php

use App\Models\AppRestriction;
use App\Models\Profile;
use App\Models\Schedule;
use App\Models\User;
use App\Services\Policy\PolicyComposer;
use Database\Seeders\PolicyFixtureSeeder;

beforeEach(function () {
    $this->parent = User::factory()->create();
    (new PolicyFixtureSeeder)->run($this->parent);
});

it('composes exactly the golden fixture shared with the Mac', function () {
    $json = json_encode(app(PolicyComposer::class)->compose($this->parent), JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES)."\n";

    expect($json)->toBe(file_get_contents(base_path('tests/Fixtures/policy.json')));
});

it('serves the envelope with the policy, version and active profile', function () {
    [$device, $token] = enrolledDevice($this->parent, ['active_profile_id' => PolicyFixtureSeeder::PROFILE_ID]);

    $response = $this->getJson('/api/v1/device/policy', bearer($token))->assertOk();

    expect($response->json('version'))->toBe($device->policy_version)
        ->and($response->json('activeProfileId'))->toBe(PolicyFixtureSeeder::PROFILE_ID)
        ->and($response->json('manualOverride'))->toBeNull()
        ->and($response->json('policy'))->toBe(json_decode(file_get_contents(base_path('tests/Fixtures/policy.json')), true))
        ->and($response->headers->get('ETag'))->toBe('"v'.$device->policy_version.'"');
});

it('includes inactive schedules so Follows Schedule rules can resolve', function () {
    [, $token] = enrolledDevice($this->parent);

    $schedules = collect($this->getJson('/api/v1/device/policy', bearer($token))->json('policy.schedules'));

    expect($schedules->firstWhere('id', PolicyFixtureSeeder::HOMEWORK_ID)['isActive'])->toBeFalse();
});

it('answers 304 when the device already has this version', function () {
    [$device, $token] = enrolledDevice($this->parent);

    $this->getJson('/api/v1/device/policy', bearer($token) + ['If-None-Match' => '"v'.$device->policy_version.'"'])
        ->assertStatus(304);
    $this->getJson('/api/v1/device/policy', bearer($token) + ['If-None-Match' => '"v0"'])->assertOk();
});

it('bumps the version and queues policyChanged when a schedule changes', function () {
    [$device, $token] = enrolledDevice($this->parent);
    $before = $device->policy_version;

    Schedule::query()->find(PolicyFixtureSeeder::HOMEWORK_ID)->update(['is_active' => true]);

    $device->refresh();
    expect($device->policy_version)->toBe($before + 1)
        ->and($device->events()->sole()->only(['type', 'payload']))->toBe([
            'type' => 'policyChanged', 'payload' => ['version' => $before + 1],
        ]);
});

it('bumps the version for app rule and profile changes and deletions', function () {
    [$device] = enrolledDevice($this->parent);
    $before = $device->policy_version;

    AppRestriction::query()->find(PolicyFixtureSeeder::STEAM_ID)->delete();
    Profile::query()->find(PolicyFixtureSeeder::PROFILE_ID)->update(['name' => 'Alexandra']);
    Schedule::factory()->for($this->parent)->create();

    expect($device->refresh()->policy_version)->toBe($before + 3);
});

it('does not bump on a save that changed nothing', function () {
    [$device] = enrolledDevice($this->parent);
    $before = $device->policy_version;

    Schedule::query()->find(PolicyFixtureSeeder::HOMEWORK_ID)->save();

    expect($device->refresh()->policy_version)->toBe($before);
});

it('leaves a dangling Follows Schedule rule when its schedule is deleted', function () {
    Schedule::query()->find(PolicyFixtureSeeder::SCHOOL_NIGHTS_ID)->delete();

    $chrome = AppRestriction::query()->find(PolicyFixtureSeeder::CHROME_ID);
    expect($chrome->allowed_schedule_id)->toBeNull()
        ->and($chrome->isDangling())->toBeTrue();
});

it("never serves another parent's rules", function () {
    [, $token] = enrolledDevice(User::factory()->create());

    $this->getJson('/api/v1/device/policy', bearer($token))
        ->assertOk()
        ->assertJsonPath('policy', ['schedules' => [], 'restrictions' => []]);
});
