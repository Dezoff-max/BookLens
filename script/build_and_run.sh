#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
CONFIGURATION="${BOOKLENS_CONFIGURATION:-debug}"
APP_NAME="BookLens"
BUNDLE_ID="com.dmitry.booklens"
MIN_SYSTEM_VERSION="15.0"
APP_VERSION="${BOOKLENS_APP_VERSION:-1.0.1}"
BUILD_NUMBER="${BOOKLENS_BUILD_NUMBER:-2}"
SIGN_IDENTITY="${BOOKLENS_SIGN_IDENTITY:--}"
SWIFT_BUILD_DIR="${BOOKLENS_BUILD_DIR:-${TMPDIR:-/tmp}/booklens-swiftpm-build}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/booklens-stage.XXXXXX")"
STAGED_APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
STAGED_CONTENTS="$STAGED_APP_BUNDLE/Contents"
STAGED_MACOS="$STAGED_CONTENTS/MacOS"
STAGED_RESOURCES="$STAGED_CONTENTS/Resources"
STAGED_BINARY="$STAGED_MACOS/$APP_NAME"
STAGED_INFO_PLIST="$STAGED_CONTENTS/Info.plist"
APP_ICON="$ROOT_DIR/Assets/AppIcon/BookLens.icns"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

if [[ "$MODE" != "package" && "$MODE" != "--package" ]]; then
  "$ROOT_DIR/script/quit_booklens.sh"
fi

cd "$ROOT_DIR"
if [[ "$CONFIGURATION" == "release" ]]; then
  swift build --scratch-path "$SWIFT_BUILD_DIR" -c release --product "$APP_NAME"
  BUILD_BIN_DIR="$(swift build --scratch-path "$SWIFT_BUILD_DIR" -c release --show-bin-path)"
else
  swift build --scratch-path "$SWIFT_BUILD_DIR" --product "$APP_NAME"
  BUILD_BIN_DIR="$(swift build --scratch-path "$SWIFT_BUILD_DIR" --show-bin-path)"
fi
test -f "$APP_ICON"
BUILD_BINARY="$BUILD_BIN_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BUILD_BIN_DIR/BookLens_BookLens.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$STAGED_MACOS" "$STAGED_RESOURCES" "$DIST_DIR"
cp "$BUILD_BINARY" "$STAGED_BINARY"
chmod +x "$STAGED_BINARY"
if [[ -d "$ROOT_DIR/BookLensApp/Resources" ]]; then
  /usr/bin/ditto "$ROOT_DIR/BookLensApp/Resources" "$STAGED_RESOURCES"
fi
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  /usr/bin/ditto "$RESOURCE_BUNDLE" "$STAGED_RESOURCES/BookLens_BookLens.bundle"
fi
/usr/bin/ditto "$APP_ICON" "$STAGED_RESOURCES/BookLens.icns"

cat >"$STAGED_INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>BookLens</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
  </array>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>org.idpf.epub-container</string>
      <key>UTTypeDescription</key>
      <string>EPUB Book</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
        <string>public.archive</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array><string>epub</string></array>
        <key>public.mime-type</key>
        <string>application/epub+zip</string>
      </dict>
    </dict>
  </array>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.reference</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

/usr/bin/xattr -cr "$STAGED_APP_BUNDLE"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --deep --options runtime --sign - --timestamp=none "$STAGED_APP_BUNDLE"
else
  /usr/bin/codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" --timestamp "$STAGED_APP_BUNDLE"
fi
/usr/bin/codesign --verify --deep --strict "$STAGED_APP_BUNDLE"
/usr/bin/ditto "$STAGED_APP_BUNDLE" "$APP_BUNDLE"
# Desktop/FileProvider can attach empty Finder metadata during the final copy.
# It is not part of the signed bundle and makes strict verification reject it.
FINAL_BUNDLE_VERIFIED=0
for ((attempt = 1; attempt <= 5; attempt++)); do
  /usr/bin/xattr -d com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.ResourceFork "$APP_BUNDLE" 2>/dev/null || true
  if /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE" 2>/dev/null; then
    FINAL_BUNDLE_VERIFIED=1
    break
  fi
  /bin/sleep 0.1
done
if [[ "$FINAL_BUNDLE_VERIFIED" -ne 1 ]]; then
  /usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --package|package)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--package|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
