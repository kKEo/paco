# PaCo Cloud server

The web-hosted half of PaCo for a parent without a second Mac: a browser dashboard to manage cloud-enrolled child Macs and see their screen time, and the device API those Macs' daemons talk to.

Laravel 12, Livewire (Volt + Flux), Octane on FrankenPHP, MariaDB (10.6 or newer) in production, SQLite for development and tests. Design and protocol: [PaCo Cloud server](../docs/gitbook/developer-guide/cloud-server.md) in the developer guide.

## Run it locally

Without Docker (PHP 8.3+, Composer, Node):

```bash
make server-install      # from the repository root: deps, .env, SQLite, seed, assets
make server-serve        # http://localhost:8080
```

Sign in as `parent@example.com` / `password` (PIN `123456`). `make server-reset` wipes and re-seeds. Request emails are queued: run `php artisan queue:work` alongside (they land in `storage/logs/laravel.log` with the default `log` mailer), or use `composer run dev`, which also starts the queue and Vite.

With Docker (Octane + FrankenPHP, MariaDB 11.4, queue worker, scheduler, Mailpit on http://localhost:8025):

```bash
make server-up
docker compose -f server/compose.yaml --profile mariadb exec app php artisan db:seed --force
```

Enroll a Mac: `make server-enroll-code` prints a one-time code. A Debug build of PaCo accepts `http://localhost:8080` as the server address; Release builds require `https://`.

Stand in for the parent while working on the daemon:

```bash
php artisan paco:devices
php artisan paco:push-event "<Mac name>" setManualInternet '{"enabled":false,"minutes":10}'
php artisan paco:push-event "<Mac name>" clearManualInternet
php artisan paco:approve [--minutes=45] [--deny]
php artisan paco:set-pin [--user=parent@example.com]
```

## Tests

```bash
make server-test                         # Pest, SQLite in memory
vendor/bin/pint                          # code style
```

`tests/MariaDb` and `tests/Redis` run only against real servers (the whole suite runs on MariaDB too):

```bash
docker run -d --name paco-mariadb -p 3306:3306 -e MARIADB_DATABASE=paco_test -e MARIADB_USER=paco -e MARIADB_PASSWORD=paco -e MARIADB_RANDOM_ROOT_PASSWORD=1 mariadb:11.4
DB_CONNECTION=mariadb DB_HOST=127.0.0.1 DB_DATABASE=paco_test DB_USERNAME=paco DB_PASSWORD=paco vendor/bin/pest
PACO_TEST_REDIS=1 REDIS_CLIENT=predis vendor/bin/pest tests/Redis
```

`tests/Fixtures/policy.json` is the policy wire format shared with the Mac (`PaCoTests/CloudFixtureTests.swift`). If you change it on purpose, change both sides.

## Deploy

A small VPS with Docker:

1. Point a DNS name at it and open ports 80 and 443.
2. Copy `.env.example` to `.env` and set `APP_KEY` (`php artisan key:generate --show`), `DB_PASSWORD`, `PACO_DOMAIN`, the `MAIL_*` settings, and optionally `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` (`php artisan webpush:vapid --show`) for browser notifications.
3. Choose the database (see below): keep `COMPOSE_PROFILES=mariadb` for the bundled MariaDB container, or point at your own server.
4. `docker compose -f compose.yaml -f compose.prod.yaml up -d --build`. FrankenPHP's Caddy obtains the certificate; migrations run when the app container starts.
5. Back up the database nightly. Bundled: `docker compose exec db sh -c 'mariadb-dump -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" --single-transaction "$MARIADB_DATABASE"' > paco.sql`.

### Database

MariaDB 10.6 or newer; CI tests 10.6 and 11.4.

* **Bundled** (default): the `db` service, `mariadb:11.4`, runs under the compose profile `mariadb`, which `.env` enables with `COMPOSE_PROFILES=mariadb`. Data lives in the `mariadbdata` volume.
* **An existing server:** remove `COMPOSE_PROFILES=mariadb` from `.env` and set `DB_HOST`, `DB_PORT` (3306), `DB_DATABASE`, `DB_USERNAME` and `DB_PASSWORD`. The `db` container is then not started. Create the database and user first:

  ```sql
  CREATE DATABASE paco CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
  CREATE USER 'paco'@'%' IDENTIFIED BY 'a long random password';
  GRANT ALL PRIVILEGES ON paco.* TO 'paco'@'%';
  ```

  From a container, a server on the Docker host itself is `host.docker.internal` (Docker Desktop) or the host's bridge address on Linux. For a TLS connection, set `MYSQL_ATTR_SSL_CA` to the CA file path inside the container.

The connection pins the session time zone to UTC (`DB_TIMEZONE`) and READ COMMITTED isolation (`DB_ISOLATION_LEVEL`); leave both at their defaults.

Do not run it on shared hosting or plain PHP-FPM: each enrolled Mac holds a request open for up to 25 seconds, so the server needs Octane workers (`OCTANE_WORKERS`, at least the number of Macs plus headroom). Proxy and PHP timeouts must exceed `PACO_LONGPOLL_MAX_SECONDS` plus a few seconds.

## Settings

| Variable | Default | Meaning |
|---|---|---|
| `PACO_LONGPOLL_MAX_SECONDS` | 25 | How long a device poll is held |
| `PACO_LONGPOLL_MAX_CONCURRENT` | 200 | Held polls before devices are told to retry later |
| `PACO_LONGPOLL_WAITER` | `polling` | `redis` wakes polls on commit instead of checking every second (set in `compose.prod.yaml`) |
| `PACO_ENROLL_CODE_TTL_MINUTES` | 15 | Lifetime of an enrollment code |
| `VAPID_*` | empty | Browser push for new requests; mail only when empty |

The scheduler (`php artisan schedule:work`, the `scheduler` service) denies requests unanswered for 24 hours and prunes old codes, events and usage.
