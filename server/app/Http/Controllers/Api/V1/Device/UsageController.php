<?php

namespace App\Http\Controllers\Api\V1\Device;

use App\Http\Controllers\Controller;
use App\Http\Requests\Device\UsageRequest;
use App\Services\Usage\UsageIngest;
use Illuminate\Http\JsonResponse;

class UsageController extends Controller
{
    public function __invoke(UsageRequest $request, UsageIngest $ingest): JsonResponse
    {
        $dates = $ingest->ingest($request->device(), $request->validated('timeZone'), $request->validated('days'));

        return response()->json(['stored' => $dates], 202);
    }
}
