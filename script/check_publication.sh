#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

test -f Package.swift
test -f README.md
test -f LICENSE
test -f SECURITY.md
test -f Documentation/PRIVACY.md
test -d .git

FAILED=0
while IFS= read -r TRACKED_FILE; do
  case "$TRACKED_FILE" in
    App/*|Data/*|*.app/*|*.dmg|*.dmg.sha256|*.store|*.store-*|*.sqlite|*.sqlite3|*.log|.env|.env.*|auth.json|credentials.json|*.p12|*.mobileprovision|ChatGPT\ Image*.png)
      echo "Forbidden file tracked by Git: $TRACKED_FILE" >&2
      FAILED=1
      ;;
  esac
done < <(git ls-files)

if git grep -nI -E 'sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' -- .; then
  echo "A possible secret was found in tracked files." >&2
  FAILED=1
fi

PRIVATE_USER_PATH="/Users/${USER:-$(/usr/bin/id -un)}/"
PRIVATE_WORKSPACE="$(cd "$ROOT_DIR/../.." && pwd)"
if git grep -nI -F "$PRIVATE_USER_PATH" -- . \
  || git grep -nI -F "$PRIVATE_WORKSPACE" -- .; then
  echo "A private absolute path was found." >&2
  FAILED=1
fi

if [[ "$FAILED" -ne 0 ]]; then
  exit 1
fi

if [[ "${1:-}" == "--test" ]]; then
  swift test --scratch-path "${TMPDIR:-/tmp}/booklens-publication-check"
fi

echo "Publication boundary: OK"
