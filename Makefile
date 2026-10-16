VERSION      ?= 1.1.0
# Developer ID signing. Leave TEAM_ID empty for an unsigned local build (the
# daemon then refuses XPC peers unless PACO_ALLOW_UNSIGNED_XPC=1, see README).
TEAM_ID      ?=
APP_IDENTITY ?= Developer ID Application
PKG_IDENTITY ?= Developer ID Installer
# `xcrun notarytool store-credentials <profile>` once, then `make notarize NOTARY_PROFILE=<profile>`.
NOTARY_PROFILE ?=
# Optional: keychain holding NOTARY_PROFILE when it is not in the default search list (CI).
NOTARY_KEYCHAIN ?=
ifneq ($(TEAM_ID),)
SIGN_FLAGS := DEVELOPMENT_TEAM=$(TEAM_ID) CODE_SIGN_STYLE=Manual \
	CODE_SIGN_IDENTITY="$(APP_IDENTITY)" ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp
else
SIGN_FLAGS :=
endif
BUILD_DIR    := build/Release
ARCHIVE_DIR  := build/archive
PKG_ROOT     := build/pkg-root
PKG_SCRIPTS  := build/pkg-scripts
PKG_OUT      := build/PaCo-$(VERSION).pkg

.PHONY: build build-release pkg notarize clean clear-pin clear-policy \
	server-install server-reset server-serve server-up server-down server-test server-pint server-enroll-code

build:
	xcodebuild -project PaCo.xcodeproj -scheme PaCo -destination "platform=macOS" build

build-release:
	xcodebuild -project PaCo.xcodeproj -scheme PaCo \
		-configuration Release \
		-destination "platform=macOS" \
		-derivedDataPath build/DerivedData \
		$(SIGN_FLAGS) \
		build

pkg: build-release
	# ── Prepare staging tree ──────────────────────────────────────────
	rm -rf "$(PKG_ROOT)" "$(PKG_SCRIPTS)"
	mkdir -p "$(PKG_ROOT)/Applications"
	mkdir -p "$(PKG_ROOT)/Library/LaunchDaemons"
	mkdir -p "$(PKG_ROOT)/Library/LaunchAgents"
	mkdir -p "$(PKG_ROOT)/Library/Application Support/PaCo"
	mkdir -p "$(PKG_SCRIPTS)"

	# Copy PaCo.app
	cp -R "build/DerivedData/Build/Products/Release/PaCo.app" \
	      "$(PKG_ROOT)/Applications/"

	# Copy helper binaries into the app's Resources (they keep their own signatures;
	# the daemon derives its XPC requirement from the Team ID in its signature).
	cp "build/DerivedData/Build/Products/Release/PaCoDaemon" \
	   "$(PKG_ROOT)/Applications/PaCo.app/Contents/Resources/"
	cp "build/DerivedData/Build/Products/Release/PaCoAgent" \
	   "$(PKG_ROOT)/Applications/PaCo.app/Contents/Resources/"

	# LaunchDaemon plist
	cp packaging/com.paco.daemon.plist \
	   "$(PKG_ROOT)/Library/LaunchDaemons/"

	# LaunchAgent plist
	cp packaging/com.paco.agent.plist \
	   "$(PKG_ROOT)/Library/LaunchAgents/"

	# ── postinstall script ────────────────────────────────────────────
	@printf '#!/bin/bash\nset -e\n\n'\
