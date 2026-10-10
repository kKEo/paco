---
description: Trust boundaries, what each mitigation defends against, and what is out of scope.
---

# Security model

## Assets and adversary

The adversary is the **monitored child**: logged in to a **standard** macOS account on their own Mac, curious, technically able, possibly with the source code. Assets to protect:

1. The enforcement decision (internet on/off, which apps run).
2. The parent PIN.
3. The parent–child channel.

## Trust boundaries and mitigations

| Threat | Mitigation | Where |
|---|---|---|
| Edit the schedule or forge an extension on disk | Policy lives only in the daemon, persisted root-owned under `/Library/Application Support/PaCo/`; the agent only reads it | `PolicyEngine` |
| Call the daemon from an arbitrary binary | Code-signing requirement on every XPC connection | `DaemonDelegate` |
| Make the daemon kill an arbitrary process | Kill only if the target's *signed* bundle ID is in the parent's restricted set | `ProcessManager` |
| Delete the pf anchor | Integrity check every 15 s re-applies the block | `FirewallManager.verifyIntegrity` |
| Unload the agent | Daemon re-bootstraps it every 15 s; launchd `KeepAlive` | `DaemonService.ensureAgentRunning` |
| Reboot to get an open window | Intended block state persisted and re-applied at daemon start | `reconcileOnStartup` |
| Open the parent dashboard on a shared Mac | PIN gate on every open; re-locks on popover close and app deactivation | `AppState.isUnlocked` |
| Brute-force the PIN through the UI | 5 attempts, then a 5-minute lockout, shared by local and remote checks | `PINManager` |
| Recover the PIN offline from the child's Mac | The PIN hash never leaves the parent; a child asks the parent to verify (`.verifyPIN`) | `AppDelegate.verifyPINWithParent` |
| Send commands to a child from the LAN | TLS-PSK with a pairing-derived key; an unpaired child drops every connection | `BonjourService` |
| Replay an approval | Each request id resolves once in the persisted `ChildRequestStore` | `ChildRequestLog` |
| Crash the app with a malformed payload | KDF rejects empty salt/password; frames are length-bounded; decode failures are ignored | `CryptoKDF`, `FrameCodec` |

## XPC peer validation

At startup the daemon reads its own Team Identifier from its code signature (`SecCodeCopySelf` → `kSecCodeInfoTeamIdentifier`) and builds:

```
anchor apple generic
and (identifier "com.paco.app" or identifier "com.paco.agent")
and certificate leaf[subject.OU] = "<daemon's team id>"
```

Each accepted `NSXPCConnection` gets this via `setCodeSigningRequirement(_:)`, so the system validates the peer on every message. There is no PID lookup and therefore no PID-reuse race, and there is no hard-coded team id to forget.

If the daemon itself has no team id (unsigned or ad-hoc build), it refuses every peer. A **Debug** daemon accepts unsigned peers only when launched with `PACO_ALLOW_UNSIGNED_XPC=1`; this branch is compiled out of Release.

## PIN storage

* PBKDF2-HMAC-SHA256, 210,000 iterations, 16-byte random salt, 32-byte output, constant-time comparison.
* Keychain generic passwords, service `com.paco.keychain`, accessible when unlocked, this device only.
* Attempt counter and lockout end are Keychain items too.

## Out of scope

These are not defended against, by design or for now:

* **An administrator child.** An admin can `pfctl -d`, unload launchd jobs or delete files. Children must use standard accounts.
* **Physical access.** Recovery mode, target disk mode or reinstalling macOS bypass everything.
* **A LAN proxy.** Private ranges stay reachable, so a proxy on another device in the home network bypasses the block.
* **The parent's own account.** Anyone using it can delete the PIN items from the Keychain.
* **Clock changes.** Schedules use the system clock; a standard user cannot change it, an admin can.
