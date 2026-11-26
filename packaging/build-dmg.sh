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
  INSTALLER_BIN=".build/apple/Products/Release/DMXInstaller"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/DMXStudio"
  INSTALLER_BIN="$(swift build -c release --show-bin-path)/DMXInstaller"
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp packaging/import-asset.py packaging/export-character.py "$APP/Contents/Resources/"
python3 packaging/fetch-materials.py "$APP/Contents/Resources/Materials" || echo "WARNING: wood texture download incomplete; renderer uses fallback materials"
cp "$BIN" "$APP/Contents/MacOS/DMXStudio"
# Textured human meshes, converted to native SceneKit-readable USDZ offline.
# Source: Microsoft Rocketbox (MIT), converted GLB assets from avatar-studio.
CHAR="$APP/Contents/Resources/Characters"
mkdir -p "$CHAR"
# Prefer DMX Studio-owned, preconverted release assets. This directory is
# populated during development, never fetched by the installed application.
LOCAL_CHAR="packaging/character-library"
if [[ -d "$LOCAL_CHAR" ]]; then
  python3 - "$LOCAL_CHAR" "$CHAR" <<'PYCHAR'
import hashlib, json, pathlib, shutil, sys, zipfile
source, dest = map(pathlib.Path, sys.argv[1:])
manifest = json.loads((source / "manifest.json").read_text())
assets = manifest["assets"]
if not isinstance(assets, list) or not assets:
    raise ValueError("Character manifest must contain actual assets")
seen = set()
for asset in assets:
    name = asset["file"]
    if pathlib.Path(name).name != name or not name.endswith(".usdz"):
        raise ValueError("Invalid character asset filename: " + name)
    if name.casefold() in seen:
        raise ValueError("Duplicate character asset: " + name)
    seen.add(name.casefold())
    model = source / name
    if not model.is_file() or model.is_symlink():
        raise ValueError("Missing or linked character asset: " + name)
    if hashlib.sha256(model.read_bytes()).hexdigest() != asset["sha256"]:
        raise ValueError("Character asset checksum mismatch: " + name)
    if not asset.get("license") or not asset.get("source"):
        raise ValueError("Missing character asset provenance: " + name)
    with zipfile.ZipFile(model) as archive:
        if archive.testzip() is not None:
            raise ValueError("Corrupt USDZ: " + name)
        if not any(n.lower().endswith((".usd", ".usda", ".usdc")) for n in archive.namelist()):
            raise ValueError("Invalid USDZ: " + name)
    shutil.copy2(model, dest / name)
    print("Bundled local character asset:", name)
shutil.copy2(source / "manifest.json", dest / "local-manifest.json")
PYCHAR
fi
if [[ "${DMX_SKIP_CHARACTERS:-0}" != "1" ]]; then
  CACHE=".character-cache"
  mkdir -p "$CACHE"
  for NAME in andre_casual emma_casual marcus_formal priya_casual; do
    if [[ ! -s "$CHAR/$NAME.usdz" && -s "$CACHE/$NAME.usdz" ]]; then
      cp "$CACHE/$NAME.usdz" "$CHAR/$NAME.usdz"
    fi
  done
  NEED_BLENDER=0
  for NAME in andre_casual emma_casual marcus_formal priya_casual; do
    if [[ ! -s "$CHAR/$NAME.usdz" ]]; then NEED_BLENDER=1; fi
  done
  if [[ "$NEED_BLENDER" == 1 ]] && ! command -v blender >/dev/null && [[ ! -x /Applications/Blender.app/Contents/MacOS/Blender ]]; then
    brew install --cask blender
  fi
  BLENDER="$(command -v blender || echo /Applications/Blender.app/Contents/MacOS/Blender)"
  SRC="https://raw.githubusercontent.com/memoriesrohit/avatar-studio/2fd9ec82fbe1613d40ae38aadcca3f410725f740"
  TMPCHAR="$(mktemp -d)"
  curl -fLsS --retry 2 "https://raw.githubusercontent.com/microsoft/Microsoft-Rocketbox/master/LICENSE.md" -o "$CHAR/ROCKETBOX-LICENSE.txt"
  curl -fLsS --retry 2 "$SRC/LICENSE" -o "$CHAR/AVATAR-STUDIO-LICENSE.txt"
  for NAME in andre_casual emma_casual marcus_formal priya_casual; do
    if [[ -s "$CHAR/$NAME.usdz" ]]; then continue; fi
    curl -fLsS --retry 2 "$SRC/models/$NAME.glb" -o "$TMPCHAR/$NAME.glb"
    "$BLENDER" --background --factory-startup --python packaging/export-character.py -- "$TMPCHAR/$NAME.glb" "$CHAR/$NAME.usdz"
    test -s "$CHAR/$NAME.usdz"
    cp "$CHAR/$NAME.usdz" "$CACHE/$NAME.usdz"
  done
  rm -rf "$TMPCHAR"
