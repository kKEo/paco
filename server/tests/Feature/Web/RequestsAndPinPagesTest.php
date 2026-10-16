<?php

use App\Livewire\Requests;
use App\Livewire\ScreenTime;
use App\Livewire\Settings\ParentPin;
use App\Models\DeviceEvent;
use App\Models\ExtensionRequest;
use App\Models\UsageDay;
use App\Models\User;
use App\Services\Security\PinVerifier;
use Illuminate\Support\Carbon;
use Livewire\Livewire;

beforeEach(function () {
    $this->parent = User::factory()->create();
    [$this->device] = enrolledDevice($this->parent);
    $this->actingAs($this->parent);
    $this->request = ExtensionRequest::query()->create([
        'id' => '9a7d0e2c-5b7d-4c3e-9a10-2b3c4d5e6f70', 'user_id' => $this->parent->id, 'device_id' => $this->device->id,
        'requested_minutes' => 30, 'reason' => 'Essay', 'status' => 'pending',
    ]);
});

it('approves with the requested minutes by default', function () {
    Livewire::test(Requests::class)->assertSee('Essay')->call('approve', $this->request->id)->assertSee('Approved 30 minutes');

    expect($this->request->refresh()->status)->toBe('approved')
        ->and($this->device->events()->sole()->type)->toBe(DeviceEvent::APPROVE_EXTENSION);
});

it('approves with other minutes, or denies', function () {
    Livewire::test(Requests::class)->set("minutes.{$this->request->id}", 45)->call('approve', $this->request->id);
    expect($this->request->refresh()->granted_minutes)->toBe(45);

    Livewire::test(Requests::class)->call('deny', $this->request->id)->assertSee('already answered');
});

it('rejects an out-of-range grant', function () {
    Livewire::test(Requests::class)->set("minutes.{$this->request->id}", 999)->call('approve', $this->request->id)
        ->assertHasErrors(["minutes.{$this->request->id}"]);
    expect($this->request->refresh()->isPending())->toBeTrue();
});

it("cannot answer another parent's request", function () {
    $this->actingAs(User::factory()->create());
    Livewire::test(Requests::class)->call('approve', $this->request->id)->assertNotFound();
});

it('needs the password before the PIN page', function () {
    $this->get('/settings/pin')->assertRedirect(route('password.confirm'));
});

it('sets, changes and removes the parent PIN', function () {
    Livewire::test(ParentPin::class)->set('pin', '123456')->set('pin_confirmation', '654321')->call('save')->assertHasErrors('pin');
    Livewire::test(ParentPin::class)->set('pin', '12345a')->set('pin_confirmation', '12345a')->call('save')->assertHasErrors('pin');

    Livewire::test(ParentPin::class)->set('pin', '123456')->set('pin_confirmation', '123456')->call('save')->assertSee('PIN saved.');
    $pins = app(PinVerifier::class);
    expect($pins->verify($this->parent, '123456')['outcome'])->toBe('success');

    Livewire::test(ParentPin::class)->call('remove');
    expect($pins->hasPin($this->parent))->toBeFalse();
});

it('shows and clears a lockout', function () {
    $pins = app(PinVerifier::class);
    $pins->setPin($this->parent, '123456');
    foreach (range(1, 5) as $_) {
        $pins->verify($this->parent, '000000');
    }

    Livewire::test(ParentPin::class)->assertSee('Locked after 5 wrong tries')->call('resetLockout');
    expect($pins->lockedUntil($this->parent))->toBeNull();
});

it("shows today's screen time for the Mac's local day", function () {
    // 23:30 UTC is already the 17th in Warsaw.
    Carbon::setTestNow('2026-10-16T23:30:00Z');
    UsageDay::query()->create([
        'device_id' => $this->device->id, 'local_date' => '2026-10-17', 'internet_on_seconds' => 1800, 'app_seconds' => 4500,
        'app_entries' => [['bundleIdentifier' => 'com.mojang.minecraft', 'appName' => 'Minecraft', 'duration' => 4500, 'launchCount' => 2]],
        'reported_at' => Carbon::now(),
    ]);

    Livewire::test(ScreenTime::class)
        ->assertSet('device', $this->device->id)
        ->assertSee('1h 15m')
        ->assertSee('Saturday 17 October')
        ->assertSee('Minecraft');
});
