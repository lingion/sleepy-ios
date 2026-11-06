# Sleepy iOS ↔ Android v1.0.62 对齐差距矩阵

> 基线: 原 tag `v1.0.62` = commit `10adc247` (2026-10-25)。
> 对比: `v1.0.61..v1.0.62` = **101 个 Kotlin 文件, +6071 / -976**。
> iOS 侧: `sleepy-ios` worktree `.worktrees/parity-v1062`, 分支 `feature/parity-v1062`。
> 状态标记: ✅ 已有 / ❌ 缺失(需做) / 🔧 需 iOS 改造 / ⏸ 原平台独占(暂缓)。

## 0. 范围口径

- **在范围内**: v1.0.62 相对 v1.0.61 的全部新增/变更功能、UI、操作。
- **不在范围内**: 原 tag 之后的 v1.0.63-dev (HEAD `4d4c8d0b`, 13 commits) — 单次课编辑、胶囊加课、统一管理 UI、多步撤销、平板几何、nbcc webvpn、vivo 原子岛。
- **可暂缓**: 原平台独占 / 厂商定制 (Xiaomi·vivo·OPPO·Honor·Huawei 实时课程卡、电池优化白名单跳转、RemoteViews 位图渲染器、PinWidget/Render/Configure Activity、ScrollStripService、13 档 widget 矩阵)。

## 1. 12 项头部功能核验 (逐条追工作流后的判定)

| # | 功能 | Android v1.0.62 | iOS 现状 | 判定 | 证据 |
|---|---|---|---|---|---|
| 1 | 课程配色三模式 (不跟随主题/跟随主题/自定义) + 安全弧色相编排 + `course_colors` 持久表 | `util/CourseColorUtil.kt`(+204)、`CourseHueStore.kt`(新)、`CourseColorWriteGlue.kt`(新)、`CourseColorEntity/Dao`、DB v11→v12、`AppearanceScreen`(+266) | `CourseColorUtil.swift` 仅有 `stableHue`/`pickCourseColor*`; `AppPrefs` 无 `KEY_COURSE_COLOR_MODE`/`KEY_COURSE_COLOR_SEED_HUE`; DB 停在 v11; `AppearanceScreen` 无配色段 | ❌ 全缺 | B1 |
| 2 | 课前提醒形态二选一 (横幅 ⇄ 流体云, 互斥) | `ReminderScreen.kt`(+118), `AppPrefs.getBeforeClassMode` | `ReminderScreen.swift:388/397` 仍是两个独立开关 | ❌ 缺失 | B3 |
| 3 | 每课表提醒开关独立页 (`TableReminderScreen`) | `ui/screen/mine/TableReminderScreen.kt`(新,132行) + 路由 `SleepyRoute.TableReminder` | iOS DB v11 已有 `reminderEnabled` 列, 但无独立页/无路由 | 🔧 底层已有, 需 UI + 路由 | B3 |
| 4 | 小组件设置页 (`WidgetSettingsScreen`) | `ui/screen/mine/WidgetSettingsScreen.kt`(新,238行), 从「我的」进入, 通用设置页的 widget 块移出 | iOS `GeneralSettingsScreen.swift:584 WidgetSection` 仍在通用设置内, 无独立页 | 🔧 需拆页 | B4 |
| 5 | 小组件画廊 (`WidgetGalleryScreen`, 13 卡片) | `ui/screen/widget/WidgetGalleryScreen.kt`(新,161行) + `WidgetGalleryData.kt` + `WidgetPinRequest.kt` + `WidgetManagementScreen` 右上「＋」 | iOS 无画廊页; `allWidgetVariants` 仅 5 kind (iOS 用 family 尺寸而非 base/small/wide 三档) | 🔧 需画廊页 + 5 kind 卡片 (13 档矩阵属 原平台独占) | B4 |
| 6 | 多课表合并「每日议程」+ 深链 `sleepy://daily-agenda/<date>` | `widget/notification/DailyAgenda.kt`(86)、`DailyAgendaLoader.kt`(42)、`DailyScheduleSummary.kt`(45)、`DailySummaryNotificationMigration.kt`(25)、`ui/screen/today/DailyAgendaActivity.kt`(127) | iOS `widget/notification/` 无 DailyAgenda* 任何文件; 无深链处理 | ❌ 全缺 | B5 |
| 7 | 隐私政策入口 | `AboutScreen.kt`(+39) `about_privacy` → `https://sleepy.qdp.qzz.io/privacy` | `AboutScreen.swift` 仅源码/GitHub/QQ | ❌ 缺失 | B6 |
| 8 | 学校目录 4140 条 + 导入状态元数据 (`unverified`/`grad_unverified`/`catalogId`) | `data/jw/JwSchoolInfo.kt`(+35)、`SchoolSearchIndex.kt`(新)、`SchoolDomainMatch.kt`(新,+61)、`SchoolCityIndex`(+9)、`OfflineSchoolCityIndex`(+15)、`JwProtocol.kt`(+56)、`JwParserRegistry.kt`(+23) | iOS `schools.json` 仅 349 条 legacy schema (无 status/catalogId); `JwSchoolInfo.swift` 缺 `unverified`/`grad_unverified`/`catalogId`/`stableKey` | 🔧 数据 + 模型双改 | B2 |
| 9 | 未验证学校导入成功报告 (`JwImportReport`) | `data/jw/JwImportReport.kt`(新,42行) 粘贴标记 `[Sleepy导入成功]` + 隐私安全字段 | iOS 无 | ❌ 缺失 | B2/B6 |
| 10 | 新增教务协议解析器 | `JwEcuplParser`/`JwEcuplScriptParser`/`JwEcuplSuperParser`/`JwKingoZxParser`/`JwNewUrpSuperParser`/`JwNwpuPostParser`/`JwOldQzSuperParser`/`JwQzTimetableParser`/`JwScauParser`/`JwWakeUpCompatParsers`(+367)/`JwSeuParser`(+63)/`JwThuparser`(+135) 等 | iOS `data/jw/` 无对应文件 | ❌ 缺失 | B7 |
| 11 | 小爱课程表导出 | `data/parser/XiaoaiPresetData.kt`(新,234行) + `ExportScreen`(+75) | iOS `data/parser/` 无 Xiaoai | ❌ 缺失 | B6 |
| 12 | 「已存在」项复核 | — | 周视图日期打印 ✅ / 长课间 24dp 薄带 ✅ / sleepy-v1 分享格式 ✅ / 周网格最近有课日 ✅ / `reminderEnabled` 列 ✅ | ✅ 已有 | 无需做 |

