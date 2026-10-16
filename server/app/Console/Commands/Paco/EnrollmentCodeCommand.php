<?php

namespace App\Console\Commands\Paco;

use App\Models\Profile;
use App\Services\Devices\EnrollmentService;
use Illuminate\Console\Command;

class EnrollmentCodeCommand extends Command
{
    use ResolvesModels;

    protected $signature = 'paco:enrollment-code {--user= : User id or email (default: first user)} {--profile= : Profile id to pre-assign}';

    protected $description = 'Create a one-time code for enrolling a child Mac';

    public function handle(EnrollmentService $enrollment): int
    {
        $user = $this->resolveUser($this->option('user'));
        $profile = $this->option('profile')
            ? Profile::query()->ownedBy($user)->findOrFail($this->option('profile'))
            : null;

        $code = $enrollment->createCode($user, $profile);
        $this->line($code->displayCode());
        $this->comment("for {$user->email}, valid until {$code->expires_at->toDateTimeString()} UTC, single use");

        return self::SUCCESS;
    }
}
