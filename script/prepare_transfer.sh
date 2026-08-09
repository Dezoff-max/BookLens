#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BookLens"
PACKAGE_NAME="BookLens-Transfer"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_PATH="${1:-}"

if [[ -z "$TARGET_PATH" ]]; then
  echo "usage: $0 /Volumes/<USB>/$PACKAGE_NAME" >&2
  exit 2
fi

case "$TARGET_PATH" in
  /Volumes/*/BookLens-Transfer) ;;
  *)
    echo "Error: the target path must match /Volumes/<USB>/BookLens-Transfer" >&2
    exit 2
    ;;
esac

VOLUME_RELATIVE="${TARGET_PATH#/Volumes/}"
VOLUME_NAME="${VOLUME_RELATIVE%%/*}"
VOLUME_ROOT="/Volumes/$VOLUME_NAME"
EXPECTED_TARGET="$VOLUME_ROOT/$PACKAGE_NAME"
if [[ "$TARGET_PATH" != "$EXPECTED_TARGET" || ! -d "$VOLUME_ROOT" ]]; then
  echo "Error: the volume is not mounted or the target path is ambiguous." >&2
  exit 2
fi

DISK_INFO="$(/usr/sbin/diskutil info "$VOLUME_ROOT")"
if ! /usr/bin/grep -q 'Device Location:.*External' <<<"$DISK_INFO"; then
  echo "Error: $VOLUME_ROOT is not an external volume." >&2
  exit 2
fi
if /usr/bin/grep -q 'Volume Read-Only:.*Yes' <<<"$DISK_INFO"; then
  echo "Error: the volume is read-only." >&2
  exit 2
fi

AVAILABLE_KB="$(/bin/df -k "$VOLUME_ROOT" | /usr/bin/awk 'NR == 2 { print $4 }')"
if [[ -z "$AVAILABLE_KB" || "$AVAILABLE_KB" -lt 1048576 ]]; then
  echo "Error: the external drive needs at least 1 GB of free space." >&2
  exit 2
fi

APP_SUPPORT="$HOME/Library/Application Support/BookLens"
PREFERENCES="$HOME/Library/Preferences/com.dmitry.booklens.plist"
STORE="$APP_SUPPORT/BookLens.store"
test -f "$STORE"

"$ROOT_DIR/script/quit_booklens.sh"
INTEGRITY="$(/usr/bin/sqlite3 "$STORE" 'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA integrity_check;' | /usr/bin/tail -n 1)"
if [[ "$INTEGRITY" != "ok" ]]; then
  echo "Error: the local BookLens database failed integrity_check: $INTEGRITY" >&2
  exit 1
fi

BOOKLENS_CONFIGURATION=release "$ROOT_DIR/script/create_dmg.sh"
DIST_BUNDLE_VERIFIED=0
for ((attempt = 1; attempt <= 5; attempt++)); do
  /usr/bin/xattr -d com.apple.FinderInfo "$ROOT_DIR/dist/$APP_NAME.app" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.ResourceFork "$ROOT_DIR/dist/$APP_NAME.app" 2>/dev/null || true
  if /usr/bin/codesign --verify --deep --strict "$ROOT_DIR/dist/$APP_NAME.app" 2>/dev/null; then
    DIST_BUNDLE_VERIFIED=1
    break
  fi
  /bin/sleep 0.1
done
if [[ "$DIST_BUNDLE_VERIFIED" -ne 1 ]]; then
  /usr/bin/codesign --verify --deep --strict "$ROOT_DIR/dist/$APP_NAME.app"
fi
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/dist/$APP_NAME.app/Contents/Info.plist")"
DMG_PATH="$ROOT_DIR/dist/$APP_NAME-$APP_VERSION.dmg"
test -f "$DMG_PATH"
test -f "$DMG_PATH.sha256"

STAGING_ROOT="$(/usr/bin/mktemp -d "$VOLUME_ROOT/.booklens-transfer.XXXXXX")"
STAGING_PACKAGE="$STAGING_ROOT/$PACKAGE_NAME"
cleanup() {
  if [[ -d "$STAGING_ROOT" ]]; then
    /bin/rm -rf "$STAGING_ROOT"
  fi
}
trap cleanup EXIT

/bin/mkdir -p \
  "$STAGING_PACKAGE/App" \
  "$STAGING_PACKAGE/Source/BookLens" \
  "$STAGING_PACKAGE/Data/Application Support" \
  "$STAGING_PACKAGE/Data/Preferences"

/usr/bin/ditto "$ROOT_DIR/dist/$APP_NAME.app" "$STAGING_PACKAGE/App/$APP_NAME.app"
/usr/bin/ditto "$DMG_PATH" "$STAGING_PACKAGE/App/$APP_NAME-$APP_VERSION.dmg"
/usr/bin/ditto "$DMG_PATH.sha256" "$STAGING_PACKAGE/App/$APP_NAME-$APP_VERSION.dmg.sha256"
/usr/bin/xattr -d com.apple.FinderInfo "$STAGING_PACKAGE/App/$APP_NAME.app" 2>/dev/null || true
/usr/bin/xattr -d com.apple.ResourceFork "$STAGING_PACKAGE/App/$APP_NAME.app" 2>/dev/null || true

/usr/bin/rsync -a \
  --exclude '.build/' \
  --exclude 'dist/' \
  --exclude '.git/' \
  --exclude '.booklens-spike/' \
  --exclude '.DS_Store' \
  --exclude '*.xcuserstate' \
  "$ROOT_DIR/" "$STAGING_PACKAGE/Source/BookLens/"

/usr/bin/rsync -a \
  --exclude 'BookLens.store-shm' \
  --exclude 'BookLens.store-wal' \
  "$APP_SUPPORT/" "$STAGING_PACKAGE/Data/Application Support/BookLens/"
if [[ -f "$PREFERENCES" ]]; then
  /usr/bin/ditto "$PREFERENCES" "$STAGING_PACKAGE/Data/Preferences/com.dmitry.booklens.plist"
fi
/usr/bin/ditto "$ROOT_DIR/TransferAssets/README.txt" "$STAGING_PACKAGE/README.txt"
/usr/bin/ditto "$ROOT_DIR/TransferAssets/CONTINUE_IN_CODEX.md" "$STAGING_PACKAGE/CONTINUE_IN_CODEX.md"
/usr/bin/ditto "$ROOT_DIR/TransferAssets/verify_backup.command" "$STAGING_PACKAGE/verify_backup.command"
/usr/bin/ditto "$ROOT_DIR/TransferAssets/restore_booklens_data.command" "$STAGING_PACKAGE/restore_booklens_data.command"
/bin/chmod +x "$STAGING_PACKAGE/verify_backup.command" "$STAGING_PACKAGE/restore_booklens_data.command"

cd "$STAGING_PACKAGE"
find . -type f ! -name SHA256SUMS.txt -print | LC_ALL=C /usr/bin/sort | while IFS= read -r FILE; do
  /usr/bin/shasum -a 256 "$FILE"
done >SHA256SUMS.txt

/usr/bin/shasum -a 256 -c SHA256SUMS.txt >/dev/null
/usr/bin/codesign --verify --deep --strict "$STAGING_PACKAGE/App/$APP_NAME.app"
/usr/bin/hdiutil verify "$STAGING_PACKAGE/App/$APP_NAME-$APP_VERSION.dmg" >/dev/null
(cd "$STAGING_PACKAGE/App" && /usr/bin/shasum -a 256 -c "$APP_NAME-$APP_VERSION.dmg.sha256" >/dev/null)
test "$(/usr/bin/sqlite3 "file:$STAGING_PACKAGE/Data/Application Support/BookLens/BookLens.store?immutable=1" 'PRAGMA integrity_check;')" = "ok"
test -f "$STAGING_PACKAGE/Source/BookLens/Package.swift"
EXPECTED_FILE_COUNT="$(/usr/bin/wc -l <SHA256SUMS.txt | /usr/bin/tr -d ' ')"
ACTUAL_FILE_COUNT="$(find . -type f ! -name SHA256SUMS.txt | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
test "$ACTUAL_FILE_COUNT" = "$EXPECTED_FILE_COUNT"

if [[ -e "$EXPECTED_TARGET" ]]; then
  PREVIOUS_TARGET="$VOLUME_ROOT/$PACKAGE_NAME.previous-$(date +%Y%m%d-%H%M%S)"
  /bin/mv "$EXPECTED_TARGET" "$PREVIOUS_TARGET"
  echo "Previous package saved: $PREVIOUS_TARGET"
fi

/bin/mv "$STAGING_PACKAGE" "$EXPECTED_TARGET"
/bin/rmdir "$STAGING_ROOT"
trap - EXIT

echo "Package prepared: $EXPECTED_TARGET"
echo "Verify with: $EXPECTED_TARGET/verify_backup.command"
