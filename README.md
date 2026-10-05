# Tahoe Aerial Shuffle

A macOS menu bar app that adds two keys to the lock screen: Ctrl+Cmd+Q starts the aerial screensaver on every display, and ESC turns the displays off while locked. macOS itself shuffles the aerials and the desktop stills.

![macOS](https://img.shields.io/badge/macOS-27-blue) ![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-green) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## What It Does

- **Ctrl+Cmd+Q starts the screensaver.** The app intercepts the standard lock shortcut and starts `ScreenSaverEngine` instead. The screensaver plays the aerial on every display, and macOS's "require password" setting locks the screen. A plain macOS lock (Ctrl+Cmd+Q without the app) plays video only on the main display.
- **ESC while locked turns the displays off** (`pmset displaysleepnow`). macOS does this itself on the plain lock screen, but not while the screensaver is showing.

Everything else is native macOS settings, listed under Setup.

## Requirements

- macOS 27 on Apple Silicon (M-series)
- System Settings → Lock Screen → "Require password after screen saver begins or display is turned off" set to Immediately (the app only starts the screensaver; this setting is what locks)
- A keyboard with a lock screen key mapped to Ctrl+Cmd+Q. On a Keychron, set the key in Keychron Launcher to `LCTL(LGUI(KC_Q))` (hex `0x0914`). A firmware update resets custom keys, so re-apply it, or re-import a keymap export, after every flash
- **Accessibility** permission for the app (System Settings → Privacy & Security → Accessibility), for the key interception. The menu shows a warning while it's missing. Nothing else is needed; older versions also needed Full Disk Access.

## Setup

### 1. Screen saver: shuffle the aerials

System Settings → Screen Saver → **Shuffle All** (or one category: Landscape, Cityscape, Underwater, Earth), with the shuffle frequency set to **Continuously**. "Continuously" appears to play each aerial to the end, then switch to the next one: in a 10-minute test the aerial changed 3.5 minutes in and again 4.5 minutes later.

### 2. Desktop: shuffle stills from the aerials (optional)

Extract a 4K PNG frame from each aerial video macOS has downloaded:

```bash
mkdir -p ~/Library/Application\ Support/com.apple.wallpaper/aerials/stills
for f in ~/Library/Application\ Support/com.apple.wallpaper/aerials/videos/*.mov; do
    id=$(basename "$f" .mov)
    ffmpeg -i "$f" -frames:v 1 -update 1 \
        ~/Library/Application\ Support/com.apple.wallpaper/aerials/stills/"$id".png 2>/dev/null
done
```

Then System Settings → Wallpaper → Add Folder… → `~/Library/Application Support/com.apple.wallpaper/aerials/stills/`, and pick a shuffle frequency. macOS handles the timing and crossfade.

Older versions of the app kept a folder of symlinks to these stills, filtered by category, at `~/Library/Application Support/AerialShuffle/active/`. The app no longer touches that folder; a desktop pointed at it keeps working, but new stills won't appear in it.

`download_tahoe_aerials.py` is a separate tool: it downloads every aerial in the system manifest to `~/Movies/Aerials` with readable names.

### 3. Build and install

```bash
bash build.sh     # compiles, signs, and makes AerialShuffle.dmg
bash update.sh    # builds, then replaces /Applications/AerialShuffle.app and relaunches it
```

`build.sh` signs with a self-signed certificate (SHA-1 `6F076E21…`) when it's in the login keychain, so the Accessibility grant survives rebuilds; without it the build is ad-hoc signed and macOS asks again.

## How It Works

The app uses an active CGEvent tap (`.defaultTap`) on key-down events:

- **Ctrl+Cmd+Q** is consumed (so macOS doesn't do its instant lock) and replaced with `open -a ScreenSaverEngine`.
- **ESC** runs `pmset displaysleepnow` when the screen is locked. The app tracks the lock from the `com.apple.screensaver.didstart`, `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notifications. When the screensaver stops it asks the window server (`CGSSessionScreenIsLocked`), because the password prompt can still be up. Each ESC it acts on is logged: `log show --predicate 'process == "AerialShuffle"'`.

## macOS 27

The app used to do more; macOS 27.0.1 broke part of it, and the rest turned out to be redundant:

- **Lock screen aerial switching (removed).** The app wrote the next aerial into `ZCURRENTID` in the shuffle database (`~/Library/Containers/com.apple.wallpaper.extension.aerials/…/Shuffle/ShuffleOrder.db`) and force-killed `WallpaperAerialsExtension` so it reloaded, on a timer while locked. On macOS 27 that kill breaks WallpaperAgent's connection to the extension (`NSCocoaErrorDomain 4099`, then "using ultimate fallback error wallpaper"), and the lock screen shows a static image until the agent restarts. Restarting WallpaperAgent instead does switch the aerial when it's done just before the screensaver starts; restarting it while the screensaver is showing was never tested, so there's no safe way to rotate on a timer during a lock. Apple's "Continuously" shuffle covers the rest.
- **60 Hz refresh pin (removed).** The app pinned the main display to 60 Hz during the screensaver so ProMotion's adaptive rate wouldn't throttle the video. On macOS 27, unpinned, a 10-minute screensaver run looked smooth and every video player decoded a steady 30 fps (176–182 frames per 6-second window), with the main display in its 120 Hz mode.
- **Category filters and the desktop folder manager (removed).** Native settings cover them: the screen saver picks one category or all, and the desktop shuffles any folder.

## Uninstall

Use **Uninstall** in the menu bar dropdown. It removes the app from `/Applications`, its login item, and its permission entries (Accessibility, and Full Disk Access from older versions). It doesn't change your wallpaper or screen saver settings, and it leaves `~/Library/Application Support/AerialShuffle/active/` in place in case your desktop still points at it.

## Files

| File | Description |
|------|-------------|
| `AerialShuffle.swift` | Complete app source (single file) |
| `build.sh` | Compiles, generates the icon, signs, creates the DMG |
| `update.sh` | Builds and reinstalls into `/Applications` |
| `download_tahoe_aerials.py` | Downloads Apple aerial videos from the system manifest |

## License

MIT
