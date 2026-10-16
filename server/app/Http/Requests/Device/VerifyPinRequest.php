<?php

namespace App\Http\Requests\Device;

class VerifyPinRequest extends DeviceRequest
{
    public function rules(): array
    {
        return [
            'nonce' => ['required', 'uuid'],
            'pin' => ['required', 'string', 'max:64'],
        ];
    }
}
