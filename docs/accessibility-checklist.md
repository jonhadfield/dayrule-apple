# Accessibility checklist (iOS + macOS)

Tracked gates from the ios-accessibility skill review (2026-11-25). Check an
item only with evidence (manual AT pass, UITest, or unit test) — not by
assumption. Prefer completing common tasks: unlock, browse lists, complete a
to-do, set When, edit, Find, Settings, Lock.

App Store **Accessibility Nutrition Labels** need a common-task × device
evidence matrix before claiming a category. Do not treat this file as that
matrix.

## Semantics

- [x] To-do rows expose a combined label (title, Reminder / Repeats / Has notes,
  chip / overdue text) — `DayruleTodoRow`
- [x] Complete / Reopen uses “Complete {title}” (and checkbox value) —
  `DayruleCheckbox` / row actions
- [x] Icon-only chrome has speakable labels (Lock, Find, Settings, sidebar
  toggle, selection bar, Add)
- [x] Section / page headers use header traits where drawn
- [x] `accessibilityInputLabels` on awkward spoken names (`When…`, chrome,
  selection bar, Add, sheet confirm) for Voice Control — `RowAction` /
  `SheetAction` defaults + toolbar / selection bar
- [x] Custom Mac paper scrollers keep scroll-bar AX role after custom draw
  (`DayrulePaperScroller.isAccessibilityElement` / `accessibilityRole` +
  `DesignSystemTests.paperScrollerKeepsScrollBarRole`). Live VoiceOver scroll
  % / rotor actions still worth a spot-check on device.

## Navigation and focus

- [x] Gate / recovery title receives accessibility focus after screen change —
  `GateView` / `RecoveryPhraseView`
- [x] List sheets (When, Deadline, Tags, Move, Repeat, Reminder, editor) and
  Settings / Find restore VoiceOver focus to the triggering row or chrome
  control on dismiss — `AccessibilityFocusRestore` + `DayruleA11yFocus`
- [x] Project / area todo sheets + heading / move-project restore to the row or
  detail-actions control; New List popover restores to the New List control
- [x] Sheet Escape / Cancel dismiss without a focus trap — `DayruleSheet`
  Cancel + `.keyboardShortcut(.cancelAction)`; Mac also `.onExitCommand`
  (dirty → discard dialog). iOS: Cancel / interactive dismiss. Mac UITest
  `testWhenSheetDismissesWithEscape` (local; CI skips UITests)

## Input (Voice Control / Switch Control / keyboard)

- [x] Swipe / context gestures have named accessibility actions (When, Select,
  Move up/down, Trash, Restore)
- [x] Mac menu commands cover New To-Do / Project / Area, Lock, Find, Settings,
  Help, Undo
- [ ] Voice Control “Show Names” / “Show Numbers” pass on Gate, Today, When
  sheet, Settings (manual device — not automatable here)
- [ ] Full Keyboard Access / Switch Control scan pass on the same tasks
  (manual device — not automatable here)

## Adaptation

- [x] Reduce Motion: motion tokens, linger, checkbox — `Motion` /
  `LingerStore` / `DayruleCheckbox` (+ unit tests)
- [x] Hit targets meet 44pt minimum (`Tokens.minHit`) on checkbox, Add, chips,
  phone tabs, selection bar
- [x] Static text contrast ≥4.5:1 on paper surfaces light/dark —
  `DesignSystemTests`
- [x] Dynamic Type: dense fixed 16pt yields to `.body` at accessibility sizes;
  page title stacks / scales; phone-tab DT ceiling removed; sync status wraps.
  Unlocked Inbox audit still ignores residual `.dynamicType` / `.textClipped`
  on Fraunces / toolbar chrome (decision 66 residual — not a forever skip of
  large-text care)
- [x] Increase Contrast / Reduce Transparency in `DayruleColors.resolve` (+
  washes / selection / hairlines / secondary ink; unit contrast coverage)
- [x] Bold Text (`legibilityWeight`) on row titles, links, meta/chips, dense
  body, and sync short-label — `dayruleRowTitle` / `dayruleMeta` /
  `DayruleDenseBodyFont` (+ unit weight helper)
- [x] Compact sync uses distinct SF Symbols per state (not colour-only dot);
  overdue/late chips keep icon + text (`exclamationmark` vs clock) —
  `SyncStatus.compactSymbol` / `DayruleTodoRow`

## Automation

- [x] Gate `performAccessibilityAudit` (Mac filters platform-owned chrome)
- [x] Debug unlocked Inbox audit (`DAYRULE_UI_TEST_UNLOCKED`; residual DT /
  text-clipped filter only)
- [x] Unit: `AccessibilityFocusRestore.afterDismiss` delay — `DesignSystemTests`
- [x] UITest: When sheet present/dismiss keeps to-do row —
  `testWhenSheetDismissKeepsTodoRow` (VO `hasFocus` not asserted in CI)
- [x] UITest (macOS local): Escape dismisses When sheet —
  `testWhenSheetDismissesWithEscape` (CI skips DayruleUITests)
- [x] Unit: paper scroller keeps `.scrollBar` role —
  `paperScrollerKeepsScrollBarRole` (macOS)

## Nutrition-label readiness (do not claim without matrix)

| Label | Lean | Blocker |
| --- | --- | --- |
| VoiceOver | Lean | Live VO task matrix (restore + scroller %) still open |
| Dark Interface | Likely | Manual common-task pass |
| Reduced Motion | Likely | Manual common-task pass |
| Sufficient Contrast | Lean | Manual Increased Contrast / Reduce Transparency pass |
| Larger Text | Lean | Manual AX-size pass; residual Fraunces auditor noise |
| Voice Control | Lean | Manual Show Names/Numbers still open |
| Captions / Audio Descriptions | N/A | No AV content |

## Evidence notes (2026-11-28)

Automated: contrast unit tests; focus-restore delay; When dismiss + Escape
UITests; paper scroller AX role unit test; unlocked Inbox a11y audit
(residual DT / text-clipped filter only); Bold Text weight helper + compact
sync symbol tests (`#33`).

Still manual on device: live VoiceOver restore + scroller %, Voice Control
Show Names/Numbers, Full Keyboard Access / Switch Control common-task scan.

### Device script (remaining)

1. **VoiceOver (iPhone + Mac):** unlock → Today → open When on a row → dismiss;
   confirm focus returns to the row. Mac: VO interact with list scroll bar;
   confirm percentage / scroll actions.
2. **Voice Control:** Show Names / Show Numbers on Gate, Today, When sheet,
   Settings — every control reachable; awkward names covered by input labels.
3. **Full Keyboard Access / Switch Control:** same tasks; no trap; Escape /
   Cancel exits sheets.

## Open follow-ups (from 2026-11-25 review)

1. ~~Restore VO focus when When / editor / Settings / Find / project-area sheets dismiss.~~
2. ~~Dynamic Type polish pass, then re-enable filtered audit types.~~
3. ~~`accessibilityInputLabels` on row actions + chrome.~~
4. ~~Wire Increase Contrast / Reduce Transparency into paper chrome.~~
5. Manual VoiceOver pass to confirm restore after dismiss on iPhone + Mac.
6. ~~Bold Text / differentiate-without-color (compact sync + chips).~~
7. ~~Paper scroller AX role + Escape dismiss (automated).~~
8. Show Names / FKA / Switch + live VO scroller % (manual device script above).
