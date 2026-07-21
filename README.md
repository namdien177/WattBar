# WattBar

A small native macOS menu-bar app showing battery percentage, charging state, battery intake wattage, estimated time to full charge, power source, cycle count, and the three most active apps.

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
- App activity is sampled only while the popover is open, once every 30 seconds.
- Per-app wattage is not available through a public macOS API, so app activity is ranked using aggregate CPU usage as a transparent power proxy.
