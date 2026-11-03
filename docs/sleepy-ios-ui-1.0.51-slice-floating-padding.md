# Slice — 悬浮底栏: 镜像 Android LocalNavExtraBottomPadding

## What
iOS 端把全局 `safeAreaInset` 给的内容底部余量移除,改成与 原 `LocalNavExtraBottomPadding` 一字对齐的契约:

- `Sleepy/theme/Theme.swift` 新增 `localNavExtraBottomPadding: CGFloat` EnvironmentKey,默认 0。
- `Sleepy/SleepyApp.swift` 的 `floatingTabs` 注入 `.environment(\.localNavExtraBottomPadding, floatingScrollBottomPadding)`,`floatingScrollBottomPadding = = capsuleHeight + bottomFloat + 12`(FAB 余量,与 原 `navHeight + fabPadding + WindowInsets.navigationBars` 同位)。
- 四个 scroll 容器各自读 `@Environment(\.localNavExtraBottomPadding)`,在已有内容 padding 之后追加 `.padding(.bottom, navExtra)` / `Color.clear.frame(height: navExtra)`:
  - `Sleepy/ui/screen/mine/MineScreen.swift`
  - `Sleepy/ui/screen/manage/ManagementPage.swift`
  - `Sleepy/ui/screen/today/TodayScreen.swift`
  - `Sleepy/ui/component/CourseTableView.swift`(`CardsGridView` 与 `FullWeekView` 各一处)
- `docked` 模式下 env 默认 0,等价于"无额外 padding",回归老行为。

## Why
- `safeAreaInset` 会让所有内容(包括非滚动首屏、顶栏、详情 sheet)整体下移 → 悬浮药丸下方的"白条"以及课表页顶部留白都由此产生。
- original 1.0.51 的等价做法是 `MainActivity` 把 `dockExtraDp` 注入 `CompositionLocal(LocalNavExtraBottomPadding)`,各 scroll 容器各自 `padding(bottom = 16.dp + navExtra)`,docked 下为 0 → 内容背景直通屏幕底(浮空),仅滚动末尾获得 FAB 式余量。
- iOS 必须镜像这条契约,这样在 docked/floating 切换、内容首屏/滚动末行、底部 snackbar 等场景下都能与原实现一致。

## Files touched
- `Sleepy/theme/Theme.swift`
- `Sleepy/SleepyApp.swift`
- `Sleepy/ui/screen/mine/MineScreen.swift`
- `Sleepy/ui/screen/manage/ManagementPage.swift`
- `Sleepy/ui/screen/today/TodayScreen.swift`
- `Sleepy/ui/component/CourseTableView.swift`

## Verification
- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` → ** BUILD SUCCEEDED **
- `git diff --check` 无空白错误
- `rg localNavExtraBottomPadding` 命中: 注入 1 处,消费 5 处(`CardsGridView`/`FullWeekView`/`MineScreen`/`ManagementPage`/`TodayScreen`),与 原 `LocalNavExtraBottomPadding` 1 注入 + 4 消费 一字对齐