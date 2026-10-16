<?php

namespace App\Console\Commands\Paco;

use App\Models\ChildDevice;
use App\Models\User;
use RuntimeException;

/** `--user` / device arguments accept an id, an email or name, or a unique id prefix. */
trait ResolvesModels
{
    protected function resolveUser(?string $value): User
    {
        $user = match (true) {
            $value === null || $value === '' => User::query()->orderBy('id')->first(),
            ctype_digit($value) => User::query()->find((int) $value),
            default => User::query()->where('email', $value)->first(),
        };

        if ($user === null) {
            throw new RuntimeException($value ? "No user '{$value}'." : 'No users yet: register in the web UI or run db:seed.');
        }

        return $user;
    }

    protected function resolveDevice(?string $value): ChildDevice
    {
        $query = ChildDevice::query()->whereNull('revoked_at');
        $matches = ($value === null || $value === '')
            ? $query->get()
            : $query->where(fn ($q) => $q->where('id', 'like', strtolower($value).'%')->orWhere('name', $value))->get();

        if ($matches->count() !== 1) {
            throw new RuntimeException($matches->isEmpty()
                ? 'No matching enrolled device (see paco:devices).'
                : 'Ambiguous device; pass more of its id (see paco:devices).');
        }

        return $matches->first();
    }
}
