# Slice — All Tables / Edit Table parity

## What

Aligned the All Tables and Edit Table flows with original 1.0.51 while preserving the existing SwiftUI form and persistence behavior.

- `AllTablesScreen` now uses a semantic selection `Button` for each table row instead of a row-level tap gesture. Duplicate and edit actions remain independent buttons so their actions do not bubble into table selection.
- Table selection keeps the Android-aligned current-row `primaryContainer` styling, selected checkmark, current-week subtitle, and non-current `surfaceContainer` styling.
- Selection and row actions expose stable accessibility identifiers; the selection button also exposes the table name as its accessibility label.
- `EditTableScreen` resolves an explicitly requested table first, then the current table, the pending newly-created table, and finally the first available table. This preserves the editor during the observation race where a newly created table is not yet visible in the published table list.
- Existing Android-aligned editor behavior remains intact: filled fields, expandable time-slot editing, date/time and start/end validation, save/delete actions, course-count delete confirmation, smart-period serialization, and pending-new-table discard handling.

## Evidence

- original sources:
  - `app/src/main/java/com/lingion/sleepy/ui/screen/mine/AllTablesScreen.kt`
  - `app/src/main/java/com/lingion/sleepy/ui/screen/mine/EditTableScreen.kt`
- iOS sources:
  - `Sleepy/ui/screen/mine/AllTablesScreen.swift`
  - `Sleepy/ui/screen/mine/EditTableScreen.swift`
- Generic iOS build: `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` -> `** BUILD SUCCEEDED **`.
- Scoped static sweep: `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` -> zero hits.
- `git diff --check` -> clean.

## Scope

Only `AllTablesScreen.swift`, `EditTableScreen.swift`, this report, and the two matching matrix rows are included in this slice. Existing localization, import-flow, settings, screenshot, test, baseline, and other worktree changes remain outside the slice.

## Known remaining work

- Appearance, General Settings, Import Flow, Holiday/Reminder, Export/Share, About/License, shared sheets/editors, and localization/layout stress still require their own original 1.0.51 comparison and verification slices.
