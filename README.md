# WattBar

A small native macOS menu-bar app showing battery percentage, measured power flow, charging state, estimated time to full charge, power source, powered USB-C devices, cycle count, connected wireless device batteries, and the three most active apps.

Wireless devices (keyboards, mice, headsets, AirPods) appear as battery rings in the popover. Hover a Bluetooth device and click the x, or right-click it, to disconnect it. WattBar sends a notification when a device drops to the level macOS warns at (usually 20%).

## Install or update

Run this single command:

```zsh
curl --proto '=https' --tlsv1.2 -fsSL https://github.com/namdien177/WattBar/raw/refs/heads/main/Scripts/install.sh | zsh
```

The installer always downloads the latest `main`, builds a release app, installs it to `~/Applications/WattBar.app`, restarts WattBar, and removes the downloaded source and Swift build cache afterward. It verifies macOS 14+, Swift 6+, and code signing. If Xcode Command Line Tools are missing, it opens Apple's installer and tells you when to rerun the command.

Swift Package Manager handles dependencies automatically; WattBar currently has no third-party packages.

## Build manually

Requirements: macOS 14 or newer and Swift 6 from Xcode or Xcode Command Line Tools.

```sh
chmod +x Scripts/build-app.sh
Scripts/build-app.sh
open dist/WattBar.app
```

The app icon lives in `Resources/AppIcon.png` (1024x1024, SVG source in `Resources/AppIcon.svg`). After changing it, run `Scripts/make-icon.sh` to regenerate `Resources/AppIcon.icns`.

The app is local-only. macOS asks for Bluetooth access the first time you disconnect a device; nothing else needs a permission. To launch it automatically, add `WattBar.app` under **System Settings → General → Login Items**.

## Efficiency

- Battery data comes directly from IOKit; no shell process is used for routine battery updates.
- The menu-bar summary refreshes every 30 seconds with a five-second timer tolerance.
- Device names and app activity are sampled only while the popover is open, once every 30 seconds.
- Wireless device batteries come from the same in-process source `pmset -g accps` uses, read every 30 seconds (every 10 while the popover is open) so low-battery alerts arrive with the popover closed. That source is not a public API; if a future macOS removes it, the Devices section hides.
- On supported Apple Silicon Macs, WattBar reads actual adapter input, signed battery flow, Mac consumption, and per-port USB-C output from power telemetry.
- Undocumented detailed telemetry may be unavailable on other hardware or future macOS versions; WattBar falls back to battery voltage and current.
- Per-app wattage is not available through a public macOS API, so app activity is ranked using aggregate CPU usage as a transparent power proxy.
