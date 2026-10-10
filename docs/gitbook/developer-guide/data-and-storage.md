---
description: SwiftData models, files on disk and Keychain items.
---

# Data and storage

## SwiftData (app)

Store: `~/Library/Application Support/com.paco/PaCo.store`, set explicitly in `AppDelegate` so it does not collide with other apps using SwiftData's shared default store. Models live in `PaCoShared/Sources/PaCoShared/Models/` and must be registered in the `Schema([...])` list in `AppDelegate.swift`.

| Model | Key fields | Notes |
|---|---|---|
| `DeviceConfig` | `role`, `childProfileId` | One per Mac. Absent means onboarding. |
| `ChildProfile` | `name`, `schedules`, `appRestrictions`, `usageRecords` | Relationships cascade on delete. |
| `Schedule` | `label`, `daysRaw`, `offHour/Minute`, `onHour/Minute`, `gracePeriodMinutes`, `isActive`, `childProfile` | Conforms to `Schedulable`. |
| `AppRestriction` | `bundleIdentifier`, `appName`, `restrictionType`, `allowedScheduleId`, `childProfile` | |
| `UsageRecord` | `date`, `internetOnDuration`, `appUsage`, `childProfile` | Imported from `usage.json`. |
| `PairingInfo` | `parentDeviceName`, `childDeviceName`, `pairedAt` | Parent side; the key itself is in the Keychain. |
| `TimeExtensionRequest` | `id`, `childDeviceName`, `requestedMinutes`, `reason`, `statusRaw`, timestamps | `childDeviceName` is the connection identity. |

On a child Mac only `DeviceConfig` is used.

## Transfer types (PaCoShared, `Network/`)

Codable mirrors used across process and network boundaries, because the daemon and agent cannot use SwiftData:

`ScheduleTransfer`, `AppRestrictionTransfer`, `PolicyTransfer`, `DaemonPolicy`, `InternetOverride`, `ManualInternetOverride`, `UsageTransfer`, `AppUsageEntry`, `NotificationEvent`, `ChildRequestStore`/`ChildRequestRecord`, `PaCoMessage`, `PaCoResponse`, `ExtensionRequestPayload`, `ExtensionResponsePayload`, `PINVerifyRequest`, `PINVerifyResult`.

## Files

| Path | Owner | Content |
|---|---|---|
| `/Library/Application Support/PaCo/policy.json` | root, `0644` | `DaemonPolicy` |
| `/Library/Application Support/PaCo/daemon-state.json` | root | `{"blocking": Bool}`, intended firewall state |
| `/Library/Application Support/PaCo/PaCoDaemon`, `PaCoAgent` | root | Installed binaries |
| `/etc/pf.anchors/com.paco` | root | Block rules while blocking |
| `/etc/pf.conf.paco-backup` | root | Original `pf.conf` before PaCo added its anchor line |
| `~/Library/Application Support/com.paco/PaCo.store*` | user | SwiftData |
| `~/Library/Application Support/com.paco/usage.json` | user | Today's `UsageTransfer` |
| `~/Library/Application Support/com.paco/events.json` | user | Last 100 agent events |
| `~/Library/Application Support/com.paco/child-requests.json` | user | Child's request log |

## Keychain

Generic passwords with service `com.paco.keychain`; the account is the key name.

| Account | Content | Mac |
|---|---|---|
| `com.paco.pin.hash`, `com.paco.pin.salt` | PIN PBKDF2 hash and salt | Parent |
| `com.paco.pin.attempts`, `com.paco.pin.lockoutUntil` | Brute-force counter and lockout end | Parent |
| `com.paco.pairing.keys` | JSON list of `{identity, key}` | Both |

```bash
security find-generic-password -s com.paco.keychain -a com.paco.pairing.keys
```
