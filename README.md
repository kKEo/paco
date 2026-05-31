# PaCo — Parental Control for macOS

A personal-use macOS parental control app with internet on/off scheduling, app restrictions, usage tracking, and a child time-extension request/approve workflow.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+ with license accepted (`sudo xcodebuild -license`)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) 2.45+ (`brew install xcodegen`)
- Two Macs on the same local network (parent Mac + child Mac), or one Mac for single-device testing

---

## Architecture

PaCo is a single universal app that runs in two roles — **Parent** and **Child** — selected during first launch. All three binaries live inside one Xcode project.

```
PaCo/
├── PaCo/              # Main app (SwiftUI, MenuBarExtra, SwiftData)
├── PaCoDaemon/        # LaunchDaemon — root-level pf firewall + process kill
├── PaCoAgent/         # LaunchAgent — schedule evaluation, app monitoring, usage tracking
├── PaCoShared/        # Local Swift Package — models, XPC protocol, network types, security
└── PaCoTests/         # Unit tests
```

### Component Overview

| Component | Runs as | Responsibility |
|-----------|---------|---------------|
| `PaCo.app` | Logged-in user | Parent dashboard / Child status UI, SwiftData persistence, Bonjour peer discovery |
| `PaCoDaemon` | root (LaunchDaemon) | `pf` firewall anchor rules, SIGKILL blocked processes |
| `PaCoAgent` | user (LaunchAgent) | 30-second schedule tick, NSWorkspace app monitoring, usage tracking, writes shared JSON |
| `PaCoShared` | (package) | SwiftData models, XPC protocol, Codable transfer types, PIN/Keychain, schedule evaluator |

### Communication Paths

```
PaCo.app ←──── XPC ────→ PaCoDaemon   (internet on/off, kill process)
PaCo.app ←── JSON files ─→ PaCoAgent  (schedules.json, restrictions.json, config.json,
                                        usage.json, events.json — via ~/Library/Application Support/com.paco/)
Parent Mac ←── Bonjour/TCP ──→ Child Mac  (remote commands, time-extension requests/approvals)
```

### Shared JSON Files

All JSON files live in `~/Library/Application Support/com.paco/` on each Mac:

| File | Written by | Read by |
|------|-----------|---------|
| `schedules.json` | PaCo.app (parent) | PaCoAgent |
| `restrictions.json` | PaCo.app (parent) | PaCoAgent |
| `config.json` | PaCo.app (parent) | PaCoAgent |
| `usage.json` | PaCoAgent | PaCo.app |
| `events.json` | PaCoAgent + PaCo.app (child) | PaCo.app (parent, via DispatchSource watcher) |

### Internet Control

PaCo uses a `pf` anchor named `com.paco`. When internet is blocked, the daemon writes block rules to `/etc/pf.anchors/com.paco` and loads them via `pfctl`. Flushing the anchor re-enables internet. LAN traffic (10.x, 172.16.x, 192.168.x, localhost) is always allowed.

### Schedule Evaluation

The agent evaluates all active schedules every 30 seconds. Most-restrictive-wins: if any active schedule says blocked, internet is disabled. A configurable grace period (0–15 min) gives a warning window after the off-time before enforcement.

### Request/Approve Workflow

1. Child taps **Request More Time** → writes a `NotificationEvent(.extensionRequested)` to `events.json` and sends a `PaCoMessage(.requestExtension)` over Bonjour.
2. Parent's app watches `events.json` via `DispatchSource` and inserts a `TimeExtensionRequest` into SwiftData.
3. Parent sees the request in **Requests** tab or the **Home** banner, and taps Approve or Deny.
4. Approval calls `daemonClient.toggleInternet()` immediately and sends a `PaCoMessage(.approveExtension)` back to the child over Bonjour.

### Security

- Parent PIN stored in Keychain using PBKDF2/SHA-256 (10,000 iterations, 16-byte random salt).
- XPC connection validated: only connections from the expected bundle identifier are accepted.
- `pf` tamper detection: daemon re-applies rules if anchor rules are missing while blocking is active.

---

## Project Setup

### 1. Clone and generate the Xcode project

```bash
git clone <repo-url> PaCo
cd PaCo
xcodegen generate
```

### 2. Open in Xcode

```bash
open PaCo.xcodeproj
```

### 3. Build (Debug)

```bash
make build
```

Or directly:

```bash
xcodebuild -project PaCo.xcodeproj -scheme PaCo -destination "platform=macOS" build
```

### 4. Run tests

```bash
xcodebuild test -project PaCo.xcodeproj -scheme PaCoTests -configuration Debug
```

---

## Installation (Development / Local)

> **Note:** Full end-to-end testing of the daemon and agent requires a Developer ID certificate because `SMAppService` and XPC mach services enforce code signing. Without signing, the app UI works but the daemon/agent connections will fail.

### Manual install for local testing

```bash
# 1. Build release binaries
make build-release

# 2. Build and stage the installer package
make pkg

# 3. Install (requires sudo)
sudo installer -pkg build/PaCo-1.0.0.pkg -target /
```

The postinstall script:
- Copies `PaCoDaemon` and `PaCoAgent` binaries to `/Library/Application Support/PaCo/`
- Bootstraps the LaunchDaemon via `launchctl bootstrap system`
- The LaunchAgent (`com.paco.agent`) loads automatically at login

### LaunchDaemon and LaunchAgent plists

| Plist | Install path | Label |
|-------|-------------|-------|
| `packaging/com.paco.daemon.plist` | `/Library/LaunchDaemons/` | `com.paco.daemon` |
| `packaging/com.paco.agent.plist`  | `/Library/LaunchAgents/`  | `com.paco.agent`  |

### First launch

1. Open **PaCo.app** from `/Applications/`.
2. Choose **Parent** or **Child** role.
3. Parent: set a PIN and create a child profile.
4. Child: the app lives in the menu bar and advertises itself over Bonjour.
5. Parent: open **Devices** tab to discover and pair the child Mac.

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make build` | Debug build |
| `make build-release` | Release build to `build/DerivedData` |
| `make pkg` | Release build → staged pkg → `build/PaCo-<VERSION>.pkg` |
| `make clean` | Remove `build/` directory |
| `make clear-pin` | Delete stored PIN from Keychain (for testing) |

Pass a custom version:

```bash
make pkg VERSION=1.2.0
```

---

## Resetting State

```bash
# Reset role selection (triggers onboarding on next launch)
rm -rf ~/Library/Application\ Support/com.paco.app

# Clear stored PIN
make clear-pin
# or manually:
security delete-generic-password -s "com.paco.pin.hash"
security delete-generic-password -s "com.paco.pin.salt"

# Clear stale window state
defaults delete com.paco.app

# Remove shared JSON data
rm -rf ~/Library/Application\ Support/com.paco/
```

---

## Roadmap

| Version | Features |
|---------|----------|
| **V1 (current)** | Internet on/off toggle, pf scheduling, app restrictions, usage tracking, Bonjour pairing, time-extension request/approve |
| V1.2 | Daily usage budgets, bedtime mode, usage reports |
| V2.0 | DNS-level content filtering |
| V2.5 | Network Extension for per-app traffic control |
| V3.0 | iOS companion app |
