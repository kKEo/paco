<?php

namespace App\Console\Commands\Paco;

use App\Services\Requests\ExtensionRequestService;
use Illuminate\Console\Command;

class ExpireRequestsCommand extends Command
{
    protected $signature = 'paco:expire-requests';

    protected $description = 'Auto-deny time-extension requests nobody answered in time';

    public function handle(ExtensionRequestService $service): int
    {
        $count = $service->expireStale();
        $this->info("Expired {$count} request(s).");

        return self::SUCCESS;
    }
}
