---
description: Logs, state inspection and resetting.
---

# Debugging

## Logs

Everything logs through `os.Logger` with subsystem `com.paco` and categories `app`, `daemon`, `agent`, `firewall`, `network`, `security`.

```bash
log stream --level info --predicate 'subsystem == "com.paco"'
log stream --level info --predicate 'subsystem == "com.paco" AND category == "daemon"'
log show --last 1h --info --predicate 'subsystem == "com.paco"'
```

Interpolated values are private by default and show as `<private>` outside a debugger. Attach Xcode, or add `privacy: .public` to the interpolations you need while debugging.

## Daemon and agent

```bash
sudo launchctl print system/com.paco.daemon | head -30
launchctl print gui/$(id -u)/com.paco.agent | head -30
sudo launchctl kickstart -k system/com.paco.daemon      # restart the daemon
```

## Policy and firewall

```bash
cat "/Library/Application Support/PaCo/policy.json" | python3 -m json.tool
cat "/Library/Application Support/PaCo/daemon-state.json"
sudo pfctl -a com.paco -sr
```

## Bonjour

```bash
dns-sd -B _paco._tcp            # children advertising on the network
dns-sd -L "<Child Mac Name>" _paco._tcp
```

## Per-user files

```bash
ls -la ~/Library/Application\ Support/com.paco/
cat ~/Library/Application\ Support/com.paco/usage.json | python3 -m json.tool
cat ~/Library/Application\ Support/com.paco/child-requests.json | python3 -m json.tool
```

## Reset

```bash
rm -rf ~/Library/Application\ Support/com.paco        # onboarding again, all app data gone
make clear-policy                                      # daemon policy + block state
sudo pfctl -a com.paco -F rules                        # lift a block now
security delete-generic-password -s com.paco.keychain -a com.paco.pin.hash
security delete-generic-password -s com.paco.keychain -a com.paco.pin.salt
security delete-generic-password -s com.paco.keychain -a com.paco.pairing.keys
```
