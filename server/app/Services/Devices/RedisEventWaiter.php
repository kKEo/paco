<?php

namespace App\Services\Devices;

use App\Models\ChildDevice;
use Illuminate\Redis\RedisManager;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Sleep;
use Throwable;

/**
 * Wakes a held long-poll as soon as an event for its device commits.
 *
 * The outbox RPUSHes a token onto `paco:device-events:<id>` after commit; the
 * poll BLPOPs that list. A poll clears the list when it starts, then checks the
 * database, then blocks: an event committed in between still leaves a token,
 * so no wake-up is lost. Blocking is capped at a few seconds so a poll also
 * notices an unenrollment that did not go through the outbox.
 *
 * If Redis is unavailable, polls fall back to sleeping and events are still
 * delivered (just up to a second later).
 */
final class RedisEventWaiter implements EventWaiter
{
    public const MAX_BLOCK_SECONDS = 5;

    /** Tokens for a device nobody is polling expire on their own. */
    public const TOKEN_TTL_SECONDS = 60;

    public function __construct(private readonly RedisManager $redis, private readonly string $connection = 'default') {}

    public static function key(string $deviceId): string
    {
        return 'paco:device-events:'.$deviceId;
    }

    public function begin(ChildDevice $device): void
    {
        try {
            $this->redis->connection($this->connection)->del(self::key($device->getKey()));
        } catch (Throwable $e) {
            Log::warning('Long-poll Redis waiter unavailable: '.$e->getMessage());
        }
    }

    public function pause(ChildDevice $device, float $maxSeconds): void
    {
        $timeout = (int) max(1, min(self::MAX_BLOCK_SECONDS, ceil($maxSeconds)));
        try {
            $this->redis->connection($this->connection)->blpop(self::key($device->getKey()), $timeout);
        } catch (Throwable $e) {
            Log::warning('Long-poll Redis waiter unavailable: '.$e->getMessage());
            Sleep::for(1)->second();
        }
    }

    public function wake(string $deviceId): void
    {
        try {
            $redis = $this->redis->connection($this->connection);
            $redis->rpush(self::key($deviceId), '1');
            $redis->expire(self::key($deviceId), self::TOKEN_TTL_SECONDS);
        } catch (Throwable $e) {
            Log::warning('Could not wake long-poll via Redis: '.$e->getMessage());
        }
    }
}
