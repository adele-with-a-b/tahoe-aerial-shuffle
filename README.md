# Tahoe Aerial Shuffle

A macOS menu bar app that shuffles Apple aerial wallpapers on desktop and lock screen.

## Features
- Shuffles desktop wallpaper using static PNG frames extracted from Apple aerial videos
- Power button press launches screensaver then dismisses to lock screen with aerial videos
- ESC key on lock screen sleeps the display
- Separate category filters for desktop photos and lock screen aerials (Landscape, Cityscape, Underwater, Earth)
- Configurable shuffle interval for lock screen aerials
- SQLite DB updates to rotate which aerial video plays
- PKG installer with automatic permission setup

## Requirements
- macOS Tahoe (26.x) on Apple Silicon
- Apple aerial videos downloaded via `download_tahoe_aerials.py`
- Stills extracted from aerial videos

## Build
```bash
swiftc -target arm64-apple-macos14 -framework AppKit -framework SwiftUI -lsqlite3 \
    -o AerialShuffle AerialShuffle.swift
```

## Install
Build and install via the PKG installer which handles permissions and configuration.

## Files
- `AerialShuffle.swift` — Main app source
- `download_tahoe_aerials.py` — Downloads Apple aerial videos from the manifest
