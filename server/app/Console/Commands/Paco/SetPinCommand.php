<?php

namespace App\Console\Commands\Paco;

use App\Services\Security\PinVerifier;
use Illuminate\Console\Command;

class SetPinCommand extends Command
{
    use ResolvesModels;

    protected $signature = 'paco:set-pin {--user= : User id or email (default: first user)} {--remove : Remove the PIN}';

    protected $description = "Set the parent PIN used for 'Parent Access' on cloud child Macs";

    public function handle(PinVerifier $pins): int
    {
        $user = $this->resolveUser($this->option('user'));

        if ($this->option('remove')) {
            $pins->removePin($user);
            $this->info("PIN removed for {$user->email}.");

            return self::SUCCESS;
        }

        $pin = (string) $this->secret('6-digit PIN');
        if (! preg_match('/^\d{6}$/', $pin)) {
            $this->error('The PIN must be exactly 6 digits.');

            return self::FAILURE;
        }
        $pins->setPin($user, $pin);
        $this->info("PIN set for {$user->email}.");

        return self::SUCCESS;
    }
}
