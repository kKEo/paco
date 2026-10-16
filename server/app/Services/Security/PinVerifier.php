<?php

namespace App\Services\Security;

use App\Models\ParentPin;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Hash;

/**
 * The parent PIN for cloud-managed children, with the same brute-force rules
 * as PINManager on the Mac: the 5th consecutive failure locks for 300 s and
 * resets the counter; a success resets it; while locked nothing is checked.
 *
 * The hash never leaves the server. Devices only see the outcome.
 */
final class PinVerifier
{
    public const SUCCESS = 'success';

    public const INCORRECT = 'incorrect';

    public const LOCKED_OUT = 'lockedOut';

    public const NO_PIN = 'noPIN';

    public function setPin(User $user, string $pin): void
    {
        ParentPin::query()->updateOrCreate(
            ['user_id' => $user->getKey()],
            ['pin_hash' => Hash::driver($this->driver())->make($pin), 'failed_attempts' => 0, 'locked_until' => null],
        );
    }

    public function removePin(User $user): void
    {
        ParentPin::query()->where('user_id', $user->getKey())->delete();
    }

    public function hasPin(User $user): bool
    {
        return ParentPin::query()->where('user_id', $user->getKey())->exists();
    }

    public function lockedUntil(User $user): ?Carbon
    {
        $pin = ParentPin::query()->where('user_id', $user->getKey())->first();

        return $pin?->locked_until?->isFuture() ? $pin->locked_until : null;
    }

    public function resetLockout(User $user): void
    {
        ParentPin::query()->where('user_id', $user->getKey())->update(['failed_attempts' => 0, 'locked_until' => null]);
    }

    /** @return array{outcome: string, lockedOutUntil: Carbon|null} */
    public function verify(User $user, string $pin): array
    {
        $record = ParentPin::query()->where('user_id', $user->getKey())->first();
        if ($record === null) {
            return ['outcome' => self::NO_PIN, 'lockedOutUntil' => null];
        }
        if ($record->locked_until?->isFuture()) {
            return ['outcome' => self::LOCKED_OUT, 'lockedOutUntil' => $record->locked_until];
        }

        if ($pin !== '' && $this->check($pin, $record->pin_hash)) {
            $record->forceFill(['failed_attempts' => 0, 'locked_until' => null])->save();

            return ['outcome' => self::SUCCESS, 'lockedOutUntil' => null];
        }

        $attempts = $record->failed_attempts + 1;
        if ($attempts >= config('paco.pin.max_attempts')) {
            $until = Carbon::now()->addSeconds(config('paco.pin.lockout_seconds'));
            $record->forceFill(['failed_attempts' => 0, 'locked_until' => $until])->save();

            return ['outcome' => self::LOCKED_OUT, 'lockedOutUntil' => $until];
        }
        $record->forceFill(['failed_attempts' => $attempts])->save();

        return ['outcome' => self::INCORRECT, 'lockedOutUntil' => null];
    }

    private function check(string $pin, string $hash): bool
    {
        $driver = password_get_info($hash)['algoName'] === 'argon2id' ? 'argon2id' : 'bcrypt';

        return Hash::driver($driver)->check($pin, $hash);
    }

    private function driver(): string
    {
        return defined('PASSWORD_ARGON2ID') ? 'argon2id' : 'bcrypt';
    }
}
