# Slice — Holiday and Reminder parity

## Comparison

Compared `Sleepy/ui/screen/mine/HolidaySettingsScreen.swift` and
`Sleepy/ui/screen/mine/ReminderScreen.swift` against original 1.0.51
(`HolidaySettingsScreen.kt`, `ReminderScreen.kt`).

### Holiday

Three original 1.0.51 changes applied:

- **Data source card** — rebuilt as the single-row form: title and the
  `holiday_source_label` URL sit on one line, refresh is a 36pt icon
  button (`arrow.clockwise`, language-independent) shown in every
  non-loading state, a spinner occupies the icon slot while loading, and
  the failed/empty note drops below the row instead of replacing it.
  The separate full-width retry button is gone (the refresh icon is the
  retry path, matching Android).
- **Style card** — title-plus-subtitle with two `HolidayStyleChip`
  buttons replaced by `SettingsFlatCard` (title row with the segmented
  selector on the right, same as the general settings flat cards).
  The now-unreferenced `settings_holiday_style_sub` label line is gone
  from the view; the strings key stays in place. `HolidayStyleChip` is
  removed (original 1.0.51 also has no chip component).
- **Edit dialog** — the native `Picker(.segmented)` type selector is now
  the shared `SegmentedSwitcher` (full width, same as the settings tabs),
  matching original 1.0.51's switch from scattered chips. Native
  `DatePicker(.compact)` start/end fields and the sheet presentation stay
  as the documented iOS platform adaptation.

### Reminder

- **Minutes field** — restructured from a 110pt field plus an external
  unit label into a 120pt box with the unit suffix inside the field,
  matching the 原 `TextField(suffix = …)` form.
- **Fluid-fields selector** — the menu label restacked from a single row
  (value + hint + chevron) into the Android readOnly-TextField form:
  hint label above the value line with a trailing chevron. The `Menu`
  with single-select markers and the native wheel time picker stay as
  the documented iOS adaptations.

## Strings

`holiday_source_label` added to all five locales
(`unpkg.com/holiday-calendar · CN`, identical in every Android locale).
Staged hunk-only so the pre-existing uncommitted strings work (AddCourse
conflict/weeks strings, `settings_start_view` strings) stays out of this
commit and remains in the worktree.

## Verification

- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` -> ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` -> 0 hits
- `git diff --check` -> clean
- Staged diff audited: only the 7 slice files; each strings file
  contributes exactly the one `holiday_source_label` line.

## Scope

Files touched:

- `Sleepy/ui/screen/mine/HolidaySettingsScreen.swift`
- `Sleepy/ui/screen/mine/ReminderScreen.swift`
- 5 × `Sleepy/resources/*.lproj/Localizable.strings` (one key each)

No parser, DAO, repository, widget, or preference-default changes.
Native DatePickers, the reminder time-picker sheet, and the fluid-fields
`Menu` remain documented iOS platform adaptations. Existing unrelated
dirty work remains in the worktree, untouched and uncommitted.
