<?php

namespace App\Livewire\Devices;

use App\Models\ChildDevice;
use App\Models\EnrollmentCode;
use App\Models\Profile;
use App\Services\Devices\EnrollmentService;
use Illuminate\Support\Collection;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Title;
use Livewire\Component;

/** One-time code for enrolling a child Mac, like the Mac pairing code. */
#[Title('Add a Mac')]
class Enroll extends Component
{
    public string $profileId = '';

    public ?int $codeId = null;

    public function generate(EnrollmentService $enrollment): void
    {
        $profile = $this->profileId === ''
            ? null
            : Profile::query()->ownedBy(auth()->user())->findOrFail($this->profileId);

        // One live code at a time keeps the page unambiguous.
        EnrollmentCode::query()->ownedBy(auth()->user())->usable()->delete();
        $this->codeId = $enrollment->createCode(auth()->user(), $profile)->id;
    }

    public function cancel(): void
    {
        EnrollmentCode::query()->ownedBy(auth()->user())->usable()->whereKey($this->codeId)->delete();
        $this->codeId = null;
    }

    #[Computed]
    public function code(): ?EnrollmentCode
    {
        return $this->codeId
            ? EnrollmentCode::query()->ownedBy(auth()->user())->with('device')->find($this->codeId)
            : null;
    }

    #[Computed]
    public function profiles(): Collection
    {
        return Profile::query()->ownedBy(auth()->user())->orderBy('name')->get();
    }

    /** The device that redeemed the code, once it has. */
    #[Computed]
    public function enrolledDevice(): ?ChildDevice
    {
        return $this->code?->device;
    }

    public function render()
    {
        return view('livewire.devices.enroll', ['serverUrl' => rtrim(config('app.url'), '/')]);
    }
}
