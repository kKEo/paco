<?php

namespace App\Livewire\Devices;

use App\Livewire\Concerns\ConfirmsPassword;
use App\Models\ChildDevice;
use App\Models\Profile;
use App\Services\Devices\DeviceCommands;
use Illuminate\Support\Collection;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Title;
use Livewire\Component;

/** The parent's cloud-enrolled Macs: live state and remote controls. */
#[Title('Macs')]
class Index extends Component
{
    use ConfirmsPassword;

    /** Minutes for the manual on/off buttons, per device id. */
    public array $minutes = [];

    public ?string $confirmingUnenroll = null;

    public string $status = '';

    #[Computed]
    public function devices(): Collection
    {
        return ChildDevice::query()->ownedBy(auth()->user())
            ->whereNull('revoked_at')
            ->with('activeProfile')
            ->orderBy('name')
            ->get();
    }

    #[Computed]
    public function profiles(): Collection
    {
        return Profile::query()->ownedBy(auth()->user())->orderBy('name')->get();
    }

    public function setProfile(string $deviceId, string $profileId, DeviceCommands $commands): void
    {
        $device = $this->device($deviceId);
        $profile = $profileId === '' ? null : Profile::query()->ownedBy(auth()->user())->findOrFail($profileId);
        $commands->setActiveProfile($device, $profile, auth()->user());
        $this->status = $device->name.' now follows '.($profile?->name ?? 'every profile').'.';
    }

    public function setInternet(string $deviceId, bool $enabled, DeviceCommands $commands): void
    {
        $device = $this->device($deviceId);
        $minutes = (int) ($this->minutes[$deviceId] ?? 60);
        $minutes = in_array($minutes, [15, 30, 60, 120, 240], true) ? $minutes : 60;
        $commands->setManualInternet($device, $enabled, $minutes, auth()->user());
        $this->status = sprintf('Internet %s on %s for %d minutes.', $enabled ? 'on' : 'off', $device->name, $minutes);
    }

    public function backToSchedule(string $deviceId, DeviceCommands $commands): void
    {
        $device = $this->device($deviceId);
        $commands->clearManualInternet($device, auth()->user());
        $this->status = $device->name.' follows its schedules again.';
    }

    public function unenroll(string $deviceId, DeviceCommands $commands): void
    {
        if (! $this->ensurePasswordConfirmed(route('devices.index'))) {
            return;
        }
        $device = $this->device($deviceId);
        $commands->revoke($device, auth()->user());
        $this->confirmingUnenroll = null;
        $this->status = $device->name.' was removed. It keeps its current rules until it is managed again.';
        unset($this->devices);
    }

    private function device(string $id): ChildDevice
    {
        return ChildDevice::query()->ownedBy(auth()->user())->whereNull('revoked_at')->findOrFail($id);
    }

    public function render()
    {
        // The duration picker shows what the buttons will send.
        foreach ($this->devices as $device) {
            $this->minutes[$device->id] ??= 60;
        }

        return view('livewire.devices.index');
    }
}
