<?php

use App\Livewire\Devices\Enroll;
use App\Livewire\Devices\Index;
use App\Models\DeviceEvent;
use App\Models\EnrollmentCode;
use App\Models\Profile;
use App\Models\User;
use App\Services\Devices\EnrollmentService;
use Livewire\Livewire;

beforeEach(function () {
    $this->parent = User::factory()->create();
    [$this->device] = enrolledDevice($this->parent);
    $this->actingAs($this->parent);
});

it('turns the internet off for the chosen minutes', function () {
    Livewire::test(Index::class)
        ->set("minutes.{$this->device->id}", 30)
        ->call('setInternet', $this->device->id, false)
        ->assertSee('Internet off on');

    $event = $this->device->events()->sole();
    expect($event->type)->toBe(DeviceEvent::SET_MANUAL_INTERNET)
        ->and($event->payload['enabled'])->toBeFalse()
        ->and($event->payload['minutes'])->toBe(30)
        ->and($event->actor_user_id)->toBe($this->parent->id);
});

it('falls back to 60 minutes for an unexpected duration', function () {
    Livewire::test(Index::class)->set("minutes.{$this->device->id}", 999)->call('setInternet', $this->device->id, true);

    expect($this->device->events()->sole()->payload['minutes'])->toBe(60);
});

it('returns a Mac to its schedule', function () {
    Livewire::test(Index::class)->call('setInternet', $this->device->id, false)->call('backToSchedule', $this->device->id);

    expect($this->device->refresh()->manual_override)->toBeNull()
        ->and($this->device->events()->latest('id')->first()->type)->toBe(DeviceEvent::CLEAR_MANUAL_INTERNET);
});

it('assigns a profile', function () {
    $profile = Profile::factory()->for($this->parent)->create();

    Livewire::test(Index::class)->call('setProfile', $this->device->id, $profile->id);

    expect($this->device->refresh()->active_profile_id)->toBe($profile->id);
});

it('asks for the password before removing a Mac', function () {
    Livewire::test(Index::class)->call('unenroll', $this->device->id)->assertRedirect(route('password.confirm'));
    expect($this->device->refresh()->isRevoked())->toBeFalse();

    session(['auth.password_confirmed_at' => time()]);
    Livewire::test(Index::class)->call('unenroll', $this->device->id);
    expect($this->device->refresh()->isRevoked())->toBeTrue();
});

it("cannot touch another parent's Mac or profile", function () {
    [$other] = enrolledDevice();
    $foreignProfile = Profile::factory()->create();

    Livewire::test(Index::class)->call('setInternet', $other->id, false)->assertNotFound();
    Livewire::test(Index::class)->call('setProfile', $this->device->id, $foreignProfile->id)->assertNotFound();
    expect($other->events()->count())->toBe(0);
});

it('creates a one-time code and notices when it is used', function () {
    $component = Livewire::test(Enroll::class)->call('generate');
    $code = EnrollmentCode::query()->ownedBy($this->parent)->sole();
    $component->assertSee($code->displayCode());

    $result = app(EnrollmentService::class)->enroll($code->code, 'New Mac', '1.1.0', 'Europe/Warsaw');
    $component->call('$refresh')->assertSee('New Mac is connected.');
    expect($result['device']->user_id)->toBe($this->parent->id);
});

it('keeps only one live code and can cancel it', function () {
    Livewire::test(Enroll::class)->call('generate')->call('generate')->call('cancel');

    expect(EnrollmentCode::query()->ownedBy($this->parent)->usable()->count())->toBe(0);
});
