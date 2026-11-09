#!/bin/sh
# Run native Sync e2e against a local Go API (PLAN §14.2).
# Requires: sibling dayrule checkout, Docker Postgres on 55432 (or E2E_DATABASE_URL),
# Xcode, and xcodegen. Starts serve-api.sh if nothing answers on :8080.
#
# Steps:
#  1) SyncE2ETests on macOS (push + plaintext-check + second-device pull)
#  2) SyncUITests on iOS Simulator (Gate signup → Add)
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
export DAYRULE_HIBP_STUB=1
mkdir -p "$DAYRULE_E2E_OUT"

API_PID=""
STARTED_API=0
api_reachable() {
  code=$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 1 "$DAYRULE_API/" 2>/dev/null || true)
  case "$code" in
    ''|000) return 1 ;;
    *) return 0 ;;
  esac
}

cleanup() {
  if [ "$STARTED_API" = 1 ] && [ -n "${API_PID}" ] && kill -0 "$API_PID" 2>/dev/null; then
    kill "$API_PID" 2>/dev/null || true
    wait "$API_PID" 2>/dev/null || true
  fi
  rm -f /tmp/dayrule-e2e-config.json
}
trap cleanup EXIT

if ! api_reachable; then
  echo "starting local API via web/e2e/serve-api.sh …"
  # nohup: xcodebuild / parent shell must not SIGHUP the API (macOS has no setsid).
  nohup env E2E_DATABASE_URL="$E2E_DATABASE_URL" \
    /bin/sh -c "cd \"$WEB_ROOT/web\" && exec ./e2e/serve-api.sh" \
    >>"$DAYRULE_E2E_OUT/serve-api.nohup.log" 2>&1 &
  API_PID=$!
  echo "$API_PID" >"$DAYRULE_E2E_OUT/api.pid"
  STARTED_API=1
  ready=0
  for i in $(seq 1 120); do
    if api_reachable; then
      ready=1
      break
    fi
    if ! kill -0 "$API_PID" 2>/dev/null; then
      echo "API exited early; last log lines:" >&2
      tail -n 40 "$DAYRULE_E2E_OUT/api.log" 2>/dev/null || true
      tail -n 40 "$DAYRULE_E2E_OUT/serve-api.nohup.log" 2>/dev/null || true
      exit 1
    fi
    sleep 1
  done
  if [ "$ready" != 1 ]; then
    echo "API failed to become ready on $DAYRULE_API" >&2
    tail -n 40 "$DAYRULE_E2E_OUT/api.log" 2>/dev/null || true
    exit 1
  fi
else
  # Reuse an already-running local API; do not kill it on exit.
  API_PID=$(cat "$DAYRULE_E2E_OUT/api.pid" 2>/dev/null || true)
fi

cd "$ROOT"
command -v xcodegen >/dev/null && xcodegen generate

INVITE=$(DATABASE_URL_UNPOOLED="$E2E_DATABASE_URL" "$DAYRULE_E2E_OUT/invite" 1 | tr -d '[:space:]')
if [ -z "$INVITE" ]; then
  echo "failed to mint invite code" >&2
  exit 1
fi
export INVITE

python3 - <<'PY'
import json, os
with open("/tmp/dayrule-e2e-config.json", "w", encoding="utf-8") as f:
    json.dump({
        "enabled": "1",
        "api": os.environ["DAYRULE_API"],
        "web": os.environ["DAYRULE_WEB"],
        "out": os.environ["DAYRULE_E2E_OUT"],
        "database": os.environ["E2E_DATABASE_URL"],
        "invite": os.environ["INVITE"],
    }, f)
print("wrote /tmp/dayrule-e2e-config.json")
PY
echo "==> SyncE2ETests (macOS)"
xcodebuild test \
  -project Dayrule.xcodeproj \
  -scheme Dayrule \
  -destination 'platform=macOS' \
  -only-testing:DayruleTests/SyncE2ETests \
  CODE_SIGNING_ALLOWED=NO

DEST=$(xcrun simctl list devices available -j | python3 -c "
import json,sys,re
devices=json.load(sys.stdin)['devices']
candidates=[]
for runtime,devs in devices.items():
  m=re.search(r'iOS[^\d]*(\d+)', runtime)
  if not m or int(m.group(1)) < 18: continue
  for d in devs:
    if d.get('isAvailable') and 'iPhone' in d['name']:
      score = 0
      if 'iPhone 16' in d['name']: score += 10
      if 'Pro' in d['name']: score += 1
      candidates.append((score, d['udid'], d['name']))
if not candidates:
  raise SystemExit('no iPhone simulator on iOS 18+')
candidates.sort(reverse=True)
print(f'platform=iOS Simulator,id={candidates[0][1]}')
")

# Mint a fresh invite for the UI test (register consumes the previous one).
INVITE=$(DATABASE_URL_UNPOOLED="$E2E_DATABASE_URL" "$DAYRULE_E2E_OUT/invite" 1 | tr -d '[:space:]')
export INVITE
python3 - <<'PY'
import json, os
with open("/tmp/dayrule-e2e-config.json", "w", encoding="utf-8") as f:
    json.dump({
        "enabled": "1",
        "api": os.environ["DAYRULE_API"],
        "web": os.environ["DAYRULE_WEB"],
        "out": os.environ["DAYRULE_E2E_OUT"],
        "database": os.environ["E2E_DATABASE_URL"],
        "invite": os.environ["INVITE"],
    }, f)
PY

echo "==> SyncUITests ($DEST)"
# Allow time for Argon2id during create-account (64 MiB × 3).
xcodebuild test \
  -project Dayrule.xcodeproj \
  -scheme Dayrule \
  -destination "$DEST" \
  -only-testing:DayruleUITests/SyncUITests \
  -test-timeouts-enabled YES \
  CODE_SIGNING_ALLOWED=NO