## 2. 101 文件逐条判定

### 2.1 数据层 (data/, 12 文件)

| Android 文件 | 变更 | iOS 判定 |
|---|---|---|
| `data/AppDatabase.kt` | version 11→12, 加 `CourseColorEntity`/`courseColorDao()` | 🔧 B1: iOS DB 加 v12 `course_colors` |
| `data/Migrations.kt` | v11→v12 建 `course_colors` 表, **不回填** | 🔧 B1 |
| `data/entity/CourseColorEntity.kt` | 新表, 复合 PK `(tableKey, groupId)`, `hue REAL`, `GLOBAL_TABLE_KEY="__global__"` | 🔧 B1: 新建 `Sleepy/data/entity/CourseColorEntity.swift` |
| `data/dao/CourseColorDao.kt` | `upsertAll`/`upsert`/`getHueMap`/`getHue`/`clear` | 🔧 B1 |
| `data/dao/TimeTableDao.kt` | `setReminderEnabled(id, enabled)` | 🔧 B3 |
| `data/calendar/AndroidLocalCalendarStore.kt` | 新: 本地日历 provider 抽象 | ⏸ Android 平台专属 (CalendarContract) |
| `data/calendar/LocalCalendarFallback.kt` | 新: 无可写日历时自建本地日历 | 🔧 B6: iOS EventKit 无「自建日历」等价, 但需 `ensureCalendar` 兜底 + 调休日期范围扩展 |
| `data/calendar/SystemCalendarManager.kt` | 改走 fallback; 导入日期范围纳入调休目标日; 事件内容按源日、显示与闹钟按目标日 | 🔧 B6: iOS `SystemCalendarManager.swift` 需同口径 |
| `data/parser/XiaoaiPresetData.kt` | 新: 小爱 presetData 构建 + deep link | 🔧 B6 |
| `data/repository/NewTableImport.kt` | 新: 导入新建课表 | ❌ 缺失 → B7 |
| `data/repository/ScheduleRepository.kt` | (+64) 课表读写扩展 | 🔧 B7 |
| `data/jw/*` (24 文件) | 见 §2.3 | 🔧 B2/B7 |

