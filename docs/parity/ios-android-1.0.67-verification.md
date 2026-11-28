# Sleepy iOS 对齐 Android 1.0.67 改动与验证记录

最后更新日期：2026-11-28

## 基线与工作区

- Android 基准版本：`v1.0.67`（提交 `d0567a2602d098671fbfeaa44b03c0ce1433b4d7`，标签对象 `caf5f84358ca72ad0623e9eb50d2abe95d80518e`）
- iOS 基准起点：分支 `fix/ios-android-1.0.67-parity`，起点提交 `7713d54876c64d6e4cddc7e8874253999276e569`
- 工程版本号：`MARKETING_VERSION = 1.0.67`，`CURRENT_PROJECT_VERSION = 67`
- 对照范围：[Android 1.0.67 全量行为清单](android-1.0.67-inventory.md) 与公开议题 `#55` 至 `#59`

## 核心对齐与修复内容

### 1. 数据模型、课表校检与分享解析

- **零周数恢复与单次加课校验**：在 `ScheduleRepository`、`AppDatabase` 与 `TimeTableEntity` 中补齐非正周数拦截（`ScheduleRepository.Error.invalidWeekCount`）、旧异常行打开/恢复路径修复，以及单次课程合法性约束，配套新增 `WeekCountRecoveryTests` 与 `ScheduleParityPersistenceTests`。
- **组合作息数据结构与解析**：在 `PeriodTableEntity` 中保留 `comboScheduleJson` 与按日期检索接口 `timeJson(forDateKey:)`；`EffectivePeriodResolver` 与 `ImportedPeriodTableDraft` 集中解析基础作息、日期覆盖区间与调休日期规则，接入周视图行、今日、议程、通知、上课静默、日历导出、ICS 导出、桌面小组件与 Apple Watch 等全部消费点。
- **导入间隙与分享兼容性**：`TimeTableUtils` 修正导入作息缺省节次间隙推算并校验固定时间不重叠（`ImportedPeriodGapTests`）；`WakeUpShareProtocol` 与 `ScheduleParser` 对齐 WakeUP 分享口令和 JSON 导出导入中的声明周数、备注与禁用钟点保留规则（`WakeUpImportMetadataParityTests`）；`XiaoaiPresetData` 在发布缺节次数据时显式抛出带课程名与首个缺失节次的 `XiaoaiPresetDataError.missingPeriodTime`（`XiaoaiPresetDataTests`）。

### 2. 全量备份迁移、WebDAV 手动备份与教务来源绑定

- **全量备份升级与解压保护**：`MigrationDatabaseCodec`、`MigrationExecutor` 与 `MigrationPackageCodec` 在恢复（合并与覆盖）及再导出中保留 `comboScheduleJson` 与 `jwSchoolSourceJson`，新增包解压字节数与条目数量限制 `ReadLimits` 及远端预检 `MigrationPreparedArchive.decodeRemote`（`MigrationExecutorTests`、`MigrationPackageCodecTests`）。
- **WebDAV 手动备份客户端与设置页**：新增 `WebDAVClient`、`WebDAVConnectionStore` 与 `WebDAVBackupSection`，凭据仅存入应用私有安全存储且不打包进入备份归档；支持配置检查、远端列表、不覆盖上传及受限下载，下载后先校验压缩包结构再进入与本地归档统一的合并或覆盖确认；凭据或目标变更时清理旧密码且禁止自动跟随重定向，通过注入式传输与本机临时服务器完成验证（`WebDAVClientTests`）。
- **教务抓取、目录与授权更新**：对齐 `JwImportDraftCodec` 的便携来源序列化（`toSchoolSourceJson` / `readSchoolSource`）与指定课表更新资格校验（`AuthorizedSchoolUpdate`）；增强 `JwChengFangParser`（引入 `JwStaticJSON` 提取结构化课表 JSON）与 `JwPostgradSchoolParser` 表格解析；更新 `qdu_01.js`（青岛大学组合作息桥接）、`schools.json`、`manifest.json`，并补充广东工业大学离线 HTML 回归样本 `gdut-20261116.html` 与对应 `Jw*Tests`。

### 3. 日历、上课静默与通知调度

- **民用日历与设备当前时区对齐**：`CourseReminderOccurrence`（`CourseReminderCalendar`、`ReminderBellTimes`）、`DailyAgendaLoader`、`ClassDndScheduler` 与 `SystemCalendarManager` 统一按民用日解析调休映射、定日作息与设备当前时区钟点，跨午夜提前提醒及夏令时切换日保持正确本地日期。
- **通知与每日摘要隔离刷新**：`NotificationScheduler` 对每个开启提醒的课表独立维护通知台账（含课表编号与所属日期载荷核对），每日摘要（`refreshDailySummaries`）按所属日期和选定课表触发且不覆盖已有有效摘要，配套扩充 `NotificationSchedulerTests` 与 `ClassDndCivilDayTests`。

