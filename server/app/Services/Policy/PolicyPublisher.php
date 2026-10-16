<?php

namespace App\Services\Policy;

use App\Models\ChildDevice;
use App\Models\DeviceEvent;
use App\Models\User;
use App\Services\Devices\DeviceEventOutbox;
use Illuminate\Support\Facades\DB;

/**
 * Bumps `policy_version` on a parent's devices and queues `policyChanged`.
 *
 * Called by the model observers on every schedule, app rule and profile change.
 * Inside `deferred()` the publishes are collapsed into one per parent, so a page
 * action that touches several rows costs the device a single policy fetch.
 * Bound as a scoped singleton (fresh per request, also under Octane).
 */
final class PolicyPublisher
{
    private int $depth = 0;

    /** @var array<int, true> */
    private array $pendingUserIds = [];

    public function __construct(private readonly DeviceEventOutbox $outbox) {}

    public function publish(User|int $user, ?ChildDevice $only = null, ?User $actor = null): void
    {
        $userId = $user instanceof User ? $user->getKey() : $user;

        if ($this->depth > 0 && $only === null) {
            $this->pendingUserIds[$userId] = true;

            return;
        }

        DB::transaction(function () use ($userId, $only, $actor) {
            $devices = ChildDevice::query()
                ->where('user_id', $userId)
                ->whereNull('revoked_at')
                ->when($only, fn ($q) => $q->whereKey($only->getKey()))
                ->lockForUpdate()
                ->get();

            foreach ($devices as $device) {
                $device->increment('policy_version');
                $this->outbox->insert($device, DeviceEvent::POLICY_CHANGED, [
                    'version' => $device->policy_version,
                ], $actor);
            }
        });
    }

    /**
     * Run `$callback`, publishing at most once per affected parent afterwards.
     *
     * @template T
     *
     * @param  callable(): T  $callback
     * @return T
     */
    public function deferred(callable $callback): mixed
    {
        $this->depth++;
        try {
            $result = $callback();
        } finally {
            $this->depth--;
        }

        if ($this->depth === 0 && $this->pendingUserIds !== []) {
            $userIds = array_keys($this->pendingUserIds);
            $this->pendingUserIds = [];
            foreach ($userIds as $userId) {
                $this->publish($userId);
            }
        }

        return $result;
    }
}
