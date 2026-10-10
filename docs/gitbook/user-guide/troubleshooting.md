---
description: Fixes for the most common problems.
---

# Troubleshooting

## The menu bar icon is grey

PaCo cannot reach its background service. Restart the Mac. If the icon stays grey, reinstall PaCo with the installer. Builds that are not signed by the developer cannot talk to the background service at all.

## The child's Mac does not appear in Devices

* Make sure PaCo is open on the child's Mac and set up as **Child**.
* Make sure both Macs are on the same network. Guest Wi‑Fi networks often keep devices apart.
* Check **System Settings → Privacy & Security → Local Network** and allow PaCo on both Macs.
* Wake the child's Mac; a sleeping Mac is not visible.

## The child's Mac stays "Online — connecting…"

* Check the code was entered on the child's Mac: its status line should read **Paired — parent not connected**, not **Not paired with a parent**.
* If you paired with **Pair New Device**, the name must match the child's computer name exactly. Remove the entry and pair from **Nearby Devices** instead.
* Click **Retry**. PaCo also retries every 30 seconds.

## The internet does not turn off on schedule

* Check the schedule is enabled and the right days are selected. Remember that an overnight period belongs to the day it starts on.
* Check for a manual override on **Home** or an approved request that is still running.
* On a child's Mac, check it was connected after you made the change: changes reach it when it connects.
* Devices on your home network stay reachable by design.

## A blocked app still opens

* Check the Bundle ID with `osascript -e 'id of app "Name"'`.
* A **Follows Schedule** rule only blocks while its schedule has the internet off.
* The app is closed within about 10 seconds if it was already open.

## Nothing happens after a restart

The background services enforce rules after a restart, but the menu bar app needs to be in **Login Items** to pair, receive changes and send requests. See [Installing PaCo](installation.md#start-paco-at-login).

## "Parent's Mac is not connected" on the child's Mac

Parent Access checks your PIN on your Mac. Open PaCo on your Mac and wait for **Connected** in **Devices**.

## The internet stays off after removing PaCo

Run:

```bash
sudo pfctl -a com.paco -F rules
```

Then follow the full steps in [Installing PaCo → Uninstall](installation.md#uninstall).