### 2.2 util/ (8 文件)

| Android 文件 | 变更 | iOS 判定 |
|---|---|---|
| `util/AppPrefs.kt` | +85: `KEY_COURSE_COLOR_MODE`/`KEY_COURSE_COLOR_SEED_HUE`/`KEY_BEFORE_CLASS_MODE` | 🔧 B1/B3 |
| `util/CourseColorUtil.kt` | +204: `safeArcHue`/`resolveHueWithSpacing`/`planHuesForGroups`/`resolveAnchor`/`hueOf`/`persistedHue` | 🔧 B1 |
| `util/CourseColorWriteGlue.kt` | 新: 写入侧 (pinned/recalc), CLASSIC 永不写 | 🔧 B1 |
| `util/CourseHueStore.kt` | 新: 进程级 gid→hue 快照流 | 🔧 B1 |
| `util/DateUtils.kt` | +4: `shortDateChinese` | 🔧 iOS 已有 `shortDate`; 确认语种通用 ✅ |
| `util/HolidayRange.kt` | +22: `courseDateForDate`/`courseDayForDate`/`coursesForDate` | ✅ iOS `HolidayReminderPolicy.swift:56/66` 已等价落地 |
| `util/ImportedPeriodTableDraft.kt` | 新(12行) | 🔧 B7 |
| `util/TimetableViewportPolicy.kt` | +36: `expandWeightsForLongBreaks`/`longBreakCardHeightDp` | 🔧 B5: iOS 用固定 24dp 薄带, 不折权 → 只需 `longBreakCardHeightDp` 口径 (带厚不进卡高) |
| `util/WeekDisplayResolver.kt` | +25: 调休感知的 `todayHasRemaining`/`targetWeek`/`nextDates` | ✅ iOS `WeekDisplayResolver.swift:55/146` 已用 `coursesForDate` |

### 2.3 教务导入 (data/jw/, 24 文件)

新增/重写解析器 12 个: `JwEcuplParser`, `JwEcuplScriptParser`, `JwEcuplSuperParser`, `JwKingoZxParser`, `JwNewUrpSuperParser`, `JwNwpuPostParser`, `JwOldQzSuperParser`, `JwQzTimetableParser`, `JwScauParser`, `JwWakeUpCompatParsers`(+367), `JwSeuParser`(+63), `JwThuparser`(+135) — 全部 ❌ iOS 缺失 → B7。

模型/索引: `JwSchoolInfo.kt`(+35) 🔧 B2; `JwProtocol.kt`(+56) 🔧 B2; `JwParserRegistry.kt`(+23) 🔧 B2; `SchoolSearchIndex.kt`(新) 🔧 B2; `SchoolDomainMatch.kt`(新,+61) 🔧 B2; `SchoolCityIndex.kt`(+9) / `OfflineSchoolCityIndex.kt`(+15) 🔧 B2; `JwImportDraft.kt`(+12, 加 `catalogId` + `requiresSchoolConfirmation`) 🔧 B2; `JwImportViewModel.kt`(+57) 🔧 B2; `JwImportReport.kt`(新) ❌ B6; `JwOldQzParser`/`JwOldZfParser`/`JwQzParser`/`JwNewUrpParser` 既有解析器小改 🔧 B7。

### 2.4 UI (34 文件)

