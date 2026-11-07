# Sleepy iOS 1.0.64 — 功能增删设计（捏合修复 / 小组件引导 / 灵动岛实况活动 / 移除更新检查与调试台）

> 历史草案，不能作为当前实现或验收证据。本文包含已撤回的推断（必然手势竞争失败、4小时无更新失效、16.2可定时启动、本地载荷不受4KB限制）。当前约束与修复记录以 [2026-11-07 审计报告](../qa/2026-11-07-ios-audit-repair.md) 为准。

日期：2026-11-06 ｜ 分支：`feat/ios-1064-pinfix-widgetguide-liveact`（worktree `.worktrees/ios-features-1064`，基线 `5ade83b`）
用户已定调：四项独立落地；测试一律由用户在真机执行，交付侧只做编译验证 + 真机验收清单。

## 1. 范围

| # | 改动 | 类型 |
|---|------|------|
| A | 移除 Debug Console（含 `Sleepy/debug/` 全目录与接线） | 删除 |
| B | 移除获取更新（GitHub Releases 更新检查/自动检查/IPA 下载），App Store 成为唯一分发渠道 | 删除 |
| C | 修复双指捏放调整行高：功能已在 1.0.61 移植落地但默认关闭且实测捏不动（手势竞争嫌疑） | 修复 |
| D | 应用内小组件添加引导：把 Gallery 点卡片的「不支持」死胡同换成真能用的添加指引 | 新增 |
| E | 灵动岛 Live Activity（ActivityKit 实况活动），能力上限在文案与文档中注明 | 新增 |

不做：服务器 push-to-start（纯本地 App 无服务端）；Android 版对应面（流体云等）继续归 parity 矩阵管；`docs/widget-glass-preview.html` 等主 checkout 未提交文件不在本分支动。

## 2. A — 移除 Debug Console

- 删除 `Sleepy/debug/` 9 文件、`SleepyTests/DebugConsoleTests.swift`、`SleepyTests/DebugConsoleCapabilityTests.swift`。
- `SleepyApp.swift`：删 `environmentObject(debugConsole)`（:35）、`lazy var debugConsole`（:53 区段）、`start()/stop()`（:150/:161）。
- `GeneralSettingsScreen.swift`：删 `@EnvironmentObject debugConsole`（:22）、`#if DEBUG` 区（:242-244）、`DebugConsoleSettingsSection` 定义（文件尾部）。
- 已验证 `Sleepy/debug/` 之外无任何对 Console* 符号的引用（grep 全仓）；`project.yml` 的 widget/watch 排除列表中的 `"debug"` 项保留（目录不存在时无副作用，删除反而引入无关 diff 风险）。
- 本地化键 `debug_console*` 等只被 debug/ 使用的条目从 5 个 lproj 删除；实现前先 grep 确认每个键无其他消费方。

## 3. B — 移除获取更新

- 删除 `Sleepy/util/UpdateManager.swift`、`Sleepy/util/UpdateInfo.swift`；测试 `UpdateManagerDownloadFallbackTests.swift`、`UpdateInfoMirrorTests.swift` 整体删除，`VersionAndUpdateTests.swift` 只删更新检查相关用例（保留 prefs/version 通用用例，实现时逐段核对）。
- `AboutScreen.swift`：删更新横幅、`检查更新` 按钮、`checkUpdate()`、1.0.51 自动检查开关区、`about_update_check` 偏好读写。保留：版本号、开源信息、GitHub 仓库主页链接（代码公开渠道）、TestFlight 链接、反馈渠道。
- `SleepyApp.swift`：Mine tab 红点逻辑（`UpdateNotifier.noticeVisible`，:807/:855-857 区段）退化为常隐（无更新渠道即无红点），保留 badge 管道结构供未来使用；若管道失去唯一生产者则一并删除该死代码（实现时以 grep 证据定）。
- `JwImportFlow.swift` / `MineScreen.swift` / `PlatformParityNotes.swift` / `MarkdownBlocks.swift` 中的 `Update*` 引用逐一清除或改写（多为注释与文案引用，实现时给 diff）。
- `SleepyUITests/ButtonHitAreaUITests.swift` 中 about_update 按钮断言删除。
- 本地化键 `about_update*` 从 5 个 lproj 删除；文档同步 `SPEC.md` / `llms.txt` 分发渠道描述（App Store + TestFlight；GitHub 仅代码）。

## 4. C — 捏合修复（用户实测：开关已开仍捏不动）

根因假设（探查证据）：`UIPinchGestureRecognizer` 挂在 `.background(GridPinchResizer)` 的**匿名祖先 view** 上（`CourseTableView.swift:283`）——SwiftUI 层级里该祖先只是背景视图的宿主，大概率不是真正接收课表触摸的 `UIScrollView`，手势从未进入识别链；且无 delegate，与外层纵向 ScrollView / TabView 横向 pager 手势竞争必然失败。

