#!/bin/bash
set -euo pipefail

APP_NAME="AerialShuffle"
BUNDLE_ID="com.user.aerial-shuffle"
VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
PAYLOAD_DIR="$BUILD_DIR/payload"
SCRIPTS_DIR="$BUILD_DIR/scripts"
APP_BUNDLE="$PAYLOAD_DIR/Applications/$APP_NAME.app"
PKG_PATH="$SCRIPT_DIR/$APP_NAME.pkg"

echo "=== Cleaning ==="
rm -rf "$BUILD_DIR" "$PKG_PATH"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
mkdir -p "$SCRIPTS_DIR"

echo "=== Compiling ==="
swiftc -target arm64-apple-macos14 -framework AppKit -framework SwiftUI -lsqlite3 \
    -O -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "$SCRIPT_DIR/AerialShuffle.swift"

echo "=== Generating app icon ==="
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

cat > "$BUILD_DIR/gen_icon.swift" << 'ICONSWIFT'
import AppKit

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")
]

let outputDir = CommandLine.arguments[1]

for (px, filename) in sizes {
    let size = CGFloat(px)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }

    rep.size = NSSize(width: size, height: size)
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.2

    // Background gradient
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    let bg = NSGradient(
        starting: NSColor(red: 0.15, green: 0.45, blue: 0.75, alpha: 1.0),
        ending: NSColor(red: 0.08, green: 0.25, blue: 0.55, alpha: 1.0)
    )!
    bg.draw(in: path, angle: -90)

    // SF Symbol in white
    let symConfig = NSImage.SymbolConfiguration(pointSize: size * 0.45, weight: .medium)
        .applying(.init(hierarchicalColor: .white))
    if let symbol = NSImage(systemSymbolName: "mountain.2.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symConfig) {
        let symSize = symbol.size
        let x = (size - symSize.width) / 2
        let y = (size - symSize.height) / 2
        symbol.draw(in: NSRect(x: x, y: y, width: symSize.width, height: symSize.height))
    }

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(outputDir)/\(filename)"))
}
ICONSWIFT

swiftc -target arm64-apple-macos14 -framework AppKit "$BUILD_DIR/gen_icon.swift" -o "$BUILD_DIR/gen_icon"
"$BUILD_DIR/gen_icon" "$ICONSET_DIR"

# Verify iconset has files
ICON_COUNT=$(ls "$ICONSET_DIR"/*.png 2>/dev/null | wc -l | tr -d ' ')
if [ "$ICON_COUNT" -eq 0 ]; then
    echo "ERROR: Icon generation produced no PNGs"
    exit 1
fi
echo "  Generated $ICON_COUNT icon sizes"

iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "=== Creating Info.plist ==="
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Aerial Shuffle</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "=== Creating postinstall script ==="
cat > "$SCRIPTS_DIR/postinstall" << 'EOF'
#!/bin/bash
# Create config directory for the installing user
CONSOLE_USER=$(stat -f "%Su" /dev/console)
CONSOLE_HOME=$(dscl . -read /Users/"$CONSOLE_USER" NFSHomeDirectory | awk '{print $2}')
CONFIG_DIR="$CONSOLE_HOME/Library/Application Support/AerialShuffle"
ACTIVE_DIR="$CONFIG_DIR/active"

mkdir -p "$ACTIVE_DIR"
chown -R "$CONSOLE_USER" "$CONFIG_DIR"

# Kill any existing instance (SIGTERM so it can restore refresh rate)
killall AerialShuffle 2>/dev/null || true
sleep 1

# Launch the app as the console user
su "$CONSOLE_USER" -c 'open /Applications/AerialShuffle.app'

exit 0
EOF
chmod +x "$SCRIPTS_DIR/postinstall"

echo "=== Building PKG ==="
pkgbuild \
    --root "$PAYLOAD_DIR" \
    --scripts "$SCRIPTS_DIR" \
    --identifier "$BUNDLE_ID" \
    --version "$VERSION" \
    --install-location / \
    "$PKG_PATH"

echo ""
echo "=== Done ==="
echo "PKG: $PKG_PATH"
echo ""
echo "To install:  open $PKG_PATH"
