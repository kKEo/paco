<?php

namespace App\Http\Requests\Device;

class EventsRequest extends DeviceRequest
{
    public function rules(): array
    {
        return [
            'cursor' => ['nullable', 'integer', 'min:0'],
            'wait' => ['nullable', 'integer', 'min:0', 'max:60'],
        ];
    }
}
