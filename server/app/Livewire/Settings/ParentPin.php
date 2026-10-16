<?php

namespace App\Livewire\Settings;

use App\Services\Security\PinVerifier;
use Livewire\Attributes\Title;
use Livewire\Component;

/**
 * The PIN for "Parent Access" on cloud-managed Macs. Stored only here (hashed);
 * a Mac sends the typed PIN and gets back a verdict. Same lockout as on a
 * parent Mac: 5 wrong tries lock it for 5 minutes.
 */
#[Title('Parent PIN')]
class ParentPin extends Component
{
    public string $pin = '';

    public string $pin_confirmation = '';

    public string $status = '';

    public function save(PinVerifier $pins): void
    {
        $this->validate([
            'pin' => ['required', 'digits:6', 'confirmed'],
        ], ['pin.digits' => 'The PIN must be exactly 6 digits.']);

        $pins->setPin(auth()->user(), $this->pin);
        $this->reset('pin', 'pin_confirmation');
        $this->status = 'PIN saved.';
    }

    public function remove(PinVerifier $pins): void
    {
        $pins->removePin(auth()->user());
        $this->status = 'PIN removed. Parent Access on your Macs is off until you set one.';
    }

    public function resetLockout(PinVerifier $pins): void
    {
        $pins->resetLockout(auth()->user());
        $this->status = 'Lockout cleared.';
    }

    public function render(PinVerifier $pins)
    {
        return view('livewire.paco.parent-pin', [
            'hasPin' => $pins->hasPin(auth()->user()),
            'lockedUntil' => $pins->lockedUntil(auth()->user()),
        ]);
    }
}