| Android 文件 | 变更 | iOS 判定 |
|---|---|---|
| `ui/screen/mine/AppearanceScreen.kt` | +266: 课程配色段 (三选一 rail + 种子色相滑条 + 实时预览 + 重排按钮) | ❌ B1 |
| `ui/screen/mine/ReminderScreen.kt` | +118: 提醒形态互斥选择 + 「课表提醒」入口行 | ❌ B3 |
| `ui/screen/mine/TableReminderScreen.kt` | 新 | ❌ B3 |
| `ui/screen/mine/WidgetSettingsScreen.kt` | 新 | ❌ B4 |
| `ui/screen/widget/WidgetGalleryScreen.kt` | 新 | ❌ B4 |
| `ui/screen/widget/WidgetManagementScreen.kt` | +34: 右上「＋」进画廊 + ON_RESUME 重扫 | ❌ B4 |
| `ui/screen/today/DailyAgendaActivity.kt` / `DailyAgendaRoute.kt` | 新 | ❌ B5 |
| `ui/screen/mine/AboutScreen.kt` | +39: 隐私政策卡 | ❌ B6 |
| `ui/screen/mine/ExportScreen.kt` | +75: 小爱导出项 + WakeUp 分享改 `SleepyNativeExporter.exportShareText` | 🔧 B6 (iOS 已有 `exportShareText` ✅) |
| `ui/screen/mine/MineScreen.kt` | +36: 「小组件」入口项 | ❌ B4 |
| `ui/screen/mine/GeneralSettingsScreen.kt` | −78: widget 块移出到独立页 | 🔧 B4 |
| `ui/screen/mine/PeriodHeaderSettingsScreen.kt` | +36: 旧式表头「隐藏时间行」开关 + `legacyTimeWidthDp` 预览 | 🔧 B4 (iOS 已有 `KEY_PERIOD_HEADER_HIDE_TIME` + widget 侧 hideTime ✅, 需设置页 + 网格/周视图列宽收口) |
| `ui/screen/mine/EditTableScreen.kt` | +69: 未绑定课表草稿载体统一 (手动↔自动同步) | 🔧 B7 |
| `ui/screen/mine/PeriodTableEditScreen.kt` | +7: 手动改行后 smartConfig 重播种 | 🔧 B7 |
| `ui/screen/mine/LicenseScreen.kt` | +130: 新学校致谢清单 (纯文案) | 🔧 B6 (文案补齐) |
| `ui/component/CourseTableView.kt` | +211: persistedHue 渲染接入 ×3; natural/boundary 两表 (卡高走 natural 跨度, 带厚不进卡高); 线-卡协同 (横线画在间隙中点); 长课间薄带 24dp; 周视图日期 `·M月d日`; WeekStrip 等高 | 🔧 B1 (hue) + B5 (卡高口径/分隔线中点) — iOS 已用 24dp 薄带 ✅, 需补 natural 跨度卡高 + 横线中点 + 周视图日期 ✅ 部分已有 |
| `ui/component/PeriodHeaderCellContent.kt` | +62: `legacyTimeWidthDp` (hideTime 时列宽收口到标签宽, 下限 36dp) | 🔧 B4 |
| `ui/component/ConflictCard.kt` | +37: contentSpanDpOf (高度 natural / 位置 boundary 分离) + persistedHue | 🔧 B1+B5 |
| `ui/component/ColorPickerDialog.kt` | +21: 色相滑条 `onHueCommit` (拖动跟手, 松手落库) | 🔧 B1 |
| `ui/component/ShareScheduleSheet.kt` | +5: 分享改 `SleepyNativeExporter.exportShareText` | ✅ iOS 已有 |
| `ui/screen/schedule/ScheduleScreen.kt` | +46: `displayMaxWeek` (调休目标周并入); 渲染改走 `coursesForDate` 逐日投影; 详情页聚簇同域 | 🔧 B5 |
| `ui/screen/schedule/ScheduleViewModel.kt` | +25: `displayMaxWeek`/`courseDateFor`/`courseDayFor`; `changeWeek` 上限改 displayMaxWeek | 🔧 B5 |
| `ui/screen/today/TodayScreen.kt` | +32: 反向取课 (补班日=sourceDate, 放假日=无课) + persistedHue | 🔧 B1+B5 |
| `ui/nav/SleepyRoutes.kt` / `SleepyNavigator.kt` / `SleepyNavHost.kt` | +24: 新增 3 路由 (TableReminder / WidgetSettings / WidgetGallery) | 🔧 B3/B4 |
| `ui/screen/imports/SchoolSelectScreen.kt` | +76: 状态筛选/未验证学校提示 | 🔧 B2 |
| `ui/screen/imports/JwImportActivity.kt` | +168: 登录/确认流程 | 🔧 B2 |
| `ui/screen/imports/JwWebViewLoginScreen.kt` | +52 | 🔧 B2 |
| `ui/screen/imports/JwWebViewFrameCapture.kt` | +24 | 🔧 B2 |
| `ui/screen/imports/ImportSheet.kt` | +89/− | 🔧 B2 |
| `MainActivity.kt` / `SleepyApp.kt` | 接线: 小组件设置入口 + `CourseHueStore.start` | 🔧 B1/B4 |

### 2.5 widget/ (21 文件)

