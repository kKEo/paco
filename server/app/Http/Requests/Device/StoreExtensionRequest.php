<?php

namespace App\Http\Requests\Device;

class StoreExtensionRequest extends DeviceRequest
{
    public function rules(): array
    {
        return [
            'requestId' => ['required', 'uuid'],
            'childDeviceName' => ['nullable', 'string', 'max:255'],
            'profileId' => ['nullable', 'uuid'],
            'requestedMinutes' => ['required', 'integer', 'min:1', 'max:'.config('paco.requests.max_minutes')],
            'reason' => ['nullable', 'string', 'max:500'],
        ];
    }
}
