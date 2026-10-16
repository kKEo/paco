<?php

namespace App\Models;

use App\Models\Concerns\BelongsToUser;
use App\Models\Concerns\SerializesIsoDates;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Profile extends Model
{
    use BelongsToUser, HasFactory, HasUuids, SerializesIsoDates;

    protected $fillable = ['user_id', 'name'];

    public function schedules(): HasMany
    {
        return $this->hasMany(Schedule::class);
    }

    public function appRestrictions(): HasMany
    {
        return $this->hasMany(AppRestriction::class);
    }
}
