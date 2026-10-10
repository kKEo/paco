---
description: Install PaCo on the parent's and the child's Mac, and remove it again.
---

# Installing PaCo

## Requirements

* macOS 14 Sonoma or later on every Mac.
* An administrator account to run the installer.
* For two-Mac use, both Macs on the same home network (same Wi‑Fi or wired network).

{% hint style="warning" %}
**Give your child a standard account, not an administrator account.** An administrator can switch off macOS services and the firewall that PaCo relies on. Create the child's account in **System Settings → Users & Groups** with the account type **Standard**.
{% endhint %}

## Install

1. Open the `PaCo-<version>.pkg` installer on each Mac and follow the steps. You will be asked for an administrator password.
2. The installer puts **PaCo** in `/Applications` and starts two background services: one that controls the internet and closes blocked apps, and one that watches apps in each logged-in account.
3. Open **PaCo** from `/Applications`. A shield appears in the menu bar.

## Start PaCo at login

The background services start by themselves, so the rules are enforced after a restart even if PaCo is not open. The menu bar app itself does not yet start by itself, and it is needed to pair, to receive rule changes and to send time requests. Add it to Login Items on both Macs:

1. Open **System Settings → General → Login Items**.
2. Under **Open at Login**, click **+**, choose **PaCo** in Applications, and click **Open**.

On the child's Mac, do this while logged in to the child's account.

## Allow local network access

When PaCo first looks for other Macs, macOS may ask whether PaCo may find devices on your local network. Click **Allow** on both Macs. You can check this later in **System Settings → Privacy & Security → Local Network**.

## Uninstall

Run these commands in Terminal on each Mac, as an administrator. Stop the system service first, because it restarts the per-user service.

```bash
# Stop the background services
sudo launchctl bootout system/com.paco.daemon
launchctl bootout gui/$(id -u)/com.paco.agent

# Remove PaCo's firewall rules (turns the internet back on)
sudo pfctl -a com.paco -F rules

# Remove the installed files
sudo rm -f /Library/LaunchDaemons/com.paco.daemon.plist /Library/LaunchAgents/com.paco.agent.plist
sudo rm -rf "/Library/Application Support/PaCo" /Applications/PaCo.app /etc/pf.anchors/com.paco

# Restore the original firewall configuration, if PaCo made a backup
[ -f /etc/pf.conf.paco-backup ] && sudo cp /etc/pf.conf.paco-backup /etc/pf.conf && sudo pfctl -f /etc/pf.conf

# Remove PaCo's data for the current user (repeat in each account that used PaCo)
rm -rf ~/Library/Application\ Support/com.paco
```

Your parent PIN and pairing keys stay in the Keychain. To remove them as well, run these in the account that created them:

```bash
for item in com.paco.pin.hash com.paco.pin.salt com.paco.pin.attempts com.paco.pin.lockoutUntil com.paco.pairing.keys; do
  security delete-generic-password -s com.paco.keychain -a "$item" 2>/dev/null
done
```
