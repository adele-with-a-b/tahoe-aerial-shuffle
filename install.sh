#!/bin/bash
# Sets up this Mac: the lock screen keys (karabiner/install.sh), then the every-minute Aerial
# screen saver (aerial/install.sh). See README.md. Safe to re-run.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

if [ ! -f "$HOME/.config/karabiner/karabiner.json" ]; then
    [ -d /Applications/Karabiner-Elements.app ] || brew install --cask karabiner-elements
    open -a Karabiner-Elements
    echo "Karabiner-Elements needs a one-time approval: follow its prompts to allow its driver"
    echo "extension and Input Monitoring, then run this script again."
    exit 1
fi
bash "$here/karabiner/install.sh"
bash "$here/aerial/install.sh"
