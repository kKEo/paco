<?php

use App\Models\EnrollmentCode;
use App\Models\ExtensionRequest;
use App\Models\UsageDay;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/*
| MariaDB-specific guards (10.6 is the oldest supported release):
| - before 10.10, the first NOT NULL `timestamp` column of a table silently gets
|   ON UPDATE CURRENT_TIMESTAMP, so such columns are `datetime` here;
| - `timestamp` values pass through the session time zone, pinned to UTC;
| - READ COMMITTED, the isolation the outbox and long-poll were designed for.
*/

beforeEach(function () {
    if (DB::getDriverName() !== 'mariadb') {
        $this->markTestSkipped('Needs MariaDB (DB_CONNECTION=mariadb).');
    }
});

it('runs sessions in UTC at READ COMMITTED', function () {
    $session = DB::selectOne('SELECT @@session.time_zone AS tz, @@session.tx_isolation AS isolation');

    expect($session->tz)->toBe('+00:00')
        ->and($session->isolation)->toBe('READ-COMMITTED');
});

it('keeps an enrollment code expiry when the code is used', function () {
    $code = EnrollmentCode::query()->create([
        'user_id' => User::factory()->create()->id,
        'code' => 'ABCD2345',
        'expires_at' => '2030-01-01 12:00:00',
    ]);

    $code->update(['used_at' => Carbon::now()]);

    expect(DB::table('enrollment_codes')->where('id', $code->id)->value('expires_at'))->toBe('2030-01-01 12:00:00');
});

it('keeps the reported time of a usage day when it is updated', function () {
    [$device] = enrolledDevice();
    $day = UsageDay::query()->create([
        'device_id' => $device->id, 'local_date' => '2026-10-16', 'app_entries' => [],
        'reported_at' => '2026-10-16 18:00:00',
    ]);

    $day->update(['internet_on_seconds' => 60]);

    expect(DB::table('usage_days')->where('id', $day->id)->value('reported_at'))->toBe('2026-10-16 18:00:00');
});

it('has no column that updates itself', function () {
    $tables = ['enrollment_codes', 'usage_days', 'extension_requests', 'child_devices', 'parent_pins', 'device_events'];

    foreach ($tables as $table) {
        $create = DB::selectOne("SHOW CREATE TABLE `{$table}`")->{'Create Table'};
        expect($create)->not->toContain('ON UPDATE');
    }
});

it('stores timestamps as UTC across a DST change', function () {
    [$device] = enrolledDevice();
    // 02:30 on the night European clocks go back: ambiguous in a DST session zone.
    $request = ExtensionRequest::query()->create([
        'id' => '9a7d0e2c-5b7d-4c3e-9a10-2b3c4d5e6f80', 'user_id' => $device->user_id, 'device_id' => $device->id,
        'requested_minutes' => 30, 'status' => 'approved', 'granted_until' => Carbon::parse('2026-10-25T02:30:00Z'),
    ]);

    expect($request->fresh()->granted_until->toIso8601ZuluString())->toBe('2026-10-25T02:30:00Z')
        ->and(DB::selectOne('SELECT UNIX_TIMESTAMP(granted_until) AS ts FROM extension_requests WHERE id = ?', [$request->id])->ts)
        ->toEqual(Carbon::parse('2026-10-25T02:30:00Z')->timestamp);
});
