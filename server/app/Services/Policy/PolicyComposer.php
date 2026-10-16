<?php

namespace App\Services\Policy;

use App\Models\AppRestriction;
use App\Models\Schedule;
use App\Models\User;

/**
 * Builds the `PolicyTransfer` a device receives: every schedule (inactive ones
 * too, so "Follows Schedule" rules can resolve them) and every app rule of the
 * parent, unfiltered. The daemon itself filters by its active profile, exactly
 * as it does for a policy pushed from a parent Mac by SyncManager.
 */
final class PolicyComposer
{
    /** @return array{schedules: list<array>, restrictions: list<array>} */
    public function compose(User $user): array
    {
        $schedules = Schedule::query()->ownedBy($user)
            ->orderBy('created_at')->orderBy('id')->get()
            ->map->toTransfer()->values()->all();

        $restrictions = AppRestriction::query()->ownedBy($user)
            ->orderBy('created_at')->orderBy('id')->get()
            ->map->toTransfer()->values()->all();

        return ['schedules' => $schedules, 'restrictions' => $restrictions];
    }
}
