#!/bin/bash
# FreeDisplay — Local build WITHOUT full Xcode.
#
# Builds the .app bundle directly with swiftc + actool + codesign, using only the
# Command Line Tools. Intended for Hackintosh / no-Apple-Developer-account setups.
#
# Usage:  ./build-local.sh           # build into build-local/FreeDisplay.app
#         ./build-local.sh install   # build, then copy to /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/FreeDisplay"
OUT="$ROOT/build-local"
APP="$OUT/FreeDisplay.app"
CONTENTS="$APP/Contents"
SDK="$(xcrun --show-sdk-path)"
TARGET="x86_64-apple-macos14.0"
BUNDLE_ID="com.freedisplay.app"

echo "==> Cleaning $OUT"
rm -rf "$OUT"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "==> Compiling Swift sources (this takes ~30s)…"
# -undefined dynamic_lookup: resolves the private CGVirtualDisplay / IOAVService
#   symbols declared in the bridging header at runtime instead of link time.
# -parse-as-library: required because the entry point uses the @main attribute.
# NOTE: -swift-version 5 is REQUIRED. The project relies on Swift 5 concurrency
# semantics (project.yml sets SWIFT_STRICT_CONCURRENCY: minimal). Building in
# Swift 6 language mode turns the services' @MainActor DDC-completion closures —
# which legitimately run on a background I2C queue — into hard runtime isolation
# traps (SIGILL / dispatch_assert_queue_fail) on the first DDC read.
swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -swift-version 5 \
  -parse-as-library \
  -O \
  -import-objc-header "$SRC/FreeDisplay-Bridging-Header.h" \
  -Xlinker -undefined -Xlinker dynamic_lookup \
  -o "$CONTENTS/MacOS/FreeDisplay" \
  $(find "$SRC" -name '*.swift')

echo "==> Building app icon (iconutil — no Xcode needed)…"
# actool requires full Xcode, so build the .icns straight from the PNGs with
# iconutil, which ships with the Command Line Tools.
ICONSET="$OUT/AppIcon.iconset"
ICONSRC="$SRC/Assets.xcassets/AppIcon.appiconset"
if [[ -d "$ICONSRC" ]]; then
  mkdir -p "$ICONSET"
  cp "$ICONSRC/icon_16.png"   "$ICONSET/icon_16x16.png"
  cp "$ICONSRC/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
  cp "$ICONSRC/icon_32.png"   "$ICONSET/icon_32x32.png"
  cp "$ICONSRC/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
  cp "$ICONSRC/icon_128.png"  "$ICONSET/icon_128x128.png"
  cp "$ICONSRC/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
  cp "$ICONSRC/icon_256.png"  "$ICONSET/icon_256x256.png"
  cp "$ICONSRC/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
  cp "$ICONSRC/icon_512.png"  "$ICONSET/icon_512x512.png"
  cp "$ICONSRC/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
  iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns" \
    && echo "    AppIcon.icns built" \
    || echo "    (iconutil failed — app will use a default icon)"
  rm -rf "$ICONSET"
fi

echo "==> Writing Info.plist…"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>FreeDisplay</string>
    <key>CFBundleDisplayName</key>     <string>FreeDisplay</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>      <string>FreeDisplay</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>CFBundleIconName</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHumanReadableCopyright</key><string>FreeDisplay - Free &amp; Open Source</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>FreeDisplay needs Screen Recording permission to show live per-display previews.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing (with entitlements)…"
codesign --force --deep --sign - \
  --entitlements "$SRC/FreeDisplay.entitlements" \
  "$APP" 2>/dev/null || codesign --force --deep --sign - "$APP"

echo "==> Verifying bundle…"
codesign --verify --verbose=2 "$APP" 2>&1 | sed 's/^/    /' || true

echo ""
echo "Built: $APP"

if [[ "${1:-}" == "install" ]]; then
  echo "==> Installing to /Applications…"
  rm -rf "/Applications/FreeDisplay.app"
  cp -R "$APP" "/Applications/FreeDisplay.app"
  echo "Installed: /Applications/FreeDisplay.app"
fi
