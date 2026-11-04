# v1.0.63 系统动效切片交接

## 证据与验证边界

- 已读 `docs/undo-wakeup-motion-v1063-review.md`，并读取 Android `git diff v1.0.62..v1.0.63` 的 `SleepyMotion.kt`、`SleepyMaterialTransition.kt`、`NoRippleClickable.kt`、`Theme.kt`、`MainActivity.kt`、`SleepyNavHost.kt`、`PillNavigationBar.kt`、`TimeSlotEditor.kt`、`PeriodTableEditScreen.kt`。
- popup 起止缩放 0.8、content 0.92、普通 press 0.98 来自实际 tag diff。SwiftUI 空间 spring 与 effects 分开；response 0.30/0.42、damping 0.7/0.8 是 iOS 原生近似参数，不宣称与 Compose 的 stiffness 逐帧相同。
- 本机未编译、运行 XCTest 或模拟器；未派代理、提交、推送。以下“接入”仅指源码消费者已连接，视觉及交互验收归线上 CI/主会话。

## 已连接的消费者

| 文件 | 实际变化 |
| --- | --- |
| `Sleepy/ui/component/SleepyMotion.swift` | `SleepyMotionPolicy` 统一 popup/content/expand/press；空间与透明度分相；`SleepyPopup` 保留显隐宿主；`SleepyMotionButtonStyle` 支持 disabled/dragSource 例外并保持矩形命中域。 |
| `Sleepy/ui/nav/SleepyMaterialTransition.swift` | 已被 `PresentOverlay` 使用的 forward 入口改为 content 家族。pop/predictive 不再使用旧 identity/固定 tween；保留旧 API 名以兼容当前宿主。这里只改变覆盖页一侧，底页仍须下文接线。 |
| `Sleepy/ui/component/PillNavigationBar.swift` | 贴底与悬浮两个 badge 都接 popup。普通按钮改为实际可见 VStack 作 label，0.98 能缩到图标文字，而不是只缩透明命中面；thumb 保留旧 spring 并尊重 Reduce Motion。 |
| `Sleepy/ui/component/NavigationRailBar.swift` | 普通项与组合项切换接 content，徽标接 popup，按钮接 press，组合项状态色接 fastEffects。 |
| `Sleepy/ui/component/NativeBaselineSlider.swift` | ghost 缩放以真实拇指为中心，透明度分开；nil/靠近基线退场保留最后位置；generation 防旧完成回调隐藏新基线；不增加触摸识别器；原生 slider 几何保留。 |
| `Sleepy/ui/component/QuickAddCourse.swift` | 胶囊显隐接 popup；只有 selection 是否为空触发动画，调整节次边界仍直接跟手。退出立即关闭命中/无障碍访问。 |
| `Sleepy/ui/screen/mine/PeriodTableEditScreen.swift` | 展开实际高度与淡入淡出分相，箭头 defaultSpatial，增删行的宿主空间按 defaultSpatial 改变；删除/保存数据路径不变。 |
| `Sleepy/ui/screen/schedule/ScheduleScreen.swift` | 追加授权后接入 undo/redo 胶囊 popup；宿主持久存在，退场立即关闭命中/无障碍访问；6pt 间距随内容移除，隐藏不占空槽。 |
| `Sleepy/ui/component/TimeSlotEditor.swift` | 追加授权后接入手动作息行 expand 过渡与行数驱动的空间变化；空白行 secondaryContainer / 完整行 surface 使用 defaultEffects 渐变，动画限定于背景。 |

Reduce Motion：popup/content 缩放=1，press=1，空间动画=nil，thumb=nil，SwiftUI 保留 0.1s 短淡入淡出。UIKit ghost 在减少动态效果开启或尚未进入窗口时直接落到终态。

## 跨切片接线与追加授权收口

### 1. `SleepyApp.swift`：底页与自绘 tab / 右栏

此文件明确禁改，因此本切片未编辑。可直接消费已写在 `SleepyNavHost.swift` 的两个独立组件：

```swift
// PresentOverlay.body 的 ZStack 中，只替换原 content 那一行：
content.modifier(SleepyNavigationUnderlay(covered: shownScreen != nil))

// AppRoot.tabContent：
SleepyNavigationContent(selection: root.currentTab) { tab in
    screen(for: tab)
}
```

`tabletRightPane` 把原 `Group { switch tab ... }` 包进 `SleepyNavigationContent(selection: tabletRightTab) { tab in ... }`，删除原末尾 `.id(tab).transition(.opacity).animation(.easeInOut(duration: 0.2), value: tab)` 三行。原生 TabView 分支不用此宿主。

底页 modifier 维持内容树身份，covered=true 缩小淡出并禁命中/隐藏 VoiceOver，covered=false 同步淡入放大；不应以 if 移除底页，否则滚动/表单状态会丢。调用点必须用 `shownScreen`，不能用更早改变的外部 `overlayScreen`。现有直接从非 nil 路由换另一个路由仍无过渡；如要覆盖这一路，单独为 overlayContent 加稳定路由 identity 和容器级动画，并检查编辑页已有 `.id(CourseEditorIdentity)`。

### 2. `Theme.swift`：全局普通按钮

虽然任务允许 SleepyButtonStyle 所在文件，但又明确禁止 Theme.swift；实际定义就在该文件 241 行附近，因此未改。请所有者给 `SleepyButtonStyle` 加 `accessibilityReduceMotion` / `isEnabled` 环境与默认 `dragSource=false`，沿用其 `contentShape(Rectangle())`，scale 使用：

