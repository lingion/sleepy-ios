# Slice 8: Mine and Manage typography

## What

Aligned the top-level Mine and Manage page typography with original 1.0.51 Material 3 roles:

- Mine title uses `headlineMedium` at 28pt.
- Manage title uses `headlineMedium` at 28pt with medium weight.
- Manage current-table name uses `titleLarge` at 22pt with semibold weight.

## Why

The existing iOS titles were smaller than the Android baseline, and the Manage current-table name did not match the 原 `titleLarge` scale. This slice applies only the confirmed typography deltas; the matrix keeps both screens `in-progress` until their remaining screen-level differences are addressed.

## Evidence

- Original source: `app/src/main/java/com/lingion/sleepy/ui/screen/mine/MineScreen.kt`
- Original source: `app/src/main/java/com/lingion/sleepy/ui/screen/manage/ManagementPage.kt`
- iOS sources: `Sleepy/ui/screen/mine/MineScreen.swift`, `Sleepy/ui/screen/manage/ManagementPage.swift`
- `git diff --check`: passed
- Generic iOS build: `BUILD SUCCEEDED`

## Known remaining work

Mine and Manage remain `in-progress` in `docs/sleepy-ios-ui-1.0.51-matrix.md`. Full section hierarchy, controls, icons, action semantics, and screen-level parity still require comparison and verification.
