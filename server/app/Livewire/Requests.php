<?php

namespace App\Livewire;

use App\Models\ExtensionRequest;
use App\Services\Requests\ExtensionRequestService;
use Illuminate\Support\Collection;
use InvalidArgumentException;
use Livewire\Attributes\Computed;
use Livewire\Attributes\Title;
use Livewire\Component;

/**
 * "More time" requests from cloud Macs. Unlike on a parent Mac, approving works
 * while the child's Mac is offline: the grant waits for it on the server.
 */
#[Title('Requests')]
class Requests extends Component
{
    /** Minutes to grant, per request id (defaults to what was asked). */
    public array $minutes = [];

    public string $status = '';

    #[Computed]
    public function pending(): Collection
    {
        return ExtensionRequest::query()->ownedBy(auth()->user())
            ->where('status', ExtensionRequest::PENDING)->with('device')->oldest()->get();
    }

    #[Computed]
    public function history(): Collection
    {
        return ExtensionRequest::query()->ownedBy(auth()->user())
            ->where('status', '!=', ExtensionRequest::PENDING)->with('device')->latest()->limit(50)->get();
    }

    public function approve(string $id, ExtensionRequestService $service): void
    {
        $request = $this->find($id);
        $minutes = (int) ($this->minutes[$id] ?? $request->requested_minutes);
        if ($minutes < 1 || $minutes > config('paco.requests.max_minutes')) {
            $this->addError("minutes.$id", 'Between 1 and '.config('paco.requests.max_minutes').' minutes.');

            return;
        }
        $this->resolve(fn () => $service->approve($request, $minutes, auth()->user()),
            "Approved {$minutes} minutes for {$request->device->name}.");
    }

    public function deny(string $id, ExtensionRequestService $service): void
    {
        $request = $this->find($id);
        $this->resolve(fn () => $service->deny($request, auth()->user()), "Denied {$request->device->name}'s request.");
    }

    private function resolve(callable $action, string $message): void
    {
        try {
            $action();
            $this->status = $message;
        } catch (InvalidArgumentException) {
            $this->status = 'That request was already answered.';
        }
        unset($this->pending, $this->history);
    }

    private function find(string $id): ExtensionRequest
    {
        return ExtensionRequest::query()->ownedBy(auth()->user())->with('device')->findOrFail($id);
    }

    public function render()
    {
        return view('livewire.paco.requests');
    }
}
