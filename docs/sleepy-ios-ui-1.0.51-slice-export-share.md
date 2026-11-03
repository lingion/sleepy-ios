# Slice — Export/Share parity

## Comparison

Compared `Sleepy/ui/screen/mine/ExportScreen.swift` and
`Sleepy/ui/component/ShareScheduleSheet.swift` against original 1.0.51
(`ExportScreen.kt`, `ShareScheduleSheet.kt`).

## Implemented

### ExportScreen — export target picker

original 1.0.51 exports a locally-pinned table rather than only the
current one. iOS now matches:

- The top info card is a button with a trailing chevron and opens an
  export-target picker sheet. Row style follows the ScheduleScreen table
  switcher (the look Android's dialog is explicitly aligned to): pinned
  row `primaryContainer` + checkmark, 2-line name, `surfaceContainer`
  otherwise, 360pt scroll cap.
- The main current table shows a localized "current schedule" badge in
  the picker.
- Selection pins locally (`exportTableId`) and never writes the home
  schedule's `selectedTableId` or the widget default table — same
  contract as Android.
- Courses for a pinned non-current table load once through
  `ScheduleRepository(AppDatabase.getShared()).getCourses` so the
  course-count line stays accurate; the current table keeps using the
  observed `state.courses`.
- `export_pick_table` and `export_current_table_badge` added to all
  five locales with the Android values.

### ShareScheduleSheet

The sheet's three existing rows already match original implementation 1.0.51 (item
visuals, dividers, title). No change was needed beyond the shared gap
below.

## Known gap (documented, not shipped)

original 1.0.51 has a fourth export row — sleepy-v1 native format
(`export_native_title`, Star icon, `.sleepy` file / `【来自Sleepy】`
share text). It requires `SleepyNativeExporter` + `SleepyNativeFormat`
(CRC32, escaping, Nd presets, parser counterpart, 89-test suite). That
is the data/parser layer, which the alignment matrix explicitly excludes
("Parser, DAO, repository, widget, and preference-default changes are
outside this matrix"), and the native-format work exists on a separate
pending branch. Both surfaces carry this gap until that port lands;
`export_native_*` strings are intentionally not added while no row uses
them.

## Verification

- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` -> ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` -> 0 hits
- `git diff --check` -> clean
- Strings staged hunk-only: pre-existing uncommitted strings work
  (AddCourse conflict/weeks, `settings_start_view`) stays uncommitted.

## Scope

Files touched:

- `Sleepy/ui/screen/mine/ExportScreen.swift`
- 5 × `Sleepy/resources/*.lproj/Localizable.strings` (two keys each)

No parser, DAO, repository, widget, or preference-default changes.
Existing unrelated dirty work remains in the worktree, untouched.
