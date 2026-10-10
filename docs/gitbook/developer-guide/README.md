---
description: Orientation for developers working on PaCo.
---

# Developer Guide

This guide explains how PaCo is built: the processes, how they talk to each other, where policy lives and how it is enforced, the security model, and how to build, test and ship.

## In one paragraph

PaCo is one Xcode project with four targets. A SwiftUI menu bar **app** holds the parent's data in SwiftData and runs the UI for both roles. A root **daemon** owns the enforcement policy, evaluates schedules every 30 seconds and drives the `pf` firewall and process killing. A per-user **agent** watches running apps, asks the daemon to kill restricted ones and records usage. A shared Swift **package** holds models, the schedule evaluator, wire types and crypto. A parent's app pushes policy to a child's app over Bonjour with TLS-PSK, and each app hands it to its local daemon over XPC.

## Reading order

1. [Getting started](getting-started.md): build, run, test.
2. [Architecture](architecture.md): the four targets and their responsibilities.
3. [Communication channels](communication.md): XPC, files and Bonjour, with sequence diagrams.
4. [Policy and enforcement](policy-and-enforcement.md): the core semantics.
5. [Security model](security-model.md): trust boundaries and what is out of scope.
6. [Contributing](contributing.md): conventions and the traps to avoid.

The remaining pages go deep on one subsystem each.

## Repository layout

```
PaCo/                 SwiftUI menu bar app (both roles)
  AppDelegate.swift   startup, role wiring, message handling
  AppState.swift      mode, role, PIN gate
  Services/           BonjourService, DaemonXPCClient, SyncManager, ChildRequestLog
  Views/              Onboarding, Dashboard (parent), Child
PaCoDaemon/           root LaunchDaemon: PolicyEngine, FirewallManager, ProcessManager
PaCoAgent/            per-user LaunchAgent: AppMonitor, UsageTracker
PaCoShared/           Swift package used by all targets
  Models/             SwiftData @Model types
  Network/            Codable transfer types, wire format, DaemonPolicy
  Schedule/           ScheduleEvaluator
  Security/           PIN, pairing keys, Keychain, PBKDF2
  Usage/              UsageLedger
  Firewall/           FirewallRuleBuilder
  XPC/                DaemonXPCProtocol
PaCoTests/            XCTest bundle (links PaCoShared only)
packaging/            launchd plists for the installer
project.yml           XcodeGen spec — the source of truth for the Xcode project
Makefile              build, pkg, notarize, reset helpers
docs/gitbook/         this book
```
