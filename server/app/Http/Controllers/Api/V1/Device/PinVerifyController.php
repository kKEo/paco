<?php

namespace App\Http\Controllers\Api\V1\Device;

use App\Http\Controllers\Controller;
use App\Http\Requests\Device\VerifyPinRequest;
use App\Services\Security\PinVerifier;
use App\Support\Iso;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Str;

/**
 * "Parent Access" on a cloud child. The reply is exactly a PINVerifyResult:
 * nonce, outcome and lockedOutUntil. Nothing about the PIN itself is returned.
 */
class PinVerifyController extends Controller
{
    public function __invoke(VerifyPinRequest $request, PinVerifier $pins): JsonResponse
    {
        $result = $pins->verify($request->device()->user, $request->validated('pin'));

        return response()->json([
            'nonce' => Str::lower($request->validated('nonce')),
            'outcome' => $result['outcome'],
            'lockedOutUntil' => Iso::format($result['lockedOutUntil']),
        ]);
    }
}
