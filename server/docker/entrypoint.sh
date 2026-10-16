#!/bin/sh
# Prepare caches and run migrations once, from the web container only
# (PACO_MIGRATE=1), then hand over to the service command.
set -e

if [ "${PACO_MIGRATE:-0}" = "1" ]; then
    php artisan migrate --force --no-interaction
fi
if [ "${APP_ENV:-production}" = "production" ]; then
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
fi

exec "$@"
