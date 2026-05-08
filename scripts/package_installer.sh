#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Contextual Mac Translator"
PACKAGE_NAME="Contextual-Mac-Translator-v0.1.4-macos-arm64.pkg"
PACKAGE_IDENTIFIER="app.lookerlab.translator.installer"
PACKAGE_VERSION="0.1.4"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/scripts/package_app.sh" "$CONFIG"

APP_DIR="$ROOT_DIR/.build/app/$APP_NAME.app"
PKG_DIR="$ROOT_DIR/.build/installer"
PKG_PATH="$PKG_DIR/$PACKAGE_NAME"
STAGING_DIR="$PKG_DIR/root"

rm -rf "$PKG_DIR"
mkdir -p "$STAGING_DIR"

export COPYFILE_DISABLE=1
ditto --norsrc "$APP_DIR" "$STAGING_DIR/$APP_NAME.app"
find "$STAGING_DIR/$APP_NAME.app" -exec xattr -c {} +
codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/$APP_NAME.app"

pkgbuild \
  --root "$STAGING_DIR" \
  --install-location "/Applications" \
  --identifier "$PACKAGE_IDENTIFIER" \
  --version "$PACKAGE_VERSION" \
  "$PKG_PATH"

pkgutil --payload-files "$PKG_PATH" >/dev/null

echo "$PKG_PATH"
