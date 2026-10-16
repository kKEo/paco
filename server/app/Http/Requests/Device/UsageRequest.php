<?php

namespace App\Http\Requests\Device;

class UsageRequest extends DeviceRequest
{
    public function rules(): array
    {
        return [
            'timeZone' => ['required', 'timezone:all'],
            'days' => ['required', 'array', 'min:1', 'max:7'],
            'days.*.date' => ['required', 'date'],
            'days.*.profileId' => ['nullable', 'uuid'],
            'days.*.internetOnDuration' => ['required', 'numeric', 'min:0', 'max:86400'],
            'days.*.appUsage' => ['present', 'array', 'max:500'],
            'days.*.appUsage.*.bundleIdentifier' => ['required', 'string', 'max:255'],
            'days.*.appUsage.*.appName' => ['required', 'string', 'max:255'],
            'days.*.appUsage.*.duration' => ['required', 'numeric', 'min:0', 'max:86400'],
            'days.*.appUsage.*.launchCount' => ['required', 'integer', 'min:0'],
        ];
    }
}
