# iPhone Duo dual-window

Decision 76. Complements the fold-safe first slice (decision 24).

## What ships

- `UIApplicationSupportsMultipleScenes` is enabled so Device Hub can open a
  second Dayrule window across the hinge (Book / Open).
- Both windows share the process `AppModel` (`@State` on `DayruleApp`), so
  unlock, sync and lock stay one vault — not two accounts.
- Each window keeps its own navigation stack (Inbox vs project, etc.).
- Unlocked regular-width chrome still wraps in `FoldSafeContainer` so Book
  pose does not span the crease.

## How to verify (simulator)

1. Boot **iPhone Duo** (iOS 27.1+ SDK).
2. Unlock Dayrule (or `DAYRULE_UI_TEST_UNLOCKED` for an empty vault).
3. In Device Hub, set **Book** or **Open**, then open a second window
   (system multi-window affordance / “New Window” if offered).
4. Confirm both panes show unlocked chrome; lock from one locks the vault
   for both.
5. Optional: `DuoUnlockedChromeTests` + `/tmp/dayrule-duo-unlock.json` for
   Closed / Book / Open captures (not run in CI).

## Still later

- Hinge-aware animation polish beyond `FoldLayout` slotting.
- Duo-specific App Store screenshot set.
