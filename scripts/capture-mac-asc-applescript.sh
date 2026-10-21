#!/usr/bin/env bash
# Mac App Store screenshots via System Events + screencapture (not XCUITest).
# Signs out of any local session, then signs in as the agent test account
# (agent-creds.txt). Refuses to write PNGs until Kitchen is visible.
# Usage: scripts/capture-mac-asc-applescript.sh [path/to/creds]
# See docs/agent-test-account.md — do not use App Review creds.txt here.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -ge 1 ]]; then
  CREDS="$1"
else
  CREDS="$ROOT/agent-creds.txt"
fi
OUT="${SCREENSHOT_DIR:-$ROOT/docs/app-store-screenshots/macos}"
APP="${DAYRULE_APP:-}"
WINID_BIN=/tmp/dayrule-winid

if [[ ! -f "$CREDS" ]]; then
  echo "missing creds file: $CREDS" >&2
  exit 1
fi
EMAIL="$(grep -v '^[[:space:]]*$' "$CREDS" | grep -v '^#' | sed -n '1p')"
PASSWORD="$(grep -v '^[[:space:]]*$' "$CREDS" | grep -v '^#' | sed -n '2p')"
if [[ -z "$EMAIL" || -z "$PASSWORD" ]]; then
  echo "creds file needs email then password" >&2
  exit 1
fi
echo "Mac ASC capture as ${EMAIL}"

if [[ -z "$APP" ]]; then
  APP="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/Dayrule-*/Build/Products/Debug/Dayrule.app 2>/dev/null | head -1 || true)"
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "Dayrule.app not found — build Debug for macOS first" >&2
  exit 1
fi

# Helper: CGWindowID for layer-0 Dayrule window
if [[ ! -x "$WINID_BIN" ]]; then
  cat > /tmp/dayrule-winid.swift <<'SWIFT'
import Cocoa
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
  fputs("no window list\n", stderr); exit(1)
}
for w in info {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let layer = w[kCGWindowLayer as String] as? Int ?? -1
  if owner == "Dayrule", layer == 0 {
    print(w[kCGWindowNumber as String] as? Int ?? 0)
    exit(0)
  }
}
exit(2)
SWIFT
  swiftc /tmp/dayrule-winid.swift -o "$WINID_BIN" -framework Cocoa
fi

mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -name '*.png' -delete 2>/dev/null || true

if [[ "$EMAIL" == *appreview* ]]; then
  echo "refusing App Review mailbox — use agent-creds.txt" >&2
  exit 1
fi

killall Dayrule 2>/dev/null || true
sleep 1
open "$APP"
sleep 3

osascript <<'EOF'
tell application "Dayrule" to activate
delay 0.8
EOF

# Lock to the password gate (⇧⌘L). Escape any open sheet first.
osascript <<'EOF' || true
tell application "Dayrule" to activate
delay 0.3
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    key code 53 -- escape
    delay 0.3
    key code 53
    delay 0.3
    keystroke "l" using {command down, shift down}
  end tell
end tell
EOF

# Wait until the Debug gate's three text fields exist (API / email / password).
echo "waiting for sign-in gate…"
GATE=0
for i in $(seq 1 30); do
  sleep 1
  COUNT="$(osascript <<'EOF' 2>/dev/null || echo 0
tell application "System Events"
  tell process "Dayrule"
    set ui to entire contents of window 1
    set n to 0
    repeat with e in ui
      try
        if (class of e as string) is "text field" then set n to n + 1
      end try
    end repeat
    return n
  end tell
end tell
EOF
)"
  COUNT="$(echo "$COUNT" | tr -d '[:space:]')"
  if [[ "$COUNT" =~ ^[0-9]+$ ]] && [[ "$COUNT" -ge 3 ]]; then
    GATE=1
    echo "gate ready ($COUNT fields)"
    break
  fi
  # Re-nudge lock if still on lists
  if (( i % 5 == 0 )); then
    osascript -e 'tell application "System Events" to tell process "Dayrule" to keystroke "l" using {command down, shift down}' 2>/dev/null || true
  fi
done
if [[ "$GATE" -ne 1 ]]; then
  echo "sign-in gate never appeared" >&2
  exit 1
fi

# Debug Mac gate: API + email + password are ordinary AX text fields.
# Clipboard/keystroke paste is unreliable on SwiftUI — set AX value instead.
echo "filling gate (production API + agent account)…"
python3 - "$EMAIL" "$PASSWORD" <<'PY'
import json, subprocess, sys
email, password = sys.argv[1], sys.argv[2]
api = "https://dayrule.app"

