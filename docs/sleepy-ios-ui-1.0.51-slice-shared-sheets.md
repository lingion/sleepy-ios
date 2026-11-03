# Slice — Shared sheets/editors parity

## Comparison

Compared `CourseDetailSheet.swift`, `DateTimePickers.swift`,
`SmartPeriodEditor.swift`, `TimeSlotEditor.swift`, `SettingsCards.swift`
against original 1.0.51 sources (`ui/component/*.kt`).

## Implemented

### CourseDetailSheet

- Conflict cluster key routed through
  `ConflictLayoutEngine.conflictClusterKey` — same source as
  ConflictClusterCard / topOverrides (was a locally re-derived
  `day:startNode:step` string).
- `DefaultTopPickerSection` geometry to the original platform values: group spacing 2,
  title padding top/bottom 4, row spacing 4, row vertical padding 4,
  radio icon 20pt.
- Edit button fixed 40pt height (M3 Button 40dp).
- Header xmark kept — documented iOS adaptation; 3 XCUITests anchor
  `detail_close`.

### TimePickerField

- Label restacked to the readOnly-TextField form: empty value = 16pt
  label placeholder; filled = 12pt label above 16pt value (M3 floating
  label, filled variant).
- New `fillsWidth` parameter for 原 `weight(1f)` /
  `fillMaxWidth()` call sites; `DatePickerField` unchanged.
- AddCourse's two clock fields keep the default (that row is verified
  and Android AddCourse was not re-derived here).

### SmartPeriodEditor

- `NumberField` ports the M3 filled TextField: floating label (12pt
  above the value when a label exists) and the unit suffix inside the
  field at 16pt onSurfaceVariant (was an external 12pt caption).
- `AddBreakChip` label 12→14pt (FilterChip labelLarge).
- Empty preview placeholder 12→16pt (原 passes no style →
  bodyLarge).
- Break-group delete icon button 28×28 (IconButton 28dp).

### TimeSlotEditor

- Add-period label 14pt (TextButton labelLarge); row fields fill width;
  delete icon button 32×32 (IconButton 32dp).

### SettingsCards

- Verified no drift: `SectionHeader`, `SettingsCard`, `DisplayModeOption`,
  `SettingToggleRow`, `SettingsFlatCard` all match; Android's
  `subtitle`/`content` parameters on `SettingsFlatCard` are used by no
  原 call site, so the iOS shape is complete.
- Whole-card tap area on `SettingsCard` stays header-only (documented
  iOS adaptation consistent with the verified Appearance/General rows).

## M3 filled-TextField height (documented adaptation)

Android M3 filled TextField has a 56dp minimum height. iOS field
components across the app use ~36–50pt natural heights; replicating
56dp only here would break consistency with the already-verified
screens that embed these fields, so heights stay as-is.

## Verification

- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build`
  -> ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` -> 0 hits
- `git diff --check` -> clean
- Commit `aed4863` (code) — author lingion@hrbeu.edu.cn, no Claude
  trailer.

## Scope

Files touched: the four component files above. No strings, no parser,
DAO, repository, widget, or preference-default changes. Unrelated dirty
work (AddCourseScreen, AppPrefs, SwipeBackGestureUITests, user strings
lines, audit_shots, classic-eams docs) remains uncommitted.
