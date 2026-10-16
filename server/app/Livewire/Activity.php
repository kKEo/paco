<?php

namespace App\Livewire;

use App\Models\ChildDevice;
use App\Models\DeviceEvent;
use Illuminate\Support\Collection;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\Component;

/** What was sent to each Mac and whether it arrived (the device outbox). */
#[Title('Activity')]
class Activity extends Component
{
    #[Url]
    public string $device = '';

    #[Computed]
    public function devices(): Collection
    {
        return ChildDevice::query()->ownedBy(auth()->user())->orderBy('name')->get();
    }

    #[Computed]
    public function events(): Collection
    {
        return DeviceEvent::query()
            ->whereIn('device_id', $this->devices->pluck('id'))
            ->when($this->device !== '', fn ($q) => $q->where('device_id', $this->device))
            ->with(['device', 'actor'])
            ->latest('id')->limit(100)->get();
    }

    public static function describe(DeviceEvent $event): string
    {
        $p = $event->payload ?? [];

        return match ($event->type) {
            DeviceEvent::POLICY_CHANGED => 'Rules updated (version '.($p['version'] ?? '?').')',
            DeviceEvent::ACTIVE_PROFILE_CHANGED => 'Profile changed',
            DeviceEvent::APPROVE_EXTENSION => 'Extra time approved: '.($p['grantedMinutes'] ?? '?').' min',
            DeviceEvent::DENY_EXTENSION => 'Request denied',
            DeviceEvent::SET_MANUAL_INTERNET => 'Internet '.(($p['enabled'] ?? false) ? 'on' : 'off').' for '.($p['minutes'] ?? '?').' min',
            DeviceEvent::CLEAR_MANUAL_INTERNET => 'Back to schedule',
            DeviceEvent::UNENROLLED => 'Removed from PaCo Cloud',
            default => $event->type,
        };
    }

    public function render()
    {
        return view('livewire.paco.activity');
    }
}