def run_as(script: str) -> str:
    r = subprocess.run(["osascript", "-e", script], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(r.stderr.strip() or r.stdout.strip() or "osascript failed")
    return r.stdout.strip()

run_as(
    """
tell application "Dayrule" to activate
delay 0.3
tell application "System Events" to tell process "Dayrule" to set frontmost to true
"""
)

def set_field(index: int, value: str) -> None:
    lit = json.dumps(value)
    run_as(
        f"""
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    set ui to entire contents of window 1
    set fields to {{}}
    repeat with e in ui
      try
        if (class of e as string) is "text field" then set end of fields to e
      end try
    end repeat
    if (count of fields) < {index} then error "expected field #{index}"
    set f to item {index} of fields
    set focused of f to true
    delay 0.1
    set value of f to {lit}
    delay 0.15
  end tell
end tell
"""
    )

set_field(1, api)
set_field(2, email)
set_field(3, password)

verify = run_as(
    """
tell application "System Events"
  tell process "Dayrule"
    set ui to entire contents of window 1
    set fields to {}
    repeat with e in ui
      try
        if (class of e as string) is "text field" then set end of fields to e
      end try
    end repeat
    return (value of item 1 of fields as string) & "|" & (value of item 2 of fields as string) & "|" & (length of (value of item 3 of fields as string) as string)
  end tell
end tell
"""
)
api_v, email_v, pass_len = verify.split("|", 2)
if "dayrule.app" not in api_v or email_v != email or int(pass_len) < 1:
    raise SystemExit(f"gate fill failed: api={api_v!r} email={email_v!r} pass_len={pass_len}")
print(f"gate ok api={api_v} email={email_v} pass_len={pass_len}")
PY
PASSWORD=""

osascript <<'EOF'
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    try
      set ui to entire contents of window 1
      repeat with e in ui
        try
          if (class of e as string) is "checkbox" then
            if (value of e as integer) is 0 then click e
            exit repeat
          end if
        end try
      end repeat
    end try
    delay 0.2
    -- Mac SwiftUI leaves Sign in untitled; the wide primary button is Sign in.
    set ui to entire contents of window 1
    set signed to false
    repeat with e in ui
      try
        if (class of e as string) is "button" then
          set s to size of e
          if (item 1 of s) > 300 then
            click e
            set signed to true
            exit repeat
          end if
        end if
      end try
    end repeat
    if signed is false then error "Sign in button not found"
  end tell
end tell
EOF

echo "waiting for agent vault (Kitchen)…"
READY=0
for i in $(seq 1 90); do
  sleep 2
  HIT="$(osascript <<'EOF' 2>/dev/null || true
tell application "System Events"
  tell process "Dayrule"
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if ((class of e as string) is "static text") and (name of e is "Kitchen") then
          return "yes"
        end if
      end try
    end repeat
    repeat with e in ui
      try
        if (class of e as string) is "static text" then
          set nm to name of e as string
          if nm contains "wrong" or nm contains "Could" or nm contains "network" or nm contains "Invalid" or nm contains "try again" then
            return "err:" & nm
          end if
        end if
      end try
    end repeat
    return "no"
  end tell
end tell
EOF
)"
  if [[ "$HIT" == "yes" ]]; then
    READY=1
    break
  fi
  if [[ "$HIT" == err:* ]]; then
    echo "$HIT" >&2
    break
  fi
  if (( i % 5 == 0 )); then
    echo "  …still unlocking ($i)"
  fi
done

if [[ "$READY" -ne 1 ]]; then
  echo "agent vault (Kitchen) never appeared — refusing to capture" >&2
  killall Dayrule 2>/dev/null || true
  exit 1
fi
echo "agent vault visible (Kitchen)"

shot() {
  local name="$1"
  sleep 0.7
  local wid
  wid="$("$WINID_BIN")"
  screencapture -l "$wid" "$OUT/$name.png"
  echo "wrote $name.png"
}

click_sidebar() {
  local label="$1"
  osascript <<EOF
tell application "Dayrule" to activate
delay 0.2
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if ((class of e as string) is "static text") and (name of e is "$label") then
          set p to position of e
          set s to size of e
          set x to (item 1 of p) + (item 1 of s) / 2
          set y to (item 2 of p) + (item 2 of s) / 2
          click at {x, y}
          delay 1.0
          return
        end if
      end try
    end repeat
    error "sidebar label not found: $label"
  end tell
end tell
EOF
}

click_sidebar "Today"
shot "01-today"
click_sidebar "Inbox"
shot "02-inbox"
click_sidebar "Scheduled"
shot "03-scheduled"
click_sidebar "Backlog"
shot "04-backlog"

# Kitchen project then Paint todo / editor if possible
osascript <<'EOF'
tell application "Dayrule" to activate
delay 0.2
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if ((class of e as string) is "static text") and (name of e is "Kitchen") then
          set p to position of e
          set s to size of e
          click at {(item 1 of p) + (item 1 of s) / 2, (item 2 of p) + (item 2 of s) / 2}
          delay 1.2
          exit repeat
        end if
      end try
    end repeat
  end tell
end tell
EOF
shot "05-project-kitchen"

osascript <<'EOF' || true
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if ((class of e as string) is "static text") and (name of e is "Paint the cupboards") then
          set p to position of e
          set s to size of e
          click at {(item 1 of p) + (item 1 of s) / 2, (item 2 of p) + (item 2 of s) / 2}
          delay 1.2
          exit repeat
        end if
      end try
    end repeat
  end tell
end tell
EOF
shot "06-editor-checklist"

# Leave the gate so the user's personal session isn't left open mid-automation;
# they can sign back in as themselves.
osascript <<'EOF' || true
tell application "System Events"
  tell process "Dayrule"
    keystroke "l" using {command down, shift down}
  end tell
end tell
EOF

n="$(find "$OUT" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')"
echo "wrote $n pngs in $OUT (agent account only)"
if [[ "$n" -lt 6 ]]; then
  echo "expected 6 screenshots" >&2
  exit 1
fi
