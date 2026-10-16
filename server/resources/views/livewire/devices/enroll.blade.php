<div class="flex max-w-2xl flex-col gap-6" @if ($this->code && ! $this->enrolledDevice) wire:poll.3s @endif>
    <div>
        <flux:heading size="xl" level="1">Add a Mac</flux:heading>
        <flux:text>Connect your child's Mac to PaCo Cloud with a one-time code.</flux:text>
    </div>

    <ol class="list-decimal space-y-2 ps-5 text-sm text-zinc-600 dark:text-zinc-300">
        <li>Install PaCo on the child's Mac and open it.</li>
        <li>Choose <strong>Set up as Child</strong>, then <strong>PaCo Cloud, from a browser</strong>.
            On a Mac that is already set up, use <strong>Use PaCo Cloud</strong> at the bottom of the PaCo menu.</li>
        <li>Type the server address and the code below.</li>
    </ol>

    @if ($this->enrolledDevice)
        <flux:callout icon="check-circle" variant="success" heading="{{ $this->enrolledDevice->name }} is connected.">
            <x-slot name="actions">
                <flux:button size="sm" :href="route('devices.index')" wire:navigate>Go to Macs</flux:button>
            </x-slot>
        </flux:callout>
    @elseif ($this->code && $this->code->isUsable())
        <div class="rounded-xl border border-zinc-200 p-6 dark:border-zinc-700">
            <flux:text>Server address</flux:text>
            <div class="mb-4 font-mono text-lg">{{ $serverUrl }}</div>
            <flux:text>Code</flux:text>
            <div class="font-mono text-4xl tracking-widest" data-test="enrollment-code">{{ $this->code->displayCode() }}</div>
            <flux:text class="mt-3 text-xs">
                Valid until {{ $this->code->expires_at->format('H:i') }} UTC, for one Mac.
                @if ($this->code->activeProfile)
                    The Mac will follow the “{{ $this->code->activeProfile->name }}” profile.
                @endif
            </flux:text>
            <div class="mt-4 flex gap-2">
                <flux:button size="sm" wire:click="generate">New code</flux:button>
                <flux:button size="sm" variant="ghost" wire:click="cancel">Cancel</flux:button>
            </div>
        </div>
    @else
        @if ($this->code)
            <flux:callout icon="clock" variant="warning" heading="That code expired. Create a new one." />
        @endif
        <div class="flex flex-wrap items-end gap-3">
            <flux:select label="Profile for this Mac" wire:model="profileId" class="max-w-xs">
                <flux:select.option value="">Every profile's rules</flux:select.option>
                @foreach ($this->profiles as $profile)
                    <flux:select.option value="{{ $profile->id }}">{{ $profile->name }}</flux:select.option>
                @endforeach
            </flux:select>
            <flux:button variant="primary" wire:click="generate">Create code</flux:button>
        </div>
    @endif
</div>
