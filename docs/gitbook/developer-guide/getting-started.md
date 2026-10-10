---
description: Generate the project, build, run and test.
---

# Getting started

## Prerequisites

* macOS 14 or later, Xcode 15 or later.
* [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`.
* For end-to-end testing of the daemon and agent: a Developer ID certificate.

## Generate the Xcode project

The Xcode project is generated from `project.yml`. Never edit `PaCo.xcodeproj` by hand; regenerate it after adding, removing or renaming source files, or changing targets.

```bash
xcodegen generate
```

## Build

```bash
make build                 # Debug build of the PaCo scheme (builds all four targets)
make build-release         # Release build into build/DerivedData
```

## Test

```bash
xcodebuild test -project PaCo.xcodeproj -scheme PaCoTests -configuration Debug

# One class or one method
xcodebuild test -project PaCo.xcodeproj -scheme PaCoTests \
  -only-testing:PaCoTests/ScheduleEvaluatorTests/testOvernightWindowBlocksIntoNextMorning
```

The test bundle links only PaCoShared. Logic that needs unit tests must live in the package. See [Testing](testing.md).

## Running it

What works depends on signing:

| Setup | UI | Daemon/agent |
|---|---|---|
| Run the app from Xcode, unsigned | Works | Not installed, so the icon is grey and enforcement is off |
| Installed pkg built with `TEAM_ID` | Works | Works |
| Installed Debug daemon with `PACO_ALLOW_UNSIGNED_XPC=1` | Works | Works, development only |

The daemon accepts XPC peers only if they are signed by the same team as the daemon itself. See [Security model](security-model.md#xpc-peer-validation) and [Packaging and release](packaging.md).

### Two Macs, or one

Pairing and policy push need two Macs on one network, each with the pkg installed, one set up as Parent and one as Child. A single Mac in the Parent role exercises the daemon, firewall, agent, schedules, app rules and usage, because the parent also pushes policy to its own daemon.

### Reset state between runs

```bash
rm -rf ~/Library/Application\ Support/com.paco    # app database + per-user files
make clear-policy                                  # daemon policy + intended block state (sudo)
sudo pfctl -a com.paco -F rules                    # lift a block immediately
```
