#!/bin/bash
set -euo pipefail
SOURCE="${1:-/Applications/DMX Studio.app}"
STAGING="$HOME/DMX-Character-Staging"
DEST="$HOME/DMX Character Preview.app"
MALE="$STAGING/6f64316a0ebccd590d847fb1/model.usdz"
FEMALE="$STAGING/78fea943058095c95e323772/model.usdz"
test -d "$SOURCE/Contents/Resources/Characters"
test ! -e "$DEST" || { echo "Preview already exists; rename it before retrying."; exit 1; }
for asset in "$MALE" "$FEMALE"; do
  test -s "$asset"
  unzip -tq "$asset"
done
ditto "$SOURCE" "$DEST"
CHAR="$DEST/Contents/Resources/Characters"
for name in andre_casual marcus_formal; do cp "$MALE" "$CHAR/$name.usdz"; done
for name in emma_casual priya_casual; do cp "$FEMALE" "$CHAR/$name.usdz"; done
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.redvelvetstudios.dmxstudio.characterpreview' "$DEST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName DMX Character Preview' "$DEST/Contents/Info.plist"
codesign --force --deep --sign - "$DEST"
echo "Local preview created: $DEST"
echo "Quit the stable app before launching. Use a new empty show; do not save over existing shows."
echo "Preview only: material-only meshes, unverified scale and licensing. Do not distribute."
open "$DEST"