### 4. 界面交互、多语文案、小组件与 Apple Watch

- **课表手势与编辑界面优化（参考 issue #58 #59）**：改进 `NativeWeekPager` 的横向分页防误触与自定义回退手势、`NativeCourseDrag` 的浮动课程外部点击拦截、`QuickAddCourse` 的原生胶囊拖动手柄与无障碍步进、`CourseTableView` 与 `TodayScreen` 的宽屏多列并发碰撞布局及日汇总筹码、`CourseOccurrenceEditor` 的屏幕旋转恢复焦点、`ImportSheet` 兼容 iOS 16.4 原生输入框焦点管理，以及主题、字体缩放、导出与设置页面多轮布局和文案同步（`zh-Hans`、`zh-Hant`、`en`、`ja`、`es`）。
- **小组件实例隔离、今日切日与锁屏组件（参考 issue #56 #57）**：新增 `SleepyWidgetIntents.swift`（`SelectTimetableIntent`、`TodayNavIntent` 等）及 `TodayIntentWidget`、`TwoDayIntentWidget`、`WeekGridIntentWidget`、`WeekListIntentWidget`、`WeekViewIntentWidget`（含 iOS 17 以下静态兼容路径）、`TodayDateNavStore` 深链切日与按小组件键隔离、`LockScreenCourseWidget.swift` 锁屏课程组件，以及 `WidgetBoundaryScheduler` 的跨午夜与最忙日自动翻日边界（`WidgetSemanticsTests`、`WidgetCompactWindowParityTests`）。
- **Apple Watch 主端与表盘组件**：更新 `SleepyWatch` 的按上课日取课及组合作息解析（`WatchStore`、`TodayView`、`WeekView`、`CountdownView`）和 `SleepyWatchWidgets` 表盘材质适配（`WatchTimelineSupport` 等），并通过 `WatchAgendaCoreTests` 与 `WatchTimeStripAgendaTests` 逻辑验证。
- **工程与分发文档同步**：`project.yml` 与 `Sleepy.xcodeproj` 同步新增源文件与 `1.0.67 (67)` 版本号；`README.md`、`SPEC.md`、`llms.txt` 同步移除已下线 TestFlight 入口，统一 App Store 为官方安装与更新渠道。

## 全量测试、构建与真机验证结果

以下全部测试、构建与真机安装均在最后一次 Swift 代码与 UI 测试文件修改（`SleepyUITests/AddCoursesEntryUITests.swift`）完成后于 **2026-11-27** 执行完毕：

### 1. 单元测试套件（SleepyTests）

- 执行环境：macOS 本机 Xcode `14.3.1`（`14E300c`），隔离模拟器 `Sleepy 1.0.67 isolated QA iPhone`（iOS `16.4`，UDID `F74EA555-D755-47A3-BE64-BFBE8A44604F`）
- 执行命令：
  ```bash
  xcodebuild -project Sleepy.xcodeproj -scheme Sleepy -configuration Debug \
    -destination "platform=iOS Simulator,id=F74EA555-D755-47A3-BE64-BFBE8A44604F" \
    -derivedDataPath build/NoWatchDerivedData \
    -clonedSourcePackagesDirPath build/DerivedData/SourcePackages/checkouts \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO "-only-testing:SleepyTests" test
  ```
- 运行结果：**通过** — 共执行 **2751** 项测试，跳过 **12** 项，失败 **0** 项（未预期失败 0 项），耗时 `192.869` 秒（日志：`build/final-unit2.log`，产物：`build/NoWatchDerivedData/Logs/Test/Test-Sleepy-2026.11.27_08-35-48-+0800.xcresult`）。
- 跳过用例明细（12 项）：
  1. `HolidayViewportTests.testBenchmarkViewportBatchAgainstPerCellWork`
  2. `ScheduledActivitySystemTests.testCancellingPendingActivityPreventsItsStart`
  3. `ScheduledActivitySystemTests.testScheduledActivityStartsAndEndsThroughSystem`
  4. `SleepyControlsGeometryTests.testNativeIconButtonRendersAsADiscWithinItsTouchSlot`
  5. `ThemeCacheProbeTests.testBenchmarkCustomProviderAgainstOriginalDerivationPath`
  6. `ThemeCacheProbeTests.testBenchmarkProviderSystemAndPresetResolution`
  7. `ThemeCacheProbeTests.testBenchmarkProviderTerminalVectorAgainstConstructorPath`
  8. `ThemeCacheProbeTests.testBenchmarkSystemChurnBeyondCacheCapacity`
  9. `ThemeCacheProbeTests.testBenchmarkSystemFourAppearanceEndpoints`
  10. `ThemeCacheProbeTests.testBenchmarkSystemWarmSingleEndpoint`
  11. `ThemeCacheProbeTests.testBenchmarkUncachedVectorConversionContext`
  12. `WeekProjectionCacheTests.testBenchmarkWarmThreePageProjectionAgainstUncachedPath`

