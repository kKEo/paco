<?php

namespace App\Providers;

use App\Models\AppRestriction;
use App\Models\Profile;
use App\Models\Schedule;
use App\Observers\PolicySourceObserver;
use App\Services\Devices\DeviceTokens;
use App\Services\Devices\EventWaiter;
use App\Services\Devices\PollingEventWaiter;
use App\Services\Devices\RedisEventWaiter;
use App\Services\Policy\PolicyPublisher;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;
use Laravel\Fortify\Fortify;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        // Fortify is used for its two-factor actions only; login and the
        // challenge are Volt pages (routes/auth.php).
        Fortify::ignoreRoutes();

        // Per request (also under Octane): holds the deferred-publish state.
        $this->app->scoped(PolicyPublisher::class);
        $this->app->bind(EventWaiter::class, fn ($app) => config('paco.longpoll.waiter') === 'redis'
            ? new RedisEventWaiter($app['redis'], config('paco.longpoll.redis_connection'))
            : new PollingEventWaiter);
    }

    public function boot(): void
    {
        if ($this->app->environment('production')) {
            URL::forceScheme('https');
        }

        Auth::viaRequest('device-token', function (Request $request) {
            $result = app(DeviceTokens::class)->authenticate($request->bearerToken());

            return is_string($result) ? null : $result;
        });

        Schedule::observe(PolicySourceObserver::class);
        AppRestriction::observe(PolicySourceObserver::class);
        Profile::observe(PolicySourceObserver::class);

        $this->configureRateLimiting();
    }

    private function configureRateLimiting(): void
    {
        $deviceKey = fn (Request $request) => 'device:'.($request->user()?->getAuthIdentifier() ?? $request->ip());

        // Heartbeat (2/min) + long-poll (~3/min) leave plenty of headroom.
        RateLimiter::for('device', fn (Request $request) => Limit::perMinute(120)->by($deviceKey($request)));
        RateLimiter::for('device-usage', fn (Request $request) => Limit::perMinute(30)->by($deviceKey($request)));
        // The PIN lockout (5 / 300 s) is the real brute-force guard; this caps load.
        RateLimiter::for('device-pin', fn (Request $request) => Limit::perMinute(10)->by($deviceKey($request)));
        RateLimiter::for('enroll', fn (Request $request) => Limit::perMinute(10)->by('enroll:'.$request->ip()));
    }
}
