#!/bin/bash
# Installs the lock-screen keys on top of Karabiner-Elements (brew install --cask karabiner-elements):
#   - builds esc-if-locked and screen-lock-watch into ~/.local/libexec/karabiner/
#   - runs screen-lock-watch as the LaunchAgent ai.openclaw.aerial-shuffle-lockwatch
#   - merges the rules in aerial-shuffle.json into Karabiner's selected profile, and tells
#     Karabiner to modify the Keychron Q6 HE (Karabiner skips a device that is also a pointing
#     device unless told otherwise, and the Q6 HE reports as both)
# Safe to re-run.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$HOME/.local/libexec/karabiner"
label="ai.openclaw.aerial-shuffle-lockwatch"
plist="$HOME/Library/LaunchAgents/$label.plist"

mkdir -p "$bin"
for t in esc-if-locked screen-lock-watch; do
    swiftc -O -target arm64-apple-macos14 "$here/$t.swift" -o "$bin/$t"
done

if ! grep -q "$bin/screen-lock-watch" "$plist" 2>/dev/null; then
    cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key><array><string>$bin/screen-lock-watch</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLIST
    command -v launchd-name >/dev/null && launchd-name --no-reload "$label"
fi
launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"

python3 - "$here/aerial-shuffle.json" "$bin" <<'PY'
import json, os, sys
p = os.path.expanduser("~/.config/karabiner/karabiner.json")
cfg = json.load(open(p))
rules_in = json.loads(open(sys.argv[1]).read().replace("@BIN@", sys.argv[2]))["rules"]   # @BIN@: where the helpers were built
prof = next(x for x in cfg["profiles"] if x.get("selected"))
rules = prof.setdefault("complex_modifications", {}).setdefault("rules", [])
mine = {r["description"] for r in rules_in}
rules[:] = [r for r in rules if r.get("description") not in mine] + rules_in
q6he = {"is_keyboard": True, "is_pointing_device": True, "product_id": 2912, "vendor_id": 13364}
devs = prof.setdefault("devices", [])
devs[:] = [d for d in devs if d.get("identifiers") != q6he] + [{"identifiers": q6he, "ignore": False}]
tmp = p + ".tmp"
json.dump(cfg, open(tmp, "w"), indent=4)
os.replace(tmp, p)
print("karabiner rules:", [r["description"] for r in rules])
PY
