<?php

namespace Database\Factories;

use App\Models\ChildDevice;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Carbon;

/** @extends Factory<ChildDevice> */
class ChildDeviceFactory extends Factory
{
    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            'name' => "Alex's MacBook",
            'enrolled_at' => Carbon::now(),
            'last_seen_at' => Carbon::now(),
            'policy_version' => 1,
            'time_zone' => 'Europe/Warsaw',
            'daemon_version' => '1.1.0',
        ];
    }

    public function revoked(): static
    {
        return $this->state(fn () => ['revoked_at' => Carbon::now(), 'device_token_hash' => null]);
    }
}
