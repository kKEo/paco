<?php

namespace App\Services\Devices;

use App\Models\ChildDevice;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

/**
 * Device bearer tokens: `pcd_<deviceUuid>.<43-char base64url secret>`.
 * Only SHA-256 of the secret is stored; the full token is shown once, in the
 * enrollment response, and lives on the Mac in a root-only file.
 */
final class DeviceTokens
{
    public const PREFIX = 'pcd_';

    public const INVALID = 'invalid_token';

    public const REVOKED = 'device_revoked';

    /** Issue a fresh token, invalidating every earlier one. Returns the plaintext token. */
    public function issue(ChildDevice $device): string
    {
        $secret = $this->secret();
        $device->forceFill([
            'device_token_hash' => hash('sha256', $secret),
            'previous_token_hash' => null,
            'token_rotated_at' => Carbon::now(),
        ])->save();

        return self::PREFIX.$device->getKey().'.'.$secret;
    }

    /**
     * Replace the token the device authenticated with. The old one stays valid
     * until the new one is first used: if the reply is lost, the device simply
     * keeps using the old token and rotates again later.
     */
    public function rotate(ChildDevice $device): string
    {
        $secret = $this->secret();
        $device->forceFill([
            'previous_token_hash' => $device->device_token_hash,
            'device_token_hash' => hash('sha256', $secret),
            'token_rotated_at' => Carbon::now(),
        ])->save();

        return self::PREFIX.$device->getKey().'.'.$secret;
    }

    private function secret(): string
    {
        return rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
    }

    /**
     * The device a token belongs to, or the reason it was refused
     * (`invalid_token` / `device_revoked`).
     */
    public function authenticate(?string $token): ChildDevice|string
    {
        if ($token === null || ! str_starts_with($token, self::PREFIX)) {
            return self::INVALID;
        }

        [$id, $secret] = array_pad(explode('.', substr($token, strlen(self::PREFIX)), 2), 2, '');
        if (! Str::isUuid($id) || $secret === '') {
            return self::INVALID;
        }

        $device = ChildDevice::query()->find(Str::lower($id));
        if ($device === null) {
            return self::INVALID;
        }
        if ($device->isRevoked()) {
            return self::REVOKED;
        }
        $hash = hash('sha256', $secret);
        if ($device->device_token_hash !== null && hash_equals($device->device_token_hash, $hash)) {
            if ($device->previous_token_hash !== null) {
                // The new token is in use: the rotation is complete.
                $device->forceFill(['previous_token_hash' => null])->save();
            }

            return $device;
        }
        if ($device->previous_token_hash !== null && hash_equals($device->previous_token_hash, $hash)) {
            return $device;
        }

        return self::INVALID;
    }
}
