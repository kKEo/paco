<?php

namespace App\Services\Devices;

use App\Models\ChildDevice;
use App\Models\EnrollmentCode;
use App\Models\Profile;
use App\Models\User;
use App\Support\Crockford;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

final class EnrollmentService
{
    public function __construct(private readonly DeviceTokens $tokens) {}

    /** A fresh one-time code for `$user`, unique among the codes still usable. */
    public function createCode(User $user, ?Profile $profile = null, ?string $deviceNameHint = null): EnrollmentCode
    {
        do {
            $code = Crockford::generate(8);
        } while (EnrollmentCode::query()->usable()->where('code', $code)->exists());

        return EnrollmentCode::query()->create([
            'user_id' => $user->getKey(),
            'code' => $code,
            'device_name_hint' => $deviceNameHint,
            'active_profile_id' => $profile?->getKey(),
            'expires_at' => Carbon::now()->addMinutes(config('paco.enrollment.code_ttl_minutes')),
        ]);
    }

    /**
     * Redeem a code: create the device and issue its token. Returns null when the
     * code is unknown, expired or already used. The conditional update makes two
     * racing redemptions of the same code produce exactly one device.
     *
     * @return array{device: ChildDevice, token: string}|null
     */
    public function enroll(string $rawCode, string $deviceName, ?string $daemonVersion, ?string $timeZone): ?array
    {
        $code = Crockford::normalize($rawCode);

        return DB::transaction(function () use ($code, $deviceName, $daemonVersion, $timeZone) {
            $enrollment = EnrollmentCode::query()->usable()->where('code', $code)->first();
            if ($enrollment === null) {
                return null;
            }

            $claimed = EnrollmentCode::query()->usable()
                ->whereKey($enrollment->getKey())
                ->update(['used_at' => Carbon::now()]);
            if ($claimed !== 1) {
                return null;
            }

            $device = ChildDevice::query()->create([
                'user_id' => $enrollment->user_id,
                'name' => $deviceName,
                'enrolled_at' => Carbon::now(),
                'last_seen_at' => Carbon::now(),
                'active_profile_id' => $enrollment->active_profile_id,
                'daemon_version' => $daemonVersion,
                'time_zone' => $timeZone,
                'policy_version' => 1,
            ]);
            $enrollment->forceFill(['used_by_device_id' => $device->getKey()])->save();

            return ['device' => $device, 'token' => $this->tokens->issue($device)];
        });
    }
}
