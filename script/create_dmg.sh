#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BookLens"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/booklens-dmg.XXXXXX")"

cleanup() {
  if [[ -d "$STAGING_DIR" ]]; then
    find "$STAGING_DIR" -depth -delete
  fi
}
trap cleanup EXIT

BOOKLENS_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --package
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
OUTPUT_PATH="${1:-$DIST_DIR/$APP_NAME-$APP_VERSION.dmg}"
case "$OUTPUT_PATH" in
  "$DIST_DIR"/*.dmg) ;;
  *)
    echo "Error: the DMG must be inside $DIST_DIR" >&2
    exit 2
    ;;
esac

/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"
/usr/bin/xattr -cr "$STAGING_DIR/$APP_NAME.app"
/usr/bin/codesign --verify --deep --strict "$STAGING_DIR/$APP_NAME.app"

TEMP_DMG="$DIST_DIR/.$APP_NAME-$APP_VERSION-$(date +%Y%m%d-%H%M%S).dmg"
/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$TEMP_DMG" >/dev/null
/usr/bin/hdiutil verify "$TEMP_DMG" >/dev/null

/bin/rm -f "$OUTPUT_PATH" "$OUTPUT_PATH.sha256"
/bin/mv "$TEMP_DMG" "$OUTPUT_PATH"
(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$(basename "$OUTPUT_PATH")" >"$(basename "$OUTPUT_PATH").sha256"
)

echo "DMG created: $OUTPUT_PATH"
echo "SHA-256: $OUTPUT_PATH.sha256"
