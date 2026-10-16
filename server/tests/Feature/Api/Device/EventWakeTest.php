<?php

use App\Models\ChildDevice;
use App\Models\DeviceEvent;
use App\Services\Devices\DeviceEventOutbox;
use App\Services\Devices\EventWaiter;
use Illuminate\Support\Facades\DB;

/** Records wake-ups instead of touching Redis. */
class RecordingWaiter implements EventWaiter
{
    public array $woken = [];

    public array $begun = [];

    public function begin(ChildDevice $device): void
    {
        $this->begun[] = $device->id;
    }

    public function pause(ChildDevice $device, float $maxSeconds): void {}

    public function wake(string $deviceId): void
    {
        $this->woken[] = $deviceId;
    }
}

beforeEach(function () {
    $this->waiter = new RecordingWaiter;
    app()->instance(EventWaiter::class, $this->waiter);
});

it('wakes the poll only after the event is committed', function () {
    [$device] = enrolledDevice();
    $outbox = app(DeviceEventOutbox::class);

    DB::beginTransaction();
    $outbox->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET);
    expect($this->waiter->woken)->toBe([]);
    DB::commit();

    expect($this->waiter->woken)->toBe([$device->id]);
});

it('does not wake anyone for a rolled-back event', function () {
    [$device] = enrolledDevice();

    DB::beginTransaction();
    app(DeviceEventOutbox::class)->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET);
    DB::rollBack();

    expect($this->waiter->woken)->toBe([]);
});

it('prepares the waiter only for a poll that may wait', function () {
    [$device, $token] = enrolledDevice();
    config(['paco.longpoll.max_seconds' => 0]);

    $this->getJson('/api/v1/device/events?wait=0', bearer($token))->assertOk();
    expect($this->waiter->begun)->toBe([]);
});
