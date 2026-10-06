#!/usr/bin/env python3
"""Writes Aerial's settings, cache and playlist in /Users/Shared/Aerial. Run by install.sh while
Aerial is quit; DEFAULTS_DIR holds the default settings files that defaults.swift printed.

  - settings: automatic downloads off, the same aerial on every display, drawn as a plain video
    layer, no version banner, and the first-launch wizard skipped (screen saver only, menu bar app)
  - cache: every aerial macOS has downloaded, cloned in under the name Aerial looks for. A clone
    shares the original's disk blocks, so this takes no extra space.
  - playlist "Every minute": the aerials Apple puts in Shuffle All, 60 seconds each, reshuffled
    after the last one. Rebuilt only when that set of aerials has changed.

Usage: configure.py DEFAULTS_DIR
"""
import json
import os
import random
import subprocess
import sys
import time
import uuid

BASE = "/Users/Shared/Aerial"
APPLE = os.path.expanduser("~/Library/Application Support/com.apple.wallpaper/aerials")
PLAYLIST = "Every minute"

SETTINGS = {
    "screensaver.json": {
        ("cache", "enableManagement"): False,
        ("displays", "intViewingMode"): 1,  # cloned: the same aerial on every display
        # 4K HDR. Apple ships no HDR files, so this plays the same 4K SDR files, but an HDR format
        # makes Aerial hand macOS a real video layer instead of copying each frame into a picture
        # layer. Aerial avoids the video layer for SDR because macOS 26 drew it at half size in a
        # corner; macOS 27 draws it full screen (checked 2026-10-05 on three displays).
        ("videos", "intVideoFormat"): 4,
    },
    "companion.json": {
        ("firstLaunchCompleted",): True,
        ("intWallpaperMode",): 0,  # screen saver only; the desktop wallpaper is left alone
        ("wallpaperModeChosen",): True,
        ("intAppPresentation",): 0,  # menu bar
        ("appPresentationChosen",): True,
        ("reclaimMacOSWallpaperVideosAtStartup",): False,  # would delete macOS's own aerial videos
    },
    "overlay-config.json": {
        ("showVersionAtStartup",): False,
    },
}


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
    os.replace(tmp, path)


def configure_settings(defaults_dir):
    for name, overrides in SETTINGS.items():
        path = f"{BASE}/{name}"
        existed = os.path.exists(path)
        data = json.load(open(path if existed else f"{defaults_dir}/{name}"))
        before = json.dumps(data, sort_keys=True)
        for keys, value in overrides.items():
            node = data
            for k in keys[:-1]:
                node = node[k]
            node[keys[-1]] = value
        if not existed or json.dumps(data, sort_keys=True) != before:
            write_json(path, data)
            print(f"{name}: {'updated' if existed else 'written'}")
        else:
            print(f"{name}: already set")


def clone_cache(assets):
    downloaded = {f[:-4] for f in os.listdir(f"{APPLE}/videos") if f.endswith(".mov")}
    os.makedirs(f"{BASE}/Cache", exist_ok=True)
    added = 0
    for a in assets:
        url = a.get("url-4K-SDR-240FPS")
        if a["id"] not in downloaded or not url:
            continue
        dst = f"{BASE}/Cache/{os.path.basename(url)}"
        if not os.path.exists(dst):
            subprocess.run(["/bin/cp", "-c", f"{APPLE}/videos/{a['id']}.mov", dst], check=True)
            added += 1
    print(f"cache: {len(downloaded)} aerials downloaded by macOS, {added} newly cloned in")
    return downloaded


def build_playlist(assets, downloaded):
    shuffle = [a for a in assets if a["id"] in downloaded and a.get("includeInShuffle")]
    os.makedirs(f"{BASE}/Playlists", exist_ok=True)
    index_path = f"{BASE}/Playlists/_index.json"
    index = json.load(open(index_path)) if os.path.exists(index_path) else {"version": 1, "playlists": []}
    mine = next((p for p in index["playlists"] if p["name"] == PLAYLIST), None)
    if mine:
        old = json.load(open(f"{BASE}/Playlists/{mine['id']}.json"))
        if {e["videoId"] for e in old["entries"]} == {a["id"] for a in shuffle}:
            print(f"playlist '{PLAYLIST}': unchanged, {len(shuffle)} aerials")
            return
    else:
        mine = {"id": str(uuid.uuid4()).upper(), "name": PLAYLIST,
                "order": max((p["order"] for p in index["playlists"]), default=-1) + 1}
        index["playlists"].append(mine)
    random.shuffle(shuffle)
    entries = [{"videoId": a["id"], "videoName": a.get("accessibilityLabel", ""), "secondaryName": "",
                "playDuration": 60.0} for a in shuffle]
    now = time.time() - 978307200  # Swift's default Date encoding counts seconds from 2001-01-01
    write_json(f"{BASE}/Playlists/{mine['id']}.json",
               {"id": mine["id"], "name": PLAYLIST, "createdAt": now, "cycleMode": 1, "entries": entries})
    mine["entryCount"] = len(entries)
    write_json(index_path, index)
    state_path = f"{BASE}/playlists.json"
    state = json.load(open(state_path)) if os.path.exists(state_path) else {"version": 1, "screenPlaylists": {}}
    state["sharedPlaylist"] = {"entries": entries, "currentIndex": 0, "filterMode": -1,
                               "filterStrings": [f"userPlaylist:{mine['id']}"], "generatedAt": now,
                               "cycleMode": 1}
    write_json(state_path, state)
    print(f"playlist '{PLAYLIST}': written, {len(entries)} aerials")


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    os.makedirs(BASE, exist_ok=True)
    configure_settings(sys.argv[1])
    assets = json.load(open(f"{APPLE}/manifest/entries.json"))["assets"]
    downloaded = clone_cache(assets)
    if not downloaded:
        sys.exit("No aerials downloaded yet. Download some in System Settings → Wallpaper, then re-run.")
    build_playlist(assets, downloaded)


if __name__ == "__main__":
    main()
