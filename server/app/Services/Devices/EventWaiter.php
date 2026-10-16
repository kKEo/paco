<?php

namespace App\Services\Devices;

use App\Models\ChildDevice;

/**
 * How a held long-poll waits between checks for new events.
 *
 * - `polling` (default): sleep a second between indexed `id > cursor` queries.
 * - `redis`: block on a per-device Redis list that the outbox pushes to after
 *   each event commits, so a poll wakes the moment there is something to send.
 *
 * Select with PACO_LONGPOLL_WAITER. The API is the same either way.
 */
interface EventWaiter
{
    /** Called once when a poll starts, before its first check. */
    public function begin(ChildDevice $device): void;

    /** Wait at most `$maxSeconds` (or until woken) before the next check. */
    public function pause(ChildDevice $device, float $maxSeconds): void;

    /** An event for the device was committed: wake its poll, if one is held. */
    public function wake(string $deviceId): void;
}
