VERSION      ?= 1.0.0
BUILD_DIR    := build/Release
ARCHIVE_DIR  := build/archive
PKG_ROOT     := build/pkg-root
PKG_SCRIPTS  := build/pkg-scripts
PKG_OUT      := build/PaCo-$(VERSION).pkg

.PHONY: build build-release pkg clean clear-pin clear-policy

build:
	xcodebuild -project PaCo.xcodeproj -scheme PaCo -destination "platform=macOS" build

build-release:
	xcodebuild -project PaCo.xcodeproj -scheme PaCo \
		-configuration Release \
		-destination "platform=macOS" \
		-derivedDataPath build/DerivedData \
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

	# Copy helper binaries into the app's Resources
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
'CONSOLE_UID=$$(stat -f %u /dev/console)\n'\
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
		"$(PKG_OUT)"

	@echo ""
	@echo "Package written to: $(PKG_OUT)"

clean:
	rm -rf build

clear-pin:
	security delete-generic-password -s "com.paco.pin.hash" 2>/dev/null; true
	security delete-generic-password -s "com.paco.pin.salt" 2>/dev/null; true

clear-policy:
	sudo rm -f "/Library/Application Support/PaCo/policy.json" "/Library/Application Support/PaCo/daemon-state.json"
