# PaCo — Parental Control for macOS

[![CI](https://github.com/kKEo/paco/actions/workflows/ci.yml/badge.svg)](https://github.com/kKEo/paco/actions/workflows/ci.yml) [![Docs](https://github.com/kKEo/paco/actions/workflows/docs.yml/badge.svg)](https://github.com/kKEo/paco/actions/workflows/docs.yml)

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
PaCo.app ←──── XPC ────→ PaCoDaemon   (policy push, active profile, override grant, internet on/off, kill process)
PaCoAgent ←─── XPC ────→ PaCoDaemon   (fetch policy, internet status, kill process)
PaCoAgent ──→ JSON files ──→ PaCo.app  (usage.json; events.json is an agent-side log — via ~/Library/Application Support/com.paco/)
Parent Mac ←── Bonjour/TCP ──→ Child Mac  (policy push, PIN verification, time-extension requests/approvals)
```

### Where the policy lives

The enforcement policy (schedules, app restrictions, active profile, approved override) is owned by the **root daemon**: it is pushed in over XPC, persisted to `/Library/Application Support/PaCo/policy.json` (root-owned), and evaluated by the daemon itself every 30 seconds. Nothing in the monitored user's home directory influences enforcement. The agent is a reporter: it reads the policy back over XPC to know which apps to watch, asks the daemon to kill restricted ones, and keeps the usage snapshot.

### Shared JSON Files

All JSON files live in `~/Library/Application Support/com.paco/` on each Mac:

| File | Written by | Read by |
|------|-----------|---------|
| `usage.json` | PaCoAgent | PaCo.app |
| `events.json` | PaCoAgent | nobody yet — activity log (app blocked, internet on/off), the hook for future notifications |
| `child-requests.json` | PaCo.app (child) | PaCo.app (child) — sent requests and their outcomes, survives relaunch |

### Policy Push (parent → child)

The parent app keeps one TLS-PSK connection per paired child open app-wide: it browses from launch and auto-connects whenever a discovered service has a stored pairing key (retrying every 30 s and giving up on a connection stuck for 20 s). On every connect, and after every schedule or app-rule change, the parent sends a `PaCoMessage(.updatePolicy)` carrying a `PolicyTransfer` (active schedules + all restrictions). The child app hands it to its local root daemon over XPC, acknowledges with a `PaCoResponse`, and the daemon enforces it at once. A child that is offline receives the current policy when it next connects. On the parent Mac the same policy is also pushed to the parent's own daemon, so a single Mac can be both parent and child for testing.

### Internet Control

PaCo uses a `pf` anchor named `com.paco`. When internet is blocked, the daemon writes block rules to `/etc/pf.anchors/com.paco` and loads them via `pfctl`. Flushing the anchor re-enables internet. LAN traffic (10.x, 172.16.x, 192.168.x, localhost) is always allowed.

### Schedule Evaluation

The daemon evaluates the active profile's schedules every 30 seconds (`PolicyEngine`). Most-restrictive-wins: if any active schedule says blocked, internet is disabled. A configurable grace period (0–15 min) gives a warning window after the off-time before enforcement.

- **Days mean "the night that starts on that day".** An overnight window (off later than on, e.g. 21:00 → 07:00) on Thursday blocks until Friday 07:00 and does not block Friday evening. Same-day windows (09:00 → 15:00) apply to the selected day only.
- **Profiles.** Schedules and app rules belong to a child profile; a device enforces the active profile's rules (chosen under Profiles) plus any without a profile. With no active profile, everything applies.
- **Manual toggle.** The Home switch forces internet on or off for 60 minutes (`ManualInternetOverride`), then the schedule takes over again. Home shows the override and a "Back to schedule" button. Precedence: manual toggle → approved extension → schedules.
- **"Follows Schedule" app rules** block the app exactly while the chosen schedule blocks the internet (an approved extension lifts both). A disabled schedule blocks nothing; a deleted one leaves the rule flagged in red and the app blocked until the rule is re-added.

### Request/Approve Workflow

1. Child taps **Request More Time** (enabled only while the parent is connected) → sends a `PaCoMessage(.requestExtension)` over Bonjour and records the request in `child-requests.json`. The child view shows "waiting for parent…".
2. Parent's app receives it on the paired connection and inserts a `TimeExtensionRequest` into SwiftData, attributed to the *pairing identity* the request arrived on (not the name in the payload), which is also how the reply is routed.
3. Parent sees the request in **Requests** tab or the **Home** banner, and taps Approve or Deny. Approve is disabled while that child is offline; the request stays pending until the grant was actually sent.
4. The child receives `.approveExtension`, matches it against its persisted request (each id resolves once — replay guard), grants the override to its daemon over XPC, and shows "Approved — internet on until HH:MM". The daemon enables internet immediately. A denial shows "Request denied".

### Usage Tracking

The agent counts **foreground** time per regular (Dock) app using `NSWorkspace` activation events (`UsageLedger`), so an app that is open shows its time immediately, apps already running when the agent starts count from then, and helpers are not listed. Internet-on time comes from the daemon's state. Counters reset at midnight; a snapshot is written every 30 s to `usage.json` and restored on agent restart.

### Parent Access on a child Mac

The parent PIN hash never leaves the parent Mac. When a parent types the PIN on a child Mac, the child sends it to the parent over the TLS-PSK channel (`.verifyPIN`) and the parent answers with the verdict, applying the same brute-force lockout as its own dashboard. The child must be connected to the parent for this to work.

### Security

- Parent PIN stored in the parent's Keychain using PBKDF2/SHA-256 (210,000 iterations, 16-byte random salt); it is never copied to a child.
- XPC: the daemon attaches a code-signing requirement to every connection (`anchor apple generic`, identifier `com.paco.app` or `com.paco.agent`, and the daemon's own Team ID read from its signature). An unsigned daemon refuses every peer unless a Debug build is run with `PACO_ALLOW_UNSIGNED_XPC=1`.
- Policy is root-owned (`/Library/Application Support/PaCo/policy.json`) and only changeable through the daemon's XPC interface.
- Parent ↔ child traffic is TLS-PSK with a key derived from the one-time pairing code. An unpaired child advertises for discovery only and drops every incoming connection.
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

> **Note:** Full end-to-end testing of the daemon and agent requires a Developer ID certificate: the daemon derives its XPC code-signing requirement from its own Team ID, so all four targets must be signed by the same team (set `DEVELOPMENT_TEAM` in `project.yml` or Xcode's Signing settings). Without signing, the app UI works but the daemon refuses every connection; for local Debug runs you can add `PACO_ALLOW_UNSIGNED_XPC=1` to the daemon's `EnvironmentVariables` in its launchd plist.

### Manual install for local testing

```bash
# 1. Build and stage a signed installer package (TEAM_ID = your 10-char Team ID)
make pkg TEAM_ID=ABCDE12345

# 2. Optional: notarize + staple (after `xcrun notarytool store-credentials paco` once)
make notarize TEAM_ID=ABCDE12345 NOTARY_PROFILE=paco

# 3. Install (requires sudo)
sudo installer -pkg build/PaCo-1.0.0.pkg -target /
```

Without `TEAM_ID` the build is unsigned (local UI testing only). With it, all four targets are signed with your Developer ID Application certificate and hardened runtime, and the pkg with your Developer ID Installer certificate.

The postinstall script:
- Boots out any previously installed daemon/agent so an upgrade does not keep the old binaries running
- Copies `PaCoDaemon` and `PaCoAgent` binaries to `/Library/Application Support/PaCo/`
- Bootstraps the LaunchDaemon via `launchctl bootstrap system` and the LaunchAgent into the console user's GUI domain

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
5. Parent: open **Devices** tab to discover and pair the child Mac. From then on the parent connects to the child automatically whenever both are on the network and pushes schedules and app rules to it.

---

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make build` | Debug build |
| `make build-release` | Release build to `build/DerivedData` (signed when `TEAM_ID` is set) |
| `make notarize` | Build the pkg, submit to Apple notary service, staple (`TEAM_ID`, `NOTARY_PROFILE`) |
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
# Reset the app's database (role selection, profiles, schedules, rules, pairings)
rm -f ~/Library/Application\ Support/com.paco/PaCo.store*

# Clear stored PIN
make clear-pin
# or manually:
security delete-generic-password -s "com.paco.pin.hash"
security delete-generic-password -s "com.paco.pin.salt"

# Clear stale window state
defaults delete com.paco.app

# Remove everything app-side (database + usage/events/request logs)
rm -rf ~/Library/Application\ Support/com.paco/

# Remove the daemon's policy and block state (root-owned)
make clear-policy
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