### 2. watchOS 目标编译（Sleepy Watch 与嵌入式 SleepyWatchWidgets）

- 执行环境：Xcode `14.3.1`（`WatchOS9.4.sdk`）
- 执行命令：
  ```bash
  xcodebuild -project Sleepy.xcodeproj -scheme "Sleepy Watch" -configuration Debug \
    -destination generic/platform=watchOS -derivedDataPath build/WatchDerivedData \
    -clonedSourcePackagesDirPath build/DerivedData/SourcePackages/checkouts \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO build
  ```
- 运行结果：**BUILD SUCCEEDED**（日志：`build/watch-build2.log`；编译期提示 `WATCHOS_DEPLOYMENT_TARGET = 10.0` 高于 Xcode 14.3.1 WatchOS 9.4 SDK 版本上限，未阻断构建）。

### 3. UI 自动化测试套件（SleepyUITests）

- 执行环境：Xcode `14.3.1`，隔离模拟器 `Sleepy 1.0.67 isolated QA iPhone`（iOS `16.4`，UDID `F74EA555-D755-47A3-BE64-BFBE8A44604F`）
- 执行命令：
  ```bash
  xcodebuild -project Sleepy.xcodeproj -scheme Sleepy -configuration Debug \
    -destination "platform=iOS Simulator,id=F74EA555-D755-47A3-BE64-BFBE8A44604F" \
    -derivedDataPath build/NoWatchDerivedData \
    -clonedSourcePackagesDirPath build/DerivedData/SourcePackages/checkouts \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
    CODE_SIGNING_ALLOWED=NO "-only-testing:SleepyUITests" test
  ```
- 运行结果：**通过** — 共执行 **250** 项测试，跳过 **5** 项，失败 **0** 项（未预期失败 0 项），耗时 `14631.467` 秒（日志：`build/final-ui3.log`，产物：`build/NoWatchDerivedData/Logs/Test/Test-Sleepy-2026.11.27_09-37-17-+0800.xcresult`）。
- 跳过用例明细（5 项）：
  1. `InteractionPerformanceUITests.testProcessLaunchToResponsive`
  2. `InteractionPerformanceUITests.testTabsAndSettingsRoundTrip`
  3. `InteractionPerformanceUITests.testWarmWeekPaging`
  4. `ReminderPermissionDeniedTests.testMasterOnWithNotificationPermissionDeniedKeepsIndependentActivitySettings`
  5. `WidgetArchivingUITests.testAllWidgetsArchiveSuccessfully`

### 4. 真机 Debug 签名构建与非破坏性安装（iPhone 6s Plus）

- 目标设备：`iPhone 6s Plus`（系统 `iOS 15.8.8`，UDID `3e9ae5414eeea7342fb15d596a5e2c5e26731f59`）
- 签名说明与处理：本机仅缓存 `D9UP75W466.com.lingion.sleepy` 与 `D9UP75W466.com.lingion.sleepy.widget` 开发描述文件（有效期至 `2027-11-10`，共享容器 `group.com.lingion.sleepy`）；苹果开发者后台因账户 PLA 协议待更新提示无法自动签发 `SleepyWatch` 所需 Watch App Group 描述文件，且当前无已配对 watchOS 10 手表。参照主工作区 `project-device.yml` 惯例，构建期间在被忽略目录生成的临时 `build/SleepyDevice.xcodeproj` 中移除 `SleepyWatch` 依赖，安装完成后立即清理该临时工程，仓库 `project.yml` 与 `Sleepy.xcodeproj` 保持原样。
- 执行结果：**BUILD SUCCEEDED**（`build/device-build.log`）；`codesign -dvv` 校验开发团队 `D9UP75W466`、`Authority = Apple Development: Lingion Kong (WMY7J93AC3)`、`CFBundleShortVersionString = 1.0.67`、`CFBundleVersion = 67`；通过 `ios-deploy --no-wifi` 非破坏性安装成功（`[100%] Installed package`，`build/device-install.log`），并通过 `pymobiledevice3 apps list` 核对设备已注册 `1.0.67 (67)`、`MinimumOSVersion = 15.6` 及共享容器 `group.com.lingion.sleepy`（`/private/var/mobile/Containers/Shared/AppGroup/F10934CF-C5BB-4DB5-B50A-AF1FB951FB8D`）。

## 尚未覆盖的平台边界与环境说明

