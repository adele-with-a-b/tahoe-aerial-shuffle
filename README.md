# Tahoe Aerial Shuffle

A macOS Tahoe menu bar app that shuffles Apple aerial wallpapers on both the desktop and lock screen.

![macOS](https://img.shields.io/badge/macOS-Tahoe_26.x-blue) ![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-green) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## What It Does

- **Desktop wallpaper shuffle** — Cycles through 4K PNG stills extracted from Apple aerial videos using native macOS photo folder shuffle with smooth crossfade transitions
- **Lock screen aerial shuffle** — Picks a different aerial each time you lock with Ctrl+Cmd+Q, by updating the system shuffle database just before the screensaver starts
- **Lock screen interception** — Intercepts Ctrl+Cmd+Q (the standard macOS lock shortcut), pins the display to a fixed 60Hz refresh rate to prevent ProMotion's adaptive mode from throttling during the screensaver, then launches the screensaver so aerials start playing immediately on the lock screen. The original adaptive refresh rate is restored automatically when the user unlocks.
- **ESC to sleep** — Pressing ESC on the lock screen sleeps the display
- **Category filters** — Independent category selection for desktop photos and lock screen aerials:
  - 🏔️ Landscape
  - 🏙️ Cityscape
  - 🐠 Underwater
  - 🌍 Earth
- **Menu bar controls** — NSMenu dropdown with live-updating category checkboxes and current aerial name display

## Screenshots

*Menu bar dropdown with category filters and shuffle controls*

## Requirements

- macOS Tahoe (26.x) or macOS 27 on Apple Silicon (M-series)
- Apple aerial videos (downloaded automatically via included script)
- System Settings → Screensaver set to "Shuffle All Aerials"
- System Settings → Lock Screen → "Require password after screen saver begins or display is turned off" set to Immediately (the app only starts the screensaver; this setting is what locks)
- A keyboard with a lock screen key mapped to Ctrl+Cmd+Q. On a Keychron, set the key in Keychron Launcher to `LCTL(LGUI(KC_Q))` (hex `0x0914`). A firmware update resets custom keys, so re-apply it, or re-import a keymap export, after every flash

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
    ffmpeg -i "$f" -frames:v 1 -update 1 \
        ~/Library/Application\ Support/com.apple.wallpaper/aerials/stills/"$id".png 2>/dev/null
done
```

### 3. Build

```bash
bash build.sh
```

This compiles the app, generates an app icon, and creates a PKG installer.

### 4. Install via PKG

The included build process creates a PKG installer that:
- Installs the app to `/Applications`
- Creates the config directory
- Launches the app automatically

On first launch, macOS will prompt for:
- **Accessibility** — for intercepting the lock screen shortcut (Ctrl+Cmd+Q)
- **Full Disk Access** — for reading Apple's wallpaper data and the aerial shuffle database

### 5. Configure desktop wallpaper

In System Settings → Wallpaper, set the desktop to shuffle from:
```
~/Library/Application Support/AerialShuffle/active/
```

The app manages this folder with symlinks based on your category selection.

## How It Works

### Lock Screen Interception

The app uses an active CGEvent tap (`.defaultTap`) to intercept Ctrl+Cmd+Q keypresses. When detected, the event is consumed (preventing the default instant-lock behavior) and replaced with a custom sequence:

1. **Next aerial** — The next lock screen aerial is picked (see Aerial Shuffle below)
2. **Refresh rate pin** — The display is switched from adaptive ProMotion to a fixed 60Hz mode, preventing macOS from throttling the refresh rate during the screensaver (which makes aerial videos look sluggish)
3. **Screensaver launch** — `ScreenSaverEngine` is opened so the aerial video starts playing immediately; macOS's "require password" setting handles the actual screen lock

When the user unlocks, the app listens for the `com.apple.screenIsUnlocked` distributed notification and restores the original adaptive display mode.

### Aerial Shuffle

On each Ctrl+Cmd+Q, before the screensaver starts, the app updates `ZCURRENTID` in the system shuffle database at `~/Library/Containers/com.apple.wallpaper.extension.aerials/Data/Library/Application Support/Shuffle/ShuffleOrder.db`, then sends SIGTERM to `WallpaperAgent`. launchd restarts the agent, the restart ends the running `WallpaperAerialsExtension`, and a fresh extension connects in about half a second; the app waits for it (up to 3 s) before starting the screensaver.

The app never changes the aerial while the screensaver is showing. On macOS 26 it did that on a timer by force-killing `WallpaperAerialsExtension`. On macOS 27 that kill breaks the agent's connection to the extension (`NSCocoaErrorDomain 4099` in `log show --predicate 'process == "WallpaperAgent"'`), and the lock screen shows a static fallback image until the agent restarts. A screensaver started by idle timeout or a hot corner plays whatever aerial is loaded.

The database holds one row whose `Z_PK` is not stable: it was 1 on macOS 26 and 19 after the macOS 27 upgrade. The app therefore uses the most recently modified row. Each attempt overwrites `~/Library/Application Support/AerialShuffle/last-shuffle.txt` with one line: `ok: row N …: old -> new; agent … restarted, extension … up in Ns; ZCURRENTID now …`, or the check that failed and sqlite3's error. Read that file first when the lock screen stops changing.

### Desktop Photo Shuffle

The app maintains a folder of symlinks (`active/`) pointing to stills matching the selected categories. macOS handles the shuffle timing and crossfade transitions natively.

## Uninstall

Use the **Uninstall** option in the menu bar dropdown. It removes:
- The app from `/Applications`
- Config directory at `~/Library/Application Support/AerialShuffle/`
- TCC permission entries (Accessibility, Full Disk Access)
- Launch at login registration

Note: Aerial stills in `~/Library/Application Support/com.apple.wallpaper/aerials/stills/` are preserved.

## Files

| File | Description |
|------|-------------|
| `AerialShuffle.swift` | Complete app source (single file) |
| `build.sh` | Compiles app, generates icon, creates PKG installer |
| `download_tahoe_aerials.py` | Downloads Apple aerial videos from the system manifest |

## License

MIT
