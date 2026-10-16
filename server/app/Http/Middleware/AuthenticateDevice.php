<?php

namespace App\Http\Middleware;

use App\Services\Devices\DeviceTokens;
use Closure;
use Illuminate\Contracts\Auth\Middleware\AuthenticatesRequests;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Authenticates `/api/v1/device/*` with the device bearer token and makes the
 * ChildDevice the request's user. Refusals are JSON with a machine-readable
 * reason; on `device_revoked` the daemon forgets its cloud enrollment.
 *
 * Implementing AuthenticatesRequests puts it in Laravel's middleware priority
 * list ahead of ThrottleRequests. Without that, priority sorting runs the
 * throttles first, `$request->user()` is still null and every device would be
 * rate limited by IP instead of by device.
 */
class AuthenticateDevice implements AuthenticatesRequests
{
    public function __construct(private readonly DeviceTokens $tokens) {}

    public function handle(Request $request, Closure $next): Response
    {
        $result = $this->tokens->authenticate($request->bearerToken());
        if (is_string($result)) {
            return response()->json(['error' => $result], 401);
        }

        Auth::shouldUse('device');
        Auth::guard('device')->setUser($result);

        return $next($request);
    }
}
