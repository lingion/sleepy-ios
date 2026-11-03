# Slice — Today parity

## Comparison

Compared `Sleepy/ui/screen/today/TodayScreen.swift` with original 1.0.51 `ui/screen/today/TodayScreen.kt`.

The implementations are aligned for the current 1.0.51 surface:

- Both derive the current day and actual semester week from the timetable start date.
- Both suppress course filtering outside the semester and show the matching before-start/after-end empty-state copy.
- Both use the same conflict lane grouping, full-width single-course rows, side-by-side conflict lanes, 6-point lane spacing, and hairline separators.
- Both provide the same header hierarchy, week/course stat chips, 16-point page padding, and extra bottom clearance for the floating dock.
- Both open the shared course detail sheet and route edit back to the root editor.
- Both use the shared palette-based course color resolver, adaptive foreground color, fixed 76-point time column, two-line course title, and teacher/room metadata.

## Scope

No source change was required. The existing SwiftUI implementation already contains the original 1.0.51 behavior from prior parity work. Only this report and the Today row in the alignment matrix are included.

## Verification

- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` -> ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` -> 0 hits
- `git diff --check` -> clean

## Remaining work

Other matrix rows remain pending or in-progress and require their own source comparisons and verification slices.
