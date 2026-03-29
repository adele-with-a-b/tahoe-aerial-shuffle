# Tahoe Aerial Shuffle

A macOS Tahoe menu bar app that shuffles Apple aerial wallpapers on both the desktop and lock screen.

![macOS](https://img.shields.io/badge/macOS-Tahoe_26.x-blue) ![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-green) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## What It Does

- **Desktop wallpaper shuffle** — Cycles through 4K PNG stills extracted from Apple aerial videos using native macOS photo folder shuffle with smooth crossfade transitions
- **Lock screen aerial shuffle** — Rotates which aerial video plays on the lock screen by updating the system shuffle database on a configurable timer
- **Power button override** — Pressing the power button launches the screensaver momentarily, then dismisses it to the lock screen showing aerial videos (instead of the default instant-lock behavior)
- **ESC to sleep** — On the lock screen, pressing ESC sleeps the display
- **Category filters** — Independent category selection for desktop photos and lock screen aerials:
  - 🏔️ Landscape
  - 🏙️ Cityscape
  - 🐠 Underwater
  - 🌍 Earth
- **Menu bar controls** — NSMenu dropdown with live-updating category checkboxes, shuffle interval picker, and current aerial name display

## Screenshots

*Menu bar dropdown with category filters and shuffle controls*

## Requirements

- macOS Tahoe (26.x) on Apple Silicon (M-series)
- Apple aerial videos (downloaded automatically via included script)
- System Settings → Screensaver set to "Shuffle All Aerials"

## Setup

### 1. Download aerial videos

```bash
python3 download_tahoe_aerials.py
```

This reads the system manifest at `~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json` and downloads all available aerial videos.

### 2. Extract stills

Extract a 4K PNG frame from each aerial video for desktop wallpaper use:

```bash
mkdir -p ~/Library/Application\ Support/com.apple.wallpaper/aerials/stills
for f in ~/Library/Application\ Support/com.apple.wallpaper/aerials/videos/*.mov; do
    id=$(basename "$f" .mov)
    ffmpeg -i "$f" -vframes 1 -q:v 1 \
        ~/Library/Application\ Support/com.apple.wallpaper/aerials/stills/"$id".png 2>/dev/null
done
```

### 3. Build

```bash
swiftc -target arm64-apple-macos14 -framework AppKit -framework SwiftUI -lsqlite3 \
    -o AerialShuffle AerialShuffle.swift
```

### 4. Install via PKG

The included build process creates a PKG installer that:
- Installs the app to `/Applications`
- Sets `DisableScreenLockImmediate` for power button interception
- Creates the config directory
- Launches the app automatically

On first launch, macOS will prompt for:
- **Accessibility** — for posting keyboard events
- **Input Monitoring** — for the global event tap
- **Full Disk Access** — for reading the aerial shuffle database

### 5. Configure desktop wallpaper

In System Settings → Wallpaper, set the desktop to shuffle from:
```
~/Library/Application Support/AerialShuffle/active/
```

The app manages this folder with symlinks based on your category selection.

## How It Works

### Power Button Detection

The power button generates a single `NX_SYSDEFINED` (type 14) CGEvent. The app distinguishes it from caps lock (which generates 2+ type 14 events in a burst) and mouse clicks (tracked via timestamp proximity) using a 100ms counting window.

### Aerial Shuffle

The app updates `ZCURRENTID` in the system shuffle database at `~/Library/Containers/com.apple.wallpaper.extension.aerials/Data/Library/Application Support/Shuffle/ShuffleOrder.db`, then kills `WallpaperAerialsExtension` to force a reload.

### Desktop Photo Shuffle

The app maintains a folder of symlinks (`active/`) pointing to stills matching the selected categories. macOS handles the shuffle timing and crossfade transitions natively.

## Uninstall

Use the **Uninstall** option in the menu bar dropdown. It removes:
- The app from `/Applications`
- Config directory at `~/Library/Application Support/AerialShuffle/`
- TCC permission entries
- `DisableScreenLockImmediate` setting
- Launch at login registration

Note: Aerial stills in `~/Library/Application Support/com.apple.wallpaper/aerials/stills/` are preserved.

## Files

| File | Description |
|------|-------------|
| `AerialShuffle.swift` | Complete app source (single file, ~500 lines) |
| `download_tahoe_aerials.py` | Downloads Apple aerial videos from the system manifest |

## License

MIT