- **Xcode 26.3、iOS 17+ 与 iOS 26 运行时**：受限本机 Xcode `14.3.1`（iOS `16.4` 模拟器 / WatchOS `9.4` SDK），`#if compiler(>=5.9)`（iOS 17 `AppIntents` 交互式小组件与按实例独立选表）与 `#if compiler(>=6.2)`（iOS 26 玻璃外观与 `ActivityKit` 定时实况活动）已做语法与条件编译兼容收口，尚未在 Xcode `26.3`、iOS `17+` 或 iOS `26` 真机与模拟器环境实际编译运行。
- **物理 Apple Watch 实机运行**：`SleepyWatch` 与 `SleepyWatchWidgets` 已通过 watchOS 通用构建与核心算法单测，尚未在真实配对 watchOS `10+` 手表上实机运行、测试表盘渲染或同步通知。
- **外部实时联调场景**：真实学校教务账号在线登录抓取、远端授权 WebDAV 服务器实际读写、系统桌面长按 WidgetKit 添加多实例并测试交互按钮，需后续使用独立测试数据在真机手工或专项集成测试中补充验证。
- **系统分享扩展入口（`I06`）**：根 `project.yml` 未包含独立 Share Extension 目标，维持通过主应用文档打开（`CFBundleDocumentTypes` / `onOpenURL`）承接外部导入文件。

## 后续真机反馈修复（iOS 15 网格左右滑动顶部空白）

- **问题现象**：`iPhone 6s Plus`（`iOS 15.8.8`）在网格视图左右滑动切换周次时顶部出现意外空白区域。
- **根因定位**：`NativeWeekPager` 内 `PageHost` 此前仅在 `#available(iOS 16.4, *)` 时设置 `safeAreaRegions = []`，在 `iOS 15` 上未剥离嵌入 `UIPageViewController` 内部 `_UIQueuingScrollView` 与祖先 `UINavigationController` 传播的安全区与自动滚动内边距；同时 `UIPageViewController` 未关闭 `automaticallyAdjustsScrollViewInsets` 且 `_UIQueuingScrollView` 未锁定 `.never` 及禁用纵向回弹，`ScheduleScreen` 外层 `GeometryReader` 在普通滑动切换 `selectedWeek` 时亦附带隐式位移动画。
- **改动文件**：[NativeWeekPager.swift](../../Sleepy/ui/component/NativeWeekPager.swift)、[ScheduleScreen.swift](../../Sleepy/ui/screen/schedule/ScheduleScreen.swift) 与 [NativeWeekPagerTests.swift](../../SleepyTests/NativeWeekPagerTests.swift)（新增 `SleepyLegacyHostingSafeArea` 在 `iOS 16.4` 以下剥离 `PageHost` 安全区并置 `.ignoresSafeArea()`，增加 `PagingController` 与子滚动视图 `.never` / 垂直偏移归零保护，并在非拖拽切周时取消外层 `GeometryReader` 隐式动画）。
- **改动后复验（2026-11-27）**：
  - 全量单元测试 `SleepyTests`（`build/pager-fix-unit.log`）：执行 **2753** 项（含新增 2 项 `NativeWeekPagerTests` 用例），跳过 **12** 项（与上文相同的 12 项基准/系统能力/几何跳过用例），失败 **0** 项，耗时 `248.252` 秒，`TEST SUCCEEDED`。
  - 定向 UI 回归（`CourseDragUITests`、`NavigationTransitionCanvasUITests`、`ScheduleFlowUITests`，`build/pager-fix-ui.log`）：共执行 **28** 项（分别 10 / 9 / 9 项），失败 **0** 项，耗时 `3690.135` 秒，`TEST SUCCEEDED`（其余 `SleepyUITests` 用例仅在前置全量基线运行通过，本次未全量重跑）。
  - watchOS 编译 `Sleepy Watch`（`build/pager-fix-watch.log`）：`BUILD SUCCEEDED`。
  - `iPhone 6s Plus`（`iOS 15.8.8`）Debug `1.0.67 (67)` 重新编译、签名校验与 `ios-deploy --no-wifi` 非破坏性安装成功（`build/pager-fix-device.log`、`build/pager-fix-install.log`）；`iOS 15.8.8` 真机交互目视无顶部空白需用户真机滑动确认。
