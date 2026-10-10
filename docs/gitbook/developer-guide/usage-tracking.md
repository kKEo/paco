---
description: Foreground time per app and internet-on time.
---

# Usage tracking

## Model

`UsageLedger` (PaCoShared, `Usage/UsageLedger.swift`) is a pure value type that accounts **foreground** time per bundle ID plus launch counts. It has no AppKit dependency, so all of its behaviour is unit-tested.

| Event | Effect |
|---|---|
| `activate(bundleId:appName:at:)` | Fold the previous foreground interval into its total, start a new one. `nil` pauses accrual. |
| `launch(bundleId:appName:)` | Increment the launch count. |
| `terminate(bundleId:at:)` | If it was the foreground app, fold its interval and stop. |
| `snapshot(at:)` | Totals including the still-running interval, sorted by duration. |
| `reset(at:)` | New day: totals cleared, the current foreground app keeps accruing from `at`. |

## Agent wiring

* `AppMonitor` reports `didActivateApplicationNotification`, plus the frontmost app at start, so an app already open when the agent starts counts from then.
* Only `activationPolicy == .regular` apps are reported for usage. Helpers and background agents are ignored. Restrictions still apply to every process.
* `UsageTracker` owns the ledger and internet-on time. Internet time is derived from the daemon's state, polled every 30 s through `isInternetEnabled`; on a change the tracker starts or stops an interval and appends an event.
* Every tick writes a `UsageTransfer` to `usage.json`. On agent start the tracker restores today's snapshot so a restart does not reset the day.
* At midnight counters reset; an open internet interval restarts from the rollover.

## App side

`AppDelegate` watches `usage.json` with a `DispatchSource` and `SyncManager.readUsage` upserts a `UsageRecord` for the day and profile. The child view reads `usage.json` directly every 30 seconds.

## Precision

Internet time has 30-second granularity. App time is exact to the notification, with snapshots up to 30 s stale on disk.
