#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Contextual Mac Translator"
APP_VERSION="0.7.1"
DMG_NAME="Contextual-Mac-Translator-v${APP_VERSION}-macos-arm64.dmg"
ZIP_NAME="Contextual-Mac-Translator-v${APP_VERSION}-macos-arm64.zip"
VOLUME_NAME="Contextual Mac Translator"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Optional notarization. Export NOTARY_PROFILE to enable:
#   export NOTARY_PROFILE="translator-notary"
# where "translator-notary" is the name passed to
# `xcrun notarytool store-credentials` once during setup. When unset, the
# DMG is built but not notarized (still installable, but Gatekeeper will
# require right-click -> Open on first launch).
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# Sparkle sign_update path. Falls back to the bundled tools/ copy if
# the canonical Sparkle install directory isn't present.
SPARKLE_SIGN_UPDATE="${SPARKLE_SIGN_UPDATE:-$HOME/.local/share/sparkle-2.9.2/bin/sign_update}"

"$ROOT_DIR/scripts/package_app.sh" "$CONFIG"

APP_DIR="$ROOT_DIR/.build/app/$APP_NAME.app"
DMG_DIR="$ROOT_DIR/.build/dmg"
STAGING_DIR="$DMG_DIR/staging"
DMG_PATH="$DMG_DIR/$DMG_NAME"
ZIP_PATH="$DMG_DIR/$ZIP_NAME"

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

# Sparkle prefers .zip over .dmg for updates — extracts faster and the
# Updater.app can swap a .app bundle in place without needing a mounted
# volume. We zip directly from the .app/, NOT from the DMG staging.
echo "Creating Sparkle update zip..."
(
  cd "$(dirname "$APP_DIR")"
  /usr/bin/ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"
)

if [ -n "$NOTARY_PROFILE" ]; then
  echo "Submitting DMG to Apple notarization (profile: $NOTARY_PROFILE)..."
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  echo "Stapling notarization ticket to DMG..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"

  echo "Submitting Sparkle zip to Apple notarization..."
  xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  # Cannot staple to a .zip directly — staple to the .app inside, then
  # re-zip so the stapled ticket travels with the update bundle.
  echo "Stapling notarization ticket to .app inside zip..."
  xcrun stapler staple "$APP_DIR"
  xcrun stapler validate "$APP_DIR"
  (
    cd "$(dirname "$APP_DIR")"
    rm -f "$ZIP_PATH"
    /usr/bin/ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"
  )
  echo "Notarization complete and stapled (DMG + zip)."
fi

# Generate Sparkle appcast entry. sign_update reads private key from the
# macOS Keychain (created by generate_keys); it prints the EdDSA
# signature + file size on stdout in attribute form.
if [ -x "$SPARKLE_SIGN_UPDATE" ]; then
  echo ""
  echo "================================================================"
  echo "Sparkle appcast entry — paste into docs/appcast.xml <channel>:"
  echo "================================================================"
  SIG_ATTRS="$("$SPARKLE_SIGN_UPDATE" "$ZIP_PATH")"
  PUB_DATE="$(LC_TIME=C date "+%a, %d %b %Y %H:%M:%S %z")"
  RELEASE_URL="https://github.com/hoangperry/hp-translator/releases/download/v${APP_VERSION}/${ZIP_NAME}"

  cat <<EOF
    <item>
      <title>v${APP_VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <description><![CDATA[
        <p>See <a href="https://github.com/hoangperry/hp-translator/releases/tag/v${APP_VERSION}">release notes</a> on GitHub.</p>
      ]]></description>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${RELEASE_URL}"
        sparkle:version="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_DIR/Contents/Info.plist")"
        sparkle:shortVersionString="${APP_VERSION}"
        ${SIG_ATTRS}
        type="application/octet-stream" />
    </item>
EOF
  echo "================================================================"
else
  echo "WARNING: $SPARKLE_SIGN_UPDATE not found — skipping appcast entry."
  echo "         Install Sparkle CLI tools or set SPARKLE_SIGN_UPDATE." >&2
fi

echo ""
echo "DMG: $DMG_PATH"
echo "ZIP: $ZIP_PATH"