- **二轮真机复现与根因定位（`HiddenBarNavigationController` 导航栏显隐泄漏）**：
  - 在 `iPhone 6s Plus`（`iOS 15.8.8`）通过隔离探针确认，首轮修复后左右翻页切换新托管子控制器时，页面内的 `UIHostingController` 会将 SwiftUI 默认的未隐藏导航栏偏好向上传播给外层 `UINavigationController`，在转场期间将 `isNavigationBarHidden` 翻回 `false`，使导航栏由 `(0, -64, 414, 44)` 下移到 `(0, 20, 414, 44)`，并把顶部安全区从 `20pt` 推至 `64pt`，造成页面整体下移并在顶部露出 `44pt` 空白。
  - **二轮改动**：在 [SleepyNavHost.swift](../../Sleepy/ui/nav/SleepyNavHost.swift) 引入私有 `HiddenBarNavigationController` 子类持续锁定 `isNavigationBarHidden = true` 并在 `viewWillLayoutSubviews` / `viewDidLayoutSubviews` 复核隐藏状态，同时在 `SleepyNativeNavigationCoordinator.content(for:)` 与 [NativeWeekPager.swift](../../Sleepy/ui/component/NativeWeekPager.swift) 子视图显式施加 `.navigationBarHidden(true)`；在 [NativeWeekPagerTests.swift](../../SleepyTests/NativeWeekPagerTests.swift) 新增 `testNavigationHostKeepsNavigationBarHiddenAcrossHostingBarRequestsAndPaging` 回归锁定。
  - **二轮改动后复验（2026-11-27）**：
    - `iPhone 6s Plus`（`iOS 15.8.8`）隔离真机探针（`SleepyProbe`）：`DevicePagerProbeTests`（1/1）、`NativeWeekPagerTests`（6/6）与 `DeviceGridSwipeProbeUITests`（1/1）全部通过，`navBarHidden=true` 且导航栏与页面区域在翻页前、转场中与翻页后保持稳定。
    - 全量单元测试 `SleepyTests`（`build/nav-fix-unit.log`）：执行 **2754** 项（含新增测试），跳过 **12** 项，失败 **0** 项，耗时 `198.078` 秒，`TEST SUCCEEDED`。
    - 定向 UI 回归（`CourseEditorUITests/testSaveCourseAppearsInSchedule`、`MineSettingsUITests/testBackupShowsWebDAVSetupWithoutRequiringAConnection`、`NavigationTransitionCanvasUITests`、`ScheduleFlowUITests`、`SwipeBackGestureUITests`，`build/nav-fix-ui.log`）：共执行 **24** 项，失败 **0** 项，耗时 `949.021` 秒，`TEST SUCCEEDED`。
    - watchOS 编译 `Sleepy Watch`（`build/nav-fix-watch.log`）：`BUILD SUCCEEDED`。
    - `iPhone 6s Plus`（`iOS 15.8.8`）Debug `1.0.67 (67)` 重新构建（`build/nav-fix-device.log`）并非破坏性安装成功（`build/nav-fix-install.log`）。

## 系统能力隐藏、体积压缩与流畅度全链路优化（2026-11-28）

### 1. 系统版本与硬件能力门控（隐藏不支持的设置入口）

- **液态玻璃界面风格门控**：在 [UIStyle.swift](../../Sleepy/theme/UIStyle.swift) 新增 `SleepyUIStyle.supportsLiquidGlass` 与 `effectiveStyle`，在低于 `iOS 26` 且未显式传入 `-ui_style` 测试参数时强制回退 `.classic`；在 [AppearanceScreen.swift](../../Sleepy/ui/screen/mine/AppearanceScreen.swift) 当不支持液态玻璃时隐藏整个界面风格选择卡片（不再展示二选一选项）。
- **Watch 时间带与设备支持门控**：在 [WidgetSettingsScreen.swift](../../Sleepy/ui/screen/mine/WidgetSettingsScreen.swift) 通过 `WidgetSettingsScreen.supportsWatchTimeStrip` 校验 `WCSession.isSupported()` 及 `#available(iOS 17.0, *)`，对不支持配对或低于 `iOS 17` 的设备隐藏 Apple Watch 课程时间带配置区块。
- **时效性通知与实况活动门控**：在 [BackgroundReliabilityProbe.swift](../../Sleepy/widget/notification/BackgroundReliabilityProbe.swift) 与 [BackgroundReliabilitySnapshot.swift](../../Sleepy/widget/notification/BackgroundReliabilitySnapshot.swift) 采集 `timeSensitiveSupported`（`settings.timeSensitiveSetting != .notSupported`），并在 [ReminderScreen.swift](../../Sleepy/ui/screen/mine/ReminderScreen.swift) 按该标记隐藏不受支持的时效性通知状态行，定时实况活动状态继续受 `ClassDayActivityCore.supportsScheduledActivities` 门控。
- **验证覆盖**：新增 [OSCapabilityGatingTests.swift](../../SleepyTests/OSCapabilityGatingTests.swift)（4/4 通过），并在 [BackgroundReliabilityTests.swift](../../SleepyTests/BackgroundReliabilityTests.swift)、[MineSettingsUITests.swift](../../SleepyUITests/MineSettingsUITests.swift) 与 [WatchTimeStripSettingsUITests.swift](../../SleepyUITests/WatchTimeStripSettingsUITests.swift) 中补充低于 `iOS 26` 与低于 `iOS 17` 的入口隐藏断言；[QuickAddCourseUITests.swift](../../SleepyUITests/QuickAddCourseUITests.swift) 补充液态玻璃测试覆盖 `testLiquidGlassQuickAddEdgeHandlesDragCleanly`。

### 2. 应用安装包体积压缩（由 27,183,745 字节降至 9,967,943 字节）

