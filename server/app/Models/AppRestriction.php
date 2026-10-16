<?php

namespace App\Models;

use App\Models\Concerns\BelongsToUser;
use App\Models\Concerns\SerializesIsoDates;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Mirrors the Mac's AppRestrictionTransfer. */
class AppRestriction extends Model
{
    use BelongsToUser, HasFactory, HasUuids, SerializesIsoDates;

    public const TYPE_BLOCKED = 'blocked';

    public const TYPE_SCHEDULED_ONLY = 'scheduledOnly';

    public const TYPES = [self::TYPE_BLOCKED, self::TYPE_SCHEDULED_ONLY];

    protected $fillable = [
        'user_id', 'profile_id', 'bundle_identifier', 'app_name',
        'restriction_type', 'allowed_schedule_id',
    ];

    public function profile(): BelongsTo
    {
        return $this->belongsTo(Profile::class);
    }

    public function allowedSchedule(): BelongsTo
    {
        return $this->belongsTo(Schedule::class, 'allowed_schedule_id');
    }

    /**
     * A "Follows Schedule" rule whose schedule is gone. The daemon keeps such an
     * app blocked (never silently lenient); the dashboard flags it.
     */
    public function isDangling(): bool
    {
        return $this->restriction_type === self::TYPE_SCHEDULED_ONLY && $this->allowed_schedule_id === null;
    }

    /** The JSON object the daemon decodes as `AppRestrictionTransfer`. */
    public function toTransfer(): array
    {
        return [
            'id' => $this->id,
            'bundleIdentifier' => $this->bundle_identifier,
            'appName' => $this->app_name,
            'restrictionType' => $this->restriction_type,
            'allowedScheduleId' => $this->allowed_schedule_id,
            'profileId' => $this->profile_id,
        ];
    }
}
