<?php

namespace App\Http\Controllers\Api\V1\Device;

use App\Http\Controllers\Controller;
use App\Http\Requests\Device\EnrollRequest;
use App\Services\Devices\DeviceEventOutbox;
use App\Services\Devices\EnrollmentService;
use App\Support\Iso;
use Illuminate\Http\JsonResponse;

class EnrollController extends Controller
{
    public function __invoke(EnrollRequest $request, EnrollmentService $enrollment, DeviceEventOutbox $outbox): JsonResponse
    {
        $result = $enrollment->enroll(
            $request->string('code'),
            $request->string('deviceName'),
            $request->input('daemonVersion'),
            $request->input('timeZone'),
        );

        if ($result === null) {
            return response()->json(['error' => 'invalid_code'], 410);
        }

        $device = $result['device'];

        return response()->json([
            'deviceId' => $device->id,
            'deviceName' => $device->name,
            'deviceToken' => $result['token'],
            'policyVersion' => $device->policy_version,
            'eventCursor' => $outbox->latestId($device),
            'serverTime' => Iso::now(),
        ], 201);
    }
}
