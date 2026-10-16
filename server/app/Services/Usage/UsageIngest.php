<?php

namespace App\Services\Usage;

use App\Models\ChildDevice;
use App\Models\UsageDay;
use Illuminate\Support\Carbon;

/**
 * Stores UsageTransfer snapshots. Each snapshot is the running total for one
 * day, so the newest one for a (device, local date) replaces the row.
 *
 * The day is the *child's* local day: `date` is the start of that day on the
 * Mac, converted into the zone the device reports. The server's own zone is
 * never used for bucketing.
 */
final class UsageIngest
{
    /**
     * @param  list<array{date: string, profileId?: string|null, internetOnDuration: int|float, appUsage: list<array>}>  $days
     * @return list<string> the local dates stored
     */
    public function ingest(ChildDevice $device, string $timeZone, array $days): array
    {
        $stored = [];
        foreach ($days as $day) {
            $localDate = Carbon::parse($day['date'])->setTimezone($timeZone)->toDateString();
            $entries = collect($day['appUsage'] ?? [])->map(fn (array $e) => [
                'bundleIdentifier' => (string) $e['bundleIdentifier'],
                'appName' => (string) $e['appName'],
                'duration' => (int) round((float) $e['duration']),
                'launchCount' => (int) $e['launchCount'],
            ])->values()->all();

            UsageDay::query()->updateOrCreate(
                ['device_id' => $device->getKey(), 'local_date' => $localDate],
                [
                    'profile_id' => $day['profileId'] ?? null,
                    'internet_on_seconds' => (int) round((float) $day['internetOnDuration']),
                    'app_seconds' => array_sum(array_column($entries, 'duration')),
                    'app_entries' => $entries,
                    'reported_at' => Carbon::now(),
                ],
            );
            $stored[] = $localDate;
        }

        if ($device->time_zone !== $timeZone) {
            $device->forceFill(['time_zone' => $timeZone])->save();
        }

        return $stored;
    }
}
