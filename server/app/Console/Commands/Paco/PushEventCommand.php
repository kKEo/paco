<?php

namespace App\Console\Commands\Paco;

use App\Models\DeviceEvent;
use App\Models\Profile;
use App\Services\Devices\DeviceCommands;
use App\Services\Policy\PolicyPublisher;
use Illuminate\Console\Command;

/** Stand-in for the parent dashboard while developing the daemon client. */
class PushEventCommand extends Command
{
    use ResolvesModels;

    protected $signature = 'paco:push-event {device : Device id prefix or name} {type : setManualInternet|clearManualInternet|activeProfileChanged|policyChanged|unenrolled} {payload? : JSON, e.g. {"enabled":false,"minutes":10}}';

    protected $description = 'Queue a command for a cloud device (delivered on its next long-poll)';

    public function handle(DeviceCommands $commands, PolicyPublisher $publisher): int
    {
        $device = $this->resolveDevice($this->argument('device'));
        $payload = json_decode($this->argument('payload') ?? '{}', true) ?? [];

        match ($this->argument('type')) {
            DeviceEvent::SET_MANUAL_INTERNET => $commands->setManualInternet(
                $device, (bool) ($payload['enabled'] ?? false), (int) ($payload['minutes'] ?? 60)),
            DeviceEvent::CLEAR_MANUAL_INTERNET => $commands->clearManualInternet($device),
            DeviceEvent::ACTIVE_PROFILE_CHANGED => $commands->setActiveProfile($device,
                isset($payload['profileId']) ? Profile::query()->ownedBy($device->user)->findOrFail($payload['profileId']) : null),
            DeviceEvent::POLICY_CHANGED => $publisher->publish($device->user, $device),
            DeviceEvent::UNENROLLED => $commands->revoke($device),
            default => throw new \InvalidArgumentException('Unknown type. Use paco:approve for extension requests.'),
        };

        $this->info("Queued {$this->argument('type')} for {$device->name}.");

        return self::SUCCESS;
    }
}
