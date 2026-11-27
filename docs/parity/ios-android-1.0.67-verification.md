# Sleepy iOS 对齐 Android 1.0.67 改动与验证记录

最后更新日期：2026-11-27

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
