---
description: Unit tests, what they cover, and the manual test plan.
---

# Testing

## Unit tests

`PaCoTests` is an XCTest bundle that links **only PaCoShared**. App, daemon and agent code cannot be imported, which is why decision logic lives in the package.

```bash
xcodebuild test -project PaCo.xcodeproj -scheme PaCoTests -configuration Debug
```

| Suite | Tests | Covers |
|---|---|---|
| `ScheduleEvaluatorTests` | 17 | Same-day and overnight windows, day attribution across midnight and Sunday→Monday, grace periods, most-restrictive-wins, overrides |
| `DaemonPolicyTests` | 9 | Profile filtering of schedules and restrictions, precedence of manual override and extension, "Follows Schedule" rules, `apply`, round-trip |
| `ChildRequestStoreTests` | 9 | Record/resolve, replay rejection, withdraw, expiry, pruning, persistence across reload |
| `UsageLedgerTests` | 8 | Foreground accrual, switching, termination, seeding, day reset, pause |
| `ModelTests` | 7 | Model initialisers and Codable round-trips |
| `PairingKeyTests` | 5 | Deterministic derivation, code generation, constant-time compare, empty-salt guard |
| `FirewallRuleTests` | 4 | Rule content, preserved destinations, `quick` ordering invariant |
| `FrameCodecTests` | 4 | Encode/decode, big-endian header, malformed headers |
| `PINManagerTests` | 4 | Hashing and verification |

There are 67 tests in total. None of them touch the Keychain, launchd, pf or the network.

## Manual test plan

The daemon, agent, firewall and Bonjour need a signed install. With two Macs:

1. **Pairing.** Parent sees the child under Nearby Devices; pair; status becomes Connected within 30 s.
2. **Policy push.** Add a schedule covering "now" on the parent; the child's internet goes off within a second; `policy.json` on the child lists it.
3. **Overnight semantics.** A Thursday 21:00–07:00 schedule blocks Friday 02:00 and not Friday 22:00.
4. **App rules.** Block an app; it quits on launch and within 10 s if already open. A "Follows Schedule" rule on a disabled schedule does not block.
5. **Request flow.** Child requests 15 min; parent approves; child internet on immediately; the card shows the end time. Relaunch the child app before approving; the approval is still accepted.
6. **Offline.** Put the child to sleep; Approve is disabled; Deny works.
7. **Parent Access.** Correct PIN unlocks; 5 wrong PINs lock out on the parent too; with the parent offline the prompt says so.
8. **Manual toggle.** Home switch on the parent: banner appears; "Back to schedule" clears it.
9. **Tamper.** `sudo pfctl -a com.paco -F rules` during a block; rules return within 15 s.
10. **Reboot.** Reboot during a block; internet stays off from boot.
11. **Usage.** Keep an app frontmost for a few minutes; its time grows while open.
