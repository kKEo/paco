<?php

use App\Models\DeviceEvent;
use App\Services\Devices\DeviceCommands;
use App\Services\Devices\EventWaiter;
use App\Services\Devices\RedisEventWaiter;
use Illuminate\Support\Facades\Redis;

/*
| Against a real Redis: PACO_TEST_REDIS=1 REDIS_CLIENT=predis (CI's pgsql job,
| or `docker run -p 6379:6379 redis:7-alpine` locally).
*/

beforeEach(function () {
    if (! env('PACO_TEST_REDIS')) {
        $this->markTestSkipped('Set PACO_TEST_REDIS=1 with a Redis server to run.');
    }
    config(['paco.longpoll.waiter' => 'redis']);
    app()->forgetInstance(EventWaiter::class);
});

it('returns from a held poll as soon as an event commits', function () {
    [$device, $token] = enrolledDevice();
    $waiter = app(EventWaiter::class);
    expect($waiter)->toBeInstanceOf(RedisEventWaiter::class);

    $waiter->begin($device);
    $started = microtime(true);
    $waiter->wake($device->id);
    $waiter->pause($device, 5);

    expect(microtime(true) - $started)->toBeLessThan(1.0);
});

it('blocks up to the timeout when nothing happens', function () {
    [$device] = enrolledDevice();
    $waiter = app(EventWaiter::class);

    $waiter->begin($device);
    $started = microtime(true);
    $waiter->pause($device, 1);

    expect(microtime(true) - $started)->toBeGreaterThanOrEqual(0.9);
});

it('leaves a wake-up for an event committed before the poll blocks', function () {
    [$device, $token] = enrolledDevice();
    app(DeviceCommands::class)->clearManualInternet($device);

    expect(Redis::connection()->llen(RedisEventWaiter::key($device->id)))->toBe(1);

    $this->getJson('/api/v1/device/events?wait=10', bearer($token))
        ->assertOk()->assertJsonPath('events.0.type', DeviceEvent::CLEAR_MANUAL_INTERNET);
});
