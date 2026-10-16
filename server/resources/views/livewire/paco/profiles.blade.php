<div class="flex max-w-3xl flex-col gap-6">
    <div>
        <flux:heading size="xl" level="1">Profiles</flux:heading>
        <flux:text>One per child. A Mac follows one profile's schedules and app rules, plus the ones set for every profile.</flux:text>
    </div>

    <form wire:submit="create" class="flex items-end gap-3">
        <flux:input label="New profile" wire:model="name" placeholder="Child's name" class="max-w-xs" />
        <flux:button type="submit" variant="primary">Add</flux:button>
    </form>

    <div class="divide-y divide-zinc-200 rounded-xl border border-zinc-200 dark:divide-zinc-700 dark:border-zinc-700">
        @forelse ($this->profiles as $profile)
            <div class="flex flex-wrap items-center justify-between gap-3 p-4" wire:key="profile-{{ $profile->id }}">
                @if ($editingId === $profile->id)
                    <form wire:submit="save" class="flex items-center gap-2">
                        <flux:input wire:model="editingName" size="sm" />
                        <flux:button size="sm" type="submit" variant="primary">Save</flux:button>
                        <flux:button size="sm" wire:click="$set('editingId', null)">Cancel</flux:button>
                    </form>
                @else
                    <div>
                        <flux:heading>{{ $profile->name }}</flux:heading>
                        <flux:text class="text-xs">
                            {{ $profile->schedules_count }} {{ Str::plural('schedule', $profile->schedules_count) }},
                            {{ $profile->app_restrictions_count }} app {{ Str::plural('rule', $profile->app_restrictions_count) }}
                            @if ($macs = $this->devicesByProfile->get($profile->id))
                                · followed by {{ $macs->pluck('name')->join(', ') }}
                            @endif
                        </flux:text>
                    </div>
                    <div class="flex items-center gap-2">
                        @if ($confirmingDelete === $profile->id)
                            <flux:text class="text-xs">Its rules will apply to every profile.</flux:text>
                            <flux:button size="sm" wire:click="$set('confirmingDelete', null)">Cancel</flux:button>
                            <flux:button size="sm" variant="danger" wire:click="delete('{{ $profile->id }}')">Delete</flux:button>
                        @else
                            <flux:button size="sm" variant="ghost" icon="pencil" wire:click="edit('{{ $profile->id }}')">Rename</flux:button>
                            <flux:button size="sm" variant="ghost" icon="trash" wire:click="$set('confirmingDelete', '{{ $profile->id }}')">Delete</flux:button>
                        @endif
                    </div>
                @endif
            </div>
        @empty
            <div class="p-6 text-center"><flux:text>No profiles yet. Without one, every rule applies to every Mac.</flux:text></div>
        @endforelse
    </div>
</div>
