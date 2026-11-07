# 系统取色与主题动效冻结交接

## 状态

源码接线与新增测试已写入，待主会话收录并执行线上 CI。未在本机编译、运行测试或模拟器；未派代理、提交、推送。静态 `git diff --check` 无空白错误；这不是编译或运行验证。

本轮没有发现阻止实现 30 槽插值的结构性问题：使用单棵内容树上的 `AnimatableModifier`，120 维 RGBA 向量，未用主题 `.id` 或双树 crossfade。实际中断连续性、视觉效果与状态保留仍须 CI/原生验收。

## 实际文件

### 新增生产源码

| 路径 | 内容 | target |
| --- | --- | --- |
| `Sleepy/theme/SystemColorSeed.swift` | 版本化 seed/snapshot、独立 defaults key、环境值 | Sleepy、SleepyWidget、SleepyWatch、SleepyWatchWidgets |
| `Sleepy/theme/SystemColorScheme.swift` | 统一 HSV/M3 角色解析、对比度修正、sRGB ARGB | 同上四个 target |
| `Sleepy/theme/SystemColorProbe.swift` | own-window 采样、直接 window 子视图传感器、key/active 去重发布 | 仅 Sleepy 有效代码 |
| `Sleepy/theme/ThemeColorVector.swift` | 30 槽插值、根布局颜色消费者 | 仅 Sleepy 有效代码 |

后两文件整文件以 `#if os(iOS) && !WIDGET_EXT && !WATCH_APP` 隔离。`Theme.swift` 中 `SleepyMotionPolicy` 与插值器引用使用同一守卫，Widget/watch 走直接 environment 注入。可以给后两文件只收录 Sleepy；若按 project.yml 扫全 theme，其他 target 也会编译成空文件，无需引入 ui/component。

截至本轮收口读取，`.pbxproj` 尚无上述四文件及下述三测试的 membership。主会话集中处理工程，本文作者未修改 `.pbxproj` 或 `project.yml`。AppGroupResolver 已在四个生产 target；新增 seed store 使用现有 resolver，不依赖 AppPrefs 通知。

### 修改生产源码

- `Sleepy/theme/CustomSchemeDeriver.swift`：系统种子重用原模板算法，合法灰度保持中性；原自定义入口行为保留。
- `Sleepy/theme/Theme.swift`：统一 system resolver、普通按压、稳定主题插值；非 App target 无动效策略依赖。
- `Sleepy/SleepyApp.swift`：仅本轮的 AppRoot／PresentOverlay 区域：窗口局部 snapshot/probe、sheet 环境、原生 Tab tint、平板背景消费者、底页 forward/pop、自绘 tab/右栏宿主。QuickAdd/onAddAt 回调保留。顶部 WindowGroup/AppDelegate 的 Debug 修改属于 main。
- `Sleepy/ui/screen/mine/AppearanceScreen.swift`：SystemThemeCard 来源说明及明确 fallback。
- `Sleepy/util/CourseColorWriteGlue.swift`：system anchor 同源解析；仅原有显式操作读取，采样器不订阅或触发课程 DB 重算。
- `Sleepy/widget/WidgetContent.swift`、`WidgetBackgroundCompat.swift`：区分 fullColor/accented/vibrant；纯模式枚举放在共享 WidgetContent，UIKit/WidgetKit 模式转换留在 watch 排除的 Compat 文件。
- `Sleepy/widget/TodayWidgetView.swift`、`TwoDayWidgetView.swift`、`WeekViewWidgetView.swift`、`WeekListWidgetView.swift`、`WeekGridWidgetView.swift`：真实模式和实时 contrast 参数转接。WeekGrid 小档复用 Today 入口的探测；大档传到 WeekGridBody。
- `Sleepy/ui/component/CourseTableView.swift`：网格拖课按钮 `SleepyButtonStyle(dragSource: true)`。
- `Sleepy/ui/component/ConflictCard.swift`：仅前景可拖课程卡传 `dragSource: true`，不影响沉底切换按钮。两处是当前 `CourseDragSource` 实际挂载点。

## 测试与 CI 契约

新增文件收录 **SleepyTests**，执行但不要替换既有测试：

