<div class="flex max-w-4xl flex-col gap-6" wire:poll.10s>
    <div>
        <flux:heading size="xl" level="1">Requests</flux:heading>
        <flux:text>Your child asks for more internet time from their Mac. Unanswered requests are denied after {{ config('paco.requests.expire_after_hours') }} hours.</flux:text>
    </div>

    @if ($status)
        <flux:callout icon="check-circle" variant="success" :heading="$status" />
    @endif

    <div class="space-y-3">
        @forelse ($this->pending as $request)
            @php($tz = $request->device->time_zone ?: config('app.timezone'))
            <div class="flex flex-wrap items-center justify-between gap-4 rounded-xl border border-amber-300 bg-amber-50 p-4 dark:border-amber-700 dark:bg-amber-950/30" wire:key="pending-{{ $request->id }}">
                <div>
                    <flux:heading>{{ $request->device->name }} asks for {{ $request->requested_minutes }} minutes</flux:heading>
                    <flux:text class="text-xs">
                        {{ $request->created_at->setTimezone($tz)->format('D H:i') }}
                        @if ($request->reason !== '') · “{{ $request->reason }}” @endif
                        @unless ($request->device->isOnline()) · the Mac is offline; it gets your answer when it is back @endunless
                    </flux:text>
                </div>
                <div class="flex items-center gap-2">
                    <flux:input type="number" size="sm" min="1" max="{{ config('paco.requests.max_minutes') }}" class="w-24"
                                wire:model="minutes.{{ $request->id }}" placeholder="{{ $request->requested_minutes }}" />
                    <flux:text class="text-sm">min</flux:text>
                    <flux:button size="sm" variant="primary" wire:click="approve('{{ $request->id }}')">Approve</flux:button>
                    <flux:button size="sm" wire:click="deny('{{ $request->id }}')">Deny</flux:button>
                </div>
                <flux:error name="minutes.{{ $request->id }}" />
            </div>
        @empty
            <div class="rounded-xl border border-dashed border-zinc-300 p-8 text-center dark:border-zinc-700">
                <flux:text>No requests waiting.</flux:text>
            </div>
        @endforelse
    </div>

    @if ($this->history->isNotEmpty())
        <div>
            <flux:heading>Earlier</flux:heading>
            <div class="mt-2 divide-y divide-zinc-200 rounded-xl border border-zinc-200 dark:divide-zinc-700 dark:border-zinc-700">
                @foreach ($this->history as $request)
                    @php($tz = $request->device->time_zone ?: config('app.timezone'))
                    <div class="flex flex-wrap items-center justify-between gap-2 p-3 text-sm" wire:key="past-{{ $request->id }}">
                        <div>
                            <span class="font-medium">{{ $request->device->name }}</span>
                            asked for {{ $request->requested_minutes }} min · {{ $request->created_at->setTimezone($tz)->format('D j M H:i') }}
                            @if ($request->reason !== '') · “{{ $request->reason }}” @endif
                        </div>
                        @switch($request->status)
                            @case('approved')
                                <flux:badge color="green" size="sm">Approved {{ $request->granted_minutes }} min, until {{ $request->granted_until?->setTimezone($tz)->format('H:i') }}</flux:badge>
                                @break
                            @case('denied')
                                <flux:badge color="red" size="sm">Denied</flux:badge>
                                @break
                            @case('expired')
                                <flux:badge size="sm">Expired</flux:badge>
                                @break
                            @default
                                <flux:badge size="sm">Withdrawn</flux:badge>
                        @endswitch
                    </div>
                @endforeach
            </div>
        </div>
    @endif
</div>
