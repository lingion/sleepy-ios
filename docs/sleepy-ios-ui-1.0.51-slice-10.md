# Slice 10: Add Course parity

## What

Aligned `AddCourseScreen` with original 1.0.51 per-slot week semantics, dynamic step
cap, clamped-hint surface, and pre-save conflict confirmation.

- Each meeting block carries its own `startWeek / endWeek / weekType` so a single
  course can split odd/even or custom-week slots without losing identity.
- The grouping key when re-hydrating a course with the same `groupId` now
  matches Android:
  `ownTime-startNode-step-startTime-endTime-startWeek-endWeek-type`.
  Slots that differ only by week range or week type are no longer collapsed.
- The step field's upper bound is derived from the active timetable:
  `maxNode - startNode + 1`, mirroring the original `stepCap`. Raising the start
  node coerces the existing `step` immediately and flags `clamped`.
- `NumberStepperField` exposes an optional `onClamp` callback; when a typed or
  stepped value is clipped, the parent block is marked `clamped`, the block
  background switches to `errorContainer`, and a "period values are limited by
  this timetable's N periods" hint appears under the controls.
- Validation now reports per-slot week order errors and per-slot step-exceeds-
  max errors with the actual range, using the timetable's `timeJson` as the
  source of truth.
- `save(...)` runs the existing `ConflictDetailReporter` over every draft slot
  against every stored course (excluding the edited group). On conflict it
  shows a confirmation alert with each localized detail line and only commits
  when the user picks **Save anyway**. The confirmation gate reuses the
  unchanged alert pattern already in the project.
- `block.clamped` is now persisted only as in-memory state; the entity uses the
  per-block week range and week type, removing the previous global week fields
  from `buildCourseEntity`.
- Conflict detail format strings were fixed in every locale
  (`en / zh-Hans / zh-Hant / es / ja`) — the four object arguments now use
  valid `%1$@`/`%2$@`/`%3$@`/`%4$@` placeholders that line up with
  `ConflictDetailReporter.formatDetail(template: ...)`.

## Evidence

- Original source: `app/src/main/java/com/lingion/sleepy/ui/screen/edit/AddCourseScreen.kt`
  (grouping key, clamped state, dynamic stepCap, conflict pre-save dialog).
- iOS source: `Sleepy/ui/screen/edit/AddCourseScreen.swift`,
  `Sleepy/util/ConflictDetailReporter.swift`,
  `Sleepy/resources/{en,zh-Hans,zh-Hant,es,ja}.lproj/Localizable.strings`.
- `git diff --check`: passed.
- Generic iOS build: `** BUILD SUCCEEDED **`.

## Scope

Only `AddCourseScreen.swift` and the conflict-related localization keys were
modified for this slice. Existing custom theme behavior, other screens, and
unrelated worktree changes were preserved.

## Known remaining work

- The custom-week type (`weekType == 3`) still falls back to "active in every
  week of the configured range" inside `CourseEntity.inWeek(_:)` and the
  conflict reporter. A true custom-week list editor is still pending for
  original 1.0.51 parity; until that editor exists, the picker round-trips the
  value without altering the semantics.
- The conflict reporter's section-range test still assumes nodes-per-day are
  dense. This matches original 1.0.51 today but should be revisited alongside
  `TimeTableUtils.parseNodes` if sparse timetables become supported.
