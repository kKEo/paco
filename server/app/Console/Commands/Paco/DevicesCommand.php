<?php

namespace App\Console\Commands\Paco;

use App\Models\ChildDevice;
use Illuminate\Console\Command;

class DevicesCommand extends Command
{
    protected $signature = 'paco:devices {--all : Include unenrolled devices}';

    protected $description = 'List cloud-enrolled child Macs';

    public function handle(): int
    {
        $devices = ChildDevice::query()->with('user')
            ->when(! $this->option('all'), fn ($q) => $q->whereNull('revoked_at'))
            ->orderBy('created_at')->get();

        $this->table(
            ['Id', 'Name', 'Parent', 'Online', 'Internet', 'Policy v', 'Last seen', 'Zone'],
            $devices->map(fn (ChildDevice $d) => [
                substr($d->id, 0, 8),
                $d->name.($d->isRevoked() ? ' (unenrolled)' : ''),
                $d->user->email,
                $d->isOnline() ? 'yes' : 'no',
                match ($d->last_status['internetEnabled'] ?? null) {
                    true => 'on', false => 'off', default => '?'
                },
                $d->policy_version,
                $d->last_seen_at?->diffForHumans() ?? 'never',
                $d->time_zone ?? '?',
            ]),
        );

        return self::SUCCESS;
    }
}
