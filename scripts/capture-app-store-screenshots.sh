#!/usr/bin/env bash
# Capture App Store screenshots (demo account → production API).
# Usage: scripts/capture-app-store-screenshots.sh [path/to/creds.txt]
# Env:   CAPTURE=iphone|ipad|macos|all  (default: all)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CREDS="${1:-$ROOT/creds.txt}"
OUT="${SCREENSHOT_DIR:-$ROOT/docs/app-store-screenshots}"
CAPTURE="${CAPTURE:-all}"
mkdir -p "$OUT/iphone" "$OUT/ipad" "$OUT/macos"
CFG=/tmp/dayrule-asc-capture.json

if [[ ! -f "$CREDS" ]]; then
  echo "missing creds file: $CREDS (email then password, one per line)" >&2
  exit 1
fi
EMAIL="$(grep -v '^[[:space:]]*$' "$CREDS" | sed -n '1p')"
PASSWORD="$(grep -v '^[[:space:]]*$' "$CREDS" | sed -n '2p')"
echo "capturing as ${EMAIL} (CAPTURE=$CAPTURE)"

write_cfg() {
  local dir="$1"
  python3 - "$CFG" "$EMAIL" "$PASSWORD" "$dir" <<'PY'
import json, sys
path, email, password, out = sys.argv[1:5]
with open(path, "w") as f:
    json.dump({"email": email, "password": password, "outDir": out}, f)
PY
  chmod 600 "$CFG"
}

IPHONE_DEST='platform=iOS Simulator,name=iPhone 16 Pro,OS=18.0'
IPAD_DEST='platform=iOS Simulator,name=iPad Pro 13-inch (M4),OS=18.0'
MAC_DEST='platform=macOS'

run() {
  local dest="$1" subdir="$2"
  local dir="$OUT/$subdir"
  mkdir -p "$dir"
  rm -f "$dir"/*.png
  write_cfg "$dir"
  echo "→ $subdir ($dest)"
  xcodebuild \
    -project "$ROOT/Dayrule.xcodeproj" \
    -scheme Dayrule \
    -destination "$dest" \
    -only-testing:DayruleUITests/AppStoreScreenshotTests/testCaptureScreenshots \
    test
  local n
  n="$(ls -1 "$dir"/*.png 2>/dev/null | wc -l | tr -d ' ')"
  echo "wrote $n pngs in $dir"
  if [[ "$n" -lt 1 ]]; then
    echo "no screenshots produced" >&2
    exit 1
  fi
}

want() {
  [[ "$CAPTURE" == "all" || "$CAPTURE" == "$1" ]]
}

want iphone && run "$IPHONE_DEST" iphone
want ipad && run "$IPAD_DEST" ipad
want macos && run "$MAC_DEST" macos

# iPad capture runs in landscape so NavigationSplitView is side-by-side (portrait
# overlays the sidebar on the list). XCUIScreen still writes a portrait buffer —
# rotate to ASC 13″ landscape size 2752×2064.
if want ipad; then
  for f in "$OUT"/ipad/*.png; do
    [[ -f "$f" ]] || continue
    w="$(sips -g pixelWidth "$f" 2>/dev/null | awk '/pixelWidth/ {print $2}')"
    h="$(sips -g pixelHeight "$f" 2>/dev/null | awk '/pixelHeight/ {print $2}')"
    if [[ "$w" -lt "$h" ]]; then
      sips -r 270 "$f" --out "$f" >/dev/null
    fi
  done
fi

rm -f "$CFG"

echo "Done. Upload from $OUT"
shopt -s nullglob
sips -g pixelWidth -g pixelHeight \
  "$OUT"/iphone/*.png "$OUT"/ipad/*.png "$OUT"/macos/*.png 2>/dev/null | paste - - -
