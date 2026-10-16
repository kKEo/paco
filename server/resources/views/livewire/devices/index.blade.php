<div class="flex flex-col gap-6" wire:poll.15s>
    <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
            <flux:heading size="xl" level="1">Macs</flux:heading>
            <flux:text>Child Macs managed from here. Changes reach a Mac within seconds while it is online.</flux:text>
        </div>
        <flux:button variant="primary" icon="plus" :href="route('devices.enroll')" wire:navigate>Add a Mac</flux:button>
    </div>

    @if ($status)
        <flux:callout icon="check-circle" variant="success" :heading="$status" />
    @endif

    @forelse ($this->devices as $device)
        @php
            $s = $device->last_status ?? [];
            $tz = $device->time_zone ?: config('app.timezone');
            $manual = $device->activeManualOverride();
            $grant = isset($s['override']['grantedUntil']) ? \Illuminate\Support\Carbon::parse($s['override']['grantedUntil']) : null;
            $inSync = ($s['policyVersion'] ?? null) === $device->policy_version;
        @endphp
        <div class="rounded-xl border border-zinc-200 p-5 dark:border-zinc-700" wire:key="device-{{ $device->id }}">
            <div class="flex flex-wrap items-start justify-between gap-4">
                <div class="flex items-center gap-3">
                    <flux:icon.computer-desktop class="size-8 text-zinc-400" />
                    <div>
                        <flux:heading size="lg">{{ $device->name }}</flux:heading>
                        <flux:text class="text-xs">
                            @if ($device->isOnline())
                                <span class="text-green-600 dark:text-green-400">● Online</span>
                            @else
                                <span class="text-zinc-500">○ Offline</span> · last seen {{ $device->last_seen_at?->diffForHumans() ?? 'never' }}
                            @endif
                            · {{ $tz }} · PaCo {{ $device->daemon_version ?? '?' }}
                        </flux:text>
                    </div>
                </div>
                <div class="text-right">
                    @if (! array_key_exists('internetEnabled', $s))
                        <flux:badge>Waiting for first report</flux:badge>
                    @elseif ($s['internetEnabled'])
                        <flux:badge color="green" icon="wifi">Internet on</flux:badge>
                    @else
                        <flux:badge color="red" icon="no-symbol">Internet off</flux:badge>
                    @endif
                    @if (($s['action'] ?? null) === 'gracePeriod')
                        <flux:text class="mt-1 text-xs">Grace period: {{ \App\Support\Duration::short($s['graceRemainingSeconds'] ?? 0) }} left</flux:text>
                    @endif
                    @unless ($inSync)
                        <flux:text class="mt-1 text-xs text-amber-600">Latest rules not applied yet</flux:text>
                    @endunless
                </div>
            </div>

            <div class="mt-4 grid gap-4 md:grid-cols-2">
                <div class="space-y-2">
                    <flux:text class="font-medium">Right now</flux:text>
                    @if ($manual)
                        <flux:text>
                            Manually {{ $manual['enabled'] ? 'on' : 'off' }} until
                            {{ \Illuminate\Support\Carbon::parse($manual['until'])->setTimezone($tz)->format('H:i') }}
                        </flux:text>
                        <flux:button size="sm" wire:click="backToSchedule('{{ $device->id }}')">Back to schedule</flux:button>
                    @elseif ($grant && $grant->isFuture())
                        <flux:text>Extra time granted until {{ $grant->setTimezone($tz)->format('H:i') }}</flux:text>
                    @else
                        <flux:text>Following the schedules.</flux:text>
                    @endif

                    <div class="flex flex-wrap items-center gap-2 pt-1">
                        <flux:select size="sm" class="max-w-32" wire:model="minutes.{{ $device->id }}">
                            @foreach ([15, 30, 60, 120, 240] as $m)
                                <flux:select.option value="{{ $m }}">{{ $m }} min</flux:select.option>
                            @endforeach
                        </flux:select>
                        <flux:button size="sm" icon="wifi" wire:click="setInternet('{{ $device->id }}', true)">Turn on</flux:button>
                        <flux:button size="sm" icon="no-symbol" wire:click="setInternet('{{ $device->id }}', false)">Turn off</flux:button>
                    </div>
                </div>

                <div class="space-y-2">
                    <flux:text class="font-medium">Profile</flux:text>
                    <flux:select size="sm" wire:change="setProfile('{{ $device->id }}', $event.target.value)">
                        <flux:select.option value="" :selected="$device->active_profile_id === null">Every profile's rules</flux:select.option>
                        @foreach ($this->profiles as $profile)
                            <flux:select.option value="{{ $profile->id }}" :selected="$device->active_profile_id === $profile->id">{{ $profile->name }}</flux:select.option>
                        @endforeach
                    </flux:select>
                    <flux:text class="text-xs">The Mac enforces this profile's schedules and app rules, plus the ones for every profile.</flux:text>
                    <div class="flex gap-3 pt-1 text-sm">
                        <flux:link :href="route('screen-time', ['device' => $device->id])" wire:navigate>Screen time</flux:link>
                        <flux:link :href="route('activity', ['device' => $device->id])" wire:navigate>Activity</flux:link>
                    </div>
                </div>
            </div>

            <div class="mt-4 flex justify-end">
                @if ($confirmingUnenroll === $device->id)
                    <div class="flex flex-wrap items-center gap-2">
                        <flux:text class="text-sm">Remove {{ $device->name }}? It keeps its current rules but stops reporting.</flux:text>
                        <flux:button size="sm" wire:click="$set('confirmingUnenroll', null)">Cancel</flux:button>
                        <flux:button size="sm" variant="danger" wire:click="unenroll('{{ $device->id }}')">Remove</flux:button>
                    </div>
                @else
                    <flux:button size="sm" variant="ghost" icon="trash" wire:click="$set('confirmingUnenroll', '{{ $device->id }}')">Remove Mac</flux:button>
                @endif
            </div>
        </div>
    @empty
        <div class="rounded-xl border border-dashed border-zinc-300 p-10 text-center dark:border-zinc-700">
            <flux:heading>No Macs yet</flux:heading>
            <flux:text class="mt-2">Install PaCo on your child's Mac, choose “Set up as Child”, then “PaCo Cloud”.</flux:text>
            <flux:button class="mt-4" variant="primary" :href="route('devices.enroll')" wire:navigate>Add a Mac</flux:button>
        </div>
    @endforelse
</div>
