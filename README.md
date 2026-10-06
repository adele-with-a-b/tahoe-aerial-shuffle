# Tahoe Aerial Shuffle

A lock-screen setup for macOS 27: Ctrl+Cmd+Q starts an aerial screen saver on every display that changes to a new aerial every minute, and ESC on the lock screen turns the displays off. It's built from Karabiner-Elements and the open-source [Aerial](https://github.com/AerialScreensaver/Aerial) screen saver, plus two small helpers and an installer.

![macOS](https://img.shields.io/badge/macOS-27-blue) ![Apple Silicon](https://img.shields.io/badge/Apple_Silicon-arm64-green) ![Swift](https://img.shields.io/badge/Swift-6-orange)

## What It Does

- **Ctrl+Cmd+Q starts the screen saver.** Karabiner turns the key into `open -a ScreenSaverEngine`, and macOS's "require password" setting locks the screen behind it. Every display shows the same aerial, cropped to its own shape.
- **A new aerial every minute.** Aerial plays a playlist of the aerials in Apple's Shuffle All, 60 seconds each, and reshuffles after the last one. A new session continues the playlist from roughly where the last one stopped.
- **ESC on the lock screen turns the displays off,** and they stay off. Any other key, the mouse or Touch ID wakes them. ESC while unlocked works normally.
- **Nothing is downloaded.** Aerial plays the aerials macOS has already downloaded, cloned into its cache so they take no extra disk space, and its own downloads are off.
- **The desktop wallpaper is left alone.** Aerial is only the screen saver.

## Requirements

- macOS 27 on Apple Silicon, with [Homebrew](https://brew.sh) and the Xcode Command Line Tools (`xcode-select --install`)
- The aerials you want, downloaded by macOS (System Settings → Wallpaper). Aerial plays only what's in `~/Library/Application Support/com.apple.wallpaper/aerials/videos/`
- System Settings → Lock Screen → "Require password after screen saver begins or display is turned off" set to **Immediately**. Ctrl+Cmd+Q only starts the screen saver; this setting is what locks
- A key that sends Ctrl+Cmd+Q. On a Keychron, set it in Keychron Launcher to `LCTL(LGUI(KC_Q))` (hex `0x0914`). A firmware update resets custom keys, so re-apply it, or re-import a keymap export, after every flash

## Install

```bash
bash install.sh
```

On a Mac without Karabiner-Elements, the first run installs it, opens it and stops: approve its driver extension and Input Monitoring prompts, then run it again. The script is safe to re-run. A re-run also adds aerials macOS has downloaded since to the playlist.

It runs two installers, which also work on their own:

- **`karabiner/install.sh`** builds the two helpers into `~/.local/libexec/karabiner/`, runs `screen-lock-watch` as the LaunchAgent `ai.openclaw.aerial-shuffle-lockwatch`, and merges the rules in `karabiner/aerial-shuffle.json` into Karabiner's selected profile. It also tells Karabiner to modify the Keychron Q6 HE: Karabiner skips a keyboard that also reports as a pointing device unless told otherwise, and the Q6 HE reports as both. Another keyboard like that needs its own entry under Karabiner → Devices.
- **`aerial/install.sh`** installs Aerial (`brew install --cask aerial`), writes its settings, cache and playlist in `/Users/Shared/Aerial/` (`aerial/configure.py`), and makes it the screen saver with [PaperSaver](https://github.com/AerialScreensaver/PaperSaver), the library Aerial itself uses for that. It fetches Aerial's source for the installed version, and PaperSaver, into `~/Library/Caches/tahoe-aerial-shuffle/` to build from.

## How It Works

### The keys

macOS 27 gives no ordinary app the key presses on the lock screen, so the keys are handled inside Karabiner, which owns the keyboard:

- **Ctrl+Cmd+Q** is replaced with `open -a ScreenSaverEngine`, so macOS never sees it and doesn't do its plain instant lock (which plays video only on the main display).
- **ESC** is swallowed while Karabiner's variable `aerial_screen_locked` is 1. On release, Karabiner runs `esc-if-locked`, which asks the window server whether the screen is locked (`CGSSessionScreenIsLocked`) and runs `pmset displaysleepnow` if it is. If it isn't, the variable was stale: that ESC is lost, and the variable is corrected so the next one goes through.
- **`screen-lock-watch`** keeps the variable in step with the lock. It sets it through `karabiner_cli` from the `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked` notifications, and from the window server when it starts.

The helpers log to `log show --predicate 'subsystem == "com.user.aerial-shuffle"'`.

### The screen saver

Aerial reads its settings from JSON files in `/Users/Shared/Aerial/`. `configure.py` sets:

| Setting | File | Value |
|---|---|---|
| Automatic downloads (`cache.enableManagement`) | `screensaver.json` | off |
| Viewing mode (`displays.intViewingMode`) | `screensaver.json` | 1, cloned: the same aerial on every display |
| Video format (`videos.intVideoFormat`) | `screensaver.json` | 4, 4K HDR (see below) |
| First-launch wizard | `companion.json` | done: screen saver only, menu bar app |
| Delete macOS's own aerial videos at startup | `companion.json` | off |
| Version banner at startup | `overlay-config.json` | off |

Aerial decodes these files strictly: a file missing any older key is replaced by the defaults, and the defaults turn downloads back on. So a file that doesn't exist yet is written in full from Aerial's own defaults, which `aerial/defaults.swift` prints when compiled against the Aerial source for the installed version.

The cache is a folder of APFS clones of macOS's videos, each named after the file in that aerial's `url-4K-SDR-240FPS` entry in Apple's manifest, which is the name Aerial looks for. A clone shares the original's disk blocks.

The playlist, "Every minute", is an Aerial user playlist (`Playlists/<id>.json`) whose entries each play for 60 seconds, reshuffled on wrap-around. `playlists.json` makes it the playlist every display plays.

**Why 4K HDR:** Apple ships no HDR versions, so Aerial plays the same 4K SDR files either way. But only for an HDR format does Aerial give macOS a real video layer. For SDR it copies each frame into an ordinary picture layer, because macOS 26 drew its video layer at half size in a corner. macOS 27 draws it full screen (checked 2026-10-05 on three displays).

Aerial updates itself (Sparkle). The setup was tested on Aerial 4.1.6; Aerial installed 4.1.7 on 2026-10-05, and re-running `aerial/install.sh` with 4.1.7 worked.

## macOS 27 Findings

- **No app sees key presses on the lock screen.** A session event tap, a HID-level event tap and IOHIDManager all received 0 of 8 ESC presses on the screen saver lock. Karabiner, whose core runs as root and seizes the keyboard, receives them.
- **An ESC that reaches macOS wakes the displays again,** 0.4 s after `pmset displaysleepnow` turned them off ("Display is asleep on activity tickle" in the power log). So ESC has to be swallowed, and the locked-or-not decision has to happen inside Karabiner.
- **The built-in screen saver can't change aerials faster.** Its fastest shuffle setting, Continuously, appears to start the next aerial when the current video ends, and the downloaded aerials run from 30 seconds to 15 minutes. Apple's aerials extension has a hidden "Every 5 Seconds (Internal)" option behind the `ShowFiveSecondAerialShuffleOption` default in `com.apple.wallpaper.aerial`, but it reads that default only after checking that the Mac runs an Apple-internal build, so it does nothing elsewhere.

## Earlier Versions

This repo used to build AerialShuffle.app, a menu bar app that intercepted the keys with an event tap and, before macOS 27, switched lock-screen aerials on a timer by editing the aerials shuffle database. macOS 27 withholds lock-screen keys from apps, which broke it. Its source is in the history up to commit `08fe766`.

## Desktop: Shuffle Stills From the Aerials (Optional)

Extract a 4K PNG frame from each aerial video macOS has downloaded:

```bash
mkdir -p ~/Library/Application\ Support/com.apple.wallpaper/aerials/stills
for f in ~/Library/Application\ Support/com.apple.wallpaper/aerials/videos/*.mov; do
    id=$(basename "$f" .mov)
    ffmpeg -i "$f" -frames:v 1 -update 1 \
        ~/Library/Application\ Support/com.apple.wallpaper/aerials/stills/"$id".png 2>/dev/null
done
```

Then System Settings → Wallpaper → Add Folder… → `~/Library/Application Support/com.apple.wallpaper/aerials/stills/`, and pick a shuffle frequency.

`download_tahoe_aerials.py` is a separate tool: it downloads every aerial in the system manifest to `~/Movies/Aerials` with readable names. Aerial doesn't use those copies.

## Uninstall

- **Screen saver:** choose another one in System Settings → Screen Saver, then `brew uninstall --cask aerial` and move `/Users/Shared/Aerial` to the Trash. The cache holds clones, so this leaves macOS's own videos in place.
- **Keys:** remove the two rules in Karabiner-Elements → Complex Modifications, run `launchctl bootout gui/$(id -u)/ai.openclaw.aerial-shuffle-lockwatch`, and move `~/Library/LaunchAgents/ai.openclaw.aerial-shuffle-lockwatch.plist` and `~/.local/libexec/karabiner/` to the Trash.
- **Build cache:** `~/Library/Caches/tahoe-aerial-shuffle/`.

## Files

| File | Description |
|------|-------------|
| `install.sh` | Runs both installers |
| `karabiner/install.sh` | Builds the helpers, starts the lock watcher, merges the Karabiner rules |
| `karabiner/aerial-shuffle.json` | The two Karabiner rules |
| `karabiner/esc-if-locked.swift` | Run by Karabiner on ESC release: turns the displays off if locked |
| `karabiner/screen-lock-watch.swift` | Keeps Karabiner's `aerial_screen_locked` variable in step with the lock |
| `aerial/install.sh` | Installs Aerial and makes it the screen saver |
| `aerial/configure.py` | Writes Aerial's settings, cache and playlist |
| `aerial/defaults.swift` | Prints Aerial's default settings files, built against Aerial's source |
| `download_tahoe_aerials.py` | Downloads Apple aerial videos from the system manifest |

## License

MIT
