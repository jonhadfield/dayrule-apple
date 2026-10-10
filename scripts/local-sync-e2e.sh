#!/bin/sh
# Run native Sync e2e against a local Go API (PLAN §14.2).
# Requires: sibling dayrule checkout, Docker Postgres on 55432 (or E2E_DATABASE_URL),
# Xcode, and xcodegen. Starts serve-api.sh if nothing answers on :8080.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WEB_ROOT="${DAYRULE_WEB:-$(cd "$ROOT/../dayrule" 2>/dev/null && pwd || true)}"
if [ -z "${WEB_ROOT:-}" ] || [ ! -d "$WEB_ROOT/web/e2e" ]; then
  echo "set DAYRULE_WEB to the dayrule repo root (expected sibling ../dayrule)" >&2
  exit 1
fi

export E2E_DATABASE_URL="${E2E_DATABASE_URL:-postgres://postgres:test@127.0.0.1:55432/dayrule_test?sslmode=disable}"
export DAYRULE_API="${DAYRULE_API:-http://127.0.0.1:8080}"
export DAYRULE_WEB="$WEB_ROOT"
export DAYRULE_E2E_OUT="${DAYRULE_E2E_OUT:-$WEB_ROOT/web/e2e/.out}"
export DAYRULE_E2E=1

API_PID=""
cleanup() {
  if [ -n "${API_PID}" ] && kill -0 "$API_PID" 2>/dev/null; then
    kill "$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if ! curl -sf -o /dev/null "$DAYRULE_API/api/v1/sync/head" 2>/dev/null; then
  # head requires auth; any HTTP response means the process is up.
  if ! curl -s -o /dev/null -w '' --connect-timeout 1 "$DAYRULE_API/" 2>/dev/null; then
    echo "starting local API via web/e2e/serve-api.sh …"
    (
      cd "$WEB_ROOT/web"
      exec ./e2e/serve-api.sh
    ) &
    API_PID=$!
    for i in $(seq 1 60); do
      if curl -s -o /dev/null -w '' --connect-timeout 1 "$DAYRULE_API/" 2>/dev/null; then
        break
      fi
      if ! kill -0 "$API_PID" 2>/dev/null; then
        echo "API exited early; last log lines:" >&2
        tail -n 40 "$DAYRULE_E2E_OUT/api.log" 2>/dev/null || true
        exit 1
      fi
      sleep 1
    done
  fi
fi

cd "$ROOT"
command -v xcodegen >/dev/null && xcodegen generate

# SyncE2ETests are macOS-only (Process for invite / plaintext-check).
# Config sidecar: xcodebuild does not reliably forward env into the test host.
CFG=/tmp/dayrule-e2e-config.json
export CFG
python3 - <<'PY'
import json, os
path = os.environ["CFG"]
with open(path, "w", encoding="utf-8") as f:
    json.dump({
        "enabled": "1",
        "api": os.environ["DAYRULE_API"],
        "web": os.environ["DAYRULE_WEB"],
        "out": os.environ["DAYRULE_E2E_OUT"],
        "database": os.environ["E2E_DATABASE_URL"],
    }, f)
print("wrote", path)
PY

cleanup_cfg() {
  rm -f "$CFG"
  cleanup
}
trap cleanup_cfg EXIT

xcodebuild test \
  -project Dayrule.xcodeproj \
  -scheme Dayrule \
  -destination 'platform=macOS' \
  -only-testing:DayruleTests/SyncE2ETests \
  CODE_SIGNING_ALLOWED=NO
