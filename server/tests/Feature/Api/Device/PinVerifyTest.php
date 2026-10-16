<?php

use App\Services\Security\PinVerifier;
use Illuminate\Support\Carbon;

const NONCE = 'C0FFEE00-5B7D-4C3E-9A10-2B3C4D5E6F70';

function verifyPin(string $token, string $pin)
{
    return test()->postJson('/api/v1/device/pin/verify', ['nonce' => NONCE, 'pin' => $pin], bearer($token));
}

beforeEach(function () {
    Carbon::setTestNow('2026-10-16T18:00:00Z');
    [$this->device, $this->token] = enrolledDevice();
});

it('answers noPIN before the parent set one', function () {
    verifyPin($this->token, '123456')->assertOk()->assertExactJson([
        'nonce' => strtolower(NONCE), 'outcome' => 'noPIN', 'lockedOutUntil' => null,
    ]);
});

it('verifies the PIN and returns only the verdict', function () {
    app(PinVerifier::class)->setPin($this->device->user, '123456');

    $response = verifyPin($this->token, '123456')->assertOk();

    expect(array_keys($response->json()))->toBe(['nonce', 'outcome', 'lockedOutUntil'])
        ->and($response->json('outcome'))->toBe('success');
    verifyPin($this->token, '654321')->assertJsonPath('outcome', 'incorrect');
});

it('locks out on the 5th failure for 300 s, like PINManager', function () {
    app(PinVerifier::class)->setPin($this->device->user, '123456');

    foreach (range(1, 4) as $_) {
        verifyPin($this->token, '000000')->assertJsonPath('outcome', 'incorrect');
    }
    verifyPin($this->token, '000000')->assertJson(['outcome' => 'lockedOut', 'lockedOutUntil' => '2026-10-16T18:05:00Z']);

    // While locked, even the right PIN is refused and nothing is counted.
    verifyPin($this->token, '123456')->assertJson(['outcome' => 'lockedOut', 'lockedOutUntil' => '2026-10-16T18:05:00Z']);

    Carbon::setTestNow('2026-10-16T18:05:01Z');
    verifyPin($this->token, '123456')->assertJsonPath('outcome', 'success');
});

it('resets the failure count on success', function () {
    app(PinVerifier::class)->setPin($this->device->user, '123456');
    foreach (range(1, 4) as $_) {
        verifyPin($this->token, '000000');
    }
    verifyPin($this->token, '123456')->assertJsonPath('outcome', 'success');

    verifyPin($this->token, '000000')->assertJsonPath('outcome', 'incorrect');
});

it('stores an argon2id hash, never the PIN', function () {
    app(PinVerifier::class)->setPin($this->device->user, '123456');

    $hash = $this->device->user->parentPin->pin_hash;
    expect($hash)->not->toContain('123456')
        ->and(password_get_info($hash)['algoName'])->toBe(defined('PASSWORD_ARGON2ID') ? 'argon2id' : 'bcrypt');
});

it('rate limits verification requests', function () {
    app(PinVerifier::class)->setPin($this->device->user, '123456');
    foreach (range(1, 10) as $_) {
        verifyPin($this->token, '123456')->assertOk();
    }
    verifyPin($this->token, '123456')->assertStatus(429);
});
