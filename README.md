# WattBar

A small native macOS menu-bar app showing battery percentage, measured power flow, charging state, estimated time to full charge, power source, powered USB-C devices, cycle count, and the three most active apps.

## Install or update

Because this is a private repository, first make sure [GitHub CLI](https://cli.github.com/) is authenticated with `gh auth login`. Then run this single command:

```zsh
curl --proto '=https' --tlsv1.2 -fsSL --config <(printf 'header = "Authorization: Bearer %s"\nheader = "Accept: application/vnd.github.raw+json"\n' "$(gh auth token)") https://api.github.com/repos/namdien177/WattBar/contents/Scripts/install.sh | zsh
```

The installer always downloads the latest `main`, builds a release app, installs it to `~/Applications/WattBar.app`, restarts WattBar, and removes the downloaded source and Swift build cache afterward. It verifies macOS 14+, Swift 6+, code signing, and GitHub authentication. If Xcode Command Line Tools are missing, it opens Apple's installer and tells you when to rerun the command.

Swift Package Manager handles dependencies automatically; WattBar currently has no third-party packages.

## Build manually

Requirements: macOS 14 or newer and Swift 6 from Xcode or Xcode Command Line Tools.

```sh
chmod +x Scripts/build-app.sh
Scripts/build-app.sh
open dist/WattBar.app
```

The app is local-only and requires no permissions. To launch it automatically, add `WattBar.app` under **System Settings → General → Login Items**.

## Efficiency

- Battery data comes directly from IOKit; no shell process is used for routine battery updates.
- The menu-bar summary refreshes every 30 seconds with a five-second timer tolerance.
- Device names and app activity are sampled only while the popover is open, once every 30 seconds.
- On supported Apple Silicon Macs, WattBar reads actual adapter input, signed battery flow, Mac consumption, and per-port USB-C output from power telemetry.
- Undocumented detailed telemetry may be unavailable on other hardware or future macOS versions; WattBar falls back to battery voltage and current.
- Per-app wattage is not available through a public macOS API, so app activity is ranked using aggregate CPU usage as a transparent power proxy.