fi


# Bundle approved candidate payloads, never LFS pointer text or unlicensed bodies.
python3 - "$CHAR" <<'PYCANDIDATES'
import pathlib, shutil, zipfile, hashlib, json, subprocess
src = pathlib.Path("packaging/character-candidates")
dest = pathlib.Path(__import__("sys").argv[1])
paths = [src / "bodies/male.usdz"] + [src / "hair" / f"{sex}-{i:02}.usdz" for sex, count in [("male",21),("female",12)] for i in range(1,count+1)]
if src.exists():
    records = []
    for path in paths:
        pointer = subprocess.check_output(["git","show",f"HEAD:{path}"]).decode()
        expected = next(line.split("sha256:")[1] for line in pointer.splitlines() if line.startswith("oid sha256:"))
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError(f"Missing or corrupt LFS payload: {path}")
        with zipfile.ZipFile(path) as z:
            if z.testzip() or not any(n.lower().endswith((".usd",".usda",".usdc")) for n in z.namelist()):
                raise ValueError(f"Invalid USDZ: {path}")
        target = dest / "Candidates" / path.parent.name / path.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path,target)
        records.append({"id":path.stem,"slot":path.parent.name,"file":str(target.relative_to(dest)),"sha256":expected})
    shutil.copy2(src / "CREDITS.md",dest / "Candidates" / "CREDITS.md")
    (dest / "Candidates" / "catalog.json").write_text(json.dumps(records,indent=2))
    morph = src / "face-morphs"
    data = json.loads((morph / "nose-presets.json").read_text())
    base = morph / "base.obj"
    if hashlib.sha256(base.read_bytes()).hexdigest() != data["baseSHA256"]:
        raise ValueError("Face morph base checksum mismatch")
    if sum(line.startswith("v ") for line in base.read_text().splitlines()) != data["vertexCount"]:
        raise ValueError("Face morph vertex count mismatch")
    if len(data["presets"]) != 15 or not data["exclusive"]:
        raise ValueError("Unexpected nose preset catalog")
    target = dest / "Candidates" / "face-morphs"
    target.mkdir(parents=True, exist_ok=True)
    for name in ("base.obj", "nose-presets.json", "LICENSE.ASSETS.md"):
        shutil.copy2(morph / name, target / name)
    print("Bundled topology-specific face morph source and 15 nose presets")
    print(f"Bundled {len(records)} approved character candidates")
PYCANDIDATES

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
  <key>NSDocumentsFolderUsageDescription</key><string>DMX Studio saves your sessions, presets, set lists and songs in Documents › DMX Studio.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>DMX Studio Session</string>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>Owner</string>
      <key>LSItemContentTypes</key><array><string>com.redvelvetstudios.dmxsession</string></array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>com.redvelvetstudios.dmxsession</string>
      <key>UTTypeDescription</key><string>DMX Studio Session</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string><string>public.archive</string></array>
      <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>dmxsession</string></array></dict>
    </dict>
  </array>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>NSCameraUsageDescription</key><string>DMX Studio uses your camera only when you enable it to capture photos or short videos of your lighting setup for troubleshooting.</string>
  <key>NSMicrophoneUsageDescription</key><string>DMX Studio listens to your microphone or computer audio (through BlackHole) to keep the lights on the beat and follow the sound.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>DMX Studio listens to the separated vocals of your songs to learn the lyrics, so the light show can follow what is being sung.</string>
  <key>NSLocalNetworkUsageDescription</key><string>DMX Studio looks for wireless DMX devices (like PKnight Art-Net boxes) on your network and sends lighting data to them.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature (no paid Apple developer account needed)
# Lyrics transcription engine (whisper.cpp, built by the "Whisper transcription engine" workflow)
if curl -sfL -o "$APP/Contents/Resources/whisper-cli" "https://github.com/josephbrooks7/dmx-studio/releases/download/whisper-1/whisper-cli"; then
  chmod +x "$APP/Contents/Resources/whisper-cli"
  codesign --force --sign - "$APP/Contents/Resources/whisper-cli"
  echo "bundled whisper-cli"
