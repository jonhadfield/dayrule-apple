#!/usr/bin/env python3
"""Mac ASC screenshots for the agent test account only.

Uses System Events + HID clicks + screencapture. Project rows are not in the
AX tree — gate is selecting Kitchen via coordinates under Trash (seeded
agent vault). Never uses App Review creds.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CREDS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "agent-creds.txt"
OUT = Path(
    __import__("os").environ.get(
        "SCREENSHOT_DIR", str(ROOT / "docs/app-store-screenshots/macos")
    )
)
WINID = Path("/tmp/dayrule-winid")
CLICK = Path("/tmp/dayrule-click")
API = "https://dayrule.app"


def run_as(script: str) -> str:
    r = subprocess.run(
        ["osascript", "-e", script], capture_output=True, text=True
    )
    if r.returncode:
        raise RuntimeError(r.stderr.strip() or r.stdout.strip() or "osascript failed")
    return r.stdout.strip()


def sh(*args: str) -> None:
    subprocess.run(args, check=True)


def load_creds() -> tuple[str, str]:
    lines = [
        ln.strip()
        for ln in CREDS.read_text().splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    ]
    if len(lines) < 2:
        raise SystemExit(f"need email+password in {CREDS}")
    email, password = lines[0], lines[1]
    if "appreview" in email.lower():
        raise SystemExit("refusing App Review mailbox")
    return email, password


def find_app() -> Path:
    import glob

    matches = sorted(
        glob.glob(
            str(
                Path.home()
                / "Library/Developer/Xcode/DerivedData/Dayrule-*/Build/Products/Debug/Dayrule.app"
            )
        )
    )
    if not matches:
        raise SystemExit("Dayrule.app Debug not found")
    return Path(matches[0])


def ensure_helpers() -> None:
    """CGWindowID + HID click (System Events `click at` misses SwiftUI sidebar rows)."""
    if not (WINID.exists() and WINID.stat().st_mode & 0o111):
        src = Path("/tmp/dayrule-winid.swift")
        src.write_text(
            """
import Cocoa
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let info = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in info {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let layer = w[kCGWindowLayer as String] as? Int ?? -1
  if owner == "Dayrule", layer == 0 {
    print(w[kCGWindowNumber as String] as? Int ?? 0)
    exit(0)
  }
}
exit(2)
"""
        )
        sh("swiftc", str(src), "-o", str(WINID), "-framework", "Cocoa")
    if not (CLICK.exists() and CLICK.stat().st_mode & 0o111):
        src = Path("/tmp/dayrule-click.swift")
        src.write_text(
            """
import Cocoa
let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
  fputs("usage: click x y\\n", stderr); exit(1)
}
let pt = CGPoint(x: x, y: y)
let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)
let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)
down?.post(tap: .cghidEventTap)
usleep(40000)
up?.post(tap: .cghidEventTap)
"""
        )
        sh("swiftc", str(src), "-o", str(CLICK), "-framework", "Cocoa")


def hid_click(x: float, y: float) -> None:
    run_as('tell application "Dayrule" to activate\ndelay 0.15')
    sh(str(CLICK), str(int(x)), str(int(y)))
    time.sleep(0.85)


def window_probe() -> tuple[int, str, int]:
    """Return (window_count, front_name, text_field_count)."""
    out = run_as(
        """
tell application "System Events"
  if not (exists process "Dayrule") then return "0|none|0"
  tell process "Dayrule"
    set wc to count of windows
    if wc < 1 then return "0|none|0"
    set nm to name of window 1 as string
    set n to 0
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if (class of e as string) is "text field" then set n to n + 1
      end try
    end repeat
    return (wc as string) & "|" & nm & "|" & (n as string)
  end tell
end tell
"""
    )
    parts = out.split("|", 2)
    return int(parts[0]), parts[1], int(parts[2])


def has_static(label: str) -> bool:
    lit = json.dumps(label)
    try:
        return (
            run_as(
                f"""
tell application "System Events"
  tell process "Dayrule"
    if (count of windows) < 1 then return "no"
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if ((class of e as string) is "static text") and (name of e is {lit}) then return "yes"
      end try
    end repeat
    return "no"
  end tell
end tell
"""
            )
            == "yes"
        )
    except RuntimeError:
        return False


def gate_error() -> str | None:
    out = run_as(
        """
tell application "System Events"
  tell process "Dayrule"
    if (count of windows) < 1 then return ""
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if (class of e as string) is "static text" then
          set nm to name of e as string
          if nm contains "wrong" or nm contains "Could" or nm contains "Invalid" or nm contains "network" or nm contains "try again" then return nm
        end if
      end try
    end repeat
    return ""
  end tell
end tell
"""
    )
    return out or None


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
    if (count of fields) < {index} then error "expected field {index}, have " & (count of fields)
    set f to item {index} of fields
    set focused of f to true
    delay 0.1
    set value of f to {lit}
    delay 0.15
  end tell
end tell
"""
    )


def static_center(label: str) -> tuple[int, int]:
    lit = json.dumps(label)
    out = run_as(
        f"""
tell application "System Events"
  tell process "Dayrule"
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if ((class of e as string) is "static text") and (name of e is {lit}) then
          set p to position of e
          set s to size of e
          return ((item 1 of p) + (item 1 of s) / 2 as integer as text) & "," & ((item 2 of p) + (item 2 of s) / 2 as integer as text)
        end if
      end try
    end repeat
    error "missing " & {lit}
  end tell
end tell
"""
    )
    x, y = out.split(",", 1)
    return int(x), int(y)


