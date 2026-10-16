<?php

use Laravel\Fortify\Actions\ConfirmTwoFactorAuthentication;
use Laravel\Fortify\Actions\DisableTwoFactorAuthentication;
use Laravel\Fortify\Actions\EnableTwoFactorAuthentication;
use Laravel\Fortify\Actions\GenerateNewRecoveryCodes;
use Livewire\Volt\Component;

/*
| Two-factor authentication for the parent account (TOTP). Reached through
| password confirmation (route middleware).
*/
new class extends Component {
    public string $code = '';

    public bool $showRecoveryCodes = false;

    public function enable(EnableTwoFactorAuthentication $enable): void
    {
        $enable(auth()->user());
        $this->reset('code');
    }

    public function confirm(ConfirmTwoFactorAuthentication $confirm): void
    {
        $this->validate(['code' => ['required', 'string']]);
        $confirm(auth()->user(), preg_replace('/\s+/', '', $this->code));
        $this->reset('code');
        $this->showRecoveryCodes = true;
    }

    public function regenerate(GenerateNewRecoveryCodes $generate): void
    {
        $generate(auth()->user());
        $this->showRecoveryCodes = true;
    }

    public function disable(DisableTwoFactorAuthentication $disable): void
    {
        $disable(auth()->user());
        $this->reset('code', 'showRecoveryCodes');
    }

    public function with(): array
    {
        $user = auth()->user()->fresh();

        return [
            'enabled' => $user->hasEnabledTwoFactorAuthentication(),
            'pending' => $user->two_factor_secret !== null && $user->two_factor_confirmed_at === null,
            'qr' => $user->two_factor_secret ? $user->twoFactorQrCodeSvg() : null,
            'setupKey' => $user->two_factor_secret ? decrypt($user->two_factor_secret) : null,
            'recoveryCodes' => $user->two_factor_recovery_codes ? $user->recoveryCodes() : [],
        ];
    }
}; ?>

<section class="w-full">
    @include('partials.settings-heading')

    <x-settings.layout heading="Two-factor authentication" subheading="Ask for a code from an authenticator app when you log in.">
        <div class="space-y-6">
            @if ($enabled)
                <flux:callout icon="shield-check" variant="success" heading="Two-factor authentication is on." />

                @if ($showRecoveryCodes)
                    <div>
                        <flux:text>Keep these recovery codes somewhere safe. Each one logs you in once if you lose your phone.</flux:text>
                        <div class="mt-3 grid grid-cols-2 gap-1 rounded-lg bg-zinc-100 p-4 font-mono text-sm dark:bg-zinc-900" data-test="recovery-codes">
                            @foreach ($recoveryCodes as $recovery)
                                <div>{{ $recovery }}</div>
                            @endforeach
                        </div>
                    </div>
                @endif

                <div class="flex gap-2">
                    <flux:button wire:click="regenerate">New recovery codes</flux:button>
                    <flux:button variant="danger" wire:click="disable">Turn off</flux:button>
                </div>
            @elseif ($pending)
                <flux:text>Scan this code with an authenticator app (for example the Passwords app on a Mac or iPhone), then enter the 6-digit code it shows.</flux:text>
                <div class="inline-block rounded-lg bg-white p-3">{!! $qr !!}</div>
                <flux:text class="text-xs">Or type this key: <span class="font-mono">{{ $setupKey }}</span></flux:text>
                <form wire:submit="confirm" class="flex items-end gap-2">
                    <flux:input wire:model="code" label="Code" inputmode="numeric" autocomplete="one-time-code" class="max-w-40" />
                    <flux:button type="submit" variant="primary">Confirm</flux:button>
                    <flux:button variant="ghost" wire:click="disable">Cancel</flux:button>
                </form>
            @else
                <flux:text>Your PaCo Cloud account controls your child's Mac. A second factor keeps it safe even if your password leaks.</flux:text>
                <flux:button variant="primary" wire:click="enable">Turn on</flux:button>
            @endif
        </div>
    </x-settings.layout>
</section>
