@php($fmt = fn ($s) => \App\Support\Duration::short($s))
<div class="flex max-w-5xl flex-col gap-6" wire:poll.30s>
    <div>
        <flux:heading size="xl" level="1">Overview</flux:heading>
        <flux:text>Your child's Macs at a glance.</flux:text>
    </div>

    @if ($this->pendingRequests > 0)
        <flux:callout icon="clock" variant="warning" heading="{{ $this->pendingRequests }} {{ Str::plural('request', $this->pendingRequests) }} for more time">
            <x-slot name="actions">
                <flux:button size="sm" :href="route('requests.index')" wire:navigate>Answer</flux:button>
            </x-slot>
        </flux:callout>
    @endif

    @unless ($hasPin)
        <flux:callout icon="key" heading="Set a parent PIN">
            <flux:callout.text>It unlocks “Parent Access” on your child's Mac. Only this server knows it.</flux:callout.text>
            <x-slot name="actions">
                <flux:button size="sm" :href="route('settings.pin')" wire:navigate>Set PIN</flux:button>
            </x-slot>
        </flux:callout>
    @endunless

    <div class="grid gap-4 md:grid-cols-2">
        @forelse ($this->devices as $device)
            @php($s = $device->last_status ?? [])
            <a href="{{ route('screen-time', ['device' => $device->id]) }}" wire:navigate
               class="block rounded-xl border border-zinc-200 p-5 transition hover:border-zinc-400 dark:border-zinc-700 dark:hover:border-zinc-500">
                <div class="flex items-start justify-between gap-2">
                    <div>
                        <flux:heading size="lg">{{ $device->name }}</flux:heading>
                        <flux:text class="text-xs">{{ $device->isOnline() ? 'Online' : 'Offline · last seen '.($device->last_seen_at?->diffForHumans() ?? 'never') }}</flux:text>
                    </div>
                    @if (array_key_exists('internetEnabled', $s))
                        <flux:badge :color="$s['internetEnabled'] ? 'green' : 'red'">Internet {{ $s['internetEnabled'] ? 'on' : 'off' }}</flux:badge>
                    @endif
                </div>
                <div class="mt-4 flex gap-8">
                    <div>
                        <flux:text class="text-xs">Apps today</flux:text>
                        <div class="text-xl font-semibold">{{ $fmt($device->today?->app_seconds ?? 0) }}</div>
                    </div>
                    <div>
                        <flux:text class="text-xs">Internet on today</flux:text>
                        <div class="text-xl font-semibold">{{ $fmt($device->today?->internet_on_seconds ?? 0) }}</div>
                    </div>
                </div>
                @if ($top = collect($device->today?->sortedApps() ?? [])->take(3))
                    <flux:text class="mt-3 text-xs">{{ $top->map(fn ($a) => $a['appName'].' '.$fmt($a['duration']))->join(' · ') }}</flux:text>
                @endif
            </a>
        @empty
            <div class="rounded-xl border border-dashed border-zinc-300 p-10 text-center md:col-span-2 dark:border-zinc-700">
                <flux:heading>Add your child's Mac</flux:heading>
                <flux:text class="mt-2">Then set schedules and app rules, answer requests for more time and follow screen time from here.</flux:text>
                <flux:button class="mt-4" variant="primary" :href="route('devices.enroll')" wire:navigate>Add a Mac</flux:button>
            </div>
        @endforelse
    </div>
</div>
