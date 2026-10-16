<?php

namespace App\Models;

use App\Models\Concerns\BelongsToUser;
use App\Models\Concerns\SerializesIsoDates;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

class EnrollmentCode extends Model
{
    use BelongsToUser, SerializesIsoDates;

    protected $fillable = [
        'user_id', 'code', 'device_name_hint', 'active_profile_id',
        'expires_at', 'used_at', 'used_by_device_id',
    ];

    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
            'used_at' => 'datetime',
        ];
    }

    public function activeProfile(): BelongsTo
    {
        return $this->belongsTo(Profile::class, 'active_profile_id');
    }

    public function device(): BelongsTo
    {
        return $this->belongsTo(ChildDevice::class, 'used_by_device_id');
    }

    public function scopeUsable(Builder $query): Builder
    {
        return $query->whereNull('used_at')->where('expires_at', '>', Carbon::now());
    }

    public function isUsable(): bool
    {
        return $this->used_at === null && $this->expires_at->isFuture();
    }

    /** Grouped for display, like the Mac pairing code: `ABCD-EFGH`. */
    public function displayCode(): string
    {
        return substr($this->code, 0, 4).'-'.substr($this->code, 4);
    }
}
