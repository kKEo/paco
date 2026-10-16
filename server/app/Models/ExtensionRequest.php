<?php

namespace App\Models;

use App\Models\Concerns\BelongsToUser;
use App\Models\Concerns\SerializesIsoDates;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ExtensionRequest extends Model
{
    use BelongsToUser, HasUuids, SerializesIsoDates;

    public const PENDING = 'pending';

    public const APPROVED = 'approved';

    public const DENIED = 'denied';

    public const EXPIRED = 'expired';

    public const WITHDRAWN = 'withdrawn';

    protected $fillable = [
        'id', 'user_id', 'device_id', 'profile_id', 'child_device_name',
        'requested_minutes', 'reason', 'status', 'granted_minutes',
        'granted_until', 'resolved_at', 'resolved_by_user_id',
    ];

    protected function casts(): array
    {
        return [
            'requested_minutes' => 'integer',
            'granted_minutes' => 'integer',
            'granted_until' => 'datetime',
            'resolved_at' => 'datetime',
        ];
    }

    public function device(): BelongsTo
    {
        return $this->belongsTo(ChildDevice::class, 'device_id');
    }

    public function isPending(): bool
    {
        return $this->status === self::PENDING;
    }
}
