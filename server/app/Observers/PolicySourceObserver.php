<?php

namespace App\Observers;

use App\Services\Policy\PolicyPublisher;
use Illuminate\Database\Eloquent\Model;

/**
 * Schedules, app rules and profiles make up the policy: any change to them
 * bumps the owner's devices' policy version and queues `policyChanged`.
 */
class PolicySourceObserver
{
    public function saved(Model $model): void
    {
        if ($model->wasRecentlyCreated || $model->wasChanged()) {
            $this->publish($model);
        }
    }

    public function deleted(Model $model): void
    {
        $this->publish($model);
    }

    private function publish(Model $model): void
    {
        app(PolicyPublisher::class)->publish((int) $model->getAttribute('user_id'));
    }
}
