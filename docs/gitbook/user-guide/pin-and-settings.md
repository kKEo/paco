---
description: Change the PIN, recover a forgotten PIN, and change a Mac's role.
---

# PIN and settings

## When PaCo asks for the PIN

The dashboard asks for your PIN every time it opens. It locks again when you close the menu bar window or switch to another app.

After **5 wrong PINs**, PIN entry is locked for **5 minutes**. The same limit protects **Parent Access** on a child's Mac.

## Change the PIN

1. Open **Settings**.
2. Under **Change PIN**, enter the current PIN and a new 6-digit PIN.
3. Click **Update PIN**.

The new PIN takes effect immediately, including for **Parent Access** on paired child Macs, because they always ask your Mac.

## Forgot the PIN

The PIN is stored in the Keychain of your account on your Mac. To reset it, open Terminal **in your own account on your Mac** and run:

```bash
security delete-generic-password -s com.paco.keychain -a com.paco.pin.hash
security delete-generic-password -s com.paco.keychain -a com.paco.pin.salt
```

The next time you open the dashboard, PaCo offers **Create PIN**.

{% hint style="warning" %}
Anyone who can use your macOS account can do this. Protect your own account with a password your child does not know.
{% endhint %}

## Change a Mac's role

**Settings → Reset & Change Role…** returns the Mac to the **Welcome to PaCo** screen so you can choose Parent or Child again. Quit and reopen PaCo after choosing the new role so the network connections start fresh.