| 文件 | 验证契约 |
| --- | --- |
| `SleepyTests/SystemColorTests.swift` | 快照编码/版本/来源/损坏拒绝，合法灰度，透明/非有限拒绝，独立存储 key，预设/自定义隔离；9 种 seed × 深浅 × 对比度的文本角色及全部 surface containers；同快照 App/全彩 Widget/课程 anchor 一致；accented/vibrant 身份保留 |
| `SleepyTests/SystemColorProbeTests.swift` | 两窗口与 child tint 隔离、dimming 保留、移除/停止/透明色回落、动态色 trait、P3→sRGB；active key 所有权、foreground 重采样及共享去重 |
| `SleepyTests/ThemeColorInterpolationTests.swift` | 独立 30 角色 keypath 校验端点/中点/alpha；向量 zero/中断重定向数学；Reduce Motion 强制终值；动态 UIColor 明暗/contrast；UIHostingController 中切主题/深浅/系统种子/版本 token 后 State token 与未保存文本保留、onAppear 一次 |

active-window 用例需要宿主有 foregroundActive UIWindowScene；不满足时明确 XCTSkip，必须把这个缺口列入 CI 报告，不能视为生命周期已验证。插值数学用例不等于真实逐帧中断验收。

同时运行既有 `CustomThemeTests`、`WidgetThemeModeTests`、`WidgetGlassModeTests`（如当前 suite 中存在）、`CourseColorWriteGlueTests`、`CourseColorCommitBoundaryTests` 和动效切片的 `SleepyMotionPolicyTests`。构建四个生产 target，确认 Debug/Release 的 WIDGET_EXT/WATCH_APP 条件均有效，保留 iOS 15.6 / watchOS 10 deployment。

原生验收：预设切换、编辑同 ID 自定义主题、系统 seed 更新、深浅/增加对比度切换、动画中途反转与 Reduce Motion 中途开启；检查输入焦点/导航/滚动状态。检查 tab/右栏快速切换、overlay forward/pop、两种拖课卡长按起点与 QuickAdd 手柄；Widget fullColor/accented/vibrant 分别验收。当前测试没有证明所有真实导航和焦点场景。

## localization 交 main

| key | 中文建议 | English |
| --- | --- | --- |
| `theme_system_source_window_tint` | 配色来源：当前窗口强调色（非主屏幕或壁纸颜色） | Color source: current window tint (not Home Screen or wallpaper colors) |
| `theme_system_source_fallback` | 未取得有效窗口颜色，使用默认配色；深浅外观按外观设置跟随 | No valid window color is available. Using default colors; light and dark follow your appearance setting. |

缺 key 时 SystemThemeCard 有上述中文兜底，不显示 key 本身；完整多语言由 main 收录。旧 `theme_system_desc` 本卡不再使用，其他资源维护由 main 处理。

## 数据与能力边界

- 存储 key：`system_color_snapshot_v1`。schemaVersion=1，algorithmVersion=1；source 只有 windowTint/fallback，opaque 8-bit sRGB。窗口本地值不会被其他窗口共享快照覆盖；只有 foregroundActive key window 可发布共享值。
- App Group 不可用时存入本进程 standard defaults，不能承诺跨进程可见；watch 目前没有新增 iPhone seed 的 WatchConnectivity 同步，缺快照走明确 fallback。
- 没有已核实的公开当前壁纸／主屏幕图标着色 RGB getter。窗口 tint 不是这些能力的替代承诺；未使用私有 API，未替换成 HCT。
- 对比度阈值适用于派生完成的 system 终值：普通文字目标 4.5:1、增加对比度 7:1；不声称插值途中每帧、课程自定义色或宿主重新着色后的 Widget 也满足同一数值。
- Widget 的 `isGlass` 仅兼容旧“禁止课程色覆盖”调用，真实身份看 renderingMode。宿主模式不生成 seed，Widget 也不采样反写。
- App/Widget/anchor 同源指同一 snapshot、有效深浅和 contrast 下同一派生入口；动画中的 App 当前显示值不作为持久化课程 anchor。
- 现有 overlay 非 nil 路由直接切到另一非 nil 路由的额外过渡不属于本次底页接线；采用动效切片已有宿主契约。
