# Changelog

## 1.1.0 — PaCo Cloud

A child's Mac can now be managed from a browser, for a parent without a Mac of their own.

- **PaCo Cloud server** (`server/`, self-hosted): web dashboard for Macs, profiles, schedules, app rules, time requests, screen time (today, 7 and 30 days, per app) and an activity log; parent PIN for "Parent Access"; email and browser notifications for requests; two-factor login.
- **Child Mac:** choose "PaCo Cloud" at setup (or "Use PaCo Cloud" later). The root daemon enrolls with a one-time code, takes the parent's commands within a second through a long-poll, reports what it enforces and the screen time, relays time requests and PIN checks, and keeps the server reachable while the internet is blocked.
- **Remote control the LAN setup lacks:** internet on/off for a set time, a profile per Mac, approving requests while the Mac is offline.
- The Bonjour parent-Mac setup is unchanged; a Mac uses one or the other.

Upgrading: install the new pkg on every Mac. Existing setups keep working as before.

## 1.0.0

First release: internet schedules via `pf`, app rules, usage, Bonjour pairing with TLS-PSK, time-extension requests, parent PIN.
