<?php

use App\Models\User;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Session;
use Illuminate\Validation\ValidationException;
use Laravel\Fortify\Contracts\TwoFactorAuthenticationProvider;
use Livewire\Attributes\Layout;
use Livewire\Volt\Component;

/*
| Second step of the login for a parent with two-factor authentication: the
| password was checked by the login page, which left `login.id` in the session.
*/
new #[Layout('components.layouts.auth')] class extends Component {
    public string $code = '';

    public string $recovery_code = '';

    public bool $useRecovery = false;

    public function mount(): void
    {
        if (! $this->pendingUser()) {
            $this->redirectRoute('login', navigate: true);
        }
    }

    public function verify(TwoFactorAuthenticationProvider $provider): void
    {
        $user = $this->pendingUser();
        if (! $user) {
            $this->redirectRoute('login', navigate: true);

            return;
        }

        $key = 'two-factor:'.$user->getKey();
        if (RateLimiter::tooManyAttempts($key, 5)) {
            throw ValidationException::withMessages([
                $this->useRecovery ? 'recovery_code' : 'code' => __('auth.throttle', ['seconds' => RateLimiter::availableIn($key), 'minutes' => ceil(RateLimiter::availableIn($key) / 60)]),
            ]);
        }

        $valid = $this->useRecovery
            ? $this->useRecoveryCode($user)
            : $provider->verify(decrypt($user->two_factor_secret), preg_replace('/\s+/', '', $this->code));

        if (! $valid) {
            RateLimiter::hit($key);
            throw ValidationException::withMessages([
                $this->useRecovery ? 'recovery_code' : 'code' => 'That code is not valid.',
            ]);
        }

        RateLimiter::clear($key);
        $remember = (bool) Session::pull('login.remember', false);
        Session::forget('login.id');
        Auth::login($user, $remember);
        Session::regenerate();

        $this->redirectIntended(default: route('dashboard', absolute: false), navigate: true);
    }

    private function useRecoveryCode(User $user): bool
    {
        $code = trim($this->recovery_code);
        if ($code === '' || ! in_array($code, $user->recoveryCodes(), true)) {
            return false;
        }
        $user->replaceRecoveryCode($code);

        return true;
    }

    private function pendingUser(): ?User
    {
        $id = Session::get('login.id');

        return $id ? User::query()->find($id) : null;
    }
}; ?>

<div class="flex flex-col gap-6">
    @if ($useRecovery)
        <x-auth-header title="Use a recovery code" description="Enter one of the recovery codes you saved when you turned on two-factor authentication." />
        <form wire:submit="verify" class="flex flex-col gap-6">
            <flux:input wire:model="recovery_code" label="Recovery code" required autofocus autocomplete="one-time-code" />
            <flux:button variant="primary" type="submit" class="w-full">Log in</flux:button>
        </form>
        <flux:link class="text-center text-sm" wire:click="$set('useRecovery', false)">Use the code from your app instead</flux:link>
    @else
        <x-auth-header title="Two-factor authentication" description="Enter the 6-digit code from your authenticator app." />
        <form wire:submit="verify" class="flex flex-col gap-6">
            <flux:input wire:model="code" label="Code" inputmode="numeric" required autofocus autocomplete="one-time-code" />
            <flux:button variant="primary" type="submit" class="w-full">Log in</flux:button>
        </form>
        <flux:link class="text-center text-sm" wire:click="$set('useRecovery', true)">Use a recovery code</flux:link>
    @endif
</div>