| Android 文件 | 变更 | iOS 判定 |
|---|---|---|
| `widget/notification/DailyAgenda.kt` | 新 | ❌ B5 |
| `widget/notification/DailyAgendaLoader.kt` | 新 | ❌ B5 |
| `widget/notification/DailyScheduleSummary.kt` | 新 | ❌ B5 |
| `widget/notification/DailySummaryNotificationMigration.kt` | 新 (清理旧日摘要通知) | ❌ B5 |
| `widget/notification/CourseNotificationScheduler.kt` | ±170: 改调休取课语义 + 议程通知接入 | 🔧 B5 |
| `widget/notification/ClassDndScheduler.kt` | +9: 反向取课 | 🔧 B5 (iOS `ClassDndScheduler.swift` 需同口径) |
| `widget/HolidayTransferHelper.kt` | +27: `courseDateForDate`/`courseDayForDate` | ✅ iOS `HolidayTransferHelper.swift:15` 已有 |
| `widget/WidgetWeekDataLoader.kt` | +29 | 🔧 B5 |
| `widget/WidgetContent.kt` | +7 | 🔧 B5 |
| `widget/WidgetGalleryData.kt` / `WidgetPinRequest.kt` | 新 | ❌ B4 |
| `widget/WidgetVariantInfo.kt` | +38: 13 档 base/small/wide 矩阵 | ⏸ 13 档矩阵属原平台机制; iOS 保留 5 kind × family, 画廊按 5 kind 出卡 |
| `widget/WeekGridWidgetProvider.kt` | +190 | 🔧 B5 (iOS WidgetKit 视图层重写) |
| `widget/WidgetBitmapRenderers.kt` | +58 | ⏸ RemoteViews 位图渲染 |
| `widget/WidgetCompactWindow.kt` | +15 | 🔧 B5 |
| `widget/TodayWidget.kt` / `TwoDayWidget.kt` / `WeekListWidget.kt` / `WeekViewWidget.kt` | 各 +7~11 (调休取课) | 🔧 B5 |
| `widget/WeekGridPreviewActivity.kt` / `WidgetRenderActivity.kt` | +6/+2 | ⏸ 原平台 Activity 预览 |

## 3. iOS 侧「已有」免做清单 (复核确认)

- 周视图日期打印 (`CourseTableView.swift:611` `showDate` + `DateUtils.shortDate`)
- 长课间固定 24dp 薄带 (`CourseTableView.swift:531`, widget 侧 `WeekGridWidgetView.swift:352`)
- sleepy-v1 分享格式 (`SleepyNativeExporter.exportShareText`)
- 周网格「最近有课日」(`WeekDisplayResolver.swift`, `WidgetDataLoaders.swift:59`)
- `reminderEnabled` 列 (iOS DB v11 已有)
- widget 无色/分隔线/最近有课日 三个 pref + 字符串 (`settings_widget_colorless` 等)
- `mine_refresh_widgets` / `widget_manage_entry` 字符串
- 调休取课三件套 (`HolidayReminderPolicy.swift:56/66`, `HolidayTransferHelper.swift:15`)

## 4. 原平台独占 / 厂商定制 (暂缓清单)

| 项 | 原因 |
|---|---|
| 实时课程卡 (Fluid Cloud / Live Card) + `VendorLive*` 全套 | 小米/vivo/OPPO/荣耀/华为/魅族厂商 API 不可移植; iOS 对应物 = ActivityKit 实况活动/灵动岛(iOS 16.1+), 本 app 未实现该切片 |
| 电池优化白名单跳转 (`BatteryOptimizationIntents` / `BatterySettingsLauncher`) | 原平台厂商设置页 |
| `RemoteViews` 位图渲染器 (`WidgetBitmapRenderers`) | 原平台渲染机制 |
| PinWidget / WidgetRender / WidgetConfigure Activity | 原平台 Activity 机制 (iOS 用 WidgetKit 配置意图) |
| `ScrollStripService` | 原平台前台服务 |
| 13 档 widget base/small/wide 矩阵 | iOS WidgetKit 以 family 尺寸表达, 5 kind 已覆盖 |
| `HighRefreshRate` | 原平台厂商高刷 API |
| `NoRippleClickable` | Compose 涟漪语义 (iOS 用 ButtonStyle) |
| `ClassicEamsWebVpn` | 属 v1.0.63-dev, 出范围 |

## 5. 实施批次

