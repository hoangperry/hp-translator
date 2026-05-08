#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Contextual Mac Translator"
DMG_NAME="Contextual-Mac-Translator-v0.1.3-macos-arm64.dmg"
VOLUME_NAME="Contextual Mac Translator"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/package_app.sh" "$CONFIG"

APP_DIR="$ROOT_DIR/.build/app/$APP_NAME.app"
DMG_DIR="$ROOT_DIR/.build/dmg"
STAGING_DIR="$DMG_DIR/staging"
DMG_PATH="$DMG_DIR/$DMG_NAME"

rm -rf "$DMG_DIR"
mkdir -p "$STAGING_DIR"

export COPYFILE_DISABLE=1
ditto --norsrc "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

hdiutil verify "$DMG_PATH" >/dev/null

echo "$DMG_PATH"
