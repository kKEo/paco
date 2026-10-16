<?php

namespace App\Http\Controllers\Api\V1\Device;

use App\Http\Controllers\Controller;
use App\Models\ChildDevice;
use App\Services\Devices\DeviceTokens;
use App\Support\Iso;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** The daemon rotates its token every 30 days (CloudCredentials.needsTokenRotation). */
class RotateTokenController extends Controller
{
    public function __invoke(Request $request, DeviceTokens $tokens): JsonResponse
    {
        /** @var ChildDevice $device */
        $device = $request->user();

        return response()->json([
            'deviceToken' => $tokens->rotate($device),
            'rotatedAt' => Iso::format($device->token_rotated_at),
        ]);
    }
}
