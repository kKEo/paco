<?php

use Livewire\Volt\Component;

new class extends Component {
    public function with(): array
    {
        return [
            'vapidKey' => config('webpush.vapid.public_key'),
            'subscriptions' => auth()->user()->pushSubscriptions()->count(),
        ];
    }
}; ?>

<section class="w-full">
    @include('partials.settings-heading')

    <x-settings.layout heading="Notifications" subheading="How you hear about requests for more time.">
        <div class="space-y-6">
            <div>
                <flux:heading size="sm">Email</flux:heading>
                <flux:text>Every request is mailed to {{ auth()->user()->email }}.</flux:text>
            </div>

            <div x-data="pacoPush(@js($vapidKey))" x-init="init()">
                <flux:heading size="sm">This browser</flux:heading>
                @if (! $vapidKey)
                    <flux:text>Browser notifications are not set up on this server (it needs VAPID keys, see the server README).</flux:text>
                @else
                    <flux:text x-show="!supported">This browser cannot show notifications from websites.</flux:text>
                    <div x-show="supported" class="mt-2 space-y-2">
                        <flux:text x-show="subscribed">Notifications are on for this browser.</flux:text>
                        <flux:text x-show="!subscribed">Get a notification here as soon as your child asks for more time.</flux:text>
                        <flux:text x-show="error" x-text="error" class="text-red-600"></flux:text>
                        <flux:button x-show="!subscribed" variant="primary" x-on:click="subscribe()" ::disabled="busy">Turn on</flux:button>
                        <flux:button x-show="subscribed" x-on:click="unsubscribe()" ::disabled="busy">Turn off</flux:button>
                    </div>
                    <flux:text class="mt-2 text-xs">{{ $subscriptions }} {{ Str::plural('browser', $subscriptions) }} receive notifications.</flux:text>
                @endif
            </div>
        </div>
    </x-settings.layout>
</section>

@script
<script>
    Alpine.data('pacoPush', (vapidKey) => ({
        supported: 'serviceWorker' in navigator && 'PushManager' in window,
        subscribed: false,
        busy: false,
        error: '',
        async init() {
            if (!this.supported || !vapidKey) return;
            const registration = await navigator.serviceWorker.register('/sw.js');
            this.subscribed = !!(await registration.pushManager.getSubscription());
        },
        async subscribe() {
            this.busy = true; this.error = '';
            try {
                if (await Notification.requestPermission() !== 'granted') {
                    this.error = 'Notifications are blocked for this site in the browser settings.';
                    return;
                }
                const registration = await navigator.serviceWorker.ready;
                const key = Uint8Array.from(atob(vapidKey.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));
                const subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
                await this.send('POST', subscription.toJSON());
                this.subscribed = true;
                $wire.$refresh();
            } catch (e) {
                this.error = 'Could not turn on notifications: ' + e.message;
            } finally {
                this.busy = false;
            }
        },
        async unsubscribe() {
            this.busy = true; this.error = '';
            const registration = await navigator.serviceWorker.ready;
            const subscription = await registration.pushManager.getSubscription();
            if (subscription) {
                await this.send('DELETE', { endpoint: subscription.endpoint });
                await subscription.unsubscribe();
            }
            this.subscribed = false;
            this.busy = false;
            $wire.$refresh();
        },
        send(method, body) {
            return fetch('{{ route('push-subscriptions') }}', {
                method,
                headers: {
                    'Content-Type': 'application/json',
                    'Accept': 'application/json',
                    'X-CSRF-TOKEN': document.querySelector('meta[name=csrf-token]')?.content ?? '{{ csrf_token() }}',
                },
                body: JSON.stringify(body),
            }).then((r) => { if (!r.ok) throw new Error('server answered ' + r.status); });
        },
    }));
</script>
@endscript
