<?php

use App\Models\ChildDevice;
use App\Models\User;
use App\Services\Devices\DeviceTokens;
use Illuminate\Foundation\Testing\DatabaseMigrations;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

pest()->extend(TestCase::class)
    ->use(RefreshDatabase::class)
    ->in('Feature');

// Tests that need committed rows visible to a second connection (no wrapping
// transaction). They only run against PostgreSQL; see tests/Postgres.
pest()->extend(TestCase::class)
    ->use(DatabaseMigrations::class)
    ->in('Postgres');

pest()->extend(TestCase::class)
    ->use(RefreshDatabase::class)
    ->in('Redis');

/*
| Helpers for the device API tests.
*/

/**
 * An enrolled device with a valid token.
 *
 * @return array{0: ChildDevice, 1: string}
 */
function enrolledDevice(?User $user = null, array $attributes = []): array
{
    $device = ChildDevice::factory()->for($user ?? User::factory()->create())->create($attributes);
    $token = app(DeviceTokens::class)->issue($device);

    return [$device->fresh(), $token];
}

/** @return array<string, string> */
function bearer(string $token): array
{
    return ['Authorization' => 'Bearer '.$token, 'Accept' => 'application/json'];
}

/** ISO-8601 with no fractional seconds, as the Swift `.iso8601` strategy requires. */
expect()->extend('toBeSwiftIsoDate', function () {
    return $this->toMatch('/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$/');
});
