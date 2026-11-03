# Root navigation / dock — original 1.0.51 parity

## Comparison
- Compared `Sleepy/SleepyApp.swift` with 原 `MainActivity.kt` and its `AppRoot`/`MainTabs` flow.
- Four root tabs, selected-tab state, docked/floating navigation modes, status-bar handling, and floating scroll clearance are already aligned.
- Overlay navigation covers add/edit course, tables, appearance, general settings, holiday, export, reminder, about, and license flows.
- Back handling preserves the Android layering: dismiss the active overlay/edit session first, return from secondary tabs to Schedule, then require a second back action to exit.
- URL routing covers course deep links and pending import text, with import completion returning to Schedule.

## Scope
- No source change was required in `Sleepy/SleepyApp.swift`; the implementation was already present in prior root/dock parity commits.
- The shared `PillNavigationBar` docked-background correction is recorded in `docs/sleepy-ios-ui-1.0.51-slice-1.md`.
- Unrelated worktree changes, screenshots, localization files, and `xcuserdata` were not touched.

## Verification
- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` → ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` → 0 hits
- `git diff --check` → clean

## Matrix
- Root navigation / dock changed from `in-progress` to `verified` after source comparison and build verification.
