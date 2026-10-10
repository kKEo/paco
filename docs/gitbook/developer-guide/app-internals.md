---
description: AppDelegate lifecycle, AppState, the PIN gate and SyncManager.
---

# App internals

## Startup

All startup runs once in `AppDelegate.applicationDidFinishLaunching`. Never put startup work in a view's `onAppear`: with `MenuBarExtra(.window)`, content appears only when the popover opens and again on every open.

Sequence:

1. `appState.determineMode(context:)` reads `DeviceConfig` and sets `role` and `mode`.
2. `daemonClient.connect()`, then a 30-second status refresh timer.
3. Wire callbacks: `SyncManager.onPolicyChanged` → `publishPolicy`; `AppState.onActiveProfileChanged` → `setActiveProfile` XPC; `AppState.remotePINVerifier` → `verifyPINWithParent`.
4. Re-assert the active profile to the daemon.
5. Start the `usage.json` watcher and import usage once.
6. `configureRole()` and `observeRole()`.

`PaCoApp` injects `appState` (Observation), `daemonClient` and `bonjour` (`ObservableObject`) and the model container into the `MenuBarExtra` content.

## Role wiring

`configureRole()` is idempotent per role and re-runs when `appState.role` changes, observed with `withObservationTracking`, so finishing onboarding needs no relaunch.

| Child | Parent |
|---|---|
| `onIncomingMessage` → `handleChildIncoming` | `SyncManager.syncAll` → push to own daemon |
| `onIncomingResponse` → `handleChildResponse` (PIN results) | `onChildRequest` → `handleParentIncoming` |
| `startAdvertising(name:)` | `onChildResponse` → log acks |
| | `onParentConnected` → `pushPolicy(to:)` |
| | `startBrowsing()` |

## AppState and the PIN gate

`AppState` is `@Observable`:

* `mode`: `.onboarding`, `.parent` or `.child`. Drives `ContentView`.
* `role`: persisted `DeviceRole?`. Drives networking.
* `isUnlocked`: the dashboard shows only while true; otherwise `ParentUnlockView`.

`lock()` runs from `DashboardView.onDisappear` and `applicationDidResignActive`. On a child it also returns `mode` to `.child`.

`attemptUnlock(pin:unlockOnSuccess:)` does the Keychain check with lockout and is shared by the parent's own unlock and the parent's answer to a child's `.verifyPIN` (with `unlockOnSuccess: false`). `attemptRemoteUnlock(pin:completion:)` is the child's path; `verifyPINWithParent` sends a nonce-tagged request and fails with `.parentUnavailable` after 10 seconds.

## SyncManager

`SyncManager.currentPolicy(context:)` always **fetches fresh** from the `ModelContext`. Views call `syncSchedules`/`syncRestrictions` after `context.save()`; all three entry points publish the same full policy.

{% hint style="warning" %}
Never pass a `@Query` array into sync code. Inside a button action it still reflects the state before the insert or delete, which left enforcement one change behind.
{% endhint %}

`publishPolicy` runs only in the parent role and sends to the local daemon and every identity in `bonjour.connectedIdentities`.

## Child side

* `.updatePolicy` → `daemonClient.pushPolicy` → reply `PaCoResponse` with the daemon's result.
* `.approveExtension` → `ChildRequestLog.resolve` (rejects unknown or replayed ids) → `grantOverride`.
* `.denyExtension` → `ChildRequestLog.resolve`.

`ChildRequestLog` is an `ObservableObject` wrapper over the pure `ChildRequestStore`, persisted to `child-requests.json`. Pending entries older than 24 hours are dropped at load. The child view records a request only after `sendToParent` succeeded.