- **Widget 与 Watch 脱离 GRDB**：新增基于系统 `sqlite3` C 接口的轻量级封装 [LiteSQLite.swift](../../Sleepy/data/LiteSQLite.swift)，将 `SleepyWidget`、`SleepyWatch`、`SleepyWatchWidgets` 所用到的数据库访问（`AppDatabase.swift`、DAO、Entity、`ScheduleRepository.swift`、`WatchSyncSnapshot.swift`、`CourseHueStore.swift`、`CourseReminderOccurrence.swift` 与 `SleepyWatchApp.swift`）切换至 `LiteSQLite`。此前 `LiteDatabase` 在写事务内执行 `PRAGMA journal_mode = WAL`，SQLite 会拒绝该语句，导致小组件加载共享库时在 `AppDatabase.swift:318` 触发 `fatalError`（真机崩溃日志符号化结果）。现改为在事务外设置 WAL，并新增 `LiteSQLiteTests` 覆盖初始化与跨库读取。
- **小组件建表归属**：小组件扩展以 `createSchema: false` 打开共享库，建表只由主应用的 GRDB 迁移器负责，以防两侧各自建表后迁移器的 `CREATE TABLE` 冲突。这是代码推理得出的防护，未在设备上复现。
- **静态大资源增量编码与 LZMA 打包**：新增 [pack-resources.py](../../scripts/pack-resources.py) 与 [BundledAssetLoader.swift](../../Sleepy/util/BundledAssetLoader.swift)，将 `schools.json` 压为 `schools.json.lzma`（`953,948` 字节降至 `101,684` 字节），将 `school_cities.json` 剥离开发字段后压为 `school_cities.json.lzma`（`165,677` 字节降至 `23,408` 字节），将城市边界编码为 `SCB2` 差分 varint 并压为 `school_city_boundaries.bin.lzma`（SCB2 原始 `627,086` 字节，无损 LZMA 为 `434,796` 字节；当前交付的有损简化版为 `214,296` 字节，见下文「城市边界有损简化」），将 `shiguang` 原始脚本移至 `Sleepy/resources-src/shiguang` 并经 `esbuild` 精简空白与语法及精简运行时 `manifest.json` 后打包为 `shiguang.pack.lzma`（`2,860,664` 字节降至 `333,852` 字节）；同时生成小组件与手表专用精简多语言表 `Sleepy/resources-ext/*.lproj`（原始文本共计 `29,065` 字节）。相关读取点（`JwImportViewModel.swift`、`JwSgAssetBridge.swift`、`OfflineSchoolCityIndex.swift`、`SchoolCityLocator.swift` 及对应 `Jw*Tests`、`OfflineSchoolCityIndexTests`）已同步适配解包。
- **图像调色板压缩与冗余字符串清理**：移除未使用的 `SleepyLogo.imageset`；将 iOS 与 Watch 端 `AppIcon-1024.png` 无损视觉量化为 256 色调色板（`37,891` 字节降至 `17,570` 字节），将 `LaunchLogo.png` 量化为 128 色带透明通道 PNG（`14,763` 字节降至 `2,889` 字节）；并从 5 语言 `Sleepy/resources/*.lproj/Localizable.strings` 删除 67 条零引用遗留键。
- **构建与打包参数收敛**：在 [project.yml](../../project.yml) 与 [build-ipa.sh](../../scripts/build-ipa.sh) 的 `Release` 分支配置 `SWIFT_OPTIMIZATION_LEVEL=-Osize`、`GCC_OPTIMIZATION_LEVEL=z`、`STRINGS_FILE_OUTPUT_ENCODING=UTF-8`、`LLVM_LTO=NO`、`DEAD_CODE_STRIPPING=YES`、`-Wl,-dead_strip` 与 `-Wl,-dead_strip_dylibs`。同时移除了 `OTHER_SWIFT_FLAGS` 中的 `-Xfrontend -disable-reflection-metadata`、`-Xfrontend -conditional-runtime-records` 与 `-disable-cmo`。实测在这三个标志存在的 Release 模拟器构建中，应用启动时多次以 `EnvironmentObject` 注入失败闪退；去掉这些自定义标志后，模拟器与真机均未复现。本轮没有逐个隔离各标志的单独作用，只能确认整组移除后问题消失。
- **城市边界有损简化（待用户确认）**：顶点数超过 220 个、且经纬跨度均不小于 0.15 度的大环，按 0.01 度（约 1.1 km）的容差做 RDP 抽稀，并量化到 0.005 度网格。无锡市、三门峡市，以及它们在简化后被误判到的相邻城市常州市、洛阳市，保持全分辨率。回归范围是 491 个行政区域的外环质心代表点，加上 23 个坐标用例，全部通过。这不是逐点边界精度验证，靠近行政区界的学校仍可能被匹配到相邻城市。将 `scripts/pack-resources.py` 中的 `SCB_SIMPLIFY_LARGE_RINGS` 设为 `False`，可得到与原资产逐字节一致的无损版本，体积约增加 220 KB，安装包会超过 10 MB。
- **精确字节对照**：优化前基准包 `build/Sleepy-baseline.ipa` 为 `27,183,745` 字节（约 `25.92 MiB`）；终版 `./scripts/build-ipa.sh Release` 生成 `build/Sleepy-unsigned.ipa` 为 `9,967,943` 字节（约 `9.51 MiB`），较基线缩减 `63.3%`，且严格低于 `10,000,000` 十进制字节与 `10 MiB` 上限。

