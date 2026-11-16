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
RCLICK = Path("/tmp/dayrule-rclick")
AXFOCUS = Path("/tmp/dayrule-axfocus")
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
    import os

    override = os.environ.get("DAYRULE_APP")
    if override:
        p = Path(override)
        if not p.is_dir():
            raise SystemExit(f"DAYRULE_APP not found: {p}")
        return p

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
    # Prefer newest mtime — multiple DerivedData folders may exist.
    return Path(max(matches, key=lambda m: Path(m).stat().st_mtime))


def ensure_helpers() -> None:
    """CGWindowID + HID click + AX focus-by-identifier."""
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
    if not (RCLICK.exists() and RCLICK.stat().st_mode & 0o111):
        src = Path("/tmp/dayrule-rclick.swift")
        src.write_text(
            """
import Cocoa
let args = CommandLine.arguments
guard args.count >= 3, let x = Double(args[1]), let y = Double(args[2]) else {
  fputs("usage: rclick x y\\n", stderr); exit(1)
}
let pt = CGPoint(x: x, y: y)
let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: pt, mouseButton: .right)
let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: pt, mouseButton: .right)
down?.post(tap: .cghidEventTap)
usleep(40000)
up?.post(tap: .cghidEventTap)
"""
        )
        sh("swiftc", str(src), "-o", str(RCLICK), "-framework", "Cocoa")
    if not (AXFOCUS.exists() and AXFOCUS.stat().st_mode & 0o111):
        src = Path("/tmp/dayrule-axfocus.swift")
        src.write_text(
            r"""
import ApplicationServices
import Cocoa
import Foundation

let args = CommandLine.arguments
guard args.count >= 2 else {
  fputs("usage: axfocus <AXIdentifier>\n", stderr); exit(1)
}
let want = args[1]
let trust = AXIsProcessTrustedWithOptions(
  [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
)
guard trust else { fputs("accessibility not trusted\n", stderr); exit(2) }

func children(_ el: AXUIElement) -> [AXUIElement] {
  var raw: CFTypeRef?
  guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &raw) == .success,
        let arr = raw as? [AXUIElement] else { return [] }
  return arr
}

func identifier(of el: AXUIElement) -> String? {
  var raw: CFTypeRef?
  // SwiftUI maps accessibilityIdentifier → AXIdentifier.
  if AXUIElementCopyAttributeValue(el, "AXIdentifier" as CFString, &raw) == .success,
     let s = raw as? String { return s }
  return nil
}

func find(_ root: AXUIElement, id: String, depth: Int = 0) -> AXUIElement? {
  if depth > 40 { return nil }
  if identifier(of: root) == id { return root }
  for c in children(root) {
    if let hit = find(c, id: id, depth: depth + 1) { return hit }
  }
  return nil
}

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "uk.co.lessknown.dayrule")
guard let app = apps.first else { fputs("Dayrule not running\n", stderr); exit(3) }
let appEl = AXUIElementCreateApplication(app.processIdentifier)
guard let target = find(appEl, id: want) else {
  fputs("missing \(want)\n", stderr); exit(4)
}
AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
// Also raise + press if it's a button-like control.
AXUIElementPerformAction(target, kAXPressAction as CFString)
exit(0)
"""
        )
        sh(
            "swiftc",
            str(src),
            "-o",
            str(AXFOCUS),
            "-framework",
            "Cocoa",
            "-framework",
            "ApplicationServices",
        )


def hid_click(x: float, y: float, settle: float = 0.35) -> None:
    run_as('tell application "Dayrule" to activate\ndelay 0.08')
    sh(str(CLICK), str(int(x)), str(int(y)))
    time.sleep(settle)


def hid_right_click(x: float, y: float, settle: float = 0.35) -> None:
    run_as('tell application "Dayrule" to activate\ndelay 0.08')
    sh(str(RCLICK), str(int(x)), str(int(y)))
    time.sleep(settle)


