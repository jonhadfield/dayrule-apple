#!/usr/bin/env bash
# Mirror dayrule shared fixtures at a pinned SHA.
# Usage: scripts/sync-shared.sh <web-repo-sha> [path-to-dayrule-repo]
set -euo pipefail

SHA="${1:?web commit SHA required}"
WEB_REPO="${2:-$HOME/Repositories/dayrule}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/docs/shared"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ ! -d "$WEB_REPO/.git" ]]; then
  echo "dayrule repo not found at $WEB_REPO" >&2
  exit 1
fi

mkdir -p "$TMP/out"
if git -C "$WEB_REPO" cat-file -e "$SHA:docs/shared" 2>/dev/null; then
  git -C "$WEB_REPO" archive "$SHA" docs/shared | tar -x -C "$TMP/out"
  rm -rf "$DEST"
  mv "$TMP/out/docs/shared" "$DEST"
else
  mkdir -p "$DEST"
  git -C "$WEB_REPO" show "$SHA:docs/crypto-vectors.json" >"$DEST/crypto-vectors.json"
fi

{
  echo "web_commit=$SHA"
  (
    cd "$DEST"
    find . -type f ! -name 'SHARED.lock' -print | sed 's|^\./||' | sort | while read -r rel; do
      hash="$(shasum -a 256 "$rel" | awk '{print $1}')"
      printf '%s  %s\n' "$hash" "$rel"
    done
  )
} >"$DEST/SHARED.lock"

echo "Mirrored shared fixtures from $SHA → $DEST"
cat "$DEST/SHARED.lock"
