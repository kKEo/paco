---
description: Gaps in the current version, open questions, and the roadmap.
---

# Known limitations and roadmap

## Behaviour

* **Child Macs enforce every profile.** A child's daemon has no active profile, because profiles live only in the parent's SwiftData. The parent pushes all profiles' rules, so with several children each child's Mac enforces all of them. Fix: send the target profile per paired device, for example a profile id on `PairingInfo` passed with `.updatePolicy`.
* **No remote on/off.** The Home switch controls the local daemon. A child Mac can only be opened up remotely by approving a request.
* **Child usage stays on the child.** Nothing sends `usage.json` to the parent; the parent's Usage page shows the parent Mac's own usage.
* **No notifications.** The agent cannot post user notifications and `events.json` has no reader. Children get no message when an app is closed or a grace period starts.
* **Pairing is tied to the computer name.** Renaming the child's Mac breaks auto-connect until re-paired.
* **One parent per child.** The child stores a single key under `"parent"`.
* **Shared Mac.** On a single Mac in the Parent role, rules apply to every account, including the parent's.
* **Role reset.** **Reset & Change Role** deletes only `DeviceConfig`; profiles and rules remain in the store. Changing role at runtime does not stop the previous role's Bonjour services; relaunch after switching.

## Platform and packaging

* **Login item.** PaCo.app does not register itself to open at login; users must add it manually. `SMAppService.mainApp.register()` would fix this.
* **Local Network privacy.** `Info.plist` declares neither `NSLocalNetworkUsageDescription` nor `NSBonjourServices` (`_paco._tcp`). On macOS 15 and later these are expected for Bonjour browsing and local connections; verify on Sequoia and add them.
* **`pfctl -e` when pf is already enabled.** `applyBlockLocked` treats any non-zero exit from `pfctl -e` as a failure. If pf reports "already enabled" with a non-zero status on the shipping macOS versions, a second block would fail after the first. Verify, and consider `pfctl -E` with its reference token or ignoring that specific exit.

### Packaging

* **Binaries copied into a signed bundle.** `make pkg` copies `PaCoDaemon` and `PaCoAgent` into `PaCo.app/Contents/Resources` after the app was signed. Adding files to a sealed bundle invalidates its signature, which would break notarization and the daemon's code-signing requirement for the app. Stage the binaries directly under `Library/Application Support/PaCo/` in the pkg root instead, or embed them before signing.
* **`make clear-pin` and the README's PIN reset commands** use the Keychain item name as the service (`-s com.paco.pin.hash`). The items are stored with service `com.paco.keychain` and the key as the account, so those commands find nothing. The correct form is in [Debugging](debugging.md#reset).

## Security

See [Security model → Out of scope](security-model.md#out-of-scope): administrator children, physical access, LAN proxies, the parent's own account, and clock changes.

## Roadmap

| Version | Features |
|---|---|
| **V1 (current)** | Internet schedules via pf, app rules, usage, Bonjour pairing, time-extension requests |
| V1.2 | Daily usage budgets, bedtime mode, usage reports |
| V2.0 | DNS-level content filtering |
| V2.5 | Network Extension for per-app traffic control |
| V3.0 | iOS companion app |
