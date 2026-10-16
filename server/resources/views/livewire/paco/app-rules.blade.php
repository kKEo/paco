<div class="flex max-w-4xl flex-col gap-6">
    <div class="flex flex-wrap items-center justify-between gap-4">
        <div>
            <flux:heading size="xl" level="1">App rules</flux:heading>
            <flux:text>Blocked apps close whenever they start. Apps that follow a schedule close while it has the internet off.</flux:text>
        </div>
        @unless ($showForm)
            <flux:button variant="primary" icon="plus" wire:click="new">Add rule</flux:button>
        @endunless
    </div>

    @if ($showForm)
        <form wire:submit="save" class="space-y-4 rounded-xl border border-zinc-200 p-5 dark:border-zinc-700">
            <flux:heading>{{ $editingId ? 'Edit rule' : 'New rule' }}</flux:heading>
            <div class="flex flex-wrap gap-4">
                <flux:input label="Bundle identifier" wire:model.live.debounce.400ms="bundleIdentifier" list="known-apps" placeholder="com.valvesoftware.steam" class="max-w-sm" />
                <flux:input label="App name" wire:model="appName" placeholder="Steam" class="max-w-xs" />
            </div>
            <datalist id="known-apps">
                @foreach ($this->knownApps as $app)
                    <option value="{{ $app['bundleIdentifier'] }}">{{ $app['appName'] }}</option>
                @endforeach
            </datalist>
            @if ($this->knownApps->isNotEmpty())
                <flux:text class="text-xs">Start typing to pick from apps your Macs have reported.</flux:text>
            @endif

            <div class="flex flex-wrap items-end gap-4">
                <flux:select label="Rule" wire:model.live="type" class="max-w-xs">
                    <flux:select.option value="blocked">Blocked</flux:select.option>
                    <flux:select.option value="scheduledOnly">Follows a schedule</flux:select.option>
                </flux:select>
                @if ($type === 'scheduledOnly')
                    <flux:select label="Schedule" wire:model="scheduleId" class="max-w-xs">
                        <flux:select.option value="">Choose…</flux:select.option>
                        @foreach ($this->schedules as $schedule)
                            <flux:select.option value="{{ $schedule->id }}">{{ $schedule->label }}</flux:select.option>
                        @endforeach
                    </flux:select>
                @endif
                <flux:select label="Profile" wire:model="profileId" class="max-w-xs">
                    <flux:select.option value="">Every profile</flux:select.option>
                    @foreach ($this->profiles as $profile)
                        <flux:select.option value="{{ $profile->id }}">{{ $profile->name }}</flux:select.option>
                    @endforeach
                </flux:select>
            </div>

            <div class="flex gap-2">
                <flux:button type="submit" variant="primary">Save</flux:button>
                <flux:button wire:click="cancel">Cancel</flux:button>
            </div>
        </form>
    @endif

    <div class="divide-y divide-zinc-200 rounded-xl border border-zinc-200 dark:divide-zinc-700 dark:border-zinc-700">
        @forelse ($this->rules as $rule)
            <div class="flex flex-wrap items-center justify-between gap-3 p-4" wire:key="rule-{{ $rule->id }}">
                <div>
                    <flux:heading>{{ $rule->app_name }}</flux:heading>
                    <flux:text class="text-xs">
                        <span class="font-mono">{{ $rule->bundle_identifier }}</span> ·
                        @if ($rule->isDangling())
                            <span class="text-red-600 dark:text-red-400">its schedule was deleted, so the app stays blocked</span>
                        @elseif ($rule->restriction_type === 'scheduledOnly')
                            follows “{{ $rule->allowedSchedule?->label }}”
                        @else
                            blocked
                        @endif
                        · {{ $rule->profile?->name ?? 'every profile' }}
                    </flux:text>
                </div>
                <div class="flex items-center gap-2">
                    @if ($confirmingDelete === $rule->id)
                        <flux:button size="sm" wire:click="$set('confirmingDelete', null)">Cancel</flux:button>
                        <flux:button size="sm" variant="danger" wire:click="delete('{{ $rule->id }}')">Delete</flux:button>
                    @else
                        <flux:button size="sm" variant="ghost" icon="pencil" wire:click="edit('{{ $rule->id }}')">Edit</flux:button>
                        <flux:button size="sm" variant="ghost" icon="trash" wire:click="$set('confirmingDelete', '{{ $rule->id }}')" />
                    @endif
                </div>
            </div>
        @empty
            <div class="p-6 text-center"><flux:text>No app rules.</flux:text></div>
        @endforelse
    </div>
</div>
