<?php

namespace App\Livewire;

use App\Models\AppRestriction;
use App\Models\Profile;
use App\Models\Schedule;
use App\Models\UsageDay;
use Illuminate\Support\Collection;
use Illuminate\Validation\Rule;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Title;
use Livewire\Component;

/**
 * App rules: "Blocked" apps are closed whenever they start; "Follows schedule"
 * apps are closed while their schedule has the internet off.
 */
#[Title('App rules')]
class AppRules extends Component
{
    public bool $showForm = false;

    public ?string $editingId = null;

    public string $appName = '';

    public string $bundleIdentifier = '';

    public string $type = AppRestriction::TYPE_BLOCKED;

    public string $scheduleId = '';

    public string $profileId = '';

    public ?string $confirmingDelete = null;

    #[Computed]
    public function rules(): Collection
    {
        return AppRestriction::query()->ownedBy(auth()->user())
            ->with(['profile', 'allowedSchedule'])->orderBy('app_name')->get();
    }

    #[Computed]
    public function schedules(): Collection
    {
        return Schedule::query()->ownedBy(auth()->user())->orderBy('label')->get();
    }

    #[Computed]
    public function profiles(): Collection
    {
        return Profile::query()->ownedBy(auth()->user())->orderBy('name')->get();
    }

    /** Apps the parent's Macs have reported, to pick a bundle id from. */
    #[Computed]
    public function knownApps(): Collection
    {
        return UsageDay::query()
            ->whereHas('device', fn ($q) => $q->where('user_id', auth()->id()))
            ->latest('local_date')->limit(30)->get()
            ->flatMap(fn (UsageDay $day) => $day->app_entries ?? [])
            ->unique('bundleIdentifier')
            ->sortBy('appName')
            ->values();
    }

    public function new(): void
    {
        $this->resetForm();
        $this->showForm = true;
    }

    public function edit(string $id): void
    {
        $rule = $this->find($id);
        $this->editingId = $rule->id;
        $this->appName = $rule->app_name;
        $this->bundleIdentifier = $rule->bundle_identifier;
        $this->type = $rule->restriction_type;
        $this->scheduleId = (string) $rule->allowed_schedule_id;
        $this->profileId = (string) $rule->profile_id;
        $this->showForm = true;
    }

    /** Picking a reported app fills in its name. */
    public function updatedBundleIdentifier(string $value): void
    {
        if ($this->appName === '' && ($app = $this->knownApps->firstWhere('bundleIdentifier', $value))) {
            $this->appName = $app['appName'];
        }
    }

    public function save(): void
    {
        $owned = fn (string $table) => Rule::exists($table, 'id')->where('user_id', auth()->id());
        $this->validate([
            'appName' => ['required', 'string', 'max:100'],
            'bundleIdentifier' => ['required', 'string', 'max:255', 'regex:/^[A-Za-z0-9][A-Za-z0-9.\-]*$/'],
            'type' => ['required', Rule::in(AppRestriction::TYPES)],
            'scheduleId' => [Rule::requiredIf($this->type === AppRestriction::TYPE_SCHEDULED_ONLY), 'nullable', $owned('schedules')],
            'profileId' => ['nullable', $owned('profiles')],
        ], [
            'bundleIdentifier.regex' => 'A bundle identifier looks like com.example.App.',
            'scheduleId.required' => 'Choose the schedule this app follows.',
        ]);

        $attributes = [
            'app_name' => trim($this->appName),
            'bundle_identifier' => trim($this->bundleIdentifier),
            'restriction_type' => $this->type,
            'allowed_schedule_id' => $this->type === AppRestriction::TYPE_SCHEDULED_ONLY ? $this->scheduleId : null,
            'profile_id' => $this->profileId ?: null,
        ];
        if ($this->editingId) {
            $this->find($this->editingId)->update($attributes);
        } else {
            AppRestriction::query()->create($attributes + ['user_id' => auth()->id()]);
        }
        $this->resetForm();
        unset($this->rules);
    }

    public function delete(string $id): void
    {
        $this->find($id)->delete();
        $this->confirmingDelete = null;
        unset($this->rules);
    }

    public function cancel(): void
    {
        $this->resetForm();
    }

    private function resetForm(): void
    {
        $this->reset('showForm', 'editingId', 'appName', 'bundleIdentifier', 'type', 'scheduleId', 'profileId');
        $this->resetValidation();
    }

    private function find(string $id): AppRestriction
    {
        return AppRestriction::query()->ownedBy(auth()->user())->findOrFail($id);
    }

    public function render()
    {
        return view('livewire.paco.app-rules');
    }
}
