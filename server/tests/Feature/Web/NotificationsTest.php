<?php

use App\Models\ExtensionRequest;
use App\Models\User;
use App\Notifications\ExtensionRequested;
use NotificationChannels\WebPush\WebPushChannel;

function subscription(string $endpoint = 'https://push.example.com/send/abc'): array
{
    return ['endpoint' => $endpoint, 'keys' => ['p256dh' => 'BPublicKey', 'auth' => 'AuthSecret'], 'contentEncoding' => 'aes128gcm'];
}

it('stores and removes this browser’s subscription', function () {
    $user = User::factory()->create();

    $this->actingAs($user)->postJson('/push-subscriptions', subscription())->assertCreated();
    expect($user->pushSubscriptions()->sole()->endpoint)->toBe('https://push.example.com/send/abc');

    $this->actingAs($user)->deleteJson('/push-subscriptions', ['endpoint' => 'https://push.example.com/send/abc'])->assertOk();
    expect($user->pushSubscriptions()->count())->toBe(0);
});

it('refuses non-https endpoints and guests', function () {
    $this->postJson('/push-subscriptions', subscription())->assertUnauthorized();
    $this->actingAs(User::factory()->create())
        ->postJson('/push-subscriptions', subscription('http://push.example.com/x'))->assertStatus(422);
});

it('pushes a request to subscribed browsers, mails everyone', function () {
    config(['webpush.vapid.public_key' => 'BTestKey']);
    [$device] = enrolledDevice();
    $request = ExtensionRequest::query()->create([
        'id' => '9a7d0e2c-5b7d-4c3e-9a10-2b3c4d5e6f70', 'user_id' => $device->user_id, 'device_id' => $device->id,
        'requested_minutes' => 30, 'reason' => 'Essay', 'status' => 'pending',
    ]);
    $notification = new ExtensionRequested($request);
    $parent = $device->user;

    expect($notification->via($parent))->toBe(['mail']);

    $parent->updatePushSubscription('https://push.example.com/send/abc', 'BPublicKey', 'AuthSecret');
    expect($notification->via($parent))->toBe(['mail', WebPushChannel::class]);

    $push = $notification->toWebPush($parent, $notification)->toArray();
    expect($push['title'])->toBe("Alex's MacBook asks for 30 more minutes")
        ->and($push['body'])->toBe('Reason: Essay')
        ->and($push['data']['url'])->toBe(route('requests.index'));
});

it('does not push when the server has no VAPID keys', function () {
    config(['webpush.vapid.public_key' => null]);
    [$device] = enrolledDevice();
    $device->user->updatePushSubscription('https://push.example.com/send/abc', 'BPublicKey', 'AuthSecret');
    $request = ExtensionRequest::query()->create([
        'id' => '9a7d0e2c-5b7d-4c3e-9a10-2b3c4d5e6f70', 'user_id' => $device->user_id, 'device_id' => $device->id,
        'requested_minutes' => 30, 'status' => 'pending',
    ]);

    expect((new ExtensionRequested($request))->via($device->user))->toBe(['mail']);
});

it('renders the notifications settings page', function () {
    $this->actingAs(User::factory()->create())->get('/settings/notifications')->assertOk()->assertSee('not set up on this server');
    config(['webpush.vapid.public_key' => 'BTestKey']);
    $this->actingAs(User::factory()->create())->get('/settings/notifications')->assertOk()->assertSee('pacoPush');
});
