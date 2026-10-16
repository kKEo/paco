<?php

use App\Http\Controllers\PushSubscriptionController;
use App\Livewire\Activity;
use App\Livewire\AppRules;
use App\Livewire\Dashboard;
use App\Livewire\Devices;
use App\Livewire\Profiles;
use App\Livewire\Requests;
use App\Livewire\Schedules;
use App\Livewire\ScreenTime;
use App\Livewire\Settings\ParentPin;
use Illuminate\Support\Facades\Route;
use Livewire\Volt\Volt;

Route::get('/', function () {
    return view('welcome');
})->name('home');

// The parent dashboard. Every page is scoped to the signed-in parent.
Route::middleware(['auth', 'verified'])->group(function () {
    Route::get('dashboard', Dashboard::class)->name('dashboard');
    Route::get('devices', Devices\Index::class)->name('devices.index');
    Route::get('devices/add', Devices\Enroll::class)->name('devices.enroll');
    Route::get('requests', Requests::class)->name('requests.index');
    Route::get('screen-time', ScreenTime::class)->name('screen-time');
    Route::get('activity', Activity::class)->name('activity');
    Route::get('profiles', Profiles::class)->name('profiles.index');
    Route::get('schedules', Schedules::class)->name('schedules.index');
    Route::get('app-rules', AppRules::class)->name('app-rules.index');

    Route::get('settings/pin', ParentPin::class)->middleware('password.confirm')->name('settings.pin');

    Route::post('push-subscriptions', [PushSubscriptionController::class, 'store'])->name('push-subscriptions');
    Route::delete('push-subscriptions', [PushSubscriptionController::class, 'destroy']);
});

Route::middleware(['auth'])->group(function () {
    Route::redirect('settings', 'settings/profile');

    Volt::route('settings/profile', 'settings.profile')->name('settings.profile');
    Volt::route('settings/password', 'settings.password')->name('settings.password');
    Volt::route('settings/appearance', 'settings.appearance')->name('settings.appearance');
    Volt::route('settings/notifications', 'settings.notifications')->name('settings.notifications');
    Volt::route('settings/two-factor', 'settings.two-factor')->middleware('password.confirm')->name('settings.two-factor');
});

require __DIR__.'/auth.php';
