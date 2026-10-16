<?php

namespace Database\Seeders;

use App\Models\User;
use App\Services\Security\PinVerifier;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Hash;

/**
 * Local development data: a verified parent (parent@example.com / password,
 * PIN 123456) owning the golden-fixture policy. Enroll a Mac with
 * `php artisan paco:enrollment-code`.
 *
 * Uses no factories, so it also runs in the Docker image (no dev packages).
 */
class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        if (app()->isProduction()) {
            $this->command?->error('Refusing to seed a known password in production.');

            return;
        }

        $user = User::query()->firstOrCreate(['email' => 'parent@example.com'], [
            'name' => 'Parent',
            'password' => Hash::make('password'),
        ]);
        $user->forceFill(['email_verified_at' => Carbon::now()])->save();

        app(PinVerifier::class)->setPin($user, '123456');
        if (! $user->profiles()->exists()) {
            $this->callWith(PolicyFixtureSeeder::class, ['user' => $user]);
        }
    }
}
