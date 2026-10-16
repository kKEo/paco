<?php

namespace App\Services\Devices;

use App\Models\ChildDevice;
use Illuminate\Support\Sleep;

/** Sleeps up to one second between indexed `id > cursor` checks (sub-millisecond each). */
final class PollingEventWaiter implements EventWaiter
{
    public function begin(ChildDevice $device): void {}

    public function pause(ChildDevice $device, float $maxSeconds): void
    {
        Sleep::for((int) max(1, min(1000, round($maxSeconds * 1000))))->milliseconds();
    }

    public function wake(string $deviceId): void {}
}
