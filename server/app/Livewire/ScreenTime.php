<?php

namespace App\Livewire;

use App\Models\ChildDevice;
use App\Models\UsageDay;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Screen time reported by a Mac: foreground time per app and internet-on time,
 * per day. Days are the child's local days, as the Mac counts them.
 */
#[Title('Screen time')]
class ScreenTime extends Component
{
    #[Url]
    public ?string $device = null;

    #[Url]
    public int $days = 7;

    public function mount(): void
    {
        if (! in_array($this->days, [7, 30], true)) {
            $this->days = 7;
        }
        if ($this->device === null || ! $this->devices->contains('id', $this->device)) {
            $this->device = $this->devices->first()?->id;
        }
    }

    #[Computed]
    public function devices(): Collection
    {
        return ChildDevice::query()->ownedBy(auth()->user())->orderBy('revoked_at')->orderBy('name')->get();
    }

    #[Computed]
    public function selected(): ?ChildDevice
    {
        return $this->devices->firstWhere('id', $this->device);
    }

    #[Computed]
    public function today(): ?UsageDay
    {
        return $this->selected?->usageDays()->where('local_date', $this->selected->localToday())->first();
    }

    /** One row per day of the range, oldest first; days without a report are zero. */
    #[Computed]
    public function range(): Collection
    {
        if (! $this->selected) {
            return collect();
        }
        $end = Carbon::parse($this->selected->localToday());
        $start = $end->copy()->subDays($this->days - 1);
        $reported = $this->selected->usageDays()
            ->whereBetween('local_date', [$start->toDateString(), $end->toDateString()])
            ->get()->keyBy(fn (UsageDay $d) => $d->local_date->toDateString());

        return collect(range(0, $this->days - 1))->map(function (int $offset) use ($start, $reported) {
            $date = $start->copy()->addDays($offset);
            $day = $reported->get($date->toDateString());

            return [
                'date' => $date,
                'apps' => $day?->app_seconds ?? 0,
                'internet' => $day?->internet_on_seconds ?? 0,
            ];
        });
    }

    /** Per-app totals over the range, longest first. */
    #[Computed]
    public function topApps(): Collection
    {
        if (! $this->selected) {
            return collect();
        }
        $from = Carbon::parse($this->selected->localToday())->subDays($this->days - 1)->toDateString();

        return $this->selected->usageDays()->where('local_date', '>=', $from)->get()
            ->flatMap(fn (UsageDay $d) => $d->app_entries ?? [])
            ->groupBy('bundleIdentifier')
            ->map(fn (Collection $entries) => [
                'appName' => $entries->first()['appName'],
                'bundleIdentifier' => $entries->first()['bundleIdentifier'],
                'duration' => $entries->sum('duration'),
                'launchCount' => $entries->sum('launchCount'),
            ])
            ->sortByDesc('duration')->values()->take(15);
    }

    public function render()
    {
        return view('livewire.paco.screen-time');
    }
}
