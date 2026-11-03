# Slice 9: Theme alignment

## What

Aligned the shared iOS theme contract with original 1.0.51:

- Default light `surface` now matches 原 `background` (`#FEF7FF`).
- Default dark color roles now match `DarkScheme` from original 1.0.51.
- Shared Swift M3 typography constants now use the 原 baseline sizes for `displaySmall`, `headlineMedium`, and `titleLarge`.
- `SleepyShapes.extraLarge` now matches Android's 28dp `extraLarge` shape.
- Existing Spring, Ocean, Peach, and Slate presets were compared with 原 `ThemePresets.kt` and left unchanged because they already match.

## Evidence

- original sources: `app/src/main/java/com/lingion/sleepy/ui/theme/Theme.kt`, `ThemePresets.kt`, `app/src/main/res/values/colors.xml`
- iOS sources: `Sleepy/theme/Theme.swift`, `Sleepy/theme/ThemePresets.swift`
- `git diff --check`: passed
- Generic iOS build: `** BUILD SUCCEEDED **`

## Scope

Only `Sleepy/theme/Theme.swift` and the alignment documentation were changed for this slice. Existing custom theme behavior and unrelated worktree changes were preserved.
