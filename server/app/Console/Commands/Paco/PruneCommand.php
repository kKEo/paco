<?php

namespace App\Console\Commands\Paco;

use App\Models\DeviceEvent;
use App\Models\EnrollmentCode;
use App\Models\UsageDay;
use Illuminate\Console\Command;
use Illuminate\Support\Carbon;

class PruneCommand extends Command
{
    protected $signature = 'paco:prune';

    protected $description = 'Delete expired enrollment codes, old acknowledged events and old usage';

    public function handle(): int
    {
        $codes = EnrollmentCode::query()
            ->where(fn ($q) => $q->where('expires_at', '<', Carbon::now()->subDay())->orWhereNotNull('used_at'))
            ->where('created_at', '<', Carbon::now()->subDay())
            ->delete();

        $events = DeviceEvent::query()
            ->whereNotNull('acked_at')
            ->where('created_at', '<', Carbon::now()->subDays(config('paco.retention.event_days')))
            ->delete();

        $usage = UsageDay::query()
            ->where('local_date', '<', Carbon::now()->subDays(config('paco.retention.usage_days'))->toDateString())
            ->delete();

        $this->info("Pruned {$codes} code(s), {$events} event(s), {$usage} usage day(s).");

        return self::SUCCESS;
    }
}
