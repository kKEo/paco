<?php

namespace App\Http\Requests\Device;

class HeartbeatRequest extends DeviceRequest
{
    public function rules(): array
    {
        return [
            'policyVersion' => ['required', 'integer', 'min:0'],
            'daemonVersion' => ['nullable', 'string', 'max:40'],
            'timeZone' => ['nullable', 'timezone:all'],
            'status' => ['required', 'array'],
            'status.internetEnabled' => ['required', 'boolean'],
            'status.action' => ['required', 'string', 'in:allowed,blocked,gracePeriod'],
            'status.graceRemainingSeconds' => ['nullable', 'integer', 'min:0'],
            'status.activeProfileId' => ['nullable', 'uuid'],
            'status.manualOverride' => ['nullable', 'array'],
            'status.manualOverride.enabled' => ['required_with:status.manualOverride', 'boolean'],
            'status.manualOverride.until' => ['required_with:status.manualOverride', 'date'],
            'status.override' => ['nullable', 'array'],
            'status.override.requestId' => ['required_with:status.override', 'uuid'],
            'status.override.grantedUntil' => ['required_with:status.override', 'date'],
        ];
    }
}
