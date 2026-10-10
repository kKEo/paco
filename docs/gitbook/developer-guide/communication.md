---
description: XPC, the per-user files, and Bonjour — what flows where.
---

# Communication channels

PaCo uses three channels.

## 1. App and agent to daemon: XPC

Mach service `com.paco.daemon`, interface `DaemonXPCProtocol` in PaCoShared. Every connection carries a code-signing requirement; see [Security model](security-model.md#xpc-peer-validation).

| Method | Caller | Purpose |
|---|---|---|
| `updatePolicy(_:reply:)` | App | Replace schedules and restrictions with a JSON `PolicyTransfer`. Persisted, then re-evaluated at once. |
| `setActiveProfile(_:reply:)` | App | Select which profile's rules apply on this Mac; `nil` means all. Sent at every launch and on change. |
| `grantInternetOverride(requestId:until:reply:)` | App (child) | Approved time extension. Clears a standing manual "off". |
| `setManualInternet(enabled:minutes:reply:)` | App (parent) | Timed manual toggle from Home. |
| `clearManualInternet(reply:)` | App (parent) | "Back to schedule". |
| `fetchPolicy(reply:)` | Agent, app | The current `DaemonPolicy` as JSON. |
| `isInternetEnabled(reply:)` | Agent, app | Whether the block is currently loaded. |
| `killProcess(pid:reply:)` | Agent | Kill a process if its signed bundle ID is in the restricted set. |
| `verifyFirewallIntegrity(reply:)`, `status(reply:)` | Diagnostics | Integrity check, human-readable status. |

XPC replies arrive on an arbitrary queue. Both clients hop to the main queue before touching state.

## 2. Agent to app: per-user files

Directory: `~/Library/Application Support/com.paco/`. No policy lives here.

| File | Writer | Reader | Content |
|---|---|---|---|
| `usage.json` | Agent, every 30 s | App, via a `DispatchSource` watcher | `UsageTransfer` for today |
| `events.json` | Agent | Nobody yet | Last 100 `NotificationEvent`s: app blocked, internet on/off |
| `child-requests.json` | App (child) | App (child) | `ChildRequestStore`: sent requests and outcomes |
| `PaCo.store` | App | App | SwiftData database |

## 3. Parent app to child app: Bonjour + TLS-PSK

Service type `_paco._tcp` in `local.`. The child advertises, the parent connects. Details in [Parent–child networking](networking.md).

| Command | Direction | Payload | Reply |
|---|---|---|---|
| `.updatePolicy` | Parent → child | `PolicyTransfer` | `PaCoResponse` success/failure |
| `.requestExtension` | Child → parent | `ExtensionRequestPayload` | None; answered later |
| `.approveExtension` | Parent → child | `ExtensionResponsePayload` with `grantedMinutes` | None |
| `.denyExtension` | Parent → child | `ExtensionResponsePayload` | None |
| `.verifyPIN` | Child → parent | `PINVerifyRequest` with a nonce | `PaCoResponse` carrying `PINVerifyResult` |

## Flows

### Policy change on the parent

```mermaid
sequenceDiagram
  participant V as Dashboard view
  participant S as SyncManager
  participant D as AppDelegate (parent)
  participant PD as Parent daemon
  participant C as Child app
  participant CD as Child daemon
  V->>V: insert/delete + context.save()
  V->>S: syncSchedules(context:)
  S->>S: fetch fresh from ModelContext
  S->>D: onPolicyChanged(PolicyTransfer)
  D->>PD: updatePolicy (XPC)
  D->>C: .updatePolicy (each connected child)
  C->>CD: updatePolicy (XPC)
  CD-->>C: ok
  C-->>D: PaCoResponse(success)
```

A child that is offline gets the full policy in `onParentConnected` when it reconnects.

### Time extension

```mermaid
sequenceDiagram
  participant CV as Child view
  participant CL as ChildRequestLog
  participant P as Parent app
  participant C as Child app
  participant CD as Child daemon
  CV->>P: .requestExtension (requestId, minutes)
  CV->>CL: record(requestId) — only if the send succeeded
  P->>P: insert TimeExtensionRequest, childDeviceName = connection identity
  Note over P: parent taps Approve (enabled only while connected)
  P->>C: .approveExtension (to that identity)
  P->>P: mark approved only after the send succeeded
  C->>CL: resolve(requestId) — one-shot replay guard
  C->>CD: grantInternetOverride(until: now + minutes)
  CD->>CD: re-evaluate → enable internet
```

### Parent Access on a child

```mermaid
sequenceDiagram
  participant CV as Child: Parent Access
  participant C as Child AppDelegate
  participant P as Parent AppDelegate
  CV->>C: attemptRemoteUnlock(pin)
  C->>P: .verifyPIN(nonce, pin)
  P->>P: AppState.attemptUnlock(pin, unlockOnSuccess: false) — shared lockout
  P-->>C: PaCoResponse(PINVerifyResult(nonce, outcome))
  C-->>CV: success / incorrect / lockedOut / parentUnavailable (10 s timeout)
```
