# PaCo -- macOS Parental Control Application Design Spec

## Overview

PaCo is a macOS desktop application for parental control, focused on network access management. It is designed for personal/family use (a single parent managing 1-3 Macs at home). The application runs as a single universal app with Parent and Child role modes, communicating over the local network.

### V1 Scope

- Internet on/off toggle (manual and schedule-based) using `pf` firewall rules
- Schedule-based automation with notifications and grace periods
- App launch restrictions (block or schedule-only)
- Usage time tracking (internet time + per-app breakdown)
- Device pairing with encrypted communication
- PIN-protected parent mode, locked-down child mode

### Tech Stack

- **Language**: Swift
- **UI**: SwiftUI
- **Storage**: SwiftData (SQLite)
- **Firewall**: `pf` / `pfctl` via anchors
- **Daemon registration**: `SMAppService`
- **Device communication**: Bonjour (NWBrowser/NWListener from Network.framework) + TLS
- **IPC**: XPC (agent-to-daemon)
- **Target**: macOS 14 Sonoma and later

---

## Architecture

### Single App, Three Embedded Components

PaCo.app is one macOS application bundle containing three executables:

```
PaCo.app/
  Contents/
    MacOS/PaCo                                    # Main app (SwiftUI UI)
    Library/
      LaunchDaemons/
        com.paco.daemon.plist                     # Privileged helper (root)
      LaunchAgents/
        com.paco.agent.plist                      # User-level monitor
    Resources/
      ...
    Info.plist
```

1. **Main App (`PaCo`)** -- The SwiftUI application. On first launch, user chooses "Set up as Parent" or "Set up as Child". Parent mode shows the full dashboard. Child mode shows a locked status view (menu bar icon + minimal window).

2. **LaunchDaemon (`com.paco.daemon`)** -- Runs as root. Manages `pf` firewall rules, can terminate blocked processes. Registered via `SMAppService`. This is the enforcement engine. It reads rules from a local config file and applies them. Only the daemon can modify firewall state.

3. **LaunchAgent (`com.paco.agent`)** -- Runs as the logged-in user. Monitors app launches via `NSWorkspace.shared.notificationCenter`, tracks usage time, and communicates with both the daemon (via XPC) and the parent dashboard (via Bonjour/TLS).

### Communication Paths

```
Parent Mac                          Child Mac
+--------------+                    +----------------------+
| PaCo         |   Bonjour/TLS     | PaCo (child mode)    |
| (Dashboard)  |<------------------>| LaunchAgent          |
|              |                    |    | XPC              |
+--------------+                    |    v                  |
                                    | LaunchDaemon (root)   |
                                    |    |                  |
                                    |    v                  |
                                    | pf firewall / kill    |
                                    +----------------------+
```

