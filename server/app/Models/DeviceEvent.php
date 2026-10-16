<?php

namespace App\Models;

use App\Models\Concerns\SerializesIsoDates;
use App\Support\Iso;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A command queued for a device (delivered by long-poll, at least once) and the
 * audit record of it. The id is the poll cursor.
 */
class DeviceEvent extends Model
{
    use SerializesIsoDates;

    public const UPDATED_AT = null;

    public const POLICY_CHANGED = 'policyChanged';

    public const ACTIVE_PROFILE_CHANGED = 'activeProfileChanged';

    public const APPROVE_EXTENSION = 'approveExtension';

    public const DENY_EXTENSION = 'denyExtension';

    public const SET_MANUAL_INTERNET = 'setManualInternet';

    public const CLEAR_MANUAL_INTERNET = 'clearManualInternet';

    public const UNENROLLED = 'unenrolled';

    public const TYPES = [
        self::POLICY_CHANGED, self::ACTIVE_PROFILE_CHANGED, self::APPROVE_EXTENSION,
        self::DENY_EXTENSION, self::SET_MANUAL_INTERNET, self::CLEAR_MANUAL_INTERNET,
        self::UNENROLLED,
    ];

    protected $fillable = ['device_id', 'type', 'payload', 'actor_user_id', 'delivered_at', 'acked_at'];

    protected function casts(): array
    {
        return [
            'payload' => 'array',
            'delivered_at' => 'datetime',
            'acked_at' => 'datetime',
        ];
    }

    public function device(): BelongsTo
    {
        return $this->belongsTo(ChildDevice::class, 'device_id');
    }

    public function actor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'actor_user_id');
    }

    /** Wire shape for `GET /device/events`. */
    public function toWire(): array
    {
        return [
            'id' => $this->id,
            'type' => $this->type,
            // An empty PHP array encodes as `[]`; the daemon expects an object.
            'payload' => (object) ($this->payload ?? []),
            'createdAt' => Iso::format($this->created_at),
        ];
    }
}