```swift
motion.pressScale(pressed: configuration.isPressed,
                  enabled: isEnabled, dragSource: dragSource)
```

opacity/animation 可复用本切片 `SleepyMotionButtonStyle` 的实现。先检查所有课程长按拖动起点：使用 `SleepyButtonStyle(dragSource: true)` 或维持其现有 `.plain`，不要全局自动缩放长按拖起表面。新的独立 style 当前已实际消费于 pill/rail；并非全局按压已完成。

### 3. `ScheduleScreen.swift`：undo 胶囊（已完成源码接线）

主会话追加独占授权后，实际挂载点已改为 `SleepyPopup(visible: hasUndoSnapshot || hasRedoSnapshot)`；宿主留在原左操作区 HStack，内部传入原 `UndoRedoCapsule` 全部参数。左操作区改为零 stack spacing，胶囊和 tick 各在自身内容上保留 leading 6pt，避免隐藏 popup 宿主留下额外间距。undo/redo 禁用状态、挤压比例、accessibilityIdentifier 保留。

### 4. `TimeSlotEditor.swift`：逐行入场和行颜色（已完成源码接线）

主会话追加独占授权后，`ManualTimeSlotEditor` 的 `TimeSlotRowItem(...)` 已加 `.transition(motion.expand)`，直接持有 ForEach 的 VStack 加 `.animation(motion.defaultSpatial, value: rows.count)`；新增尾行入场、删除后空间收拢沿用现有 node identity，时间编辑不触发全行重建。

行底色为 `isBlank ? secondaryContainer : surface`，只在 RoundedRectangle 背景上按 isBlank 驱动 defaultEffects。空白判定与页面缺时提示一致：任一起止时间去空白后为空。Reduce Motion 下行空间动画 nil、过渡仅短透明度，底色保留短 effects。当前 iOS 尚无排序状态，因此不宣称已补 settle/cancel/invalid return/elevation 0↔6。长按排序是前置旧缺口，不是本次 Android 新增。

## 主题逐色槽渐变：转交系统取色负责人

精确挂载点是 `SleepyThemeProvider.body` 最后的 `.environment(\.localWakeUpColors, wakeColors)`。原有 preset/custom/system 解析不动，改为一个稳定的 `AnimatableModifier`，把中间插值 scheme 逐帧重新注入同一个 content；禁止 Crossfade 两棵树或 `.id(themeKey)`。

当前 iOS `WakeUpColorScheme` 有 **30** 个 Color 存储槽，不是 Android 的48：

1. primary/onPrimary/primaryContainer/onPrimaryContainer
2. secondary/onSecondary/secondaryContainer/onSecondaryContainer
3. tertiary/onTertiary/tertiaryContainer/onTertiaryContainer
4. background/onBackground/surface/onSurface/surfaceVariant/onSurfaceVariant
5. surfaceContainerLowest/surfaceContainerLow/surfaceContainer/surfaceContainerHigh/surfaceContainerHighest
6. outline/outlineVariant/scrim/error/onError/errorContainer/onErrorContainer

建议以固定顺序120个 RGBA分量组成 `VectorArithmetic`（30×4），作为 modifier 的 animatableData，再重建全量30槽 scheme；动画用本切片 `SleepyMotionPolicy.defaultEffects`。动态 UIColor 在读取端点时按明确 light/dark trait resolve，避免两端都被当前 trait 重解释。不要只在 themeKey 变更时重算：darkTheme、自定义同 id 的 customThemeVersion、系统种子更新也须驱动新目标 vector。中途改色由 SwiftUI 当前 presentation vector 接续，不用定时器从旧目标重播。

Android 额外18槽（inversePrimary、surfaceTint、inverseSurface、inverseOnSurface、surfaceBright、surfaceDim，以及 primary/secondary/tertiary 各四个 fixed 槽）当前无 iOS 对应字段；此次只插值已有槽，不虚构48槽覆盖。课程 palette 是独立 environment，Android 该 diff 也没插值它。

建议验证：每个槽终值等于目标；动画中途再切主题连续；切换 themeKey/darkTheme/customThemeVersion 后视图 onAppear 次数和导航/表单 state 不变；Reduce Motion 下无几何动画；系统动态色按指定 trait 解析。

## 新增测试与收录

`SleepyTests/SleepyMotionPolicyTests.swift`：6个待线上执行用例，覆盖 Reduce Motion 空间禁用、disabled/拖动按压例外、ghost 退场位置保留、恢复/减少动态效果终态、原生轨道几何、打断退场后新基线不被旧 completion 隐藏。需主会话注册测试 target；生产修改均在已有文件内。

CI/原生验收重点：快速反复切 tab/开关浮层、overlay 返回目标页、切换 Reduce Motion、QuickAdd 选择后拖手柄、ghost 出现→隐藏→立刻恢复、作息增删行与展开中途反转、徽标和 undo 退场后不拦点击。不要用本切片的静态检查替代这些运行证据。

## 冻结状态

追加两文件的消费者接线已完成，既有测试文件及断言未改。新增动效测试仍为前片的6项，全部待线上执行。此次只修改 `ScheduleScreen.swift`、`TimeSlotEditor.swift` 与本交接文档；静态 `git diff --check` 无空白错误。全局按钮、主题逐槽插值及 tab/底页挂载由主会话转交 `SleepyApp.swift` / `Theme.swift` 所有者。本代理冻结后不继续编辑。
