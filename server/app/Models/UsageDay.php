<?php

namespace App\Models;

use App\Models\Concerns\SerializesIsoDates;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** One UsageTransfer snapshot: totals for one child-local day. */
class UsageDay extends Model
{
    use SerializesIsoDates;

    protected $fillable = [
        'device_id', 'local_date', 'profile_id', 'internet_on_seconds',
        'app_seconds', 'app_entries', 'reported_at',
    ];

    protected function casts(): array
    {
        return [
            'local_date' => 'date:Y-m-d',
            'internet_on_seconds' => 'integer',
            'app_seconds' => 'integer',
            'app_entries' => 'array',
            'reported_at' => 'datetime',
        ];
    }

    public function device(): BelongsTo
    {
        return $this->belongsTo(ChildDevice::class, 'device_id');
    }

    /** App entries sorted by foreground time, longest first. */
    public function sortedApps(): array
    {
        return collect($this->app_entries ?? [])
            ->sortByDesc(fn (array $e) => $e['duration'] ?? 0)
            ->values()
            ->all();
    }
}
