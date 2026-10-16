<?php

namespace App\Services\Devices;

use App\Models\ChildDevice;
use App\Models\DeviceEvent;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Cache;

/**
 * `GET /device/events` semantics: return every event with id > cursor (oldest
 * first, at most `batch_size`), waiting up to `$wait` seconds for one to appear.
 * Passing a cursor acknowledges everything up to it.
 */
final class LongPoll
{
    private const INFLIGHT_KEY = 'paco:longpoll:inflight';

    public function __construct(private readonly EventWaiter $waiter) {}

    /** Mark everything up to `$cursor` as acknowledged by the device. */
    public function ack(ChildDevice $device, int $cursor): void
    {
        if ($cursor <= 0) {
            return;
        }
        DeviceEvent::query()
            ->where('device_id', $device->getKey())
            ->where('id', '<=', $cursor)
            ->whereNull('acked_at')
            ->update(['acked_at' => Carbon::now()]);
    }

    /**
     * @return array{events: Collection<int, DeviceEvent>, retryAfter: int|null}
     */
    public function fetch(ChildDevice $device, int $cursor, int $wait): array
    {
        $wait = max(0, min($wait, config('paco.longpoll.max_seconds')));

        // Concurrency valve: past the limit, answer at once and tell the device to
        // come back later instead of pinning another worker.
        $inflight = (int) Cache::increment(self::INFLIGHT_KEY);
        try {
            if ($wait > 0 && $inflight > config('paco.longpoll.max_concurrent')) {
                return ['events' => $this->pending($device, $cursor), 'retryAfter' => config('paco.longpoll.retry_after_seconds')];
            }

            $deadline = Carbon::now()->addSeconds($wait);
            if ($wait > 0) {
                $this->waiter->begin($device);
            }
            while (true) {
                $events = $this->pending($device, $cursor);
                if ($events->isNotEmpty()) {
                    break;
                }
                if ($this->revokedMeanwhile($device)) {
                    $events = collect([$this->syntheticUnenrolled($device, $cursor)]);
                    break;
                }
                $remaining = Carbon::now()->diffInMilliseconds($deadline, false) / 1000;
                if ($remaining <= 0) {
                    break;
                }
                $this->waiter->pause($device, $remaining);
            }
        } finally {
            Cache::decrement(self::INFLIGHT_KEY);
        }

        $ids = $events->filter(fn (DeviceEvent $e) => $e->exists)->pluck('id')->all();
        if ($ids !== []) {
            DeviceEvent::query()->whereIn('id', $ids)->whereNull('delivered_at')->update(['delivered_at' => Carbon::now()]);
        }

        return ['events' => $events, 'retryAfter' => null];
    }

    /** @return Collection<int, DeviceEvent> */
    private function pending(ChildDevice $device, int $cursor): Collection
    {
        return DeviceEvent::query()
            ->where('device_id', $device->getKey())
            ->where('id', '>', $cursor)
            ->orderBy('id')
            ->limit(config('paco.longpoll.batch_size'))
            ->get();
    }

    private function revokedMeanwhile(ChildDevice $device): bool
    {
        return ChildDevice::query()->whereKey($device->getKey())->whereNotNull('revoked_at')->exists();
    }

    private function syntheticUnenrolled(ChildDevice $device, int $cursor): DeviceEvent
    {
        $event = new DeviceEvent(['device_id' => $device->getKey(), 'type' => DeviceEvent::UNENROLLED, 'payload' => []]);
        $event->id = $cursor;
        $event->created_at = Carbon::now();

        return $event;
    }
}
