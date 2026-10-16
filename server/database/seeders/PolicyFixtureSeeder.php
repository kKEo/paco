<?php

namespace Database\Seeders;

use App\Models\AppRestriction;
use App\Models\Profile;
use App\Models\Schedule;
use App\Models\User;
use App\Services\Policy\PolicyPublisher;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;

/**
 * The policy behind tests/Fixtures/policy.json, the wire contract shared with
 * the Mac (PaCoTests/CloudFixtureTests decodes the same file into a
 * PolicyTransfer). Fixed ids and creation order keep the output byte-stable.
 *
 * - "School nights": overnight 21:00 → 07:00 on Mon–Thu and Sun, profile "Alex"
 * - "Homework hour": weekdays 16:00 → 17:00, every profile, disabled
 * - Steam: blocked, profile "Alex"
 * - Google Chrome: follows "School nights", every profile
 */
class PolicyFixtureSeeder extends Seeder
{
    public const PROFILE_ID = '6f1c2a8e-5b7d-4c3e-9a10-2b3c4d5e6f70';

    public const SCHOOL_NIGHTS_ID = '11111111-1111-4111-8111-111111111111';

    public const HOMEWORK_ID = '22222222-2222-4222-8222-222222222222';

    public const STEAM_ID = '33333333-3333-4333-8333-333333333333';

    public const CHROME_ID = '44444444-4444-4444-8444-444444444444';

    public function run(?User $user = null): void
    {
        $user ??= User::query()->orderBy('id')->firstOrFail();
        $at = Carbon::parse('2026-10-16T08:00:00Z');

        app(PolicyPublisher::class)->deferred(function () use ($user, $at) {
            $profile = $this->create(Profile::class, $at, ['id' => self::PROFILE_ID, 'user_id' => $user->id, 'name' => 'Alex']);

            $this->create(Schedule::class, $at, [
                'id' => self::SCHOOL_NIGHTS_ID, 'user_id' => $user->id, 'profile_id' => $profile->id,
                'label' => 'School nights', 'days' => [1, 2, 3, 4, 7],
                'off_hour' => 21, 'off_minute' => 0, 'on_hour' => 7, 'on_minute' => 0,
                'grace_period_minutes' => 5, 'is_active' => true,
            ]);
            $this->create(Schedule::class, $at->copy()->addMinute(), [
                'id' => self::HOMEWORK_ID, 'user_id' => $user->id, 'profile_id' => null,
                'label' => 'Homework hour', 'days' => [1, 2, 3, 4, 5],
                'off_hour' => 16, 'off_minute' => 0, 'on_hour' => 17, 'on_minute' => 0,
                'grace_period_minutes' => 0, 'is_active' => false,
            ]);
            $this->create(AppRestriction::class, $at, [
                'id' => self::STEAM_ID, 'user_id' => $user->id, 'profile_id' => $profile->id,
                'bundle_identifier' => 'com.valvesoftware.steam', 'app_name' => 'Steam',
                'restriction_type' => AppRestriction::TYPE_BLOCKED, 'allowed_schedule_id' => null,
            ]);
            $this->create(AppRestriction::class, $at->copy()->addMinute(), [
                'id' => self::CHROME_ID, 'user_id' => $user->id, 'profile_id' => null,
                'bundle_identifier' => 'com.google.Chrome', 'app_name' => 'Google Chrome',
                'restriction_type' => AppRestriction::TYPE_SCHEDULED_ONLY, 'allowed_schedule_id' => self::SCHOOL_NIGHTS_ID,
            ]);
        });
    }

    /** @param class-string<Model> $class */
    private function create(string $class, Carbon $at, array $attributes): Model
    {
        $model = new $class;
        $model->forceFill($attributes + ['created_at' => $at, 'updated_at' => $at]);
        $model->save();

        return $model;
    }
}
