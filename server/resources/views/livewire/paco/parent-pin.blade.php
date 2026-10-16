<div class="flex max-w-xl flex-col gap-6">
    <div>
        <flux:heading size="xl" level="1">Parent PIN</flux:heading>
        <flux:text>Unlocks “Parent Access” on your child's Mac. The Mac checks it with this server; it never stores the PIN.</flux:text>
    </div>

    @if ($status)
        <flux:callout icon="check-circle" variant="success" :heading="$status" />
    @endif

    @if ($lockedUntil)
        <flux:callout icon="lock-closed" variant="warning" heading="Locked after 5 wrong tries, until {{ $lockedUntil->format('H:i') }} UTC.">
            <x-slot name="actions">
                <flux:button size="sm" wire:click="resetLockout">Unlock now</flux:button>
            </x-slot>
        </flux:callout>
    @endif

    <form wire:submit="save" class="space-y-4">
        <flux:input type="password" inputmode="numeric" maxlength="6" label="{{ $hasPin ? 'New PIN' : 'PIN' }} (6 digits)" wire:model="pin" autocomplete="new-password" class="max-w-48" />
        <flux:input type="password" inputmode="numeric" maxlength="6" label="Repeat PIN" wire:model="pin_confirmation" autocomplete="new-password" class="max-w-48" />
        <div class="flex gap-2">
            <flux:button type="submit" variant="primary">{{ $hasPin ? 'Change PIN' : 'Set PIN' }}</flux:button>
            @if ($hasPin)
                <flux:button variant="ghost" wire:click="remove" wire:confirm="Remove the PIN? Parent Access on your Macs stops working until you set a new one.">Remove PIN</flux:button>
            @endif
        </div>
    </form>
</div>
