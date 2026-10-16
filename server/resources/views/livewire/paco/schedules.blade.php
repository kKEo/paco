<div class="flex max-w-4xl flex-col gap-6">
    <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
            <flux:heading size="xl" level="1">Schedules</flux:heading>
            <flux:text>When the internet is off. The most restrictive active schedule wins; times are the Mac's local time.</flux:text>
        </div>
        @unless ($showForm)
            <flux:button variant="primary" icon="plus" wire:click="new">Add schedule</flux:button>
        @endunless
    </div>

    @if ($showForm)
        <form wire:submit="save" class="space-y-4 rounded-xl border border-zinc-200 p-5 dark:border-zinc-700">
            <flux:heading>{{ $editingId ? 'Edit schedule' : 'New schedule' }}</flux:heading>
            <flux:input label="Name" wire:model="label" placeholder="School nights" class="max-w-sm" />

            <flux:fieldset>
                <flux:legend>Days</flux:legend>
                <div class="flex flex-wrap gap-3">
                    @foreach (\App\Models\Schedule::DAY_NAMES as $value => $name)
                        <label class="flex items-center gap-1 text-sm">
                            <input type="checkbox" value="{{ $value }}" wire:model="days" class="rounded"> {{ $name }}
                        </label>
                    @endforeach
                </div>
                <flux:error name="days" />
            </flux:fieldset>

            <div class="flex flex-wrap gap-4">
                <flux:input type="time" label="Internet off at" wire:model.live="offTime" class="max-w-40" />
                <flux:input type="time" label="Back on at" wire:model.live="onTime" class="max-w-40" />
                <flux:input type="number" min="0" max="15" label="Warning (minutes)" wire:model="grace" class="max-w-40" />
            </div>
            @if ($offTime > $onTime)
                <flux:text class="text-xs">Runs past midnight: a window on Thursday blocks until Friday {{ $onTime }}, not Friday evening.</flux:text>
            @endif

            <div class="flex flex-wrap items-end gap-4">
                <flux:select label="Profile" wire:model="profileId" class="max-w-xs">
                    <flux:select.option value="">Every profile</flux:select.option>
                    @foreach ($this->profiles as $profile)
                        <flux:select.option value="{{ $profile->id }}">{{ $profile->name }}</flux:select.option>
                    @endforeach
                </flux:select>
                <flux:checkbox label="Active" wire:model="isActive" />
            </div>

            <div class="flex gap-2">
                <flux:button type="submit" variant="primary">Save</flux:button>
                <flux:button wire:click="cancel">Cancel</flux:button>
            </div>
        </form>
    @endif

    <div class="divide-y divide-zinc-200 rounded-xl border border-zinc-200 dark:divide-zinc-700 dark:border-zinc-700">
        @forelse ($this->schedules as $schedule)
            <div class="flex flex-wrap items-center justify-between gap-3 p-4" wire:key="schedule-{{ $schedule->id }}">
                <div>
                    <div class="flex items-center gap-2">
                        <flux:heading>{{ $schedule->label }}</flux:heading>
                        @unless ($schedule->is_active)
                            <flux:badge size="sm">Disabled</flux:badge>
                        @endunless
                    </div>
                    <flux:text class="text-xs">
                        {{ $schedule->daysLabel() }} · off {{ $schedule->windowLabel() }}{{ $schedule->isOvernight() ? ' (next day)' : '' }}
                        · {{ $schedule->profile?->name ?? 'every profile' }}
                        @if ($schedule->grace_period_minutes) · {{ $schedule->grace_period_minutes }} min warning @endif
                    </flux:text>
                </div>
                <div class="flex items-center gap-2">
                    @if ($confirmingDelete === $schedule->id)
                        <flux:text class="text-xs">Apps that follow it stay blocked.</flux:text>
                        <flux:button size="sm" wire:click="$set('confirmingDelete', null)">Cancel</flux:button>
                        <flux:button size="sm" variant="danger" wire:click="delete('{{ $schedule->id }}')">Delete</flux:button>
                    @else
                        <flux:button size="sm" variant="ghost" wire:click="toggle('{{ $schedule->id }}')">{{ $schedule->is_active ? 'Disable' : 'Enable' }}</flux:button>
                        <flux:button size="sm" variant="ghost" icon="pencil" wire:click="edit('{{ $schedule->id }}')">Edit</flux:button>
                        <flux:button size="sm" variant="ghost" icon="trash" wire:click="$set('confirmingDelete', '{{ $schedule->id }}')" />
                    @endif
                </div>
            </div>
        @empty
            <div class="p-6 text-center"><flux:text>No schedules: the internet is always on.</flux:text></div>
        @endforelse
    </div>
</div>
