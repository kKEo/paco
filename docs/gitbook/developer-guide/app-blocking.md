---
description: How restricted apps are detected and killed.
---

# App blocking

App blocking is split between the per-user agent, which can see the user's apps, and the root daemon, which can kill them.

## Detection (agent)

`PaCoAgent/AppMonitor.swift` uses `NSWorkspace`:

* `didLaunchApplicationNotification`: check the new app immediately.
* A 10-second polling timer: check every running app, which catches apps already open when a rule arrives and apps that slipped past the notification.
* `didActivateApplicationNotification` and `didTerminateApplicationNotification`: used for usage tracking only.

On every 30-second tick, `AgentDelegate` calls `fetchPolicy` and passes `policy.activeRestrictions` to the monitor.

For each running app whose bundle ID matches a restriction:

| Restriction | Agent action |
|---|---|
| `.blocked` | Ask the daemon to kill it. |
| `.scheduledOnly` | Ask `currentPolicy.isScheduledAppAllowed(scheduleId:)`; kill if not allowed. |

## Killing (daemon)

`killProcess(pid:)` in `PaCoDaemon/ProcessManager.swift` does not trust the PID it is given:

1. It reads the target's bundle identifier from the process's **code signature** (`SecCodeCopyGuestWithAttributes` → `SecCodeCopySigningInformation`), not from a name the caller supplies.
2. It refuses if the identifier cannot be determined or is not in the restricted set.
3. Only then it sends `SIGKILL`.

The restricted set comes from `DaemonPolicy.restrictedBundleIDs`, updated by `PolicyEngine` on every policy change. A caller therefore cannot use the daemon to kill arbitrary processes, only apps the parent restricted.

## Feedback

On a successful kill the agent appends an `appBlocked` event to `events.json` and logs it. It cannot show a notification: `UNUserNotificationCenter` needs an app bundle, and the agent is a bare executable. Surfacing these events in the app is on the roadmap.
