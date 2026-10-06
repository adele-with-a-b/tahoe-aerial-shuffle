#!/bin/bash
# Makes Aerial 4 (github.com/AerialScreensaver/Aerial, brew install --cask aerial) the screen saver,
# playing a new aerial every minute from the videos macOS has already downloaded. Aerial itself
# downloads nothing. This script fetches two source trees into ~/Library/Caches/tahoe-aerial-shuffle:
#   - Aerial's source for the installed version, to build defaults.swift
#   - PaperSaver, the library Aerial uses to set the system screen saver, for its command-line tool
# configure.py does the rest. Safe to re-run; a re-run also adds aerials macOS has downloaded since.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="$HOME/Library/Caches/tahoe-aerial-shuffle"
ext="com.glouel.Aerial-App.Aerial4WallpaperExtension"
papersaver_rev="f38915e"   # PaperSaver 0.3.1, the version tested with Aerial 4.1.6

[ -d /Applications/Aerial.app ] || brew install --cask aerial
version=$(defaults read /Applications/Aerial.app/Contents/Info.plist CFBundleShortVersionString)
mkdir -p "$work"

src="$work/aerial-v$version"
[ -d "$src" ] || git clone --quiet --depth 1 --branch "v$version" https://github.com/AerialScreensaver/Aerial.git "$src"
gen="$work/defaults-v$version"
if [ ! -x "$gen" ]; then
    # The settings types need these two enums; the files that define them pull in the whole app.
    awk '/^enum OverlapWorkaround/,/^}/' "$src/Shared/Settings/PrefsAdvanced.swift" > "$work/enums.swift"
    awk '/^enum LaunchMode/,/^}/' "$src/Aerial/Model/Settings/Preferences.swift" >> "$work/enums.swift"
    swiftc -O -o "$gen" "$here/defaults.swift" "$work/enums.swift" \
        "$src/Shared/Settings/ScreensaverSettings.swift" "$src/Aerial/Model/Settings/CompanionSettings.swift" \
        "$src/Shared/Overlays/OverlayConfig.swift" "$src/Shared/Overlays/OverlayTypeDefaults.swift" \
        "$src/Shared/Core/AerialPaths.swift"
fi
mkdir -p "$work/defaults"
for f in screensaver.json companion.json overlay-config.json; do
    "$gen" "$f" > "$work/defaults/$f"
done

# Aerial rewrites its files from memory, so it must be closed while they change.
if pgrep -x Aerial >/dev/null; then
    osascript -e 'tell application "Aerial" to quit'
    sleep 3
fi
files() { cat /Users/Shared/Aerial/{screensaver,companion,overlay-config,playlists}.json 2>/dev/null | shasum; }
before=$(files)
python3 "$here/configure.py" "$work/defaults"
pids=$(pgrep -x Aerial4WallpaperExtension || true)
if [ "$(files)" != "$before" ] && [ -n "$pids" ]; then
    if [ "$(echo "$pids" | wc -w | tr -d ' ')" = 1 ]; then
        kill "$pids"   # WallpaperAgent starts it again, and it reads the new settings
    else
        echo "Several Aerial4WallpaperExtension processes ($pids); log out and back in to apply the settings."
    fi
fi
open -g -a /Applications/Aerial.app

ps="$work/papersaver"
if [ ! -x "$ps/.build/release/papersaver" ]; then
    [ -d "$ps" ] || git clone --quiet https://github.com/AerialScreensaver/PaperSaver.git "$ps"
    git -C "$ps" -c advice.detachedHead=false checkout --quiet "$papersaver_rev"
    swift build --package-path "$ps" -c release --product papersaver
fi
for _ in $(seq 30); do
    [ -n "$(pluginkit -m -i "$ext")" ] && break
    sleep 1
done
if grep -q "Screensaver extension: *$ext" <<< "$("$ps/.build/release/papersaver" wallpaper-extension get)"; then
    echo "screen saver: already Aerial"
else
    "$ps/.build/release/papersaver" wallpaper-extension set "$ext" --config aerial --slot screensaver
fi