| 批次 | 内容 | 闸门 |
|---|---|---|
| **B1** | 课程配色三模式: `CourseColorUtil` 移植 + `AppPrefs` 3 键 + DB v12 `course_colors` + DAO/Entity + `CourseHueStore`/`CourseColorWriteGlue` + `AppearanceScreen` 配色段 + 渲染层 `persistedHue` ×4 处 | G1 符号 + G3 五语言 + 单测 |
| **B2** | 学校目录: `schools.json` 升级 4140 条 + status/catalogId schema + `JwSchoolInfo` 扩展 + `SchoolSearchIndex`/`SchoolDomainMatch` + `SchoolSelectScreen` + `JwImportDraft` catalogId | 数据校验脚本 + 单测 |
| **B3** | 提醒形态互斥 + `TableReminderScreen` + 路由 + `TimeTableDao.setReminderEnabled` | 单测 + UI 冒烟 |
| **B4** | 小组件: `WidgetSettingsScreen` 独立页 + `WidgetGalleryScreen` 画廊 + `WidgetGalleryData` + 路由 + MineScreen 入口 + 旧式表头 hideTime 列宽收口 | XCUITest 冒烟 |
| **B5** | 每日议程: `DailyAgenda`/`DailyAgendaLoader`/`DailyScheduleSummary`/`DailySummaryNotificationMigration` + 议程页 + 深链 + `displayMaxWeek` + natural/boundary 卡高口径 + 分隔线中点 + 通知调度接入 | 单测 + 深链冒烟 |
| **B6** | 字符串与周边: 五语言新键全量 + 隐私政策卡 + 小爱导出 + `JwImportReport` + `LicenseScreen` 文案 + 日历导入调休口径 + `LocalCalendarFallback` iOS 等价 | G3 零缺 + 导出往返 |
| **B7** | 教务解析器 12 个新协议 + `NewTableImport` + `ImportedPeriodTableDraft` + `EditTableScreen` 草稿载体 + `PeriodTableEditScreen` smartConfig 重播种 + `ScheduleRepository` | 解析器单测 + fixture 链 |

## 6. 未验证 / 风险

- B7 的 12 个协议解析器需要每校真实 HTML 快照或反编译参考, 否则只能按原源码逐行翻译 + 合成 fixture 测试; 真站冒烟需用户账号。
- B5 的议程通知需真机验证 (通知触发时机、跨天窗口)。
- B2 的 4140 条目录含 2361 条 `pending` / 301 条 `grad_pending` — 这些只有元数据, 无可用 URL, 需确认 iOS 是否展示不可导入学校 (原平台展示并标状态)。

## 7. 失败复盘(已修)

### 7.1 `WebViewNavigationPolicyTests.testNormalNavigationUnaffectedByFix` 长期失败 — 测试夹具缺陷, 非产品缺陷

**现象**: 该用例在 `21c7c7c` 及更早的 HEAD 上**确定性失败**(4/4 次), 与 B2 无关;
`testTargetBlankOpensInPlaceWithUIDelegate` / `testWindowOpenOpensInPlaceWithUIDelegate` 同样导航到
`page2.html` 却能通过。

**根因**: 夹具 `LocalPageServer` 是**单线程 accept 循环 + 同步 read()**。WebKit 会为同一 origin
建立「投机性预连接」(speculative preconnect)—— 该 socket 建连后**不发送任何请求**。
服务器在 accept 循环里同步 `read()` 阻塞在这个空连接上, 真正的 `GET /page2.html` 只能排在
accept 队列(backlog)里, 直到 WebKit 预连接超时(约 3s)才被 accept。

**证据**:
- 给服务器加时间戳日志: 第二次 `accept` 返回于 `t+0.35s`, 但 `read` 直到 `t+3.40s` 才拿到 513 字节
  (延迟 ≈ WebKit 预连接超时), 而用例断言窗口只有 3s。
- 同页 `target=_blank` / `window.open` 用例通过, 因为它们走 `NavUIDelegate.createWebViewWith` →
  `webView.load()`, 是**新建**一次连接, 不复用被预连接占住的 origin socket。
- A/B 对照(同模板、同 harness、各 5 次): 原单线程服务器 **2/5 通过**; 每连接一线程服务器 **5/5 通过**。

**修复**: `LocalPageServer` 改为**每连接独立线程**处理, 空连接与真实请求互不阻塞。
产品代码 `NavUIDelegate` **未改动** — 该用例本来就是回归锁, 它的失败是夹具自身的缺陷。

