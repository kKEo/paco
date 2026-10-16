<?php

namespace App\Services\Devices;

use App\Models\ChildDevice;
use App\Models\DeviceEvent;
use App\Models\Profile;
use App\Models\User;
use App\Support\Iso;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;

/**
 * Parent actions on one device. Each queues an event; events are delivered at
 * least once, so every time window is sent as an absolute `until` (a replayed
 * "60 minutes" must not extend the window).
 */
final class DeviceCommands
{
    public function __construct(private readonly DeviceEventOutbox $outbox) {}

    /** Force internet on/off for `$minutes`, after which the schedule takes over. */
    public function setManualInternet(ChildDevice $device, bool $enabled, int $minutes, ?User $actor = null): DeviceEvent
    {
        if ($minutes < 1 || $minutes > 24 * 60) {
            throw new InvalidArgumentException('minutes must be between 1 and 1440');
        }
        $until = Carbon::now()->addMinutes($minutes);

        $device->forceFill(['manual_override' => ['enabled' => $enabled, 'until' => Iso::format($until)]])->save();

        return $this->outbox->push($device, DeviceEvent::SET_MANUAL_INTERNET, [
            'enabled' => $enabled,
            'minutes' => $minutes,
            'until' => Iso::format($until),
        ], $actor);
    }

    /** Drop the manual toggle: back to schedule. */
    public function clearManualInternet(ChildDevice $device, ?User $actor = null): DeviceEvent
    {
        $device->forceFill(['manual_override' => null])->save();

        return $this->outbox->push($device, DeviceEvent::CLEAR_MANUAL_INTERNET, [], $actor);
    }

    /** Choose which profile's rules the device enforces (null = all of them). */
    public function setActiveProfile(ChildDevice $device, ?Profile $profile, ?User $actor = null): DeviceEvent
    {
        if ($profile !== null && $profile->user_id !== $device->user_id) {
            throw new InvalidArgumentException('profile belongs to another account');
        }

        return DB::transaction(function () use ($device, $profile, $actor) {
            ChildDevice::query()->whereKey($device->getKey())->lockForUpdate()->first();
            $device->forceFill(['active_profile_id' => $profile?->getKey()])->save();
            // The policy envelope carries activeProfileId, so its version moves too;
            // a device that missed the event notices via the heartbeat.
            $device->increment('policy_version');

            return $this->outbox->insert($device, DeviceEvent::ACTIVE_PROFILE_CHANGED, [
                'profileId' => $profile?->getKey(),
            ], $actor);
        });
    }

    /**
     * Unenroll: queue `unenrolled` for a poll that is open right now, then kill
     * the token. Every later request from the device gets 401 `device_revoked`.
     */
    public function revoke(ChildDevice $device, ?User $actor = null): void
    {
        $this->outbox->push($device, DeviceEvent::UNENROLLED, [], $actor);
        $device->forceFill(['revoked_at' => Carbon::now(), 'device_token_hash' => null, 'previous_token_hash' => null])->save();
    }
}
