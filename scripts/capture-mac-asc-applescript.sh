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
CLICK_BIN=/tmp/dayrule-click

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

# SwiftUI sidebar rows often ignore System Events `click at`; HID does not.
if [[ ! -x "$CLICK_BIN" ]]; then
  cat > /tmp/dayrule-click.swift <<'SWIFT'
import Cocoa
let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
  fputs("usage: click x y\n", stderr); exit(1)
}
let pt = CGPoint(x: x, y: y)
let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)
let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)
down?.post(tap: .cghidEventTap)
usleep(40000)
up?.post(tap: .cghidEventTap)
SWIFT
  swiftc /tmp/dayrule-click.swift -o "$CLICK_BIN" -framework Cocoa
fi

mkdir -p "$OUT"

activate_dayrule() {
  osascript <<'EOF'
tell application "System Events"
  if not (exists process "Dayrule") then error "Dayrule process missing"
  set frontmost of process "Dayrule" to true
end tell
EOF
}

wait_for_process() {
  local i
  for i in $(seq 1 20); do
    if pgrep -x Dayrule >/dev/null 2>&1; then
      activate_dayrule 2>/dev/null && return 0
    fi
    sleep 0.5
  done
  echo "Dayrule process never became frontmost" >&2
  return 1
}

if [[ "$EMAIL" == *appreview* ]]; then
  echo "refusing App Review mailbox — use agent-creds.txt" >&2
  exit 1
fi

killall Dayrule 2>/dev/null || true
for i in $(seq 1 20); do
  pgrep -x Dayrule >/dev/null 2>&1 || break
  sleep 0.25
done
if pgrep -x Dayrule >/dev/null 2>&1; then
  echo "Dayrule still running after killall — retrying SIGKILL" >&2
  killall -9 Dayrule 2>/dev/null || true
  sleep 1
fi
open "$APP"
wait_for_process
# Wait until the layer-0 window exists (Launch Services can return before it does).
for i in $(seq 1 20); do
  if [[ -x "$WINID_BIN" ]] && "$WINID_BIN" >/dev/null 2>&1; then
    break
  fi
  sleep 0.4
done
sleep 1

# Lock to the password gate (⇧⌘L). Escape any open sheet first.
# Do not `tell application "Dayrule"` — SwiftUI often times out AppleEvents.
osascript <<'EOF' || true
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

# Wait for the sign-in form. Advanced options (API field) stay collapsed, so
# the usual gate is email + password (2 fields), not 3.
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
  if [[ "$COUNT" =~ ^[0-9]+$ ]] && [[ "$COUNT" -ge 2 ]]; then
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

# Gate fields are AX text fields. Advanced (API) is collapsed, so usually
# email + password. Overwrite email with the agent account so a personal
# vault is never unlocked. Clipboard paste is unreliable on SwiftUI.
echo "filling gate (agent account)…"
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
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
  end tell
end tell
"""
)

def field_count() -> int:
    n = run_as(
        """
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
"""
    )
    return int(n)

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

def field_values():
    raw = run_as(
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
    set bits to {}
    repeat with f in fields
      set end of bits to (value of f as string)
    end repeat
    set AppleScript's text item delimiters to linefeed
    return bits as string
  end tell
end tell
"""
    )
    return raw.splitlines()

n = field_count()
if n >= 3:
    set_field(1, api)
    set_field(2, email)
    set_field(3, password)
elif n == 2:
    set_field(1, email)
    set_field(2, password)
else:
    raise SystemExit(f"unexpected gate field count: {n}")

vals = field_values()
email_v = vals[-2] if len(vals) >= 2 else ""
pass_len = len(vals[-1]) if vals else 0
if email_v != email or pass_len < 1:
    raise SystemExit("gate fill failed: email mismatch or empty password")
print(f"gate ok fields={len(vals)} email={email_v} pass_len={pass_len}")
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

# Project rows are omitted from the AX tree. Trash is the last built-in
# list and is exposed; after unlock, HID-click below it and require the
# window title Kitchen so a personal vault is never captured.
echo "waiting for lists chrome (Trash)…"
READY=0
for i in $(seq 1 90); do
  sleep 2
  HIT="$(osascript <<'EOF' 2>/dev/null || true
tell application "System Events"
  tell process "Dayrule"
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if ((class of e as string) is "static text") then
          set nm to name of e as string
          if nm is "Trash" then return "yes"
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
  echo "lists chrome never appeared — refusing to capture" >&2
  killall Dayrule 2>/dev/null || true
  exit 1
fi
echo "lists chrome visible"

shot() {
  local name="$1"
  sleep 0.7
  local wid
  wid="$("$WINID_BIN")"
  screencapture -l "$wid" "$OUT/$name.png"
  echo "wrote $name.png"
}

label_center() {
  local label="$1"
  osascript <<EOF
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if ((class of e as string) is "static text") and (name of e is "$label") then
          set p to position of e
          set s to size of e
          return ((item 1 of p) + (item 1 of s) / 2 as integer as text) & "," & ((item 2 of p) + (item 2 of s) / 2 as integer as text)
        end if
      end try
    end repeat
    error "label not found: $label"
  end tell
end tell
EOF
}

hid_click() {
  local x="$1" y="$2"
  activate_dayrule 2>/dev/null || true
  "$CLICK_BIN" "$x" "$y"
  sleep 0.85
}

click_sidebar() {
  local label="$1"
  local xy x y
  xy="$(label_center "$label")"
  x="${xy%,*}"
  y="${xy#*,}"
  # Hit the icon column — label center alone often misses SwiftUI rows.
  hid_click $((x - 40)) "$y"
}

click_kitchen() {
  local xy x y
  xy="$(label_center "Trash")"
  x="${xy%,*}"; y="${xy#*,}"
  hid_click $((x - 20)) $((y + 56))
}

window_name() {
  osascript -e 'tell application "System Events" to tell process "Dayrule" to name of window 1 as string' 2>/dev/null || true
}

# Project rows aren't in AX. Opening the first project under Trash and
# requiring the title Kitchen is how we refuse a personal vault.
echo "probing Kitchen via HID…"
KITCHEN_OK=0
for i in $(seq 1 20); do
  click_kitchen
  if [[ "$(window_name)" == "Kitchen" ]]; then
    KITCHEN_OK=1
    echo "agent vault visible (Kitchen)"
    break
  fi
  sleep 1
done
if [[ "$KITCHEN_OK" -ne 1 ]]; then
  echo "Kitchen project never opened — refusing to capture" >&2
  killall Dayrule 2>/dev/null || true
  exit 1
fi

find "$OUT" -maxdepth 1 -name '*.png' -delete 2>/dev/null || true

click_sidebar "Today"
shot "01-today"
click_sidebar "Inbox"
shot "02-inbox"
click_sidebar "Scheduled"
shot "03-scheduled"
click_sidebar "Backlog"
shot "04-backlog"

click_kitchen
# Blur the editable page title so the shot isn't a rename field.
osascript -e 'tell application "System Events" to tell process "Dayrule" to key code 53' 2>/dev/null || true
sleep 0.3
shot "05-project-kitchen"

# Paint the cupboards may be missing from AX; click the first todo row.
if xy="$(label_center "Paint the cupboards" 2>/dev/null)"; then
  x="${xy%,*}"; y="${xy#*,}"
  hid_click "$x" "$y"
else
  ix="$(label_center "Inbox")"
  hid_click $((${ix%,*} + 340)) $((${ix#*,} + 110))
fi
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
