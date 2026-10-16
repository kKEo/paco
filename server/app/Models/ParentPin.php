<?php

namespace App\Models;

use App\Models\Concerns\BelongsToUser;
use Illuminate\Database\Eloquent\Model;

class ParentPin extends Model
{
    use BelongsToUser;

    protected $fillable = ['user_id', 'pin_hash', 'failed_attempts', 'locked_until'];

    protected $hidden = ['pin_hash'];

    protected function casts(): array
    {
        return [
            'failed_attempts' => 'integer',
            'locked_until' => 'datetime',
        ];
    }
}