### 3. 渲染热路径缓存、页签保活与翻页流畅度优化

- **偏好与高频计算缓存**：在 [AppPrefs.swift](../../Sleepy/util/AppPrefs.swift) 为主应用进程加入线程安全 `CachedDefaultsProxy` 缓存与解析结果缓存（小组件扩展进程维持禁用以保障跨进程读取一致性），将 `UserDefaults.didChangeNotification` 主域监听收窄至 `UserDefaults.standard` 并配合 `mutationRevision` 追踪变化；为 [CourseOccurrences.swift](../../Sleepy/data/repository/CourseOccurrences.swift)、[DateUtils.swift](../../Sleepy/util/DateUtils.swift)、[HolidayManager.swift](../../Sleepy/util/HolidayManager.swift)、[HolidayReminderPolicy.swift](../../Sleepy/util/HolidayReminderPolicy.swift)、[TimeTableUtils.swift](../../Sleepy/util/TimeTableUtils.swift)、[CourseColorUtil.swift](../../Sleepy/util/CourseColorUtil.swift)、[LocaleHelper.swift](../../Sleepy/util/LocaleHelper.swift)、[L10n.swift](../../Sleepy/util/L10n.swift)、[PeriodHeaderCellContent.swift](../../Sleepy/ui/component/PeriodHeaderCellContent.swift) 与 [WeekGridWidgetView.swift](../../Sleepy/widget/WeekGridWidgetView.swift) 补充 `NSLock` 缓存与快速 ASCII 解析；在 [CourseTableView.swift](../../Sleepy/ui/component/CourseTableView.swift)、[TodayScreen.swift](../../Sleepy/ui/screen/today/TodayScreen.swift) 与 [AppearanceScreen.swift](../../Sleepy/ui/screen/mine/AppearanceScreen.swift) 预分组课程字典并把外观预览分组读取改为异步后台加载。
- **页签保活与周分页零重绘**：在 [SleepyNavHost.swift](../../Sleepy/ui/nav/SleepyNavHost.swift) 与 [SleepyApp.swift](../../Sleepy/SleepyApp.swift) 引入 `SleepyKeepAliveTabContainer` 保留四个首页签的独立托管视图控制器并延迟刷新非活跃推入页；在 [NativeWeekPager.swift](../../Sleepy/ui/component/NativeWeekPager.swift) 与 [ScheduleScreen.swift](../../Sleepy/ui/screen/schedule/ScheduleScreen.swift) 引入 `WeekPageSignature`、最多 8 页 MRU 缓存、`refreshGreyDays` 整学期预计算以及独立 `PageAccessibilityWrapper`（避免改变 UIKit 容器的无障碍隐藏属性导致 [QuickAddCourse.swift](../../Sleepy/ui/component/QuickAddCourse.swift) 快速加课确认按钮命中点计算失效）。
- **热路径微基准实测（`RenderHotPathBenchTests`，`SLEEPY_RUN_PERFORMANCE_TESTS=1`，校验和前后一致）**：
  - `app_prefs_1500` 中位数耗时由 `2035.33058 ms` 降至 `18.35299 ms`（加速 `110.9` 倍，校验和 `2404729`）；
  - `date_occurrence_2000` 中位数耗时由 `1569.553253 ms` 降至 `14.058184 ms`（加速 `111.6` 倍，校验和 `356905`）；
  - `grid_pipeline_200` 中位数耗时由 `2397.541477 ms` 降至 `271.100251 ms`（加速 `8.84` 倍，校验和 `561801`）。
- **端到端交互性能实测（`InteractionPerformanceUITests`，`iOS 16.4` Debug 模拟器）**：
  - `testProcessLaunchToResponsive` 冷启动至首帧可交互均值 `2.916 s`；
  - `testTabsAndSettingsRoundTrip` 应用 CPU 耗时均值由 `7.222 s`（CPU 周期 `17,292,598.789 kC`）降至 `3.309 s`（CPU 周期 `7,692,044.645 kC`，提速 `2.18` 倍，峰值内存 `107,787.878 kB`）；
  - `testWarmWeekPaging` 应用 CPU 耗时均值由 `20.835 s`（CPU 周期 `49,886,291.904 kC`）降至 `8.984 s`（CPU 周期 `21,288,750.290 kC`，提速 `2.32` 倍，峰值内存 `121,448.858 kB`）。
  - **同一套件的后续复跑（2026-11-28，Debug 模拟器，`build/perf-tests-final.log`）**：`testTabsAndSettingsRoundTrip` 的 CPU 时间均值为 `4.426 s`，相对基线 `7.222 s` 约快 `1.63` 倍；`testWarmWeekPaging` 的 CPU 时间均值为 `11.806 s`，相对基线 `20.835 s` 约快 `1.76` 倍。与此前记录的 `3.309 s`、`8.984 s` 相比，本次慢约 `34%` 与 `31%`，端到端测量的波动较大，需要多次取中位数才能下结论。**按本次复跑，未达到“至少快 3 倍”的目标。** 热路径微基准的提升（`app_prefs_1500` 中位数约快 `110.9` 倍，`date_occurrence_2000` 约快 `111.6` 倍，`grid_pipeline_200` 约快 `8.84` 倍）不等于端到端流畅度。本轮复跑的热路径中位数为 `app_prefs_1500` 18.657 ms、`date_occurrence_2000` 16.838 ms、`grid_pipeline_200` 317.360 ms，校验和与此前一致。真机帧率与卡顿尚未测量。

