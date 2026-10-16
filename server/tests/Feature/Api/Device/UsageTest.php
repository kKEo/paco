<?php

use App\Models\UsageDay;

function usageDay(string $date, int $internet = 3600, array $apps = []): array
{
    return [
        'date' => $date,
        'profileId' => null,
        'internetOnDuration' => $internet,
        'appUsage' => $apps ?: [
            ['bundleIdentifier' => 'com.apple.Safari', 'appName' => 'Safari', 'duration' => 1200.6, 'launchCount' => 3],
            ['bundleIdentifier' => 'com.mojang.minecraft', 'appName' => 'Minecraft', 'duration' => 2400, 'launchCount' => 1],
        ],
    ];
}

it("stores a snapshot under the child's local date", function () {
    [$device, $token] = enrolledDevice();

    // Midnight in Warsaw (UTC+2 in October) is 22:00 UTC the day before.
    $this->postJson('/api/v1/device/usage', [
        'timeZone' => 'Europe/Warsaw',
        'days' => [usageDay('2026-10-15T22:00:00Z')],
    ], bearer($token))->assertStatus(202)->assertJson(['stored' => ['2026-10-16']]);

    $day = UsageDay::query()->sole();
    expect($day->device_id)->toBe($device->id)
        ->and($day->local_date->toDateString())->toBe('2026-10-16')
        ->and($day->internet_on_seconds)->toBe(3600)
        ->and($day->app_seconds)->toBe(3601)
        ->and($day->sortedApps()[0]['appName'])->toBe('Minecraft')
        ->and($day->sortedApps()[1]['duration'])->toBe(1201);
});

it('buckets the same instant differently for different zones', function () {
    [, $token] = enrolledDevice();
    $instant = '2026-10-16T00:00:00+02:00';

    $this->postJson('/api/v1/device/usage', ['timeZone' => 'Europe/Warsaw', 'days' => [usageDay($instant)]], bearer($token))
        ->assertJson(['stored' => ['2026-10-16']]);
    $this->postJson('/api/v1/device/usage', ['timeZone' => 'Pacific/Auckland', 'days' => [usageDay($instant)]], bearer($token))
        ->assertJson(['stored' => ['2026-10-16']]);
    $this->postJson('/api/v1/device/usage', ['timeZone' => 'America/Los_Angeles', 'days' => [usageDay($instant)]], bearer($token))
        ->assertJson(['stored' => ['2026-10-15']]);
});

it('replaces the totals for a day with the newer snapshot', function () {
    [, $token] = enrolledDevice();
    $body = fn (int $internet) => ['timeZone' => 'Europe/Warsaw', 'days' => [usageDay('2026-10-15T22:00:00Z', $internet)]];

    $this->postJson('/api/v1/device/usage', $body(600), bearer($token))->assertStatus(202);
    $this->postJson('/api/v1/device/usage', $body(1800), bearer($token))->assertStatus(202);

    expect(UsageDay::query()->sole()->internet_on_seconds)->toBe(1800);
});

it('backfills yesterday and today in one upload', function () {
    [$device, $token] = enrolledDevice();

    $this->postJson('/api/v1/device/usage', [
        'timeZone' => 'Europe/Warsaw',
        'days' => [usageDay('2026-10-14T22:00:00Z'), usageDay('2026-10-15T22:00:00Z', 60, [])],
    ], bearer($token))->assertJson(['stored' => ['2026-10-15', '2026-10-16']]);

    expect($device->usageDays()->count())->toBe(2);
});

it('accepts a day with no app usage', function () {
    [, $token] = enrolledDevice();

    $this->postJson('/api/v1/device/usage', [
        'timeZone' => 'Europe/Warsaw',
        'days' => [['date' => '2026-10-15T22:00:00Z', 'profileId' => null, 'internetOnDuration' => 0, 'appUsage' => []]],
    ], bearer($token))->assertStatus(202);

    expect(UsageDay::query()->sole()->app_entries)->toBe([]);
});

it('validates entries', function () {
    [, $token] = enrolledDevice();

    $this->postJson('/api/v1/device/usage', [
        'timeZone' => 'Europe/Warsaw',
        'days' => [['date' => 'yesterday-ish', 'internetOnDuration' => -1, 'appUsage' => [['appName' => 'X']]]],
    ], bearer($token))
        ->assertStatus(422)
        ->assertJsonStructure(['fields' => [
            'days.0.date', 'days.0.internetOnDuration', 'days.0.appUsage.0.bundleIdentifier',
            'days.0.appUsage.0.duration', 'days.0.appUsage.0.launchCount',
        ]]);
});
