# Slice: Localization / layout stress (P3) — original 1.0.51 alignment

Commit `6a5bf94` · 8 files · localization + truncation + accessibility
parity with original 1.0.51 `ui/` sources.

## Key parity (mechanical check, all 5 locales)

- Every `L10n.format`/`L10n.t` key referenced in `Sleepy/` exists in
  zh-Hans / zh-Hant / en / es / ja `Localizable.strings` (431 keys).
- Dynamic `format_<key>_when|_spec_N|_example` expansions for all 6 import
  format families verified present in all 5 locales (0 missing).
- New key this alignment: `jw_table_name_label` (import slice commit
  `1670e68`).
- 原 `%1$s`-style positional args map to `%1$@`/`%d` via the existing
  `L10n.format` bridge — unchanged.

## Truncation / wrapping parity

`lineLimit` distribution mirrors 原 `maxLines` per file
(CourseTableView 13↔13, ConflictCard 5↔5, SchoolSelect 2↔2, Today 3↔2,
Schedule 2↔1, PillNavBar 2↔1, CourseDetailSheet 2↔2). One gap fixed:
preview append-conflict button now `lineLimit(1)` (Android maxLines=1);
other apply buttons already single-line via `PrimaryDialogButton`.
Long-locale wrap behavior: SwiftUI default wrapping matches Android
default (wrap), no forced single-line spots beyond the audited ones.

## Accessibility label parity

原 `contentDescription` sweep over `ui/` (72 usages, mostly
decorative `= null`). Meaningful ones mapped to iOS `accessibilityLabel`:

- Schedule toolbar: `schedule_switch_table`, `schedule_undo`,
  `schedule_add_course`, `schedule_share_table` (WeekNavButton gains
  optional `a11yLabel`; chevron arrows stay identifier-only, matching
  Android's null contentDescription).
- `TimeSlotEditor` delete → `delete_period`; `SmartPeriodEditor` break
  close → `delete`; `AllTables` duplicate → `all_tables_duplicate`,
  settings → `action_settings`, topbar back → `back`;
  `Export` pick-table chevron → `export_pick_table`; `License` expand
  chevrons → `collapse`/`expand` (Android literal); `DatePickerField`
  calendar → `select_date`.

## Known iOS deviations (documented, not shipped)

- `AddCourseScreen` delete-slot icon lacks a `delete_slot` label — file
  carries the user's uncommitted work; left untouched per worktree
  preservation rule.
- VoiceOver/TalkBack behavioral differences (focus order, rotor) are
  platform-level, not parity targets.
- Locale-specific punctuation/dash rendering differences (e.g. es "—")
  inherit SF vs Roboto metrics; no truncation failures found in audit.

## Verification

- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build`
  → **BUILD SUCCEEDED** (after all P3 edits, incl. one brace restore in
  SmartPeriodEditor caught by the build).
- `rg 'onTapGesture|TODO|FIXME' Sleepy/ui Sleepy/theme` → 0 hits;
  `git diff --check` clean.
- Key-parity script result: 0 missing across 5 locales.


