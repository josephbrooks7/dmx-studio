#!/bin/bash
# Builds "DMX Studio.app" and packs it into a drag-to-install DMG.
# Usage: packaging/build-dmg.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="DMX Studio"
VERSION="${VERSION:-1.0.0}"
OUT="build"
APP="$OUT/$APP_NAME.app"
rm -rf "$OUT"; mkdir -p "$OUT"

if [[ "${1:-}" == "--universal" ]]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=".build/apple/Products/Release/DMXStudio"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/DMXStudio"
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DMXStudio"

# App icon
ICONSET="$OUT/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s packaging/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) packaging/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>DMXStudio</string>
  <key>CFBundleIdentifier</key><string>com.redvelvetstudios.dmxstudio</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>DMX Studio listens to your microphone or computer audio (through BlackHole) to keep the lights on the beat and follow the sound.</string>
  <key>NSLocalNetworkUsageDescription</key><string>DMX Studio looks for wireless DMX devices (like PKnight Art-Net boxes) on your network and sends lighting data to them.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (no paid Apple developer account needed)
codesign --force --deep --sign - "$APP"

# DMG with an Applications shortcut for drag-to-install
STAGE="$OUT/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/DMX-Studio-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"
