<?php

use App\Models\User;
use Laravel\Fortify\Actions\ConfirmTwoFactorAuthentication;
use Laravel\Fortify\Actions\EnableTwoFactorAuthentication;
use Livewire\Volt\Volt;
use PragmaRX\Google2FA\Google2FA;

function userWithTwoFactor(): User
{
    $user = User::factory()->create();
    app(EnableTwoFactorAuthentication::class)($user);
    $user->refresh();
    app(ConfirmTwoFactorAuthentication::class)($user, currentCode($user));

    return $user->refresh();
}

function currentCode(User $user): string
{
    return app(Google2FA::class)->getCurrentOtp(decrypt($user->two_factor_secret));
}

it('asks for the code instead of signing in', function () {
    $user = userWithTwoFactor();

    Volt::test('auth.login')->set('email', $user->email)->set('password', 'password')->call('login')
        ->assertRedirect(route('two-factor.login'));

    $this->assertGuest();
    expect(session('login.id'))->toBe($user->id);
});

it('signs in with a valid code', function () {
    $user = userWithTwoFactor();
    // Fortify refuses a code that was already used (here, to confirm setup).
    cache()->flush();
    session(['login.id' => $user->id, 'login.remember' => false]);

    Volt::test('auth.two-factor-challenge')->set('code', currentCode($user))->call('verify')
        ->assertHasNoErrors()->assertRedirect(route('dashboard', absolute: false));

    $this->assertAuthenticatedAs($user);
    expect(session('login.id'))->toBeNull();
});

it('rejects a wrong code and locks after five tries', function () {
    $user = userWithTwoFactor();
    session(['login.id' => $user->id]);

    foreach (range(1, 5) as $_) {
        Volt::test('auth.two-factor-challenge')->set('code', '000000')->call('verify')->assertHasErrors('code');
    }
    $errors = Volt::test('auth.two-factor-challenge')->set('code', currentCode($user))->call('verify')->errors();
    expect($errors->first('code'))->toContain('Too many');
    $this->assertGuest();
});

it('accepts each recovery code once', function () {
    $user = userWithTwoFactor();
    $recovery = $user->recoveryCodes()[0];

    session(['login.id' => $user->id]);
    Volt::test('auth.two-factor-challenge')->set('useRecovery', true)->set('recovery_code', $recovery)->call('verify')->assertHasNoErrors();
    $this->assertAuthenticatedAs($user);

    auth()->logout();
    session(['login.id' => $user->id]);
    Volt::test('auth.two-factor-challenge')->set('useRecovery', true)->set('recovery_code', $recovery)->call('verify')
        ->assertHasErrors('recovery_code');
});

it('sends a visitor without a pending login back to the login page', function () {
    $this->get('/two-factor-challenge')->assertRedirect(route('login'));
});

it('turns two-factor on and off from settings, behind the password', function () {
    $user = User::factory()->create();
    $this->actingAs($user)->get('/settings/two-factor')->assertRedirect(route('password.confirm'));

    $this->withSession(['auth.password_confirmed_at' => time()])->get('/settings/two-factor')->assertOk()->assertSee('Turn on');

    $component = Volt::test('settings.two-factor')->call('enable')->assertSee('Scan this code');
    $component->set('code', '000000')->call('confirm')->assertHasErrors('code');
    $component->set('code', currentCode($user->refresh()))->call('confirm')->assertHasNoErrors()->assertSee('Two-factor authentication is on.');
    expect($user->refresh()->hasEnabledTwoFactorAuthentication())->toBeTrue();

    $component->call('disable');
    expect($user->refresh()->hasEnabledTwoFactorAuthentication())->toBeFalse();
});
