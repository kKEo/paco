<?php

namespace App\Models\Concerns;

use App\Support\Iso;
use DateTimeInterface;

/** Model dates serialize as `2026-10-16T12:00:00Z` (no fractional seconds). */
trait SerializesIsoDates
{
    protected function serializeDate(DateTimeInterface $date): string
    {
        return Iso::format($date);
    }
}
