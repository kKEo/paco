---
description: Conventions and the traps that are easy to fall into.
---

# Contributing

## Conventions

* **Project file.** Edit `project.yml`, then `xcodegen generate`. Never hand-edit `PaCo.xcodeproj`.
* **Where logic goes.** Anything that decides something belongs in PaCoShared as a pure type with tests. Targets are thin adapters to AppKit, launchd, XPC and Network.framework.
* **Concurrency.** `SWIFT_STRICT_CONCURRENCY` is `minimal`. The app and agent keep state on the main queue; hop to main in every XPC reply and network callback. `AppDelegate` is `@MainActor`.
* **Logging.** Use `PaCoLogger` with the right category.
* **Docs.** Update this book, `README.md` and `CLAUDE.md` when behaviour changes.

## Traps

| Trap | Rule |
|---|---|
| Startup in `onAppear` | All startup goes in `AppDelegate.applicationDidFinishLaunching`. |
| `@Query` arrays in sync code | `SyncManager` fetches fresh from the `ModelContext`. |
| New SwiftData model not registered | Add it to `Schema([...])` in `AppDelegate.swift`. |
| pf rule order | Pass rules stay `quick` and before the block. `FirewallRuleTests` enforces it. |
| `FirewallManager` lock | Inside the lock, call `applyBlockLocked()`, never `disableInternet()`. |
| Reply routing | Reply to the connection identity; never to a payload's device name. |
| Peer reachability | Use `connectedIdentities` / `isParentConnected`, not the connection dictionaries. |
| PIN material on a child | Never copy it there; verify via `.verifyPIN`. |
| Bootstrap keys | An unpaired child must stay plain TCP and drop connections. |
| Publishing policy from a child | Only the parent role calls `publishPolicy`. A child's SwiftData is empty and would wipe the parent's policy. |
| KDF inputs | `CryptoKDF.deriveKey` rejects empty salt and password; keep the guard. |

## Before opening a pull request

```bash
xcodegen generate
make build
xcodebuild test -project PaCo.xcodeproj -scheme PaCoTests -configuration Debug
```

Run the relevant items of the [manual test plan](testing.md#manual-test-plan) when touching the daemon, agent or networking.
