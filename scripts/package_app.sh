#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-debug}"
APP_NAME="Contextual Mac Translator"
BINARY_NAME="ContextualMacTranslator"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/module-cache" "$ROOT_DIR/.build/cache" "$ROOT_DIR/.build/swiftpm"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export XDG_CACHE_HOME="$ROOT_DIR/.build/cache"
export SWIFTPM_HOME="$ROOT_DIR/.build/swiftpm"

swift build -c "$CONFIG"

APP_DIR="$ROOT_DIR/.build/app/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
BUILD_DIR="$ROOT_DIR/.build/$CONFIG"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$BUILD_DIR/$BINARY_NAME" "$MACOS_DIR/$BINARY_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>ContextualMacTranslator</string>
  <key>CFBundleIdentifier</key>
  <string>app.lookerlab.translator</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Contextual Mac Translator</string>
  <key>CFBundleDisplayName</key>
  <string>Contextual Mac Translator</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.2</string>
  <key>CFBundleVersion</key>
  <string>3</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Contextual Mac Translator uses keyboard automation to translate and send chat text.</string>
  <key>NSInputMonitoringUsageDescription</key>
  <string>Contextual Mac Translator listens for global hotkeys to trigger translation workflows.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
