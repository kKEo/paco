<?php

namespace App\Http\Requests\Device;

use App\Models\ChildDevice;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Exceptions\HttpResponseException;

/** Base for device API requests: JSON 422s, the device is the user. */
abstract class DeviceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function device(): ChildDevice
    {
        return $this->user();
    }

    protected function failedValidation(Validator $validator): void
    {
        throw new HttpResponseException(response()->json([
            'error' => 'invalid_request',
            'fields' => $validator->errors()->toArray(),
        ], 422));
    }
}
