#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Building ==="
bash "$SCRIPT_DIR/build.sh"

echo "=== Updating ==="
killall AerialShuffle 2>/dev/null || true
sleep 1
rm -rf /Applications/AerialShuffle.app
cp -R /tmp/aerial-shuffle-build/AerialShuffle.app /Applications/
open /Applications/AerialShuffle.app

echo "=== Done ==="
