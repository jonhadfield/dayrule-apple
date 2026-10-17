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
| Menus | Settings ⌘,, Lock ⇧⌘L, Find ⌘F (PLAN §6.6) |

## Before Add for Review (Mac)

1. **Archive + upload** a Mac build whose number is at least as new as the
   iPhone build you care about (Help, privacy contact, Add Done, etc.).
2. **Screenshots** — capture with
   `CAPTURE=macos scripts/capture-app-store-screenshots.sh` (demo account
   in local `creds.txt`). On first run, macOS may prompt to allow
   **Accessibility** for Xcode (System Settings → Privacy & Security →
   Accessibility); without it the UITest cannot see the gate. Upload sizes
   Apple lists for Mac (commonly 1280×800, 1440×900, 2560×1600 /
   2880×1800). Resize with `sips` if the window shot is Retina-scaled.
   PNGs land in `docs/app-store-screenshots/macos/`.
3. **App Review Information** — same demo account as iOS is fine; Review
   Notes can say Mac uses the sidebar (Inbox · Today · …) instead of phone
   tabs. Lock is ⇧⌘L or the toolbar lock.
4. **Copyright** — same as iOS (`2026 Jon Hadfield` unless that changes).
5. **Privacy nutrition label / encryption** — same answers as iOS for this
   binary; Mac does not add analytics.

## Intentionally deferred (PLAN)

- Extra ⌘ shortcuts and multi-window (PLAN §6.6)
- Mac-first IA that differs from iPad/desktop web

## Related

- iOS App Review demo: `docs/app-review-demo.md`
- Security checklist: `docs/security-checklist.md`
