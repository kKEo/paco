<?php

namespace App\Support;

/** Human durations as the Mac shows them: `1h 5m`, `12m`, `45s`. */
final class Duration
{
    public static function short(int|float|null $seconds): string
    {
        $total = (int) round((float) $seconds);
        $hours = intdiv($total, 3600);
        $minutes = intdiv($total % 3600, 60);

        return match (true) {
            $hours > 0 => "{$hours}h {$minutes}m",
            $minutes > 0 => "{$minutes}m",
            default => "{$total}s",
        };
    }
}
