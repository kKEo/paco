<?php

use App\Livewire\AppRules;
use App\Livewire\Profiles;
use App\Livewire\Schedules;
use App\Models\AppRestriction;
use App\Models\Profile;
use App\Models\Schedule;
use App\Models\User;
use Livewire\Livewire;

beforeEach(function () {
    $this->parent = User::factory()->create();
    [$this->device] = enrolledDevice($this->parent);
    $this->actingAs($this->parent);
});

it('creates a schedule and publishes it to the Macs', function () {
    $version = $this->device->policy_version;

    Livewire::test(Schedules::class)
        ->call('new')
        ->set('label', 'School nights')
        ->set('days', ['1', '2', '3', '4', '7'])
        ->set('offTime', '21:30')
        ->set('onTime', '07:00')
        ->set('grace', 10)
        ->call('save')
        ->assertHasNoErrors()
        ->assertSee('School nights');

    $schedule = Schedule::query()->sole();
    expect($schedule->toTransfer())->toMatchArray([
        'label' => 'School nights', 'days' => [1, 2, 3, 4, 7],
        'offHour' => 21, 'offMinute' => 30, 'onHour' => 7, 'onMinute' => 0,
        'gracePeriodMinutes' => 10, 'isActive' => true, 'profileId' => null,
    ])->and($this->device->refresh()->policy_version)->toBe($version + 1);
});

it('validates a schedule', function () {
    Livewire::test(Schedules::class)
        ->call('new')
        ->set('label', '')
        ->set('days', [])
        ->set('offTime', '21:00')
        ->set('onTime', '21:00')
        ->set('grace', 30)
        ->set('profileId', Profile::factory()->create()->id)
        ->call('save')
        ->assertHasErrors(['label', 'days', 'onTime', 'grace', 'profileId']);
});

it('edits, disables and deletes a schedule', function () {
    $schedule = Schedule::factory()->for($this->parent)->create();

    Livewire::test(Schedules::class)
        ->call('edit', $schedule->id)
        ->assertSet('offTime', '21:00')
        ->set('label', 'Bedtime (weekdays)')
        ->call('save')
        ->call('toggle', $schedule->id);
    expect($schedule->refresh()->label)->toBe('Bedtime (weekdays)')->and($schedule->is_active)->toBeFalse();

    Livewire::test(Schedules::class)->call('delete', $schedule->id);
    expect(Schedule::count())->toBe(0);
});

it("cannot edit another parent's schedule", function () {
    $foreign = Schedule::factory()->create();

    Livewire::test(Schedules::class)->call('edit', $foreign->id)->assertNotFound();
    Livewire::test(Schedules::class)->call('delete', $foreign->id)->assertNotFound();
});

it('creates a Follows Schedule app rule', function () {
    $schedule = Schedule::factory()->for($this->parent)->create();

    Livewire::test(AppRules::class)
        ->call('new')
        ->set('bundleIdentifier', 'com.google.Chrome')
        ->set('appName', 'Google Chrome')
        ->set('type', 'scheduledOnly')
        ->set('scheduleId', $schedule->id)
        ->call('save')
        ->assertHasNoErrors();

    expect(AppRestriction::query()->sole()->toTransfer())->toMatchArray([
        'bundleIdentifier' => 'com.google.Chrome', 'restrictionType' => 'scheduledOnly', 'allowedScheduleId' => $schedule->id,
    ]);
});

it('requires an own schedule for a Follows Schedule rule and a sane bundle id', function () {
    Livewire::test(AppRules::class)
        ->call('new')
        ->set('bundleIdentifier', 'not a bundle id!')
        ->set('appName', 'X')
        ->set('type', 'scheduledOnly')
        ->call('save')
        ->assertHasErrors(['bundleIdentifier', 'scheduleId'])
        ->set('scheduleId', Schedule::factory()->create()->id)
        ->call('save')
        ->assertHasErrors(['scheduleId']);
});

it('flags a rule whose schedule was deleted', function () {
    $schedule = Schedule::factory()->for($this->parent)->create();
    AppRestriction::factory()->for($this->parent)->create([
        'app_name' => 'Chrome', 'restriction_type' => 'scheduledOnly', 'allowed_schedule_id' => $schedule->id,
    ]);
    $schedule->delete();

    Livewire::test(AppRules::class)->assertSee('its schedule was deleted, so the app stays blocked');
});

it('manages profiles; deleting one makes its rules apply to everyone', function () {
    Livewire::test(Profiles::class)->set('name', 'Alex')->call('create')->assertSee('Alex');
    $profile = Profile::query()->sole();
    $schedule = Schedule::factory()->for($this->parent)->create(['profile_id' => $profile->id]);
    $version = $this->device->refresh()->policy_version;

    Livewire::test(Profiles::class)->call('edit', $profile->id)->set('editingName', 'Alexandra')->call('save');
    expect($profile->refresh()->name)->toBe('Alexandra');

    Livewire::test(Profiles::class)->call('delete', $profile->id);
    expect($schedule->refresh()->profile_id)->toBeNull()
        ->and($this->device->refresh()->policy_version)->toBe($version + 2);
});
