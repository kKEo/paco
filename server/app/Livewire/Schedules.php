<?php

namespace App\Livewire;

use App\Models\Profile;
use App\Models\Schedule;
use Illuminate\Support\Collection;
use Illuminate\Validation\Rule;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Title;
use Livewire\Component;

/**
 * Internet schedules, the same model as the Mac's Schedules tab: internet goes
 * off at "off" and back on at "on"; a window past midnight belongs to the day
 * it starts on; the most restrictive active schedule wins.
 */
#[Title('Schedules')]
class Schedules extends Component
{
    public ?string $editingId = null;

    public bool $showForm = false;

    public string $label = '';

    /** @var list<int> DayOfWeek raw values, Mon=1 … Sun=7 */
    public array $days = [1, 2, 3, 4, 5];

    public string $offTime = '21:00';

    public string $onTime = '07:00';

    public int $grace = 5;

    public bool $isActive = true;

    public string $profileId = '';

    public ?string $confirmingDelete = null;

    #[Computed]
    public function schedules(): Collection
    {
        return Schedule::query()->ownedBy(auth()->user())->with('profile')->orderBy('label')->get();
    }

    #[Computed]
    public function profiles(): Collection
    {
        return Profile::query()->ownedBy(auth()->user())->orderBy('name')->get();
    }

    public function new(): void
    {
        $this->resetForm();
        $this->showForm = true;
    }

    public function edit(string $id): void
    {
        $s = $this->find($id);
        $this->editingId = $s->id;
        $this->label = $s->label;
        $this->days = array_map('intval', $s->days);
        $this->offTime = sprintf('%02d:%02d', $s->off_hour, $s->off_minute);
        $this->onTime = sprintf('%02d:%02d', $s->on_hour, $s->on_minute);
        $this->grace = $s->grace_period_minutes;
        $this->isActive = $s->is_active;
        $this->profileId = (string) $s->profile_id;
        $this->showForm = true;
    }

    public function save(): void
    {
        $this->validate([
            'label' => ['required', 'string', 'max:60'],
            'days' => ['required', 'array', 'min:1'],
            'days.*' => ['integer', 'between:1,7'],
            'offTime' => ['required', 'date_format:H:i'],
            'onTime' => ['required', 'date_format:H:i', 'different:offTime'],
            'grace' => ['required', 'integer', 'between:0,15'],
            'profileId' => ['nullable', Rule::exists('profiles', 'id')->where('user_id', auth()->id())],
        ], [
            'onTime.different' => 'The internet must come back on at a different time than it goes off.',
            'days.required' => 'Choose at least one day.',
        ]);

        [$offHour, $offMinute] = array_map('intval', explode(':', $this->offTime));
        [$onHour, $onMinute] = array_map('intval', explode(':', $this->onTime));
        $attributes = [
            'label' => trim($this->label),
            'days' => collect($this->days)->map(fn ($d) => (int) $d)->unique()->sort()->values()->all(),
            'off_hour' => $offHour, 'off_minute' => $offMinute,
            'on_hour' => $onHour, 'on_minute' => $onMinute,
            'grace_period_minutes' => $this->grace,
            'is_active' => $this->isActive,
            'profile_id' => $this->profileId ?: null,
        ];

        if ($this->editingId) {
            $this->find($this->editingId)->update($attributes);
        } else {
            Schedule::query()->create($attributes + ['user_id' => auth()->id()]);
        }
        $this->resetForm();
        unset($this->schedules);
    }

    public function toggle(string $id): void
    {
        $schedule = $this->find($id);
        $schedule->update(['is_active' => ! $schedule->is_active]);
        unset($this->schedules);
    }

    /** "Follows Schedule" app rules that used it keep the app blocked (flagged in App rules). */
    public function delete(string $id): void
    {
        $this->find($id)->delete();
        $this->confirmingDelete = null;
        unset($this->schedules);
    }

    public function cancel(): void
    {
        $this->resetForm();
    }

    private function resetForm(): void
    {
        $this->reset('editingId', 'showForm', 'label', 'days', 'offTime', 'onTime', 'grace', 'isActive', 'profileId');
        $this->resetValidation();
    }

    private function find(string $id): Schedule
    {
        return Schedule::query()->ownedBy(auth()->user())->findOrFail($id);
    }

    public function render()
    {
        return view('livewire.paco.schedules');
    }
}
