<?php

return [
    /*
    | Device long-poll (GET /api/v1/device/events). Each held request pins a PHP
    | worker, so run under Octane (FrankenPHP) with workers >= devices + headroom.
    | Proxy and PHP timeouts must exceed max_seconds plus processing time.
    */
    'longpoll' => [
        'max_seconds' => (int) env('PACO_LONGPOLL_MAX_SECONDS', 25),
        'max_concurrent' => (int) env('PACO_LONGPOLL_MAX_CONCURRENT', 200),
        'batch_size' => 50,
        // `polling` (sleep 1 s between checks) or `redis` (woken on commit).
        'waiter' => env('PACO_LONGPOLL_WAITER', 'polling'),
        'redis_connection' => env('PACO_LONGPOLL_REDIS_CONNECTION', 'default'),
        'retry_after_seconds' => 5,
    ],

    'enrollment' => [
        'code_ttl_minutes' => (int) env('PACO_ENROLL_CODE_TTL_MINUTES', 15),
    ],

    // Mirrors PINManager on the Mac: 5 failures lock for 300 s.
    'pin' => [
        'max_attempts' => 5,
        'lockout_seconds' => 300,
    ],

    'requests' => [
        // Unanswered requests are auto-denied after this long (the Mac drops
        // pending requests older than 24 h too).
        'expire_after_hours' => 24,
        'max_minutes' => 240,
    ],

    'retention' => [
        'event_days' => 90,
        'usage_days' => 400,
    ],
];
