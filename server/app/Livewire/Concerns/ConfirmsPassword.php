<?php

namespace App\Livewire\Concerns;

use Illuminate\Support\Facades\Session;

/**
 * For destructive actions inside a page (e.g. unenrolling a Mac): require a
 * recent password confirmation, like the `password.confirm` route middleware.
 */
trait ConfirmsPassword
{
    protected function passwordRecentlyConfirmed(): bool
    {
        $confirmedAt = (int) Session::get('auth.password_confirmed_at', 0);

        return time() - $confirmedAt < (int) config('auth.password_timeout', 10800);
    }

    /** Returns false (and sends the parent to confirm) when confirmation is needed. */
    protected function ensurePasswordConfirmed(string $returnTo): bool
    {
        if ($this->passwordRecentlyConfirmed()) {
            return true;
        }
        Session::put('url.intended', $returnTo);
        $this->redirectRoute('password.confirm');

        return false;
    }
}
