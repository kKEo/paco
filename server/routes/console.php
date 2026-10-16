<?php

use Illuminate\Support\Facades\Schedule;

// Run with `php artisan schedule:work` (compose service `scheduler`).
Schedule::command('paco:expire-requests')->everyTenMinutes()->withoutOverlapping();
Schedule::command('paco:prune')->daily()->withoutOverlapping();
