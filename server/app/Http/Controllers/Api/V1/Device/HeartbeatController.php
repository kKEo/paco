<?php

namespace App\Http\Controllers\Api\V1\Device;

use App\Http\Controllers\Controller;
use App\Http\Requests\Device\HeartbeatRequest;
use App\Models\DeviceEvent;
use App\Support\Iso;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Carbon;

/**
 * Every 30 s. Records what the device is enforcing (for the dashboard) and
 * tells it whether its policy is stale: the safety net for a missed event.
 */
class HeartbeatController extends Controller
{
    public function __invoke(HeartbeatRequest $request): JsonResponse
    {
        $device = $request->device();
        $device->forceFill(array_filter([
            'last_seen_at' => Carbon::now(),
            'last_status' => $request->validated('status') + ['policyVersion' => (int) $request->validated('policyVersion')],
            'daemon_version' => $request->validated('daemonVersion'),
            'time_zone' => $request->validated('timeZone'),
        ], fn ($v) => $v !== null))->save();

        $pending = DeviceEvent::query()->where('device_id', $device->id)->whereNull('acked_at')->count();

        return response()->json([
            'serverTime' => Iso::now(),
            'policyVersion' => $device->policy_version,
            'policyStale' => (int) $request->validated('policyVersion') < $device->policy_version,
            'pendingEvents' => $pending,
        ]);
    }
}
