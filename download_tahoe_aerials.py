#!/usr/bin/env python3
"""
macOS Tahoe Aerial Wallpaper Downloader
Reads the local manifest entries.json to get Apple's CDN URLs,
then downloads all 4K SDR videos with proper names.

Usage:
    python3 download_tahoe_wallpapers.py [--output ~/Movies/Aerials] [--filter tahoe] [--dry-run]
"""

import json
import os
import sys
import argparse
import urllib.request
import urllib.error
from pathlib import Path

MANIFEST_PATH = Path.home() / "Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json"
DEFAULT_OUTPUT = Path.home() / "Movies/Aerials"

def load_manifest(path: Path) -> list[dict]:
    with open(path) as f:
        data = json.load(f)
    return data["assets"]

def sanitize_filename(name: str) -> str:
    return name.replace("/", "-").replace(":", "-").replace(" ", "_")

def download_file(url: str, dest: Path, label: str) -> None:
    if dest.exists():
        size = dest.stat().st_size
        print(f"  [skip] {label} — already exists ({size // 1024 // 1024}MB)")
        return

    print(f"  [download] {label}")
    print(f"    → {dest.name}")

    tmp = dest.with_suffix(".tmp")
    try:
        def progress(block_num, block_size, total_size):
            if total_size > 0:
                pct = min(100, block_num * block_size * 100 // total_size)
                mb_done = block_num * block_size / 1024 / 1024
                mb_total = total_size / 1024 / 1024
                print(f"\r    {pct:3d}%  {mb_done:.1f}/{mb_total:.1f} MB", end="", flush=True)

        urllib.request.urlretrieve(url, tmp, reporthook=progress)
        print()  # newline after progress
        tmp.rename(dest)
        final_mb = dest.stat().st_size / 1024 / 1024
        print(f"    ✓ {final_mb:.1f} MB saved")
    except urllib.error.HTTPError as e:
        print(f"\n    ✗ HTTP {e.code}: {e.reason}")
        if tmp.exists():
            tmp.unlink()
    except KeyboardInterrupt:
        print("\n    Interrupted — removing partial file")
        if tmp.exists():
            tmp.unlink()
        raise

def main():
    parser = argparse.ArgumentParser(description="Download macOS Tahoe aerial wallpapers")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Output directory")
    parser.add_argument("--filter", default=None, help="Only download entries whose name contains this string (case-insensitive)")
    parser.add_argument("--dry-run", action="store_true", help="List what would be downloaded without downloading")
    parser.add_argument("--list", action="store_true", help="List all available wallpapers and exit")
    args = parser.parse_args()

    if not MANIFEST_PATH.exists():
        print(f"ERROR: Manifest not found at:\n  {MANIFEST_PATH}")
        print("Make sure macOS Tahoe Screen Saver has been opened at least once to download the manifest.")
        sys.exit(1)

    assets = load_manifest(MANIFEST_PATH)
    print(f"Manifest loaded: {len(assets)} assets\n")

    # Filter
    if args.filter:
        assets = [a for a in assets if args.filter.lower() in a.get("accessibilityLabel", "").lower()]
        print(f"Filter '{args.filter}' matched {len(assets)} assets\n")

    if args.list:
        for a in sorted(assets, key=lambda x: x.get("preferredOrder", 999)):
            label = a.get("accessibilityLabel", "Unknown")
            shot = a.get("shotID", "?")
            has_url = "url-4K-SDR-240FPS" in a
            print(f"  {label:40s}  {shot:15s}  {'✓ 4K' if has_url else '✗ no URL'}")
        return

    output_dir = Path(args.output).expanduser()
    if not args.dry_run:
        output_dir.mkdir(parents=True, exist_ok=True)
        print(f"Output: {output_dir}\n")

    # Sort by preferredOrder
    assets_sorted = sorted(assets, key=lambda x: x.get("preferredOrder", 999))

    total = len(assets_sorted)
    skipped = 0

    for i, asset in enumerate(assets_sorted, 1):
        label = asset.get("accessibilityLabel", "Unknown")
        shot_id = asset.get("shotID", asset.get("id", "unknown"))
        url = asset.get("url-4K-SDR-240FPS")

        if not url:
            print(f"[{i}/{total}] {label} — no URL, skipping")
            skipped += 1
            continue

        # Build filename: ShotID_Label.mov  (e.g. TA_L_001_Tahoe_Morning.mov)
        safe_label = sanitize_filename(label)
        filename = f"{shot_id}_{safe_label}.mov"
        dest = output_dir / filename

        if args.dry_run:
            print(f"[{i}/{total}] {label}")
            print(f"    {url}")
            print(f"    → {dest}")
            print()
            continue

        print(f"[{i}/{total}] {label}")
        download_file(url, dest, label)
        print()

    if args.dry_run:
        print(f"Dry run complete. Would download {total - skipped} files.")
    else:
        print(f"Done. {total - skipped} files processed, {skipped} skipped (no URL).")

if __name__ == "__main__":
    main()
