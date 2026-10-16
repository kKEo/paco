<?php

namespace App\Models;

use App\Models\Concerns\BelongsToUser;
use App\Models\Concerns\SerializesIsoDates;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Mirrors the Mac's ScheduleTransfer. Days are DayOfWeek raw values
 * (Mon=1 … Sun=7); an overnight window belongs to the day it starts on.
 */
class Schedule extends Model
{
    use BelongsToUser, HasFactory, HasUuids, SerializesIsoDates;

    public const DAY_NAMES = [1 => 'Mon', 2 => 'Tue', 3 => 'Wed', 4 => 'Thu', 5 => 'Fri', 6 => 'Sat', 7 => 'Sun'];

    protected $fillable = [
        'user_id', 'profile_id', 'label', 'days',
        'off_hour', 'off_minute', 'on_hour', 'on_minute',
        'grace_period_minutes', 'is_active',
    ];

    protected function casts(): array
    {
        return [
            'days' => 'array',
            'off_hour' => 'integer',
            'off_minute' => 'integer',
            'on_hour' => 'integer',
            'on_minute' => 'integer',
            'grace_period_minutes' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function profile(): BelongsTo
    {
        return $this->belongsTo(Profile::class);
    }

    /** True when the window runs past midnight (off later than on). */
    public function isOvernight(): bool
    {
        return $this->off_hour * 60 + $this->off_minute > $this->on_hour * 60 + $this->on_minute;
    }

    public function daysLabel(): string
    {
        $days = collect($this->days)->map(fn ($d) => (int) $d)->sort()->values();

        return $days->map(fn (int $d) => self::DAY_NAMES[$d] ?? '?')->implode(', ');
    }

    public function windowLabel(): string
    {
        return sprintf('%02d:%02d → %02d:%02d', $this->off_hour, $this->off_minute, $this->on_hour, $this->on_minute);
    }

    /** The JSON object the daemon decodes as `ScheduleTransfer`. */
    public function toTransfer(): array
    {
        return [
            'id' => $this->id,
            'label' => $this->label,
            'days' => collect($this->days)->map(fn ($d) => (int) $d)->sort()->values()->all(),
            'offHour' => $this->off_hour,
            'offMinute' => $this->off_minute,
            'onHour' => $this->on_hour,
            'onMinute' => $this->on_minute,
            'gracePeriodMinutes' => $this->grace_period_minutes,
            'isActive' => $this->is_active,
            'profileId' => $this->profile_id,
        ];
    }
}
