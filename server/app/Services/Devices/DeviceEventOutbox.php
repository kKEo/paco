<?php

namespace App\Services\Devices;

use App\Models\ChildDevice;
use App\Models\DeviceEvent;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * The only writer of `device_events`.
 *
 * Inserts lock the device row first, so a device's events commit in id order.
 * Without that, two concurrent transactions on Postgres can commit id 11 before
 * id 10; a poller that already moved its cursor to 11 would never see 10.
 */
final class DeviceEventOutbox
{
    public function __construct(private readonly EventWaiter $waiter) {}

    public function push(ChildDevice $device, string $type, array $payload = [], ?User $actor = null): DeviceEvent
    {
        return DB::transaction(function () use ($device, $type, $payload, $actor) {
            ChildDevice::query()->whereKey($device->getKey())->lockForUpdate()->first();

            return $this->insert($device, $type, $payload, $actor);
        });
    }

    /** For callers that already hold the device row lock inside their own transaction. */
    public function insert(ChildDevice $device, string $type, array $payload = [], ?User $actor = null): DeviceEvent
    {
        $event = DeviceEvent::query()->create([
            'device_id' => $device->getKey(),
            'type' => $type,
            'payload' => $payload,
            'actor_user_id' => $actor?->getKey(),
        ]);

        // Only once it is visible to the poll's query.
        $deviceId = $device->getKey();
        DB::afterCommit(fn () => $this->waiter->wake($deviceId));

        return $event;
    }

    /** Highest event id for the device (0 when none): the cursor a new poller starts from. */
    public function latestId(ChildDevice $device): int
    {
        return (int) DeviceEvent::query()->where('device_id', $device->getKey())->max('id');
    }
}
