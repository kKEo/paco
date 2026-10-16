---
description: Parental control for macOS — internet schedules, app rules and time requests between a parent's Mac and a child's Mac.
---

# Welcome to PaCo

PaCo is a parental-control app for macOS 14 and later. It lets a parent decide when a child's Mac can reach the internet, which apps the child can open, and lets the child ask for more time with a single click.

## What PaCo does

* **Internet schedules.** Turn the internet off at set times, for example school nights from 21:00 to 07:00.
* **App rules.** Block an app completely, or block it only while a schedule has the internet off.
* **Time extension requests.** The child asks for 15–120 more minutes; the parent approves or denies from their own Mac, or from a browser.
* **Usage.** See how long the internet was on and which apps were in the foreground today.
* **Parent PIN.** Every parent screen is protected by a 6-digit PIN.
* **PaCo Cloud (optional).** No second Mac? Manage the child's Mac and follow its screen time from a web page.

With a parent's Mac, everything stays on your local network and PaCo sends nothing to the internet. [PaCo Cloud](user-guide/cloud.md) is an optional, self-hosted server for parents without a Mac of their own.

## How it fits together

You install PaCo on the parent's Mac and on the child's Mac. The parent's Mac holds the rules and sends them to the child's Mac over an encrypted connection on your home network. The child's Mac enforces them with a background service that runs even when nobody is logged in to PaCo, and keeps enforcing the last rules it received when the parent's Mac is away.

<figure><img src=".gitbook/assets/ug-overview.svg" alt="The parent's Mac sends rules and approvals to the child's Mac over an encrypted home-network connection; the child's Mac enforces them."><figcaption><p>Your Mac holds the rules; the child’s Mac enforces them.</p></figcaption></figure>

## Where to start

| You are… | Read |
|---|---|
| A parent setting PaCo up | [User Guide → Overview](user-guide/README.md) |
| A developer working on PaCo | [Developer Guide → Overview](developer-guide/README.md) |
