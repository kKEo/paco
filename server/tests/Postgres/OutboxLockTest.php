<?php

use App\Models\DeviceEvent;
use App\Services\Devices\DeviceEventOutbox;
use App\Services\Policy\PolicyPublisher;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

/*
| On PostgreSQL, sequence values are handed out before commit, so two writers
| can commit event 11 before event 10. A poller that already advanced its
| cursor past 11 would never see 10. The outbox prevents that by taking the
| device row lock for every insert; these tests prove a second writer waits.
*/

beforeEach(function () {
    if (DB::getDriverName() !== 'pgsql') {
        $this->markTestSkipped('Needs PostgreSQL (DB_CONNECTION=pgsql).');
    }
    config(['database.connections.second' => config('database.connections.'.DB::getDefaultConnection())]);
});

afterEach(function () {
    DB::purge('second');
});

/** Run `$write` on a second connection that gives up on a lock after 300 ms. */
function onSecondConnection(callable $write): void
{
    $default = DB::getDefaultConnection();
    DB::connection('second')->statement("SET lock_timeout = '300ms'");
    DB::setDefaultConnection('second');
    try {
        $write();
    } finally {
        DB::setDefaultConnection($default);
    }
}

it('makes a second outbox writer wait for the first to commit', function () {
    [$device] = enrolledDevice();
    $outbox = app(DeviceEventOutbox::class);

    DB::beginTransaction();
    $outbox->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET);

    expect(fn () => onSecondConnection(fn () => $outbox->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET)))
        ->toThrow(QueryException::class, 'lock timeout');

    DB::commit();
    onSecondConnection(fn () => $outbox->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET));
    expect(DeviceEvent::query()->where('device_id', $device->id)->count())->toBe(2);
});

it('holds the same lock while publishing a policy change', function () {
    [$device] = enrolledDevice();

    DB::beginTransaction();
    app(PolicyPublisher::class)->publish($device->user);

    expect(fn () => onSecondConnection(fn () => app(DeviceEventOutbox::class)->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET)))
        ->toThrow(QueryException::class, 'lock timeout');

    DB::rollBack();
});
