# Slice — Appearance and General Settings parity

## Comparison

Compared `Sleepy/ui/screen/mine/AppearanceScreen.swift` and
`Sleepy/ui/screen/mine/GeneralSettingsScreen.swift` against original 1.0.51.

### Appearance

The iOS Appearance surface already mirrors original 1.0.51:

- Theme preset cards in a two-column grid.
- Three-state theme mode selector (system / light / dark).
- WidgetCenter reload on save.
- Same color roles, typography, and 16/14 row spacing.

No source change was required.

### General Settings

Three 原 `SettingsFlatCard` title-row segmented selectors map to a new
iOS `SettingsFlatCard` component (`Sleepy/ui/component/SettingsCards.swift`):

- Display mode (`node` / `time`).
- Grid sub-information (`room` / `teacher` / `none`).
- Start view (`full` / `cards`).

The 原 flat title-plus-switch row for “course colorless” now maps to a
single `HStack` with the title on the left and a native `Toggle` on the
right, on the same `surfaceContainer` block and 16/14 padding.

The 原 `settings_pill` controls (grid scale, week scale, grid corner
ratio, week two-column, week two-column mode, week hide-empty-days) have no
iOS preference or rendering contract; they remain out of scope for this
presentation-only alignment and are recorded as a known iOS gap.

## Verification

- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` -> ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` -> 0 hits
- `git diff --check` -> clean

## Scope

Files touched:

- `Sleepy/ui/component/SettingsCards.swift` — new `SettingsFlatCard`.
- `Sleepy/ui/screen/mine/GeneralSettingsScreen.swift` — three `SettingsCard` selectors
  replaced with `SettingsFlatCard`; course-colorless card flattened; preserved
  `startView` preference support, `navFloating` naming, picker ordering for
  docked/floating, and native visible-day `Toggle` accessibility handling.

No parser, DAO, repository, widget, or preference-default changes were
included. Existing unrelated dirty work remains in the worktree.