修复设计（保持既有纯函数与提交语义不动）：
- **机制级根因**：hitTest 不命中的 view，其上的识别器永远收不到触摸。现状 pinch 挂在 `.background(GridPinchResizer)` 的宿主 view 上（`CourseTableView.swift:283` `host = superview`），该匿名背景 view 不在滚动内容的 hit 链上 → 识别器永不触发；且无 delegate，即便触发也与外层纵向 ScrollView / 横向 pager 竞争失败。
- 修复方案：`GridPinchResizeUIView` 保持 `isUserInteractionEnabled = false`（不吞触摸）；`syncGesture()` 沿 superview 链查找第一个 `UIScrollView`，把 pinch 挂到该 scroll view（真实触摸链祖先，对内部任何落点生效；找不到则退回现 superview 行为，保证不退化）。重挂时机 = `didMoveToWindow` + `didMoveToSuperview`。实现 `UIGestureRecognizerDelegate.shouldRecognizeSimultaneouslyWith` 恒真（与滚动/pager 并存；单指点击/滚动靠 `cancelsTouchesInView = false` 保持现状不受影响）。坐标基准 = 挂指 view 自身（`location(ofTouch:in: g.view!)`；`verticalSpan` 为平移不变量，坐标系切换不影响算法）。Android consume 屏蔽 pager 的平台偏差注释同步改写为 iOS 语义。
- 默认值：`DEFAULT_GRID_PINCH_ZOOM = false → true`（`AppPrefs.swift:94-95`）——用户明确视其为正式功能而非实验室玩具；实验室开关保留可关。
- 新增 XCUITest：`SleepyUITests/GridPinchRowHeightUITests.swift` — 启动参数注入开关键（`ProcessInfo` 对 `UserDefaults.standard` 的 launch-arg 覆盖在 TEST_HOST 模式下对 app 进程生效），两指 `XCPointer` 纵向捏合，断言顶栏 ✓（`scale_keep`）出现 → 点击 ✓ → 断言 `UserDefaults` 持久化值变化（`app.launch` 重启法或 XCUICoordinator 后置检查，实现时选可稳定断言的一种）。
- 行为不变项：tick 落盘（`ScheduleScreen.swift:118-123`）、切表回退（:217-222）、上下限 36–96dp×scale、`FullWeekView` 仍不支持（范围外）。

## 5. D — 应用内小组件添加引导

事实（本机 iOS 27.2 SDK 验证）：AppIntents 无应用内「弹窗添加小组件」API；唯一相关 `INRelevantShortcut.widgetKind`（Intents.framework, iOS 15+）只是向系统**注册建议**，提示时机由系统决定、不可编程触发。故：
- `WidgetGalleryScreen.swift` 点卡片动作改为弹出引导 sheet：展示该 widget 的显示名（`widget_*_label` 现有 5 语言键）+ 三步文案（长按桌面空白 → 点 ➕ → 搜索并点「轻课表」对应组件 → 长按图标拖上桌面）+「复制名称」按钮（`UIPasteboard.general.string`）+ 关闭按钮。替代现有 `widget_add_unsupported_hint` snackbar（键保留改写或删除，以实现 grep 定）。
- 引导 sheet 各元素带 accessibilityIdentifier，供 UI 测试断言出现。
- 新增 5 语言本地化键（实现时用 human-language-writing 口径：文案要像人写的说明，不用「您可以…体验…」式 AI 腔）。
- 不做：`INRelevantShortcut` 注册（收益不可验证、引入 SiriKit 依赖与 Info.plist 变更，超出「应用内添加」诉求本身——记此决策，未来若做单独切片）。

## 6. E — 灵动岛 Live Activity

**能力上限（必须显式写进 UI 文案与文档）**：无服务端 → 只能本地 `Activity.request`；App 退后台后无法新建/更新活动。策略 = **按课程时段一条活动**（相邻课节间隔 >60min 断段；规避 8h 存活上限与 4h 无更新腐坏）+ 系统原生倒计时（`Text(timerInterval:)` 走字；`startDate` 预创建按时点亮限 iOS 16.2+，16.1 回退即时创建）+ 前台/唤醒时刷新下一段。课间空档与下一段活动依赖回前台补开——上限文案照此写。

**SDK 实证（iOS 27.2，typecheck 探针）**：
- 不存在独立 Live Activity extension 点，也没有 `LiveActivity` 类型；正确声明 = `ActivityConfiguration(for:) { lockScreenView } dynamicIsland: { DynamicIsland{…} compactLeading:… compactTrailing:… minimal:… }` 作为 `some WidgetConfiguration` 由一个 `Widget` 返回、并列放进现有 `WidgetBundle`（WidgetKit 框架，iOS 16.1+；`end(content:dismissalPolicy:)` 为 16.2+，6.1 用旧签名 `end(using:dismissalPolicy:)`）。
- `ActivityAuthorizationInfo().areActivitiesEnabled`（非 areLiveActivitiesEnabled）。
- **结论：不新建 target。** 渲染并入现有 `SleepyWidget` extension，签名/App Group/project.yml 零改动。