'# Stop a previous install first so an upgrade does not keep the old daemon/agent running\n'\
'launchctl bootout system/com.paco.daemon 2>/dev/null || true\n'\
'CONSOLE_UID=$$(stat -f %u /dev/console)\n'\
'if [ -n "$$CONSOLE_UID" ] && [ "$$CONSOLE_UID" != "0" ]; then\n'\
'    launchctl bootout gui/$$CONSOLE_UID/com.paco.agent 2>/dev/null || true\n'\
'fi\n\n'\
'# Install daemon binary\n'\
'install -o root -g wheel -m 755 \\\n'\
'    /Applications/PaCo.app/Contents/Resources/PaCoDaemon \\\n'\
'    /Library/Application\ Support/PaCo/PaCoDaemon\n\n'\
'# Install agent binary\n'\
'install -o root -g wheel -m 755 \\\n'\
'    /Applications/PaCo.app/Contents/Resources/PaCoAgent \\\n'\
'    /Library/Application\ Support/PaCo/PaCoAgent\n\n'\
'# Load daemon (system domain)\n'\
'launchctl bootstrap system /Library/LaunchDaemons/com.paco.daemon.plist 2>/dev/null || true\n\n'\
'# Load agent into the console user'"'"'s GUI domain so it runs without waiting for a re-login\n'\
'if [ -n "$$CONSOLE_UID" ] && [ "$$CONSOLE_UID" != "0" ]; then\n'\
'    launchctl bootstrap gui/$$CONSOLE_UID /Library/LaunchAgents/com.paco.agent.plist 2>/dev/null || true\n'\
'fi\n\n'\
'exit 0\n' > "$(PKG_SCRIPTS)/postinstall"
	chmod +x "$(PKG_SCRIPTS)/postinstall"

	# ── Build flat package ────────────────────────────────────────────
	pkgbuild \
		--root "$(PKG_ROOT)" \
		--scripts "$(PKG_SCRIPTS)" \
		--identifier com.paco.pkg \
		--version "$(VERSION)" \
		--install-location / \
		$(if $(TEAM_ID),--sign "$(PKG_IDENTITY)",) \
		"$(PKG_OUT)"

	@echo ""
	@echo "Package written to: $(PKG_OUT)"

# Submit the signed pkg to Apple and staple the ticket. Requires TEAM_ID and NOTARY_PROFILE.
notarize: pkg
	@test -n "$(NOTARY_PROFILE)" || { echo "Set NOTARY_PROFILE (see 'xcrun notarytool store-credentials')"; exit 1; }
	xcrun notarytool submit "$(PKG_OUT)" --keychain-profile "$(NOTARY_PROFILE)" \
		$(if $(NOTARY_KEYCHAIN),--keychain "$(NOTARY_KEYCHAIN)",) --wait
	xcrun stapler staple "$(PKG_OUT)"

clean:
	rm -rf build

clear-pin:
	security delete-generic-password -s "com.paco.pin.hash" 2>/dev/null; true
	security delete-generic-password -s "com.paco.pin.salt" 2>/dev/null; true

clear-policy:
	sudo rm -f "/Library/Application Support/PaCo/policy.json" "/Library/Application Support/PaCo/daemon-state.json"

# ── PaCo Cloud server (server/, Laravel) ─────────────────────────────
# Without Docker: `make server-install server-serve` (SQLite, http://localhost:8080,
# seeded parent parent@example.com / password, PIN 123456).
# With Docker: `make server-up` (Postgres + Octane/FrankenPHP + Mailpit).
SERVER_DIR := server

# Safe to re-run: keeps .env, APP_KEY and data; seeds only a brand-new database.
server-install:
	cd $(SERVER_DIR) && composer install --no-interaction
	cd $(SERVER_DIR) && test -f .env || cp .env.example .env
	cd $(SERVER_DIR) && grep -q '^APP_KEY=base64' .env || php artisan key:generate --no-interaction
	cd $(SERVER_DIR) && if [ -s database/database.sqlite ]; then php artisan migrate --force; \
		else touch database/database.sqlite && php artisan migrate --seed --force; fi
	cd $(SERVER_DIR) && npm ci --no-audit --no-fund && npm run build

# Wipe the local SQLite database and re-seed the development data.
server-reset:
	cd $(SERVER_DIR) && php artisan migrate:fresh --seed --force

server-serve:
	cd $(SERVER_DIR) && PHP_CLI_SERVER_WORKERS=4 php artisan serve --port=8080

server-up:
	cd $(SERVER_DIR) && test -f .env || { cp .env.example .env && php artisan key:generate --no-interaction; }
	cd $(SERVER_DIR) && docker compose up -d --build

server-down:
	cd $(SERVER_DIR) && docker compose down

server-test:
	cd $(SERVER_DIR) && vendor/bin/pest

server-pint:
	cd $(SERVER_DIR) && vendor/bin/pint

# One-time code for enrolling a child Mac: make server-enroll-code [USER_EMAIL=parent@example.com]
server-enroll-code:
	cd $(SERVER_DIR) && php artisan paco:enrollment-code $(if $(USER_EMAIL),--user=$(USER_EMAIL),)