else
  rm -f "$APP/Contents/Resources/whisper-cli"; echo "whisper-cli not published yet: lyrics transcription falls back to Apple speech"
fi
# AI models built in, so everything works offline (no downloads at a show)
mkdir -p "$APP/Contents/Resources/Models"
if curl -sfL -o "$APP/Contents/Resources/Models/ggml-base.bin" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"; then
  echo "bundled lyrics model: $(du -h "$APP/Contents/Resources/Models/ggml-base.bin" | cut -f1)"
else rm -f "$APP/Contents/Resources/Models/ggml-base.bin"; echo "lyrics model not bundled"; fi
# the Accurate lyrics model (default) — built in so it works offline on the lighting network
if curl -sfL -o "$APP/Contents/Resources/Models/ggml-small-q8_0.bin" "https://github.com/josephbrooks7/dmx-studio/releases/download/whisper-1/ggml-small-q8_0.bin"; then
  echo "bundled accurate lyrics model: $(du -h "$APP/Contents/Resources/Models/ggml-small-q8_0.bin" | cut -f1)"
else rm -f "$APP/Contents/Resources/Models/ggml-small-q8_0.bin"; echo "accurate lyrics model not published yet"; fi
if curl -sfL -o /tmp/DemucsHQ.zip "https://github.com/josephbrooks7/dmx-studio/releases/download/hq-model-1/DemucsHQ.mlmodelc.zip"; then
  ditto -x -k /tmp/DemucsHQ.zip "$APP/Contents/Resources/Models/" && echo "bundled High Quality splitter model"
else echo "High Quality model not bundled"; fi
if curl -sfL -o /tmp/DemucsVox.zip "https://github.com/josephbrooks7/dmx-studio/releases/download/hq-model-1/DemucsVox.mlmodelc.zip"; then
  ditto -x -k /tmp/DemucsVox.zip "$APP/Contents/Resources/Models/" && echo "bundled vocals specialist model"
else echo "vocals specialist model not bundled"; fi
codesign --force --deep --sign - "$APP"

# The in-app update: the app without its AI models (a few MB). models.txt lists the models it
# expects (name and total bytes) so the update can reuse the ones already installed.
UPD="$OUT/upd/$APP_NAME.app"; mkdir -p "$OUT/upd"
ditto "$APP" "$UPD"
: > "$UPD/Contents/Resources/models.txt"
if [ -d "$APP/Contents/Resources/Models" ]; then
  for m in "$APP/Contents/Resources/Models"/*; do
    [ -e "$m" ] || continue
    b=$(find "$m" -type f -exec stat -f%z {} + | awk '{s+=$1} END {print s+0}')
    printf '%s\t%s\n' "$(basename "$m")" "$b" >> "$UPD/Contents/Resources/models.txt"
  done
fi
rm -rf "$UPD/Contents/Resources/Models"
codesign --force --deep --sign - "$UPD"
ditto -c -k --keepParent "$UPD" "$OUT/DMX-Studio-Update.zip"
echo "Built update zip ($(du -h "$OUT/DMX-Studio-Update.zip" | cut -f1)):"; cat "$UPD/Contents/Resources/models.txt"

# DMG with an Applications shortcut for drag-to-install
STAGE="$OUT/dmg"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/DMX-Studio-$VERSION.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "Built $DMG"

# The small installer: downloads the latest full DMG from the GitHub release and installs it
IAPP="$OUT/Install DMX Studio.app"
mkdir -p "$IAPP/Contents/MacOS" "$IAPP/Contents/Resources"
cp "$INSTALLER_BIN" "$IAPP/Contents/MacOS/DMXInstaller"
cp "$APP/Contents/Resources/AppIcon.icns" "$IAPP/Contents/Resources/AppIcon.icns"
cat > "$IAPP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Install DMX Studio</string>
  <key>CFBundleDisplayName</key><string>Install DMX Studio</string>
  <key>CFBundleExecutable</key><string>DMXInstaller</string>
  <key>CFBundleIdentifier</key><string>com.redvelvetstudios.dmxstudio.installer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$IAPP"
ISTAGE="$OUT/idmg"; mkdir -p "$ISTAGE"
cp -R "$IAPP" "$ISTAGE/"
# a fixed name, so releases/latest/download/DMX-Studio-Installer.dmg always gets the newest
IDMG="$OUT/DMX-Studio-Installer.dmg"
hdiutil create -volname "Install DMX Studio" -srcfolder "$ISTAGE" -ov -format UDZO "$IDMG" >/dev/null
echo "Built $IDMG ($(du -h "$IDMG" | cut -f1))"
