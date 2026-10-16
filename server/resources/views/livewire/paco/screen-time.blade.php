@php($fmt = fn ($s) => \App\Support\Duration::short($s))
<div class="flex max-w-5xl flex-col gap-6" wire:poll.60s>
    <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
            <flux:heading size="xl" level="1">Screen time</flux:heading>
            <flux:text>Time each app was in front, and how long the internet was on, as the Mac counted it.</flux:text>
        </div>
        @if ($this->devices->isNotEmpty())
            <div class="flex gap-3">
                <flux:select wire:model.live="device" class="min-w-56 max-w-xs">
                    @foreach ($this->devices as $d)
                        <flux:select.option value="{{ $d->id }}">{{ $d->name }}{{ $d->isRevoked() ? ' (removed)' : '' }}</flux:select.option>
                    @endforeach
                </flux:select>
                <flux:select wire:model.live="days" class="max-w-36">
                    <flux:select.option value="7">Last 7 days</flux:select.option>
                    <flux:select.option value="30">Last 30 days</flux:select.option>
                </flux:select>
            </div>
        @endif
    </div>

    @if (! $this->selected)
        <div class="rounded-xl border border-dashed border-zinc-300 p-10 text-center dark:border-zinc-700">
            <flux:text>Add a Mac to see its screen time.</flux:text>
            <flux:button class="mt-4" variant="primary" :href="route('devices.enroll')" wire:navigate>Add a Mac</flux:button>
        </div>
    @else
        <div class="grid gap-4 sm:grid-cols-3">
            <div class="rounded-xl border border-zinc-200 p-4 dark:border-zinc-700">
                <flux:text class="text-xs">Apps today</flux:text>
                <div class="text-2xl font-semibold">{{ $fmt($this->today?->app_seconds ?? 0) }}</div>
            </div>
            <div class="rounded-xl border border-zinc-200 p-4 dark:border-zinc-700">
                <flux:text class="text-xs">Internet on today</flux:text>
                <div class="text-2xl font-semibold">{{ $fmt($this->today?->internet_on_seconds ?? 0) }}</div>
            </div>
            <div class="rounded-xl border border-zinc-200 p-4 dark:border-zinc-700">
                <flux:text class="text-xs">Daily average, last {{ $days }} days</flux:text>
                <div class="text-2xl font-semibold">{{ $fmt($this->range->avg('apps')) }}</div>
            </div>
        </div>
        <flux:text class="text-xs">
            Today on the Mac is {{ \Illuminate\Support\Carbon::parse($this->selected->localToday())->format('l j F') }} ({{ $this->selected->time_zone ?? 'zone not reported yet' }}).
            @if ($this->today) Last report {{ $this->today->reported_at->diffForHumans() }}; the Mac reports every few minutes. @endif
        </flux:text>

        @php($max = max(1, $this->range->max('apps'), $this->range->max('internet')))
        <div class="rounded-xl border border-zinc-200 p-4 dark:border-zinc-700">
            <div class="mb-3 flex items-center gap-4 text-xs text-zinc-500">
                <span class="flex items-center gap-1"><span class="inline-block size-3 rounded-sm bg-sky-500"></span> Apps</span>
                <span class="flex items-center gap-1"><span class="inline-block size-3 rounded-sm bg-zinc-300 dark:bg-zinc-600"></span> Internet on</span>
            </div>
            <div class="flex h-48 items-end gap-1" role="img" aria-label="Daily screen time">
                @foreach ($this->range as $day)
                    <div class="flex h-full flex-1 flex-col items-center justify-end gap-1" title="{{ $day['date']->format('D j M') }}: apps {{ $fmt($day['apps']) }}, internet {{ $fmt($day['internet']) }}">
                        <div class="flex w-full flex-1 items-end justify-center gap-px">
                            <div class="w-1/2 rounded-t bg-sky-500" style="height: {{ round($day['apps'] / $max * 100, 1) }}%"></div>
                            <div class="w-1/2 rounded-t bg-zinc-300 dark:bg-zinc-600" style="height: {{ round($day['internet'] / $max * 100, 1) }}%"></div>
                        </div>
                        <span class="text-[10px] text-zinc-500">{{ $days === 7 ? $day['date']->format('D') : $day['date']->format('j') }}</span>
                    </div>
                @endforeach
            </div>
        </div>

        <div class="grid gap-6 lg:grid-cols-2">
            <div>
                <flux:heading>Today by app</flux:heading>
                <div class="mt-2 divide-y divide-zinc-200 rounded-xl border border-zinc-200 dark:divide-zinc-700 dark:border-zinc-700">
                    @forelse (collect($this->today?->sortedApps() ?? []) as $app)
                        <div class="flex items-center justify-between p-3 text-sm">
                            <span>{{ $app['appName'] }}</span>
                            <span class="tabular-nums">{{ $fmt($app['duration']) }}</span>
                        </div>
                    @empty
                        <div class="p-4 text-center"><flux:text>Nothing reported today yet.</flux:text></div>
                    @endforelse
                </div>
            </div>
            <div>
                <flux:heading>Last {{ $days }} days by app</flux:heading>
                <div class="mt-2 divide-y divide-zinc-200 rounded-xl border border-zinc-200 dark:divide-zinc-700 dark:border-zinc-700">
                    @forelse ($this->topApps as $app)
                        <div class="flex items-center justify-between p-3 text-sm">
                            <span>{{ $app['appName'] }} <span class="text-xs text-zinc-500">· opened {{ $app['launchCount'] }}×</span></span>
                            <span class="tabular-nums">{{ $fmt($app['duration']) }}</span>
                        </div>
                    @empty
                        <div class="p-4 text-center"><flux:text>No reports in this period.</flux:text></div>
                    @endforelse
                </div>
            </div>
        </div>
    @endif
</div>
