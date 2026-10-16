<?php

namespace App\Http\Controllers\Api\V1\Device;

use App\Http\Controllers\Controller;
use App\Http\Requests\Device\StoreExtensionRequest;
use App\Models\ChildDevice;
use App\Models\ExtensionRequest;
use App\Services\Requests\ExtensionRequestService;
use App\Support\Iso;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class ExtensionRequestController extends Controller
{
    public function store(StoreExtensionRequest $request, ExtensionRequestService $service): JsonResponse
    {
        $result = $service->submit($request->device(), $request->validated());
        if ($result === null) {
            return response()->json(['error' => 'request_id_conflict'], 409);
        }

        return response()->json($this->wire($result['request']), $result['created'] ? 201 : 200);
    }

    public function destroy(Request $request, string $id, ExtensionRequestService $service): JsonResponse
    {
        if (! Str::isUuid($id)) {
            return response()->json(['error' => 'not_found'], 404);
        }
        /** @var ChildDevice $device */
        $device = $request->user();
        $extension = ExtensionRequest::query()->where('device_id', $device->id)->find(Str::lower($id));
        if ($extension === null) {
            return response()->json(['error' => 'not_found'], 404);
        }
        $service->withdraw($device, $id);

        return response()->json($this->wire($extension->fresh()));
    }

    private function wire(ExtensionRequest $request): array
    {
        return [
            'requestId' => $request->id,
            'status' => $request->status,
            'requestedMinutes' => $request->requested_minutes,
            'grantedMinutes' => $request->granted_minutes,
            'grantedUntil' => Iso::format($request->granted_until),
            'createdAt' => Iso::format($request->created_at),
        ];
    }
}
