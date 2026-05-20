#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Contextual Mac Translator"
DMG_NAME="Contextual-Mac-Translator-v0.4.1-macos-arm64.dmg"
VOLUME_NAME="Contextual Mac Translator"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Optional notarization. Export NOTARY_PROFILE to enable:
#   export NOTARY_PROFILE="translator-notary"
# where "translator-notary" is the name passed to
# `xcrun notarytool store-credentials` once during setup. When unset, the
# DMG is built but not notarized (still installable, but Gatekeeper will
# require right-click -> Open on first launch).
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

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

if [ -n "$NOTARY_PROFILE" ]; then
  echo "Submitting DMG to Apple notarization (profile: $NOTARY_PROFILE)..."
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  echo "Stapling notarization ticket..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  echo "Notarization complete and stapled."
fi

echo "$DMG_PATH"
