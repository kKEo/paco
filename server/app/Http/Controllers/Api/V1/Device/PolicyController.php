<?php

namespace App\Http\Controllers\Api\V1\Device;

use App\Http\Controllers\Controller;
use App\Models\ChildDevice;
use App\Services\Policy\PolicyComposer;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * The device's policy envelope. `policy` is exactly a `PolicyTransfer`; the
 * daemon applies it with `updatePolicy` and `activeProfileId` with
 * `setActiveProfile`. `manualOverride` is informational (the toggle itself
 * arrives as an event).
 */
class PolicyController extends Controller
{
    public function __invoke(Request $request, PolicyComposer $composer): JsonResponse|Response
    {
        /** @var ChildDevice $device */
        $device = $request->user();
        $etag = '"v'.$device->policy_version.'"';

        $ifNoneMatch = array_map('trim', explode(',', (string) $request->header('If-None-Match')));
        if (in_array($etag, $ifNoneMatch, true) || in_array('W/'.$etag, $ifNoneMatch, true)) {
            return response('', 304)->setEtag('v'.$device->policy_version);
        }

        return response()->json([
            'version' => $device->policy_version,
            'activeProfileId' => $device->active_profile_id,
            'manualOverride' => $device->activeManualOverride(),
            'policy' => $composer->compose($device->user),
        ])->setEtag('v'.$device->policy_version);
    }
}
