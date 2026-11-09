# Mac App Store packaging

Dayrule is one multiplatform target (`iOS` + `macOS`). Mac chrome follows
PLAN §6.6; this note is the packaging checklist for a Mac App Store /
TestFlight upload (after the iPhone critical path).

## Already in the binary

| Item | Where |
|---|---|
| App Sandbox | `Dayrule/Resources/Dayrule.entitlements` |
| Outgoing network | `com.apple.security.network.client` |
| User-selected files (export / import) | `com.apple.security.files.user-selected.read-write` |
| Passkey Associated Domains | `webcredentials:dayrule.app` |
| Productivity category | `LSApplicationCategoryType` in `Info.plist` |
| Default window | 1280×800 (ASC minimum Mac screenshot size) |
| Menus | Settings ⌘,, Lock ⇧⌘L, Find ⌘F, Undo/Redo ⌘Z/⇧⌘Z, New To-Do ⌘N, New Project ⌥⌘N, New Area ⌥⌘A, Move to Trash ⌫, Help ⌘? (PLAN §6.6 / decisions 29, 36, 52) |

## Before Add for Review (Mac)

The 0.1.x Mac App Store release already cleared review. Use this list for
the **next** Mac submission (keep iOS and Mac on the same
`MARKETING_VERSION` / a `CURRENT_PROJECT_VERSION` at least as new as the
iPhone build you care about).

1. **Archive + upload** a Mac build. Organizer: **Distribute App → App
   Store Connect**. The local keychain may only have Apple Development +
   Developer ID; Xcode re-signs for the Mac App Store on upload if the
   team can issue **Apple Distribution**.
2. **Screenshots** — capture with
   `CAPTURE=macos scripts/capture-app-store-screenshots.sh` (agent test
   account in local `agent-creds.txt` — not App Review `creds.txt`; see
   `docs/agent-test-account.md`). On first run, macOS may prompt to allow
   **Accessibility** for Xcode (System Settings → Privacy & Security →
   Accessibility); without it the UITest cannot see the gate. If the Mac
   session is stay-unlocked, the UITest often never sees `gate.email` —
   use `scripts/capture-mac-asc-applescript.sh` after a Debug build, or
   keep the Kitchen set already in `docs/app-store-screenshots/macos/`.
   Upload sizes Apple lists for Mac (commonly 1280×800, 1440×900,
   2560×1600 / 2880×1800). Window captures are Retina-scaled (2784×1824);
   resize before ASC:

   ```bash
   mkdir -p docs/app-store-screenshots/macos-2560x1600
   for f in docs/app-store-screenshots/macos/*.png; do
     sips -z 1600 2560 "$f" --out "docs/app-store-screenshots/macos-2560x1600/$(basename "$f")"
   done
   ```

3. **App Review Information** — same demo account as iOS is fine. Paste the
   Mac bullet from `docs/app-review-demo.md` (sidebar not tabs; New List;
   ⇧⌘L / ⌘, / ⌘F).
4. **Copyright** — same as iOS (`2026 Jon Hadfield` unless that changes).
5. **Privacy nutrition label / encryption** — same answers as iOS for this
   binary; Mac does not add analytics.

## Intentionally deferred (PLAN)

- Extra ⌘ shortcuts and multi-window (PLAN §6.6)
- Mac-first IA that differs from iPad/desktop web

## Related

- iOS App Review demo: `docs/app-review-demo.md`
- Security checklist: `docs/security-checklist.md`