### 4. 终版全量复验与 iPhone 6s Plus 真机 Release 安装（2026-11-28）

以下测试与真机安装并非全部在同一代码状态下执行。最终代码状态（2026-11-28 16:29 之后的应用代码与 16:07 生成的最终资源）下执行的是：全量单元测试、Watch 构建、Release IPA 构建、Release 真机安装，以及 `WidgetArchivingUITests`、`SchoolSelectUITests`、`ReminderPermissionUITests` 与 `TopBarOverlapGlassUITests` 的复跑。

- **watchOS 目标编译（`Sleepy Watch`）**：在 Xcode `14.3.1` 针对 watchOS 模拟器构建，结果 **`BUILD SUCCEEDED`**。
- **全量单元测试（`SleepyTests`）**：共执行 **2764** 项，跳过 **15** 项，失败 **0** 项（`** TEST SUCCEEDED **`）。跳过的 15 项中包含 3 项需 iOS 26 SDK 的测试（`ScheduledActivitySystemTests` 2 项、`SleepyControlsGeometryTests` 1 项），以及 12 项未传 `SLEEPY_RUN_PERFORMANCE_TESTS=1` 时按约定跳过的基准用例（`HolidayViewportTests` 1 项、`RenderHotPathBenchTests` 3 项、`ThemeCacheProbeTests` 7 项、`WeekProjectionCacheTests` 1 项）。
- **OS 门控与热路径基准复测（`SLEEPY_RUN_PERFORMANCE_TESTS=1`）**：`OSCapabilityGatingTests`（4/4）与 `RenderHotPathBenchTests`（3/3）共 **7/7** 全部通过（`** TEST SUCCEEDED **`）。
- **UI 复跑（2026-11-28）**：11 个套件首轮执行 82 项，跳过 3 项，失败 1 项。失败项为 `WidgetArchivingUITests`，它断言了不存在的 `WeekGridWideWidget`；已改为实际注册的 `WeekGridVerticalWidget` 与 `WeekGridHorizontalWidget`，修正后该用例通过。`ReminderPermissionUITests` 与 `TopBarOverlapGlassUITests` 在批量运行中出现 runner 提前退出，单独复跑 7 项全部通过。11 个套件的整体运行早于城市边界资产与数据库建表归属的最终改动；这两项之后只重跑了上述用例、全量单元测试、Watch 构建与 Release IPA 构建，并补跑了 `WidgetArchivingUITests` 与 `SchoolSelectUITests` 子集（均通过）。
- **此前会话的核心 UI 记录（本轮未复核，仅供参考）**：11 个套件，共 74 项：`DeviceAdaptationUITests`（8）、`MineSettingsUITests`（30）、`NavigationTransitionCanvasUITests`（9）、`QuickAddCourseUITests`（4）、`ReminderPermissionUITests`（5）、`ScheduleFlowUITests`（9）、`SwipeBackGestureUITests`（4）、`TopBarOverlapEnUITests`（1）、`TopBarOverlapGlassUITests`（2）、`TopBarOverlapZhUITests`（1）、`WatchTimeStripSettingsUITests`（1）全部 **74/74** 通过，失败 **0** 项（`** TEST SUCCEEDED **`）。
- **`iPhone 6s Plus` 真机 Release 安装（`iOS 15.8.8`，UDID `3e9ae5414eeea7342fb15d596a5e2c5e26731f59`）**：使用去 Watch 临时工程构建 `-configuration Release`（`-Osize` + `LLVM_LTO=NO` + `DEAD_CODE_STRIPPING=YES`，自动开发签名，安装后立即移除临时工程），使用 `ios-deploy -i <UDID> -b <Sleepy.app>` 覆盖安装（不带卸载参数，结果为 `[100%] Installed package`），设备上已注册 `com.lingion.sleepy` `1.0.67 (67)`。安装启动后约 8 秒，`pymobiledevice3 developer dvt process-id-for-bundle-id` 返回了进程号，与上一次安装后的崩溃报告基线比对无新增。未核对应用数据内容，也未做页面交互与翻页回归；真机上的目视流畅度与隐藏项效果仍需用户在设备上确认。
