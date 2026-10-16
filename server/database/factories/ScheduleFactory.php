<?php

namespace Database\Factories;

use App\Models\Schedule;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Schedule> */
class ScheduleFactory extends Factory
{
    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            'profile_id' => null,
            'label' => 'Bedtime',
            'days' => [1, 2, 3, 4, 7],
            'off_hour' => 21,
            'off_minute' => 0,
            'on_hour' => 7,
            'on_minute' => 0,
            'grace_period_minutes' => 5,
            'is_active' => true,
        ];
    }
}
