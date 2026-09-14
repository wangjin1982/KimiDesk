#!/bin/bash
# Build KimiDesk.app: universal binary + icon + adhoc sign + zip.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.3.1"
APP="Dist/KimiDesk.app"

echo "==> 1. universal release build"
swift build -c release --arch arm64 --arch x86_64
BIN=".build/apple/Products/Release/KimiDesk"
lipo -info "$BIN"

echo "==> 2. assemble .app"
rm -rf Dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KimiDesk"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>KimiDesk</string>
  <key>CFBundleIdentifier</key><string>dev.local.kimidesk</string>
  <key>CFBundleName</key><string>KimiDesk</string>
  <key>CFBundleDisplayName</key><string>KimiDesk</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

echo "==> 3. icon"
swift Scripts/make_icon.swift /tmp/kimidesk_icon_1024.png
ICONSET=/tmp/KimiDesk.iconset
rm -rf "$ICONSET" && mkdir "$ICONSET"
sips -z 16 16     /tmp/kimidesk_icon_1024.png --out "$ICONSET/icon_16x16.png"      >/dev/null
sips -z 32 32     /tmp/kimidesk_icon_1024.png --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
sips -z 32 32     /tmp/kimidesk_icon_1024.png --out "$ICONSET/icon_32x32.png"      >/dev/null
sips -z 64 64     /tmp/kimidesk_icon_1024.png --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
sips -z 128 128   /tmp/kimidesk_icon_1024.png --out "$ICONSET/icon_128x128.png"    >/dev/null
sips -z 256 256   /tmp/kimidesk_icon_1024.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   /tmp/kimidesk_icon_1024.png --out "$ICONSET/icon_256x256.png"    >/dev/null
sips -z 512 512   /tmp/kimidesk_icon_1024.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   /tmp/kimidesk_icon_1024.png --out "$ICONSET/icon_512x512.png"    >/dev/null
cp /tmp/kimidesk_icon_1024.png "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> 4. adhoc sign"
codesign --force --deep --sign - "$APP"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|flags"

echo "==> 5. zip"
(cd Dist && ditto -c -k --keepParent KimiDesk.app "KimiDesk-${VERSION}-universal.zip")
ls -lh Dist/

# 部署到 /Applications 时务必先删后拷（cp -R 到已存在的 .app 会嵌套！）：
#   rm -rf /Applications/KimiDesk.app && cp -R Dist/KimiDesk.app /Applications/
