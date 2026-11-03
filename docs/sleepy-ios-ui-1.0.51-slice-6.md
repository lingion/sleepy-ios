# Slice 6 — Schedule 对齐原实现 1.0.51

## What
- 顶栏周导航改 `ZStack` 居中:翻页箭头紧贴 `WeekNavButton` 胶囊,左右各一组操作区(`WeekNavButton` 圆底,32dp+6dp)。学期外标签 `<status> · 第 N 周`。
- 顶栏 logo 弹 `TableSwitcherSheet`:滚动列表,当前行 `primaryContainer` 高亮 + ✓ 对勾。
- 第 N 周 胶囊改为原生 `Button`:在当前周 → `Picker(.wheel)` 弹层跳周;不在当前周 → 一键跳回实际周(等同 原 `FlowRow DropdownMenu`)。
- 撤回到 `UndoManager.hasSnapshot` 真值驱动:无可撤回快照不显示按钮(布局仍稳)。
- `WeekPager` 灰显星期缓存从单周 `[Int]` 升到 per-week `[Int: Set<Int>]`,`.task(id:)` 一并刷新,语义等价 原 `produceState(greyDays, page, startDate)`。
- `ViewModel`:`initialWeekSettled` 防止课程变更覆盖用户已选周;`changeWeek` 加 `maxWeek` 上界(选周 picker 越界保护);`createEmptyTable` 同步补入内存表,EditTableScreen 立刻可见。
- `viewMode` 用 `AppPrefs.getStartView()` 初始化,顶部切换仍只改本地页面状态(对齐 原 `AppPrefs.startView` 语义)。

## Why
- 原 `ScheduleScreen.kt` 的 `TopBar` 用 `Box` 叠加实现全宽正中,旧 iOS 用 `Spacer` 推导致视觉偏移;ZStack 后居中干净。
- 灰显星期只对当前周生效会让相邻周页回弹到空白,原实现已按页缓存;iOS 同步才能贴合手势。
- 原 `ViewModel` 在首次加载后保留用户周次,旧 iOS 每次课表数据变更都会重置;镜像后课程编辑不会再“跳回本周”。
- 原 `createEmptyTable(commitSelection = true)` 是同步插入;iOS 旧版异步等 observe,EditTableScreen 打开会找不到新表。

## Files touched
- `Sleepy/ui/screen/schedule/ScheduleScreen.swift`
- `Sleepy/ui/screen/schedule/ScheduleViewModel.swift`
- `docs/sleepy-ios-ui-1.0.51-slice-6.md`(本报告)
- `docs/sleepy-ios-ui-1.0.51-matrix.md`(Schedule 行状态)

## Verification
- `xcodebuild -scheme Sleepy -destination 'generic/platform=iOS' build` → ** BUILD SUCCEEDED **
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui` → 0 hits(整体 + Schedule 范围)
- `git diff --check` → 无空白错误
- 阶段构建告警只剩 Xcode 16 `traditional headermap style` 与无关的 Apple Developer Portal 1100 session 信息;与 Schedule 对齐无关。

## Scope
仅 Schedule 表面。`Sleepy.xcodeproj/xcuserdata/**`、其他 Slice 的脏文件、audit_shots、`util/AppPrefs.swift` 等无关改动一律不动。

## Known remaining work
- P0 根导航、P0 Today、P0 Mine、P1 Manage、P1 冲突卡片、P1 分段切换器、P1 All Tables/Edit Table、P1 General Settings、P1 Import flow、P2 关于/许可/导出/分享/假日/提醒、P2 共享 sheet/编辑器、P3 本地化压力测试,均仍在 matrix 中。Schedule 行已可验证 → `verified`。
