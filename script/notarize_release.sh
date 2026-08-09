#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
SIGN_IDENTITY="${BOOKLENS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${BOOKLENS_NOTARY_PROFILE:-}"

if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
  echo "Set the Developer ID Application identity in BOOKLENS_SIGN_IDENTITY." >&2
  exit 2
fi
if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set the keychain profile name in BOOKLENS_NOTARY_PROFILE." >&2
  echo "Create it with: xcrun notarytool store-credentials <profile>" >&2
  exit 2
fi

if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGN_IDENTITY"; then
  echo "Developer ID identity was not found in the keychain: $SIGN_IDENTITY" >&2
  exit 1
fi

BOOKLENS_CONFIGURATION=release \
BOOKLENS_SIGN_IDENTITY="$SIGN_IDENTITY" \
  "$ROOT_DIR/script/create_dmg.sh"

APP_BUNDLE="$DIST_DIR/BookLens.app"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/BookLens-$APP_VERSION.dmg"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/codesign -d --verbose=4 "$APP_BUNDLE" 2>&1 | /usr/bin/grep -q 'Runtime Version'
/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null

/usr/bin/xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$(basename "$DMG_PATH")" >"$(basename "$DMG_PATH").sha256"
)

echo "Notarized release is ready: $DMG_PATH"
echo "Checksum: $DMG_PATH.sha256"
