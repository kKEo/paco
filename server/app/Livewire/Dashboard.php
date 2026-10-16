<?php

namespace App\Livewire;

use App\Models\ChildDevice;
use App\Models\ExtensionRequest;
use App\Services\Security\PinVerifier;
use Illuminate\Support\Collection;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Title;
use Livewire\Component;

/** Overview: each Mac's state and today's screen time, plus what needs the parent. */
#[Title('Overview')]
class Dashboard extends Component
{
    #[Computed]
    public function devices(): Collection
    {
        return ChildDevice::query()->ownedBy(auth()->user())->whereNull('revoked_at')->orderBy('name')->get()
            ->each(fn (ChildDevice $d) => $d->setRelation('today', $d->usageDays()->where('local_date', $d->localToday())->first()));
    }

    #[Computed]
    public function pendingRequests(): int
    {
        return ExtensionRequest::query()->ownedBy(auth()->user())->where('status', ExtensionRequest::PENDING)->count();
    }

    public function render(PinVerifier $pins)
    {
        return view('livewire.paco.dashboard', ['hasPin' => $pins->hasPin(auth()->user())]);
    }
}
