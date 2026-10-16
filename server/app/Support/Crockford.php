<?php

namespace App\Support;

/**
 * Crockford base32 one-time codes, the same alphabet the Mac pairing code uses
 * (PairingKeyManager.generateCode): no I, L, O or U, so codes survive being
 * read aloud and retyped.
 */
final class Crockford
{
    public const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

    public static function generate(int $length = 8): string
    {
        $bytes = random_bytes($length);
        $code = '';
        for ($i = 0; $i < $length; $i++) {
            $code .= self::ALPHABET[ord($bytes[$i]) % 32];
        }

        return $code;
    }

    /** Upper-case, drop spaces and dashes, and map the look-alikes I/L→1, O→0. */
    public static function normalize(string $input): string
    {
        $code = strtoupper(preg_replace('/[\s\-]+/', '', $input) ?? '');

        return strtr($code, ['I' => '1', 'L' => '1', 'O' => '0']);
    }
}
