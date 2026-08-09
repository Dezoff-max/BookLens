#!/usr/bin/env bash
set -euo pipefail

APP_NAME="BookLens"
BUNDLE_ID="com.dmitry.booklens"

if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  exit 0
fi

if ! /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1; then
  echo "Could not close $APP_NAME cleanly. Close it manually and try again." >&2
  exit 1
fi

for ((attempt = 1; attempt <= 50; attempt++)); do
  if ! pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    exit 0
  fi
  /bin/sleep 0.1
done

echo "$APP_NAME did not finish saving its state. Close it manually and try again." >&2
exit 1
