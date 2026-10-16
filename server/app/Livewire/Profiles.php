<?php

namespace App\Livewire;

use App\Models\ChildDevice;
use App\Models\Profile;
use App\Services\Policy\PolicyPublisher;
use Illuminate\Support\Collection;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Title;
use Livewire\Component;

/** Child profiles: the unit schedules and app rules belong to. */
#[Title('Profiles')]
class Profiles extends Component
{
    public string $name = '';

    public ?string $editingId = null;

    public string $editingName = '';

    public ?string $confirmingDelete = null;

    #[Computed]
    public function profiles(): Collection
    {
        return Profile::query()->ownedBy(auth()->user())
            ->withCount(['schedules', 'appRestrictions'])
            ->orderBy('name')
            ->get();
    }

    #[Computed]
    public function devicesByProfile(): Collection
    {
        return ChildDevice::query()->ownedBy(auth()->user())->whereNull('revoked_at')
            ->whereNotNull('active_profile_id')->get()->groupBy('active_profile_id');
    }

    public function create(): void
    {
        $this->validate(['name' => ['required', 'string', 'max:60']]);
        Profile::query()->create(['user_id' => auth()->id(), 'name' => trim($this->name)]);
        $this->reset('name');
        unset($this->profiles);
    }

    public function edit(string $id): void
    {
        $profile = $this->find($id);
        $this->editingId = $profile->id;
        $this->editingName = $profile->name;
    }

    public function save(): void
    {
        $this->validate(['editingName' => ['required', 'string', 'max:60']]);
        $this->find((string) $this->editingId)->update(['name' => trim($this->editingName)]);
        $this->reset('editingId', 'editingName');
        unset($this->profiles);
    }

    /** Its schedules and app rules stay, applying to every profile from now on. */
    public function delete(string $id, PolicyPublisher $publisher): void
    {
        $profile = $this->find($id);
        $publisher->deferred(fn () => $profile->delete());
        $this->confirmingDelete = null;
        unset($this->profiles, $this->devicesByProfile);
    }

    private function find(string $id): Profile
    {
        return Profile::query()->ownedBy(auth()->user())->findOrFail($id);
    }

    public function render()
    {
        return view('livewire.paco.profiles');
    }
}