改动清单：
- `Sleepy/widget/liveactivity/SleepyClassActivityAttributes.swift`（共享源，widget target 已 include `Sleepy/widget/**`）：`ContentState { tableId, tableName, entriesJson(当日 [起分,止分,课程名,教室]), dayKey }`，`StaticAttributes` 空；纯 Foundation。
- `Sleepy/widget/liveactivity/ClassDayActivityCore.swift`：纯函数 `visibleEntry(state:now:) -> (current, next, phase)`（课前 10 分钟起算 in-session）、进度 0…1；算法复用 `WatchAgendaCore.ClassItem`（实现时最小改动：直接构造 ClassItem 或抽共享 helper）。单元测试覆盖课前窗口/课中/课间/末节课后/无课日。
- `SleepyWidget/SleepyClassLiveActivity.swift`：`ActivityConfiguration` 渲染——expanded = 课程名 + 教室 + 下课倒计时（`Text(timerInterval:)` 系统走字，后台不腐）+ 下节课预告；compactLeading = 书本 SF Symbol；compactTrailing = 剩余分钟计时；minimal = 进度环形；锁屏视图同内容。`SleepyWidgetBundle.body` 追加一行 `SleepyClassLiveActivity()`，整文件 `@available(iOS 16.1, *)` 包裹（bundle 内可用 `if #available` —— WidgetBundleBuilder 原生支持 availability 分支）。
- 主 app 管理器 `Sleepy/widget/liveactivity/ClassDayActivityManager.swift`（`@available(iOS 16.1, *)`）：`refresh()` 读 `areActivitiesEnabled` 且 `AppPrefs.isBeforeClassFluidEnabled()`（复用既有 mode=fluid 语义，不新增键——见下）且当日有课 → 复用现存活动 `update()`，否则 `Activity.request`；`end(in: 末节课+1min)`；全部课程结束则 `end(.immediate)`。调用点：冷启动、scene 激活、ReminderRescheduler（数据变更）、通知 `didReceive`、widget 深链回跳。不承诺后台自动刷新。
- `project.yml` 主 app Info.plist 加 `NSSupportsLiveActivities: true`；`SleepyWidget/Info.plist` 同步加（extension 侧系统也会校验，保守一致）。
- 用户开关 = **接通已有死配置**：ReminderScreen 展示「课前提醒方式」模式选择（横幅 / 实况通知），`reminder_mode_fluid(_sub)` 等键在 5 lproj 已存在但 iOS 隐藏未用（:8 注释「iOS 未实现流体卡片不展示模式选择」→ 本次改写此注释与逻辑；`reminder_mode_fluid_sub` 文案重写为 iOS 实况语义 + 能力上限一句）。旧 `before_class_fluid*` 偏好键全部沿用，无迁移。
- 本地化：仅新增/改写实况相关少量键（模式副标题上限说明、live activity 内无本地化——内容来自用户课程数据）；`human-language-writing` 口径。
- QA：真机验收清单（模拟器可看但按用户令以真机为准）：14 Pro+ 岛上展开/紧凑态、非岛机型锁屏条、iOS 16.0/15.6 不崩且开关隐藏、回前台后课节内容刷新、模式开关切换生效。

## 7. 验证与提交

- 编译：`xcodegen generate` 后 `xcodebuild -project Sleepy.xcodeproj -scheme Sleepy -configuration Debug -destination 'generic/platform=iOS Simulator' -arch x86_64 CODE_SIGNING_ALLOWED=NO build`（本机 VM 模拟器 x86_64 规则）。不跑任何本地测试/不装模拟器（资源规则 + 用户令）。
- 测试代码照常交付（XCUITest/单元测试），标注「由用户真机/CI 执行」。
- 提交：commit-sop 流程；分 5 个 commit（A/B/C/D/E 各一，spec+plan 文档先行）。作者邮箱 likerry22@gmail.com，禁 Co-Authored-By。
- 文档同步：SPEC.md 差异表、llms.txt 分发段、parity 矩阵中流体云行改「本 app 已实现 Live Activities 切片」。

## 8. 风险登记

1. C 的挂点方案（祖先 UIScrollView）需真机验证：识别器挂到 scroll 后仍不触发（SwiftUI 层级里课表 grid 不在 ScrollView 内容内等意外）→ 回退「ScrollView 级 UIViewRepresentable 容器」方案（工作量大一档，先做小方案）。
2. E 的 Live Activity 硬上限：单条活动最长 8 小时（无更新 4 小时）→ 活动粒度 = **课程时段**（相邻课节间隔 >60min 断段），非全天一条；`startDate` 预创建（iOS 16.2+ request 带 start 参数，SDK 已证）让系统按时点亮，16.1 回退即时 request。间隔超一节课的下午段需回前台再开一条——能力上限文案照此写。
3. E 的 `entriesJson` 只存分钟数与短字符串（课程名/教室截断到 40 字），段内 ≤12 节。
4. B 移除后 `PlatformParityNotes` 等处的 Android 更新渠道注释失去语境，改写文案时保持 GPL 与镜像仓说明准确。
5. E 的模式开关与 Android 互斥语义（banner XOR fluid）保持差异：iOS 两个开关并存（通知 + 实况），互斥选择器属 parity B3 批次不在本切片。