def window_probe(*, count_fields: bool = False) -> tuple[int, str, int]:
    """Return (window_count, front_name, field_count).

    Field counting walks the AX tree — only enable on the gate (empty vault).
    """
    if count_fields:
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
        set cls to class of e as string
        if cls is "text field" or cls is "secure text field" then set n to n + 1
      end try
    end repeat
    return (wc as string) & "|" & nm & "|" & (n as string)
  end tell
end tell
"""
        )
    else:
        out = run_as(
            """
tell application "System Events"
  if not (exists process "Dayrule") then return "0|none|0"
  tell process "Dayrule"
    set wc to count of windows
    if wc < 1 then return "0|none|0"
    set nm to name of window 1 as string
    return (wc as string) & "|" & nm & "|0"
  end tell
end tell
"""
        )
    parts = out.split("|", 2)
    return int(parts[0]), parts[1], int(parts[2])


def window_frame() -> tuple[int, int, int, int]:
    """Return (x, y, w, h) of window 1."""
    out = run_as(
        """
tell application "System Events"
  tell process "Dayrule"
    set p to position of window 1
    set s to size of window 1
    return ((item 1 of p) as integer as text) & "," & ((item 2 of p) as integer as text) & "," & ((item 1 of s) as integer as text) & "," & ((item 2 of s) as integer as text)
  end tell
end tell
"""
    )
    x, y, w, h = out.split(",")
    return int(x), int(y), int(w), int(h)


def dismiss_overlays() -> None:
    """Escape password autofill / other sheets that steal the AX tree."""
    try:
        run_as(
            """
tell application "Dayrule" to activate
delay 0.15
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    key code 53
    delay 0.2
    key code 53
  end tell
end tell
"""
        )
    except RuntimeError:
        pass


def expand_advanced() -> None:
    """Optional: DEBUG gate hides Server under Advanced.

    Skipped by default — production dayrule.app is already the unresolved
    default, and the Advanced control often has no AX name on macOS.
    """
    return


def has_static(label: str) -> bool:
    lit = json.dumps(label)
    try:
        return (
            run_as(
                f"""
tell application "System Events"
  tell process "Dayrule"
    if (count of windows) < 1 then return "no"
    tell window 1
      if (count of (static texts whose name is {lit})) > 0 then return "yes"
    end tell
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
    """Light check — never walk entire contents (hangs on large vaults)."""
    try:
        out = run_as(
            """
tell application "System Events"
  tell process "Dayrule"
    tell window 1
      set names to name of every static text
      repeat with nm in names
        set s to nm as string
        if s contains "wrong" or s contains "Could" or s contains "Invalid" or s contains "network" or s contains "try again" then return s
      end repeat
    end tell
    return ""
  end tell
end tell
"""
        )
        return out or None
    except RuntimeError:
        return None


def set_field(index: int, value: str) -> None:
    """Set the Nth text/secure field (1-based), in AX tree order."""
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
        set cls to class of e as string
        if cls is "text field" or cls is "secure text field" then set end of fields to e
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
    """Prefer direct `static texts whose name` — falls back to deep walk once."""
    lit = json.dumps(label)
    try:
        out = run_as(
            f"""
tell application "System Events"
  tell process "Dayrule"
    tell window 1
      set matches to static texts whose name is {lit}
      if (count of matches) < 1 then error "missing"
      set e to item 1 of matches
      set p to position of e
      set s to size of e
      return ((item 1 of p) + (item 1 of s) / 2 as integer as text) & "," & ((item 2 of p) + (item 2 of s) / 2 as integer as text)
    end tell
  end tell
end tell
"""
        )
    except RuntimeError:
        # Nested SwiftUI labels sometimes aren't direct static texts of the window.
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


