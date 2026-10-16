<?php

namespace App\Models;

use App\Models\Concerns\BelongsToUser;
use App\Models\Concerns\SerializesIsoDates;
use Illuminate\Auth\Authenticatable as AuthenticatableTrait;
use Illuminate\Contracts\Auth\Authenticatable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Carbon;

/**
 * A cloud-enrolled child Mac. It is the authenticated principal of the device
 * API (`$request->user()` on `/api/v1/device/*`), never of the web UI.
 */
class ChildDevice extends Model implements Authenticatable
{
    use AuthenticatableTrait, BelongsToUser, HasFactory, HasUuids, SerializesIsoDates;

    /** A device is shown as online when its last heartbeat is this recent. */
    public const ONLINE_WINDOW_SECONDS = 90;

    protected $fillable = [
        'user_id', 'name', 'device_token_hash', 'previous_token_hash', 'token_rotated_at', 'enrolled_at', 'revoked_at',
        'last_seen_at', 'last_status', 'policy_version', 'active_profile_id',
        'manual_override', 'daemon_version', 'time_zone',
    ];

    protected $hidden = ['device_token_hash', 'previous_token_hash'];

    protected function casts(): array
    {
        return [
            'enrolled_at' => 'datetime',
            'revoked_at' => 'datetime',
            'token_rotated_at' => 'datetime',
            'last_seen_at' => 'datetime',
            'last_status' => 'array',
            'policy_version' => 'integer',
            'manual_override' => 'array',
        ];
    }

    public function getAuthPasswordName(): string
    {
        return 'device_token_hash';
    }

    public function activeProfile(): BelongsTo
    {
        return $this->belongsTo(Profile::class, 'active_profile_id');
    }

    public function events(): HasMany
    {
        return $this->hasMany(DeviceEvent::class, 'device_id');
    }

    public function usageDays(): HasMany
    {
        return $this->hasMany(UsageDay::class, 'device_id');
    }

    public function extensionRequests(): HasMany
    {
        return $this->hasMany(ExtensionRequest::class, 'device_id');
    }

    public function isRevoked(): bool
    {
        return $this->revoked_at !== null;
    }

    public function isOnline(): bool
    {
        return $this->last_seen_at !== null
            && $this->last_seen_at->gt(Carbon::now()->subSeconds(self::ONLINE_WINDOW_SECONDS));
    }

    /** The manual toggle last sent, if it has not expired yet. */
    public function activeManualOverride(): ?array
    {
        $override = $this->manual_override;
        if (! is_array($override) || ! isset($override['until'])) {
            return null;
        }

        return Carbon::parse($override['until'])->isFuture() ? $override : null;
    }

    /** "Today" for this device: the child's local date is authoritative. */
    public function localToday(): string
    {
        return Carbon::now($this->time_zone ?: config('app.timezone'))->toDateString();
    }
}