def click_static(label: str) -> None:
    """Select a sidebar list. Hit the icon column — label center alone often misses."""
    x, y = static_center(label)
    hid_click(x - 40, y)


def click_signin() -> None:
    """Click Stay unlocked (if needed) then the wide Sign in button."""
    run_as(
        """
tell application "Dayrule" to activate
delay 0.2
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if (class of e as string) is "checkbox" then
          if (value of e as integer) is 0 then
            set p to position of e
            set s to size of e
            click at {(item 1 of p) + (item 1 of s) / 2, (item 2 of p) + (item 2 of s) / 2}
          end if
          exit repeat
        end if
      end try
    end repeat
    delay 0.3
    set ui to entire contents of window 1
    repeat with e in ui
      try
        if (class of e as string) is "button" then
          set desc to ""
          try
            set desc to description of e as string
          end try
          if desc is "close button" or desc is "minimize button" or desc is "full screen button" then
            -- skip chrome
          else
            set s to size of e
            set w to (item 1 of s) as integer
            if w > 300 then
              set p to position of e
              click at {(item 1 of p) + w / 2, (item 2 of p) + ((item 2 of s) as integer) / 2}
              return
            end if
          end if
        end if
      end try
    end repeat
    error "Sign in button not found"
  end tell
end tell
"""
    )


def shot(name: str) -> None:
    time.sleep(0.6)
    wid = subprocess.check_output([str(WINID)], text=True).strip()
    path = OUT / f"{name}.png"
    sh("screencapture", "-l", wid, str(path))
    if path.stat().st_size < 50_000:
        raise SystemExit(f"screenshot too small: {path}")
    print(f"wrote {path.name} ({path.stat().st_size} bytes)")


def main() -> None:
    email, password = load_creds()
    print(f"Mac agent capture as {email}")
    ensure_helpers()
    OUT.mkdir(parents=True, exist_ok=True)
    for p in OUT.glob("*.png"):
        p.unlink()

    subprocess.run(["killall", "Dayrule"], check=False, capture_output=True)
    time.sleep(1)
    app = find_app()
    sh("open", str(app))

    print("waiting for window…")
    for i in range(40):
        time.sleep(1)
        try:
            wc, name, _ = window_probe()
        except RuntimeError:
            continue
        if wc >= 1:
            print(f"window ready ({name})")
            break
    else:
        raise SystemExit("no Dayrule window")

    run_as(
        """
tell application "Dayrule" to activate
delay 0.5
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    key code 53
    delay 0.2
    keystroke "l" using {command down, shift down}
  end tell
end tell
"""
    )

    print("waiting for gate…")
    for i in range(40):
        time.sleep(1)
        try:
            _, name, fields = window_probe()
        except RuntimeError:
            continue
        print(f"  gate t={i+1} win={name!r} fields={fields}")
        if fields >= 3:
            break
        if (i + 1) % 5 == 0:
            try:
                run_as(
                    'tell application "System Events" to tell process "Dayrule" to keystroke "l" using {command down, shift down}'
                )
            except RuntimeError:
                pass
    else:
        raise SystemExit("sign-in gate never appeared")

    print("filling gate…")
    set_field(1, API)
    set_field(2, email)
    set_field(3, password)
    # verify without printing password
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
    if "dayrule.app" not in api_v or email_v != email or int(pass_len) < 12:
        raise SystemExit(f"gate fill failed: api={api_v!r} email={email_v!r} pass_len={pass_len}")
    print(f"gate ok api={api_v} email={email_v} pass_len={pass_len}")

    click_signin()
    print("waiting for lists + Kitchen (AX omits project labels)…")
    kitchen_ok = False
    for i in range(90):
        time.sleep(2)
        err = None
        try:
            err = gate_error()
        except RuntimeError:
            pass
        if err:
            raise SystemExit(f"sign-in error: {err}")
        try:
            _, name, _ = window_probe()
        except RuntimeError:
            name = "?"
        if has_static("Trash"):
            tx, ty = static_center("Trash")
            hid_click(tx - 20, ty + 56)
            time.sleep(0.3)
            try:
                _, name, _ = window_probe()
            except RuntimeError:
                pass
            if name == "Kitchen":
                print("agent vault visible (Kitchen)")
                kitchen_ok = True
                break
        if (i + 1) % 5 == 0:
            print(f"  …{i+1} win={name!r}")
    if not kitchen_ok:
        raise SystemExit(
            "Kitchen never appeared — seed the agent account before capturing"
        )

    click_static("Today")
    shot("01-today")
    click_static("Inbox")
    shot("02-inbox")
    click_static("Scheduled")
    shot("03-scheduled")
    click_static("Backlog")
    shot("04-backlog")
    tx, ty = static_center("Trash")
    hid_click(tx - 20, ty + 56)
    time.sleep(0.3)
    if window_probe()[1] != "Kitchen":
        hid_click(tx - 20, ty + 72)
    shot("05-project-kitchen")
    # First project todo — not exposed as AX static text
    ix, iy = static_center("Inbox")
    hid_click(ix + 340, iy + 110)
    shot("06-editor-checklist")

    try:
        run_as(
            'tell application "System Events" to tell process "Dayrule" to keystroke "l" using {command down, shift down}'
        )
    except RuntimeError:
        pass

    n = len(list(OUT.glob("*.png")))
    print(f"wrote {n} pngs in {OUT} (agent account only)")
    if n < 6:
        raise SystemExit("expected 6 screenshots")


if __name__ == "__main__":
    main()
