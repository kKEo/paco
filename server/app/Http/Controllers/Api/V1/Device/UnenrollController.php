<?php

namespace App\Http\Controllers\Api\V1\Device;

use App\Http\Controllers\Controller;
use App\Models\ChildDevice;
use App\Services\Devices\DeviceCommands;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The Mac disconnected itself (from "Parent Access" on the child, after a PIN
 * check). The token dies; the parent's dashboard shows the device unenrolled.
 */
class UnenrollController extends Controller
{
    public function __invoke(Request $request, DeviceCommands $commands): JsonResponse
    {
        /** @var ChildDevice $device */
        $device = $request->user();
        $commands->revoke($device);

        return response()->json(['unenrolled' => true]);
    }
}
