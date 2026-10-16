<?php

namespace App\Console\Commands\Paco;

use App\Models\ExtensionRequest;
use App\Services\Requests\ExtensionRequestService;
use Illuminate\Console\Command;

class ApproveCommand extends Command
{
    protected $signature = 'paco:approve {request? : Request id prefix (default: newest pending)} {--minutes= : Minutes to grant (default: as requested)} {--deny : Deny instead}';

    protected $description = 'Approve or deny a pending time-extension request';

    public function handle(ExtensionRequestService $service): int
    {
        $request = ExtensionRequest::query()->where('status', ExtensionRequest::PENDING)
            ->when($this->argument('request'), fn ($q, $id) => $q->where('id', 'like', strtolower($id).'%'))
            ->latest()->first();

        if ($request === null) {
            $this->error('No matching pending request.');

            return self::FAILURE;
        }

        if ($this->option('deny')) {
            $service->deny($request);
            $this->info("Denied {$request->id}.");
        } else {
            $minutes = (int) ($this->option('minutes') ?: $request->requested_minutes);
            $service->approve($request, $minutes);
            $this->info("Approved {$request->id} for {$minutes} minutes.");
        }

        return self::SUCCESS;
    }
}
