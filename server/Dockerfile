# PaCo Cloud server image: Laravel on Octane + FrankenPHP.
#
# The device long-poll holds a request for up to 25 s, which pins a worker;
# PHP-FPM would need a process per enrolled device. Octane workers are cheap
# and FrankenPHP's embedded Caddy terminates TLS (automatic certificates).

FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader --prefer-dist --no-interaction --ignore-platform-reqs
COPY . .
RUN composer dump-autoload --no-dev --optimize --no-scripts

FROM node:22-alpine AS assets
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY --from=vendor /app/vendor ./vendor
COPY resources ./resources
COPY vite.config.js ./
RUN npm run build

FROM dunglas/frankenphp:1-php8.3 AS app
RUN install-php-extensions pcntl pdo_mysql pdo_sqlite intl opcache zip redis gmp bcmath
WORKDIR /app
COPY --from=vendor /app /app
COPY --from=assets /app/public/build /app/public/build
RUN rm -f public/hot \
    && mkdir -p storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache \
    && php artisan package:discover --ansi \
    && chown -R www-data:www-data storage bootstrap/cache

ENV OCTANE_SERVER=frankenphp \
    OCTANE_WORKERS=32 \
    OCTANE_MAX_REQUESTS=1000
EXPOSE 8080

COPY docker/entrypoint.sh /usr/local/bin/paco-entrypoint
ENTRYPOINT ["paco-entrypoint"]
CMD ["sh", "-c", "exec php artisan octane:frankenphp --host=0.0.0.0 --port=8080 --workers=${OCTANE_WORKERS} --max-requests=${OCTANE_MAX_REQUESTS}"]
