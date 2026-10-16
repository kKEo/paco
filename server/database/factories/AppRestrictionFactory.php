<?php

namespace Database\Factories;

use App\Models\AppRestriction;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<AppRestriction> */
class AppRestrictionFactory extends Factory
{
    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            'profile_id' => null,
            'bundle_identifier' => 'com.example.'.fake()->unique()->word(),
            'app_name' => fake()->word(),
            'restriction_type' => AppRestriction::TYPE_BLOCKED,
            'allowed_schedule_id' => null,
        ];
    }
}
