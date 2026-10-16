<?php

namespace App\Support;

use DateTimeInterface;
use Illuminate\Support\Carbon;

/**
 * Date formatting for the device API.
 *
 * The Mac side decodes with `JSONDecoder.DateDecodingStrategy.iso8601`, which
 * rejects fractional seconds. Laravel's default model serialization emits
 * microseconds (`.000000Z`), so every date that crosses the wire goes through here.
 */
final class Iso
{
    public static function format(?DateTimeInterface $date): ?string
    {
        if ($date === null) {
            return null;
        }

        return Carbon::instance($date)->toIso8601ZuluString();
    }

    public static function now(): string
    {
        return Carbon::now()->toIso8601ZuluString();
    }
}