def keystroke(text: str, **mods: bool) -> None:
    """Type via System Events. Short chords only (e.g. ⌘N) — not free text."""
    parts = []
    if mods.get("command"):
        parts.append("command down")
    if mods.get("option"):
        parts.append("option down")
    if mods.get("shift"):
        parts.append("shift down")
    if mods.get("control"):
        parts.append("control down")
    using = f" using {{{', '.join(parts)}}}" if parts else ""
    lit = json.dumps(text)
    run_as(
        f"""
tell application "Dayrule" to activate
delay 0.1
tell application "System Events" to keystroke {lit}{using}
"""
    )
    time.sleep(0.25)


def paste_text(text: str) -> None:
    """Paste unicode titles (apostrophes / em dashes break raw keystroke)."""
    subprocess.run(
        ["pbcopy"],
        input=text.encode("utf-8"),
        check=True,
    )
    time.sleep(0.05)
    keystroke("v", command=True)
    time.sleep(0.2)


def key_code(code: int, **mods: bool) -> None:
    parts = []
    if mods.get("command"):
        parts.append("command down")
    if mods.get("option"):
        parts.append("option down")
    if mods.get("shift"):
        parts.append("shift down")
    using = f" using {{{', '.join(parts)}}}" if parts else ""
    run_as(
        f"""
tell application "Dayrule" to activate
delay 0.05
tell application "System Events" to key code {code}{using}
"""
    )
    time.sleep(0.2)