- **Dashboard <-> Agent**: Bonjour discovery + encrypted TCP (TLS 1.3 with pre-shared key derived from pairing PIN via HKDF).
- **Agent <-> Daemon**: XPC (inter-process communication, local only, Apple's recommended mechanism for privilege escalation).
- **Daemon <-> OS**: `pf` rules via `pfctl` commands, process termination via `kill`.

### Optional Remote Access (Future)

Local network by default. An optional VPN/tunnel can be added later for remote management when the parent is away from home. Not in V1 scope.

---

## Data Model

### Local Storage (SwiftData / SQLite)

Each PaCo instance (parent or child) maintains a local SQLite database via SwiftData. No cloud storage needed.

#### Core Entities

**ChildProfile**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| name | String | Child's display name |
| avatarImageData | Data? | Optional avatar image |
| createdAt | Date | Profile creation timestamp |

**Schedule**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| childProfileId | UUID | FK to ChildProfile |
| label | String | e.g., "School nights", "Weekend" |
| days | [DayOfWeek] | Bitmask of Mon-Sun |
| internetOffAt | DateComponents | Hour + minute only, e.g., hour:21 minute:0 |
| internetOnAt | DateComponents | Hour + minute only, e.g., hour:7 minute:0 |
| gracePeriodMinutes | Int | 0-15 minutes of grace after internetOffAt |
| isActive | Bool | Whether this schedule is currently enabled |

**AppRestriction**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| childProfileId | UUID | FK to ChildProfile |
| bundleIdentifier | String | e.g., "com.apple.Safari" |
| appName | String | Display name |
| restrictionType | Enum | `.blocked` or `.scheduledOnly` |
| allowedScheduleId | UUID? | If scheduledOnly, which schedule governs it |

**UsageRecord**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| childProfileId | UUID | FK to ChildProfile |
| date | Date | Calendar date |
| internetOnDuration | TimeInterval | Seconds online that day |
| appUsage | [AppUsageEntry] | Per-app breakdown (stored as JSON-encoded Data in SwiftData, decoded at read time) |

**AppUsageEntry**

| Field | Type | Description |
|-------|------|-------------|
| bundleIdentifier | String | App bundle ID |
| appName | String | Display name |
| duration | TimeInterval | Seconds of usage |
| launchCount | Int | Number of times launched |

**PairingInfo**

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| parentDeviceName | String | Parent Mac's name |
| childDeviceName | String | Child Mac's name |
| sharedSecret | -- | Stored in Keychain, not in DB |
| pairedAt | Date | When devices were paired |

**DeviceConfig**

| Field | Type | Description |
|-------|------|-------------|
| role | Enum | `.parent` or `.child` |
| childProfileId | UUID? | Which profile this device is assigned to (child mode only) |
| internetEnabled | Bool | Current manual override state |

Note: The parent PIN (PBKDF2 hash + salt) is stored in the macOS Keychain, NOT in SwiftData. Similarly, `PairingInfo.sharedSecret` is stored in the Keychain. The Keychain fields are accessed via Security framework APIs (`SecItemAdd`, `SecItemCopyMatching`).

### Sync Strategy

- Parent dashboard is the **source of truth** for rules (schedules, app restrictions, profiles).
- Child agent is the **source of truth** for usage data (it observes activity directly).
- When parent and child are on the same network, changes sync immediately via the Bonjour/TLS channel.
- When disconnected, the child agent continues enforcing the last-known rules. Changes queue on the parent and sync when reconnected.
- Conflict resolution: parent rules always win. Usage data is append-only (no conflicts possible).

---

## Core Features

### Feature 1: Internet On/Off Toggle

**Mechanism**: The LaunchDaemon manages `pf` (packet filter) rules.

- **Blocking**: Adds a rule to block all outbound TCP/UDP traffic for the child's user. This drops all internet traffic while preserving local network (LAN) communication.
- **Allowing**: Removes the block rule, restoring normal connectivity.
- **LAN exemption**: Rules always allow traffic to local subnets (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) so agent-dashboard communication continues working even when internet is "off".
- **DNS blocking**: When internet is off, DNS to external servers (port 53) is also blocked. This prevents DNS-based bypasses and gives the child a clear "no connection" experience.

**Implementation**: The daemon uses the `pf` anchor approach to isolate PaCo rules from any existing firewall configuration:

```
# Anchor: com.paco
# Load rules:  pfctl -a com.paco -f /etc/pf.anchors/com.paco
# Flush rules: pfctl -a com.paco -F rules
```

The daemon calls `pfctl` via Swift's `Process` API (formerly `NSTask`).

**Manual toggle**: Parent taps toggle in dashboard -> command sent over Bonjour/TLS to agent -> agent sends XPC to daemon -> daemon updates pf rules. Sub-second latency on LAN.

### Feature 2: Schedule-Based Automation

- The LaunchAgent runs a scheduler (`DispatchSourceTimer`) that checks schedules every 30 seconds.
- When a schedule boundary is reached (e.g., 21:00 "internet off"), the agent sends an XPC command to the daemon.
- **Conflict resolution**: Most restrictive wins. If two schedules overlap and one says "off" and another says "on", internet is off.
- **Pre-notification**: The child sees a notification 5 minutes before internet turns off: "Internet will be turned off at 9:00 PM."
- **Grace period**: Configurable 0-15 minutes after the "off" time. During the grace period, internet stays on and the child sees a countdown. Lets them save work.

### Feature 3: App Launch Restrictions

- The LaunchAgent subscribes to `NSWorkspace.didLaunchApplicationNotification`.
- When an app launches, it checks the bundle identifier against the restriction list.
- **If blocked**: The agent sends XPC to the daemon, which sends `SIGKILL` to the process (root privileges allow killing any user's process). The child sees a notification: "App X is not available right now."
- **If scheduledOnly**: Checks whether current time falls within the allowed schedule. If outside the window, kills the process.
- **Polling fallback**: Every 10 seconds, the agent polls `NSWorkspace.shared.runningApplications` to catch apps launched before the agent started or apps that respawn.

### Feature 4: Usage Time Tracking

The agent tracks two categories:

1. **Internet time**: Records timestamps when internet is enabled/disabled. Calculates total online duration per day.
2. **Per-app usage**: On app launch, records start time. On app termination (`NSWorkspace.didTerminateApplicationNotification`), calculates duration. Aggregated per day.

- Data stored locally in SQLite via SwiftData.
- Synced to parent dashboard periodically (every 5 minutes when connected) or on-demand.
- Dashboard displays: daily/weekly bar charts, top apps by usage, internet time trends.

---

## UI Design

### Role Selection (First Launch)

A simple onboarding screen with two large cards:

- **"Set up as Parent"** -- Prompts to create a 6-digit PIN. Enters dashboard mode.
- **"Set up as Child"** -- Prompts to enter the parent's PIN to authorize setup, then assign a child profile. Enters child mode.

Role is stored in `DeviceConfig` and persists. Switching roles requires the parent PIN.

### Parent Dashboard (macOS Window App)

Sidebar navigation with these sections:

- **Home** -- Overview of all paired child devices with live status (online/offline, internet on/off, current app). Prominent internet toggle per child at the top.
- **Profiles** -- Manage child profiles (name, avatar).
- **Schedules** -- Create/edit internet schedules per profile. Visual timeline editor showing on/off blocks across the week.
- **App Rules** -- Per-profile list of restricted apps. Search-and-add from installed apps on child device (synced list). Set to "Always Blocked" or "Schedule Only".
- **Usage** -- Bar charts and tables: daily internet time, per-app usage breakdown, weekly trends. Date picker for historical data.
- **Devices** -- List of paired child devices, pairing status, last seen time. "Pair New Device" button.
- **Settings** -- Change PIN, configure grace periods, notification preferences.

Key interactions:

- Real-time status updates when connected to child device.
- Greyed-out state with "Last seen: X minutes ago" when child device is disconnected.

### Child Mode (Menu Bar + Minimal Window)

- **Menu bar icon**: A small shield icon. Green = internet on, red = internet off, yellow = grace period.
- **Menu bar popover** (click icon): Current status ("Internet is ON/OFF"), next schedule change ("Internet turns off at 9:00 PM"), grace period countdown if applicable.
- **Main window** (via menu bar "Open PaCo"): Minimal view showing today's schedule as a timeline, and the child's own usage stats for the day. No controls -- purely informational. Accessing parent settings requires PIN.

### Pairing Flow

1. Parent opens Dashboard > Devices > "Pair New Device".
2. Dashboard displays a 6-digit pairing code (valid for 5 minutes).
3. On child's Mac, during child setup, user enters the pairing code.
4. Devices discover each other via Bonjour, verify the code, derive a shared TLS secret via HKDF.
5. Paired. Parent assigns a profile to the child device.

---

## Security & Tamper Resistance

### PIN Protection

- Parent PIN stored as a PBKDF2 hash with random salt in the local Keychain (not in the SQLite database).
- Lockout policy: 5 failed attempts = 5-minute lockout. 10 failed attempts = 30-minute lockout.
- PIN is required for: switching to parent mode, uninstalling the app, disabling the LaunchDaemon, changing schedules.

### LaunchDaemon Persistence

- The LaunchDaemon runs as root, registered via `SMAppService`. It auto-restarts if killed (`KeepAlive` in the launchd plist).
- Force-quitting PaCo.app does not stop enforcement. The daemon and agent continue running independently.
- Removing the daemon requires admin authentication (parent PIN triggers `AuthorizationRef` for `SMAppService` unregistration).

### Anti-Bypass Measures

**For all ages:**

- Daemon periodically (every 30 seconds) verifies its pf anchor rules are still active. If rules were removed externally, it re-applies them and logs the event. Parent receives a notification: "Someone tried to disable internet restrictions."

**For tech-savvy children:**

- **VPN bypass detection**: If a VPN app is on the blocked list, app restriction catches it. The daemon also monitors for new network interfaces (`utun*`, `ipsec*`) appearing and blocks traffic on them.
- **DNS bypass prevention**: When internet is "off", all outbound traffic is blocked including DNS. DNS-over-HTTPS bypass is impossible because HTTPS is also blocked.

**Admin account caveat**: If the child has a macOS admin account, they can ultimately bypass all controls (via `sudo`). The design assumes the child uses a Standard (non-admin) macOS account. The app warns the parent during setup if the child's macOS account has admin privileges.

### Network Communication Security

- Agent-Dashboard communication uses TLS 1.3 with a pre-shared key derived from the pairing code (via HKDF).
- All traffic encrypted, even on local network.
- Replay protection via sequence numbers in the protocol.

### Explicit Non-Goals (V1)

- Protecting against a child with physical access to another admin account on the same Mac.
- Protecting against Recovery Mode / SIP disable (OS-level concern).
- Controlling other devices (phones, tablets) -- outside scope.

---

## Feature Roadmap

| Version | Features |
|---------|----------|
| V1.0 | Internet on/off + schedules + app restrictions + usage tracking |
| V1.1 | Activity alerts + request/approve workflow |
| V1.2 | Screen time budgets + bedtime mode + weekly report |
| V2.0 | Domain/category filtering (DNS-level, no entitlement needed) |
| V2.5 | Network Extension content filtering (requires Apple entitlement) |
| V3.0 | iOS companion app + cross-device sync |

### Future Feature Descriptions

**Request/Approve Workflow (V1.1)**: When a child hits a block, they can tap "Request Access." Parent gets a notification with one-tap Approve/Deny. Temporary overrides: "Allow for 30 minutes" or "Allow until end of day." Turns the tool from punitive to collaborative.

**Screen Time Budgets (V1.2)**: Daily budgets ("2 hours of internet" or "1 hour of gaming apps") instead of fixed schedules. Child uses budget whenever they want. Teaches self-regulation.

**Bedtime Mode (V1.2)**: Superset of internet-off: dims screen brightness, enables Night Shift, blocks all apps except a configurable allow-list (e.g., Books, Music).

**Weekly Report (V1.2)**: Auto-generated summary: total screen time, top apps, internet hours, blocked attempts. Displayed in dashboard, optionally exported as PDF.

**Domain/Category Filtering (V2.0)**: Allow/block specific categories (social media, gaming, adult content, streaming) at the DNS level. Uses open-source categorized domain lists.

**Content Filtering (V2.5)**: Deep packet inspection via NEFilterDataProvider (Network Extension framework). Block specific pages, detect proxy/VPN bypass at network level. Requires Apple Developer Program + Network Extension entitlement approval.

**iOS Companion (V3.0)**: iPhone app for parent remote control. View status, toggle internet, approve requests from anywhere. Requires a lightweight relay server or iCloud-based sync.

**Location-Aware Rules (V3+)**: Different rules based on Wi-Fi SSID or IP range (home vs. school vs. elsewhere).

**AI-Assisted Monitoring (V4+)**: On-device ML for flagging concerning patterns. Privacy-preserving: all analysis on-device, parent sees alerts not raw data.
