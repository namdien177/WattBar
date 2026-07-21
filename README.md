# WattBar

A small native macOS menu-bar app showing battery percentage, measured power flow, charging state, estimated time to full charge, power source, powered USB-C devices, cycle count, and the three most active apps.

## Requirements

- macOS 14 or newer
- Xcode Command Line Tools

## Build and run

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
