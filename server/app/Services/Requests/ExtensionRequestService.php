<?php

namespace App\Services\Requests;

use App\Models\ChildDevice;
use App\Models\DeviceEvent;
use App\Models\ExtensionRequest;
use App\Models\User;
use App\Notifications\ExtensionRequested;
use App\Services\Devices\DeviceEventOutbox;
use App\Support\Iso;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use InvalidArgumentException;

/**
 * Time-extension requests from cloud devices. Unlike the Bonjour flow, an
 * approval does not need the child online: the event waits in the outbox.
 */
final class ExtensionRequestService
{
    public function __construct(private readonly DeviceEventOutbox $outbox) {}

    /**
     * Record a request (idempotent on its id). Attribution is the authenticated
     * device; the name the child put in the payload is kept for display only.
     *
     * @return array{request: ExtensionRequest, created: bool}|null null when the id belongs to another device
     */
    public function submit(ChildDevice $device, array $payload): ?array
    {
        $id = Str::lower($payload['requestId']);
        $existing = ExtensionRequest::query()->find($id);
        if ($existing !== null) {
            return $existing->device_id === $device->getKey() ? ['request' => $existing, 'created' => false] : null;
        }

        $request = ExtensionRequest::query()->create([
            'id' => $id,
            'user_id' => $device->user_id,
            'device_id' => $device->getKey(),
            'profile_id' => isset($payload['profileId']) ? Str::lower($payload['profileId']) : $device->active_profile_id,
            'child_device_name' => $payload['childDeviceName'] ?? null,
            'requested_minutes' => (int) $payload['requestedMinutes'],
            'reason' => (string) ($payload['reason'] ?? ''),
            'status' => ExtensionRequest::PENDING,
        ]);

        $device->user->notify(new ExtensionRequested($request));

        return ['request' => $request, 'created' => true];
    }

    /** The child withdrew it. Returns false when it was no longer pending. */
    public function withdraw(ChildDevice $device, string $id): bool
    {
        return ExtensionRequest::query()
            ->where('device_id', $device->getKey())
            ->whereKey(Str::lower($id))
            ->where('status', ExtensionRequest::PENDING)
            ->update(['status' => ExtensionRequest::WITHDRAWN, 'resolved_at' => Carbon::now()]) === 1;
    }

    public function approve(ExtensionRequest $request, int $minutes, ?User $actor = null): DeviceEvent
    {
        $this->assertPending($request);
        if ($minutes < 1 || $minutes > config('paco.requests.max_minutes')) {
            throw new InvalidArgumentException('minutes out of range');
        }
        $until = Carbon::now()->addMinutes($minutes);
        $request->forceFill([
            'status' => ExtensionRequest::APPROVED,
            'granted_minutes' => $minutes,
            'granted_until' => $until,
            'resolved_at' => Carbon::now(),
            'resolved_by_user_id' => $actor?->getKey(),
        ])->save();

        return $this->outbox->push($request->device, DeviceEvent::APPROVE_EXTENSION, [
            'requestId' => $request->id,
            'grantedMinutes' => $minutes,
            'grantedUntil' => Iso::format($until),
        ], $actor);
    }

    public function deny(ExtensionRequest $request, ?User $actor = null): DeviceEvent
    {
        $this->assertPending($request);

        return $this->close($request, ExtensionRequest::DENIED, $actor);
    }

    /** Auto-deny requests nobody answered in time. Returns how many. */
    public function expireStale(): int
    {
        $cutoff = Carbon::now()->subHours(config('paco.requests.expire_after_hours'));
        $count = 0;
        ExtensionRequest::query()
            ->where('status', ExtensionRequest::PENDING)
            ->where('created_at', '<', $cutoff)
            ->with('device')
            ->each(function (ExtensionRequest $request) use (&$count) {
                $this->close($request, ExtensionRequest::EXPIRED, null);
                $count++;
            });

        return $count;
    }

    private function close(ExtensionRequest $request, string $status, ?User $actor): DeviceEvent
    {
        $request->forceFill([
            'status' => $status,
            'resolved_at' => Carbon::now(),
            'resolved_by_user_id' => $actor?->getKey(),
        ])->save();

        return $this->outbox->push($request->device, DeviceEvent::DENY_EXTENSION, [
            'requestId' => $request->id,
        ], $actor);
    }

    private function assertPending(ExtensionRequest $request): void
    {
        if (! $request->isPending()) {
            throw new InvalidArgumentException("request is {$request->status}, not pending");
        }
    }
}
