# Slice 1 — 共享组件原生化收口

## What
- `Sleepy/ui/component/PillNavigationBar.swift`:Docked 底栏背景去掉 `.ignoresSafeArea(edges: .bottom)`,等价 原 `Box.background(colors.surfaceContainer)` —— 内容画到底但下边不再外溢到手势条外。
- `Sleepy/ui/component/SegmentedSwitcher.swift`:分段点击段补 `.accessibilityLabel(pair.1)` 与 `.accessibilityAddTraits(.isSelected)`,选中态可被旁白读出,语义与 Kotlin `Role.Button` 对齐。
- `Sleepy/ui/component/ConflictCard.swift`:FOLD/STACK/RAIL 命中区(FOLD 端态隐藏沉底卡、STACK 折角 switch 区、pick 弹层每行)全部从 `Color.clear.onTapGesture` 改为 `Button { … }.buttonStyle(SleepyButtonStyle())`,保留命中矩形与 `switchTap` 语义。

## Why
- 原 `PillNavigationBar.kt` Docked 分支只 `background(colors.surfaceContainer)`,不延伸到底栏外;iOS 旧版 `ignoresSafeArea(.bottom)` 会把表面色延伸到手势条下面,贴底 tab 视觉像"漂"在屏幕外。
- 选中态可访问性是合规底线:原 `Role.Tab + selected = isSel` 一行对齐,iOS 必须用 `.accessibilityAddTraits(.isSelected)` 才能在 VoiceOver 中读出"已选中"。
- `onTapGesture` 不属于语义控件,Markdown 矩阵中所有命中区都要走 `Button`,其它 Slice 已经按这条线收口,本 Slice 把剩下的几处一并补齐。

## Files touched
- `Sleepy/ui/component/PillNavigationBar.swift`
- `Sleepy/ui/component/SegmentedSwitcher.swift`
- `Sleepy/ui/component/ConflictCard.swift`
- `docs/sleepy-ios-ui-1.0.51-slice-1.md`(本报告)
- `docs/sleepy-ios-ui-1.0.51-matrix.md`(Root navigation / Conflict card / Segmented switcher 行状态)

## Verification
- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` → ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` → 0 hits
- `git diff --check` → 无空白错误
- 仅出现与本 Slice 无关的 Xcode 16 `traditional headermap style` 警告与 Developer Portal 1100 会话过期,与共享组件无关

## Scope
仅三个共享组件。其它脏文件(`SleepyApp.swift` / `AddCourseScreen.swift` / `JwImportFlow.swift` / `AllTablesScreen.swift` / `EditTableScreen.swift` / `GeneralSettingsScreen.swift` / `AppPrefs.swift` / 本地化字符串 / audit_shots / `xcuserdata`)一律不动。
