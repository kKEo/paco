<?php

use App\Http\Controllers\Api\V1\Device\EnrollController;
use App\Http\Controllers\Api\V1\Device\EventsController;
use App\Http\Controllers\Api\V1\Device\ExtensionRequestController;
use App\Http\Controllers\Api\V1\Device\HeartbeatController;
use App\Http\Controllers\Api\V1\Device\PinVerifyController;
use App\Http\Controllers\Api\V1\Device\PolicyController;
use App\Http\Controllers\Api\V1\Device\RotateTokenController;
use App\Http\Controllers\Api\V1\Device\UnenrollController;
use App\Http\Controllers\Api\V1\Device\UsageController;
use Illuminate\Support\Facades\Route;

/*
| Device API, called by PaCoDaemon on a cloud-enrolled child Mac. Stateless
| (no session/CSRF), JSON only, bearer device token on everything but enroll.
| The wire types mirror PaCoShared's Codable structs; dates are ISO-8601
| without fractional seconds.
*/

Route::prefix('v1')->group(function () {
    Route::post('enroll', EnrollController::class)
        ->middleware('throttle:enroll')
        ->name('api.enroll');

    Route::prefix('device')->middleware(['auth.device', 'throttle:device'])->name('api.device.')->group(function () {
        Route::get('policy', PolicyController::class)->name('policy');
        Route::post('heartbeat', HeartbeatController::class)->name('heartbeat');
        Route::post('usage', UsageController::class)->middleware('throttle:device-usage')->name('usage');
        Route::post('extension-requests', [ExtensionRequestController::class, 'store'])->name('requests.store');
        Route::delete('extension-requests/{id}', [ExtensionRequestController::class, 'destroy'])->name('requests.destroy');
        Route::get('events', [EventsController::class, 'index'])->name('events');
        Route::post('events/ack', [EventsController::class, 'ack'])->name('events.ack');
        Route::post('pin/verify', PinVerifyController::class)->middleware('throttle:device-pin')->name('pin.verify');
        Route::post('unenroll', UnenrollController::class)->name('unenroll');
        Route::post('token/rotate', RotateTokenController::class)->middleware('throttle:device-usage')->name('token.rotate');
    });
});
