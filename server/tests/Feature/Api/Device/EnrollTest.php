<?php

use App\Models\ChildDevice;
use App\Models\EnrollmentCode;
use App\Models\Profile;
use App\Models\User;
use App\Services\Devices\EnrollmentService;
use Illuminate\Support\Carbon;

function enrollPayload(string $code, array $extra = []): array
{
    return $extra + ['code' => $code, 'deviceName' => "Alex's MacBook", 'daemonVersion' => '1.1.0', 'timeZone' => 'Europe/Warsaw'];
}

it('enrolls a device with a valid code and returns a working token', function () {
    $user = User::factory()->create();
    $code = app(EnrollmentService::class)->createCode($user);

    $response = $this->postJson('/api/v1/enroll', enrollPayload($code->code))
        ->assertCreated()
        ->assertJsonStructure(['deviceId', 'deviceName', 'deviceToken', 'policyVersion', 'eventCursor', 'serverTime']);

    expect($response->json('deviceToken'))->toStartWith('pcd_'.$response->json('deviceId').'.')
        ->and($response->json('deviceId'))->toBe(strtolower($response->json('deviceId')))
        ->and($response->json('serverTime'))->toBeSwiftIsoDate()
        ->and($response->json('eventCursor'))->toBe(0);

    $device = ChildDevice::query()->sole();
    expect($device->user_id)->toBe($user->id)
        ->and($device->name)->toBe("Alex's MacBook")
        ->and($device->time_zone)->toBe('Europe/Warsaw')
        ->and($device->device_token_hash)->not->toContain('.');

    $this->getJson('/api/v1/device/policy', bearer($response->json('deviceToken')))->assertOk();
});

it('pre-assigns the profile chosen when the code was created', function () {
    $user = User::factory()->create();
    $profile = Profile::factory()->for($user)->create();
    $code = app(EnrollmentService::class)->createCode($user, $profile);

    $this->postJson('/api/v1/enroll', enrollPayload($code->code))->assertCreated();

    expect(ChildDevice::query()->sole()->active_profile_id)->toBe($profile->id);
});

it('accepts codes typed with spaces, dashes, lower case and look-alike letters', function () {
    $user = User::factory()->create();
    $code = app(EnrollmentService::class)->createCode($user);
    $code->forceFill(['code' => '01AB2CD1'])->save();

    $this->postJson('/api/v1/enroll', enrollPayload('oiab-2cd l'))->assertCreated();
});

it('refuses an unknown code', function () {
    $this->postJson('/api/v1/enroll', enrollPayload('ZZZZZZZZ'))
        ->assertStatus(410)->assertExactJson(['error' => 'invalid_code']);
});

it('refuses an expired code', function () {
    $code = app(EnrollmentService::class)->createCode(User::factory()->create());
    Carbon::setTestNow(Carbon::now()->addMinutes(config('paco.enrollment.code_ttl_minutes') + 1));

    $this->postJson('/api/v1/enroll', enrollPayload($code->code))->assertStatus(410);
    expect(ChildDevice::count())->toBe(0);
});

it('refuses a code that was already used', function () {
    $code = app(EnrollmentService::class)->createCode(User::factory()->create());

    $this->postJson('/api/v1/enroll', enrollPayload($code->code))->assertCreated();
    $this->postJson('/api/v1/enroll', enrollPayload($code->code))->assertStatus(410);

    expect(ChildDevice::count())->toBe(1)
        ->and(EnrollmentCode::query()->sole()->used_by_device_id)->toBe(ChildDevice::query()->sole()->id);
});

it('validates the body', function () {
    $this->postJson('/api/v1/enroll', ['code' => 'ABCD1234', 'timeZone' => 'Mars/Olympus'])
        ->assertStatus(422)
        ->assertJsonPath('error', 'invalid_request')
        ->assertJsonStructure(['fields' => ['deviceName', 'timeZone']]);
});

it('rate limits enrollment attempts per IP', function () {
    foreach (range(1, 10) as $_) {
        $this->postJson('/api/v1/enroll', enrollPayload('ZZZZZZZZ'))->assertStatus(410);
    }
    $this->postJson('/api/v1/enroll', enrollPayload('ZZZZZZZZ'))->assertStatus(429);
});
