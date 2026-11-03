# Slice — Mine and Manage parity

## Comparison

Compared the iOS Mine and Manage surfaces with original 1.0.51:

- Mine uses the same 16-point scrolling layout, headline/subtitle hierarchy, three-column statistics card, six settings destinations, and full-width widget-refresh action.
- Statistics use table count, distinct course-name count, and current week, with the same 18/8 card padding, vertical separators, colors, and typography.
- Settings rows use the same 40-point icon container, primary-container icon treatment, 16/14 row padding, separators, and semantic buttons.
- Manage uses the same page title, current-table summary card, four management cards (import, new table, manual add, edit current), 12-point card spacing, and 16-point content padding.
- Import-sheet presentation routes JW import, dismissal, import completion, and edit-table opening through the same callbacks.
- Both screens provide floating-dock bottom clearance through the local navigation environment value.

## Scope

No source change was required for these two surfaces; their existing SwiftUI implementation already reflects the original 1.0.51 behavior. Only this report and the Mine/Manage matrix rows are included. Existing General Settings, localization, import-flow, screenshots, tests, and preference changes remain outside this slice.

## Verification

- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` -> ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` -> 0 hits
- `git diff --check` -> clean
