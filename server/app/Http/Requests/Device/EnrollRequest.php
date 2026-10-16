<?php

namespace App\Http\Requests\Device;

class EnrollRequest extends DeviceRequest
{
    public function rules(): array
    {
        return [
            'code' => ['required', 'string', 'max:20'],
            'deviceName' => ['required', 'string', 'max:100'],
            'daemonVersion' => ['nullable', 'string', 'max:40'],
            'timeZone' => ['nullable', 'timezone:all'],
        ];
    }
}
