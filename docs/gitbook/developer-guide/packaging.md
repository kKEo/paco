---
description: Signing, the installer package, launchd, and notarization.
---

# Packaging and release

## Signing

Signing is not optional for a working install: the daemon derives its XPC requirement from its own Team ID and accepts only `com.paco.app` and `com.paco.agent` signed by that team.

```bash
make pkg TEAM_ID=ABCDE12345                       # signed Release build + signed pkg
make notarize TEAM_ID=ABCDE12345 NOTARY_PROFILE=paco
```

| Variable | Default | Purpose |
|---|---|---|
| `TEAM_ID` | empty | When set, builds with `DEVELOPMENT_TEAM`, manual signing, hardened runtime and secure timestamp, and signs the pkg. |
| `APP_IDENTITY` | `Developer ID Application` | Code-signing identity for the targets. |
| `PKG_IDENTITY` | `Developer ID Installer` | Identity for `pkgbuild --sign`. |
| `NOTARY_PROFILE` | empty | `xcrun notarytool` keychain profile, created once with `xcrun notarytool store-credentials`. |
| `VERSION` | `1.0.0` | Package version and file name. |

## Package layout

`make pkg` stages `build/pkg-root/`:

```
Applications/PaCo.app                       (daemon + agent copied into Contents/Resources)
Library/LaunchDaemons/com.paco.daemon.plist
Library/LaunchAgents/com.paco.agent.plist
Library/Application Support/PaCo/
```

## Postinstall

1. `launchctl bootout` the existing daemon and the console user's agent, so upgrades do not keep old binaries running.
2. `install -o root -g wheel -m 755` both binaries from the app's Resources into `/Library/Application Support/PaCo/`.
3. `launchctl bootstrap system` the daemon, and `bootstrap gui/<console uid>` the agent.

## launchd

| Plist | Label | Program | Notes |
|---|---|---|---|
| `packaging/com.paco.daemon.plist` | `com.paco.daemon` | `/Library/Application Support/PaCo/PaCoDaemon` | `RunAtLoad`, `KeepAlive`, `MachServices: com.paco.daemon` |
| `packaging/com.paco.agent.plist` | `com.paco.agent` | `/Library/Application Support/PaCo/PaCoAgent` | `RunAtLoad`, `KeepAlive`; loads in every GUI session |

## Unsigned development daemon

For local work without a certificate, install a **Debug** daemon and add to its plist:

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PACO_ALLOW_UNSIGNED_XPC</key>
    <string>1</string>
</dict>
```

Then `sudo launchctl bootout system/com.paco.daemon && sudo launchctl bootstrap system /Library/LaunchDaemons/com.paco.daemon.plist`. Never ship this.

{% hint style="warning" %}
See [Known limitations](known-limitations.md#packaging) for an open issue with copying binaries into the signed app bundle.
{% endhint %}
