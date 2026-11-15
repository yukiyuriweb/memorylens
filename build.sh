#!/bin/zsh
# swiftc で直接ビルドして build/MemoryLens.app を作る
#   ./build.sh            ビルドのみ
#   ./build.sh --install  ビルドして ~/Applications に入れ、起動し直す
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MemoryLens.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# UI strings are English in code; other languages live in Localization/*.lproj
cp -R Localization/*.lproj "$APP/Contents/Resources/"

swiftc -O -swift-version 5 -parse-as-library \
  -target arm64-apple-macos26.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/MemoryLens"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ja</string></array>
  <key>CFBundleExecutable</key><string>MemoryLens</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>local.foundry.MemoryLens</string>
  <key>CFBundleName</key><string>MemoryLens</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST=~/Applications/MemoryLens.app
  pkill -x MemoryLens || true
  mkdir -p ~/Applications
  rm -rf "$DEST"
  ditto "$APP" "$DEST"
  open "$DEST"
  echo "installed: $DEST"
fi
