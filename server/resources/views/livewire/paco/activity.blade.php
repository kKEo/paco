<div class="flex max-w-4xl flex-col gap-6" wire:poll.15s>
    <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
            <flux:heading size="xl" level="1">Activity</flux:heading>
            <flux:text>Everything sent to your Macs, newest first, and whether each Mac has received it.</flux:text>
        </div>
        <flux:select wire:model.live="device" class="min-w-56 max-w-xs">
            <flux:select.option value="">All Macs</flux:select.option>
            @foreach ($this->devices as $d)
                <flux:select.option value="{{ $d->id }}">{{ $d->name }}</flux:select.option>
            @endforeach
        </flux:select>
    </div>

    <div class="divide-y divide-zinc-200 rounded-xl border border-zinc-200 dark:divide-zinc-700 dark:border-zinc-700">
        @forelse ($this->events as $event)
            <div class="flex flex-wrap items-center justify-between gap-2 p-3 text-sm" wire:key="event-{{ $event->id }}">
                <div>
                    <span class="font-medium">{{ \App\Livewire\Activity::describe($event) }}</span>
                    <span class="text-zinc-500">· {{ $event->device->name }} · {{ $event->actor?->name ?? 'automatic' }}</span>
                </div>
                <div class="flex items-center gap-2 text-xs text-zinc-500">
                    <span title="{{ $event->created_at }}">{{ $event->created_at->diffForHumans() }}</span>
                    @if ($event->acked_at)
                        <flux:badge size="sm" color="green">Applied</flux:badge>
                    @elseif ($event->delivered_at)
                        <flux:badge size="sm" color="sky">Delivered</flux:badge>
                    @else
                        <flux:badge size="sm" color="amber">Waiting for the Mac</flux:badge>
                    @endif
                </div>
            </div>
        @empty
            <div class="p-6 text-center"><flux:text>Nothing sent yet.</flux:text></div>
        @endforelse
    </div>
</div>