def focus_ax(identifier: str, timeout: float = 3.0) -> bool:
    """Focus a control by accessibilityIdentifier (compiled AX helper)."""
    ensure_helpers()
    run_as('tell application "Dayrule" to activate\ndelay 0.05')
    try:
        r = subprocess.run(
            [str(AXFOCUS), identifier],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return False
    return r.returncode == 0


def click_popup_menu_item(label: str) -> bool:
    """Click a label in the frontmost contextual/popup menu."""
    lit = json.dumps(label)
    try:
        run_as(
            f"""
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    delay 0.12
    if not (exists menu 1) then error "no popup menu"
    click menu item {lit} of menu 1
  end tell
end tell
"""
        )
        return True
    except RuntimeError:
        return False


def click_add_field() -> None:
    """Focus the on-screen list Add field (placement follows the open list)."""
    # Prefer AX id; ⌘N focuses Add for the current list; geometry is last resort.
    if focus_ax("list.addField"):
        time.sleep(0.15)
        return
    keystroke("n", command=True)
    time.sleep(0.4)
    if focus_ax("list.addField"):
        time.sleep(0.1)
        return
    x, y, w, h = window_frame()
    ax = x + 220 + max(w - 220, 100) // 2
    ay = y + h - 36
    hid_click(ax, ay, settle=0.25)


def add_todo(title: str) -> None:
    """Focus Add, paste title, Return — uses the on-screen list's placement."""
    click_add_field()
    paste_text(title)
    time.sleep(0.12)
    key_code(36)  # Return
    time.sleep(0.35)


def focus_title_field() -> None:
    """Click the large title area then select-all (no entire-contents walk)."""
    x, y, w, h = window_frame()
    # Detail title sits just under the toolbar, right of the sidebar.
    hid_click(x + 280, y + 72)
    time.sleep(0.15)
    keystroke("a", command=True)
    time.sleep(0.1)

def create_project(name: str) -> None:
    """⌘⌥N new project and name it."""
    keystroke("n", command=True, option=True)
    time.sleep(0.55)
    try:
        focus_title_field()
    except RuntimeError:
        keystroke("a", command=True)
        time.sleep(0.08)
    paste_text(name)
    time.sleep(0.15)
    key_code(36)
    time.sleep(0.4)


def create_area(name: str) -> None:
    keystroke("a", command=True, option=True)
    time.sleep(0.55)
    try:
        focus_title_field()
    except RuntimeError:
        keystroke("a", command=True)
        time.sleep(0.08)
    paste_text(name)
    time.sleep(0.15)
    key_code(36)
    time.sleep(0.4)


def rename_front(name: str) -> None:
    """Rename the open project/area title field."""
    try:
        focus_title_field()
    except RuntimeError:
        return
    paste_text(name)
    time.sleep(0.15)
    key_code(36)
    time.sleep(0.35)


def sidebar_project_spots() -> list[tuple[int, int]]:
    """Sidebar slots under Trash (projects/areas sit there on Mac)."""
    try:
        tx, ty = static_center("Trash")
        return [(tx - 20, ty + dy) for dy in (56, 72, 88, 104, 120, 136, 152, 168)]
    except RuntimeError:
        x, y, _, _ = window_frame()
        return [(x + 36, y + 220 + i * 28) for i in range(8)]


def open_project(name: str) -> bool:
    """Click sidebar slots under Trash until window title matches."""
    for sx, sy in sidebar_project_spots():
        hid_click(sx, sy, settle=0.2)
        try:
            if window_probe()[1] == name:
                return True
        except RuntimeError:
            pass
    return False


def trash_open_untitled(title: str) -> bool:
    """Trash the open New Project / New Area detail (toolbar or ··· menu)."""
    if title == "New Area" and focus_ax("area.trash", timeout=2.0):
        time.sleep(0.3)
        return True
    # Project ··· menu — prefer description click over deep AX walks.
    try:
        run_as(
            """
tell application "System Events"
  tell process "Dayrule"
    set frontmost to true
    delay 0.1
    set clicked to false
    repeat with b in (buttons of window 1)
      try
        set d to description of b as string
        if d is "Project actions" then
          click b
          set clicked to true
          exit repeat
        end if
      end try
    end repeat
    if not clicked then
      repeat with b in (entire contents of window 1)
        try
          if (class of b as string) is "button" then
            set d to ""
            try
              set d to description of b as string
            end try
            if d is "Project actions" then
              click b
              set clicked to true
              exit repeat
            end if
          end if
        end try
      end repeat
    end if
    if not clicked then error "no Project actions"
    delay 0.25
    if not (exists menu 1) then error "no actions menu"
    click menu item "Move to Trash" of menu 1
  end tell
end tell
"""
        )
        time.sleep(0.35)
        return True
    except RuntimeError:
        key_code(53)
        time.sleep(0.1)
        return False


def trash_untitled_rows() -> None:
    """Delete leftover New Project / New Area.

    Prefer sidebar context menu; fall back to the open detail's Trash / ··· menu.
    """
    print("  trash untitled…", flush=True)
    spots = sidebar_project_spots()
    for _ in range(6):
        found = False
        for sx, sy in spots:
            hid_click(sx, sy, settle=0.18)
            try:
                title = window_probe()[1]
            except RuntimeError:
                continue
            if title not in ("New Project", "New Area"):
                continue
            found = True
            hid_right_click(sx, sy, settle=0.3)
            if click_popup_menu_item("Move to Trash"):
                time.sleep(0.35)
                print(f"    trashed {title!r} (context menu)", flush=True)
                break
            key_code(53)
            time.sleep(0.12)
            if trash_open_untitled(title):
                print(f"    trashed {title!r} (detail)", flush=True)
                break
            print(f"    skip trash {title!r}", flush=True)
            # Keep scanning other sidebar slots instead of aborting the pass.
            continue
        if not found:
            break


def ensure_named(name: str, *, area: bool = False) -> None:
    """Open name if present; else rename an untitled row; else create."""
    if open_project(name):
        return
    spots = sidebar_project_spots()
    for sx, sy in spots:
        hid_click(sx, sy, settle=0.18)
        try:
            title = window_probe()[1]
        except RuntimeError:
            continue
        if title in ("New Project", "New Area"):
            rename_front(name)
            time.sleep(0.2)
            if open_project(name) or window_probe()[1] == name:
                print(f"    renamed untitled → {name!r}", flush=True)
                return
    if area:
        create_area(name)
    else:
        create_project(name)


def seed_dense(go) -> None:
    """Fatten sparse agent vault so ASC shots look lived-in (matches UITest seed)."""
    print("seeding dense demo content…", flush=True)

    def fill(list_name: str, titles: tuple[str, ...], when: bool = False) -> None:
        print(f"  {list_name} ({len(titles)})", flush=True)
        go(list_name)
        try:
            if window_probe()[1] != list_name:
                raise SystemExit(f"expected window {list_name!r} before seed")
        except RuntimeError as e:
            raise SystemExit(f"window probe failed on {list_name}: {e}") from e
        for t in titles:
            add_todo(t)
            if when:
                # List Add already sets When=tomorrow; Escape dismisses the sheet.
                time.sleep(0.25)
                key_code(53)
                time.sleep(0.15)

    # Inbox is already dense from earlier mis-seeds — don't pile more.
    fill(
        "Today",
        (
            "Walk for twenty minutes",
            "Reply to the school email",
            "Pick up dry cleaning",
            "Book dentist check-up",
            "Water the plants",
            "Prep tomorrow's lunch",
            "Call the plumber back",
            "Put the bins out",
            "Pack the swimming bag",
            "Confirm Friday babysitter",
        ),
    )
    fill(
        "Scheduled",
        (
            "Museum with the kids",
            "MOT appointment",
            "Garden centre run",
            "Softball practice",
            "Parents evening",
            "Roofers quote visit",
            "Blood test at the GP",
        ),
        when=True,
    )
    fill(
        "Backlog",
        (
            "Plan spring planting",
            "Replace hallway bulbs",
            "Catalogue the vinyl",
            "Research heat pump quotes",
            "Frame the beach photos",
            "Service the bike",
            "Clear the loft hatch",
            "Sort the tool drawer",
            "Wash the spare duvet",
        ),
    )

    print("  org House/Kitchen/Garden/Holidays", flush=True)
    trash_untitled_rows()

    ensure_named("Kitchen")
    for t in (
        "Paint the cupboards",
        "Replace the tap washer",
        "Reorganise the pantry",
        "Buy new tea towels",
        "Descale the kettle",
        "Oil the chopping boards",
    ):
        add_todo(t)

    ensure_named("House", area=True)

    ensure_named("Garden")
    for t in (
        "Sow the sweet peas",
        "Mend the fence panel",
        "Order compost",
        "Sharpen the shears",
        "Plant the spring bulbs",
    ):
        add_todo(t)

    ensure_named("Holidays")
    for t in (
        "Book the cottage",
        "Pack the walking boots",
        "Check passport dates",
        "Arrange pet sitting",
    ):
        add_todo(t)

    trash_untitled_rows()

    print("  sync…", flush=True)
    keystroke(",", command=True)
    time.sleep(0.6)
    if focus_ax("settings.syncNow"):
        time.sleep(3)
    else:
        try:
            click_static("Sync now")
            time.sleep(3)
        except RuntimeError:
            pass
    key_code(53)
    time.sleep(0.3)
    print("seed done", flush=True)

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
        dismiss_overlays()
        try:
            _, name, fields = window_probe(count_fields=True)
        except RuntimeError:
            continue
        gate_label = has_static("Sign in to open your lists.")
        print(f"  gate t={i+1} win={name!r} fields={fields} label={gate_label}")
        # Collapsed Advanced: email + password (2). Expanded: + API (3).
        if fields >= 2 and (gate_label or name in ("Dayrule", "")):
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
    dismiss_overlays()
    expand_advanced()
    time.sleep(0.5)
    _, _, fields = window_probe(count_fields=True)
    # Field order with Advanced open: API, Email, Password.
    # With Advanced closed: Email, Password (production API is already default).
    if fields >= 3:
        set_field(1, API)
        set_field(2, email)
        set_field(3, password)
        email_idx, pass_idx = 2, 3
    else:
        set_field(1, email)
        set_field(2, password)
        email_idx, pass_idx = 1, 2
    # verify without printing password
    verify = run_as(
        f"""
tell application "System Events"
  tell process "Dayrule"
    set ui to entire contents of window 1
    set fields to {{}}
    repeat with e in ui
      try
        set cls to class of e as string
        if cls is "text field" or cls is "secure text field" then set end of fields to e
      end try
    end repeat
    set em to value of item {email_idx} of fields as string
    set plen to length of (value of item {pass_idx} of fields as string)
    return em & "|" & (plen as string)
  end tell
end tell
"""
    )
    email_v, pass_len = verify.split("|", 1)
    if email_v != email or int(pass_len) < 12:
        raise SystemExit(f"gate fill failed: email={email_v!r} pass_len={pass_len}")
    print(f"gate ok email={email_v} pass_len={pass_len} fields={fields}")

    click_signin()
    print("waiting for lists + Kitchen (AX omits project labels)…")
    list_titles = {
        "Today",
        "Inbox",
        "Scheduled",
        "Backlog",
        "Done",
        "Trash",
        "Kitchen",
        "Garden",
        "Holidays",
        "House",
    }
    kitchen_ok = False
    for i in range(90):
        time.sleep(1.2)
        try:
            _, name, _ = window_probe()
        except RuntimeError:
            name = "?"
        # Still on gate — light error check only then.
        if name in ("Dayrule", "", "none"):
            err = gate_error()
            if err:
                raise SystemExit(f"sign-in error: {err}")
        unlocked = name in list_titles
        if not unlocked:
            # Fallback: sidebar Trash label (may be nested — try once every few loops).
            if i % 3 == 0 and has_static("Trash"):
                unlocked = True
        if unlocked:
            # Confirm Kitchen exists (agent vault gate). Project rows omit AX labels.
            if name == "Kitchen" or open_project("Kitchen"):
                print("agent vault visible (Kitchen)")
                kitchen_ok = True
                break
            # Already on a smart list with Trash in the tree — agent vault is open.
            if name in list_titles and name != "Dayrule":
                print(f"agent vault visible ({name})")
                kitchen_ok = True
                break
        if (i + 1) % 5 == 0:
            print(f"  …{i+1} win={name!r}")
    if not kitchen_ok:
        raise SystemExit(
            "Kitchen never appeared — seed the agent account before capturing"
        )
    def go(list_name: str) -> None:
        """Sidebar select. After a project row, Today sometimes misses once — retry
        via Inbox, then icon + label centers."""
        for attempt in range(20):
            try:
                if window_probe()[1] == list_name:
                    return
            except RuntimeError:
                pass
            if attempt == 4 and list_name != "Inbox":
                # Project rows can leave the next Today click dead; bounce via Inbox.
                try:
                    click_static("Inbox")
                    time.sleep(0.4)
                except RuntimeError:
                    pass
            try:
                x, y = static_center(list_name)
            except RuntimeError:
                time.sleep(0.3)
                continue
            hid_click(x - 40, y)
            time.sleep(0.35)
            try:
                if window_probe()[1] == list_name:
                    return
            except RuntimeError:
                pass
            hid_click(x, y)
            time.sleep(0.35)
        raise SystemExit(f"never reached list {list_name!r}")

    # Leave Kitchen (probe used project coords) via Inbox so Today lands.
    go("Inbox")
    seed_dense(go)

    go("Today")
    shot("01-today")
    go("Inbox")
    shot("02-inbox")
    go("Scheduled")
    shot("03-scheduled")
    go("Backlog")
    shot("04-backlog")
    if not open_project("Kitchen"):
        raise SystemExit("never reached Kitchen for project shot")
    shot("05-project-kitchen")
    # First todo row under the project title (avoid AX walk for the title string).
    x, y, w, h = window_frame()
    hid_click(x + 280, y + 130, settle=0.6)
    time.sleep(0.4)
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