**修复后验证**: WebView 套件 3/3 绿; 全量 `SleepyTests` 1529 通过 / 8 跳过 / **0 失败**。


### 7.2 UI 测试「切换底栏失败」16 条同因失败 — 断言方式缺陷, 非产品缺陷

**现象**: 全量 UI 测试里 16 条失败, 全部报
`切换到底栏 tab mine 失败(选中态未翻转, 当前选中: mine)` — 失败信息自相矛盾:
「当前选中」打印的就是 `mine`, 即目标 tab 其实已经切过去了。

**根因**: 旧实现用 `XCTNSPredicateExpectation` 等「选中 trait 翻转」。该 expectation 的
predicate 在**后台线程**求值, 而 `XCUIElement` 的查询(`exists` / `isSelected` /
`descendants`)只在主线程有效 ⇒ 谓词恒为 false ⇒ 即使 UI 已经满足条件也会被判失败。

**次因**:
- 「我的」页首屏很重: 实测 tap 后 app 需 ~16s 才 idle, 旧 helper 的 10s 截止时间会在
  切换其实已生效时提前判失败。
- 旧写法 `tap(); sleep(1)` **没有任何「切换真的发生了」的断言**, tap 被吞
  (底栏重建首帧 / refreshNavMode 重判 / tab 切换过渡动画)时, 错误现场
  (`manage_import 未找到`) 与真正病因隔得很远。

**修复**: 新增统一 helper `switchToPillTab(_:timeout:)`(见 `SleepyUITests/UITestLaunch.swift`):
主线程手动轮询选中 trait、每 1s 补一次点击重试被吞的 tap、默认超时 30s、
轮询只查目标 tab(元素查询每次 ~200-900ms, 查 4 个 tab 会超时)。同款后台线程谓词缺陷
在 `ButtonHitAreaUITests` 里出现了第二次, 一并改为轮询。

### 7.3 「检查更新」用例把「无更新」当成失败

**现象**: `ButtonHitAreaUITests` 偶发 25s 超时失败。

**根因**: 旧断言只等结果 sheet。而 `AboutScreen.checkUpdate` 在「已是最新版本」时走的是
snackbar(`uiState == .idle` + `snackMessage`), 不是 sheet ⇒ app 行为正确却被判失败。

**修复**: 结果信号改为「snackbar 或 sheet 任一出现」即视为动作已触发; 并给 snackbar
补稳定标识 `about_snackbar`。

### 7.4 导入预览页「闪一下就消失」+ 确认弹窗点不到

**根因 1**: `.sheet(item:)` 的 `get` 闭包在父视图**每次重绘**时被重新求值,
`PreviewBox.id` 又是每次 `new UUID()` ⇒ 同一份预览每次渲染都是新身份 ⇒ SwiftUI
反复 dismiss + 重新 present。修复: id 改为内容派生(表/日期/课程数/冲突数)。

**根因 2**: 确认弹窗原本是预览页里的 `.sheet`。iOS 上**挂在已 present 的 sheet 内部的
`.sheet` 会被静默丢弃** ⇒ 确认按钮永远不出现。修复: 改为预览页内的 ZStack 叠层
(scrim + 确认内容)。

**根因 3**: 键盘未收起时, 预览页内容容器被顶到 y=874, 模式按钮落到屏幕外。修复:
present 预览前先 `dismissKeyboard()`。

### 7.5 加课时段删除闪退 (`EXC_BREAKPOINT`)

**根因**: `bindingForBlock(at: index)` 的 getter/setter 直接 `meetingBlocks[index]`。
删除时段时数组收缩, 但仍在消失中的卡片(`Switch.updateUIView` 等)继续读这个绑定 ⇒
`Array._checkSubscript` 越界 ⇒ SIGTRAP。

**修复**: 绑定改为按 `block.id` 查找; 找不到时返回占位稿且写入丢弃;
删除走 `removeBlock(withId:)`。

### 7.6 UI 测试跑批偶发 `XCTDaemonErrorDomain Code=18 Timed out waiting for AX loaded notification`

**判定**: 模拟器侧无障碍守护进程超时, 与被测代码无关(整批尚未开始执行用例即中止)。
**处置**: 停止挂死的 `xcodebuild` 进程 → `simctl shutdown` + `simctl boot` 重启模拟器
→ 重新 `build-for-testing` → 重跑。
