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
- [ ] `accessibilityInputLabels` on awkward spoken names (`When…`, chrome,
  long titles) for Voice Control
- [ ] Custom Mac paper scrollers verified with VoiceOver scroll
  percentage / actions (`DayrulePaperScroller`)

## Navigation and focus

- [x] Gate / recovery title receives accessibility focus after screen change —
  `GateView` / `RecoveryPhraseView`
- [x] List sheets (When, Deadline, Tags, Move, Repeat, Reminder, editor) and
  Settings / Find restore VoiceOver focus to the triggering row or chrome
  control on dismiss — `AccessibilityFocusRestore` + `DayruleA11yFocus`
- [x] Project / area todo sheets + heading / move-project restore to the row or
  detail-actions control; New List popover restores to the New List control
- [ ] No focus trap in custom overlays; escape dismisses where modal

## Input (Voice Control / Switch Control / keyboard)

- [x] Swipe / context gestures have named accessibility actions (When, Select,
  Move up/down, Trash, Restore)
- [x] Mac menu commands cover New To-Do / Project / Area, Lock, Find, Settings,
  Help, Undo
- [ ] Voice Control “Show Names” / “Show Numbers” pass on Gate, Today, When
  sheet, Settings (manual)
- [ ] Full Keyboard Access / Switch Control scan pass on the same tasks
  (manual)

## Adaptation

- [x] Reduce Motion: motion tokens, linger, checkbox — `Motion` /
  `LingerStore` / `DayruleCheckbox` (+ unit tests)
- [x] Hit targets meet 44pt minimum (`Tokens.minHit`) on checkbox, Add, chips,
  phone tabs, selection bar
- [x] Static text contrast ≥4.5:1 on paper surfaces light/dark —
  `DesignSystemTests`
- [ ] Dynamic Type / text-clipped polish; drop decision 66 audit filters
- [ ] Increase Contrast / Reduce Transparency / Bold Text environment
  adaptation in paper chrome
- [ ] Differentiate-without-color review for compact sync dot and colour-led
  chips (icons+text already help overdue/late)

## Automation

- [x] Gate `performAccessibilityAudit` (Mac filters platform-owned chrome)
- [x] Debug unlocked Inbox audit (`DAYRULE_UI_TEST_UNLOCKED`; iOS still filters
  Dynamic Type / text-clipped per decision 66)
- [ ] UITest or unit coverage for sheet focus restoration where practical

## Nutrition-label readiness (do not claim without matrix)

| Label | Lean | Blocker |
| --- | --- | --- |
| VoiceOver | Likely | Finish focus restore + manual task matrix |
| Dark Interface | Likely | Manual common-task pass |
| Reduced Motion | Likely | Manual common-task pass |
| Sufficient Contrast | Likely | Increased Contrast mode still open |
| Larger Text | Hold | Decision 66 / DT polish |
| Voice Control | Hold | Input labels + manual Show Names/Numbers |
| Captions / Audio Descriptions | N/A | No AV content |

## Open follow-ups (from 2026-11-25 review)

1. ~~Restore VO focus when When / editor / Settings / Find / project-area sheets dismiss.~~
2. Dynamic Type polish pass, then re-enable filtered audit types.
3. `accessibilityInputLabels` on row actions + chrome.
4. Wire Increase Contrast / Reduce Transparency into paper chrome.
5. Manual VoiceOver pass to confirm restore after dismiss on iPhone + Mac.
