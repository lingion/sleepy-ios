# 附录A · 76 个生产文件映射表(87 含 11 个测试)

## data/(13 文件)

| Kotlin | 行 | → Swift | 批次 |
|---|---|---|---|
| AppDatabase.kt | | data/AppDatabase.swift (GRDB) | D1 |
| dao/CourseDao.kt | | data/dao/CourseDao.swift | D1 |
| dao/TimeTableDao.kt | | data/dao/TimeTableDao.swift | D1 |
| entity/CourseEntity.kt | | data/entity/CourseEntity.swift | D1 |
| entity/TimeTableEntity.kt | | data/entity/TimeTableEntity.swift | D1 |
| entity/SmartPeriodConfig.kt | | data/entity/SmartPeriodConfig.swift | D1 |
| jw/JwCourse.kt | 22 | data/jw/JwCourse.swift | D2 |
| jw/JwProtocol.kt | 66 | data/jw/JwProtocol.swift | D2 |
| jw/JwSchoolInfo.kt | 32 | data/jw/JwSchoolInfo.swift | D2 |
| jw/JwParser.kt | 27 | data/jw/JwParser.swift | D2 |
| jw/JwQzParser.kt | 127 | data/jw/JwQzParser.swift | D2 |
| jw/JwQzCrazyParser.kt | 14 | data/jw/JwQzCrazyParser.swift | D2 |
| jw/JwUrpParser.kt | 152 | data/jw/JwUrpParser.swift | D2 |
| jw/JwNewUrpParser.kt | 193 | data/jw/JwNewUrpParser.swift | D2 |
| jw/JwNewZfParser.kt | 324 | data/jw/JwNewZfParser.swift | D2 |
| jw/JwWiseduParser.kt | 113 | data/jw/JwWisedu/JwWiseduParser.swift | D2 |
| jw/JwImportViewModel.kt | 237 | data/jw/JwImportViewModel.swift | D2 |
| parser/ScheduleParser.kt | 738 | data/parser/ScheduleParser.swift | D3 |
| parser/ScheduleExporter.kt | 187 | data/parser/ScheduleExporter.swift | D3 |
| repository/ScheduleRepository.kt | | data/repository/ScheduleRepository.swift | D3 |

## util/(9 文件)

| Kotlin | → Swift | 批次 |
|---|---|---|
| AppPrefs.kt | util/AppPrefs.swift (UserDefaults) | D1 |
| CourseColorUtil.kt | util/CourseColorUtil.swift (黄金角 HSL) | D1 |
| DateUtils.kt | util/DateUtils.swift | D1 |
| PinyinMatcher.kt | util/PinyinMatcher.swift (311 行数据表全搬) | D1 |
| TimeTableUtils.kt | util/TimeTableUtils.swift | D1 |
| LocaleHelper.kt | util/LocaleHelper.swift | D1 |
| VersionUtils.kt | util/VersionUtils.swift | D1 |
| UpdateInfo.kt | util/UpdateInfo.swift | D1 |
| UpdateManager.kt | util/UpdateManager.swift | D1 |

## ui/theme(2)

| Theme.kt (390) | ui/theme/Theme.swift | D4 |
| ThemePresets.kt (371) | ui/theme/ThemePresets.swift | D4 |

## ui/component(7)

| CourseDetailSheet.kt | ui/component/CourseDetailSheet.swift | D5 |
| CourseTableView.kt (716) | ui/component/CourseTableView.swift | D5 |
| DateTimePickers.kt | ui/component/DateTimePickers.swift | D5 |
| PillNavigationBar.kt | ui/component/PillNavigationBar.swift | D5 |
| SegmentedSwitcher.kt | ui/component/SegmentedSwitcher.swift | D5 |
| SmartPeriodEditor.kt (455) | ui/component/SmartPeriodEditor.swift | D5 |
| TimeSlotEditor.kt (241) | ui/component/TimeSlotEditor.swift | D5 |

## ui/screen(19)

| schedule/ScheduleScreen.kt (427) | ui/screen/ScheduleScreen.swift | D6 |
| schedule/ScheduleViewModel.kt | ui/screen/ScheduleViewModel.swift | D6 |
| today/TodayScreen.kt (252) | ui/screen/TodayScreen.swift | D6 |
| edit/AddCourseScreen.kt (1258) | ui/screen/AddCourseScreen.swift | D6 |
| mine/MineScreen.kt | ui/screen/MineScreen.swift | D6 |
| mine/AllTablesScreen.kt | ui/screen/AllTablesScreen.swift | D6 |
| mine/EditTableScreen.kt (369) | ui/screen/EditTableScreen.swift | D6 |
| mine/ExportScreen.kt (347) | ui/screen/ExportScreen.swift | D6 |
| mine/ReminderScreen.kt (601) | ui/screen/ReminderScreen.swift | D6 |
| mine/AppearanceScreen.kt (420) | ui/screen/AppearanceScreen.swift | D6 |
| mine/GeneralSettingsScreen.kt | ui/screen/GeneralSettingsScreen.swift | D6 |
| mine/AboutScreen.kt (367) | ui/screen/AboutScreen.swift | D6 |
| mine/UpdateChangelogDialog.kt | ui/component/UpdateChangelogDialog.swift | D6 |
| manage/ManagementPage.kt | ui/screen/ManagementPage.swift | D6 |
| imports/ImportSheet.kt (911) | ui/screen/ImportSheet.swift | D6 |
| imports/SchoolSelectScreen.kt (522) | ui/screen/SchoolSelectScreen.swift | D6 |
| imports/JwImportActivity.kt (314) | ui/screen/JwImportFlow.swift | D6 |
| imports/JwWebViewLoginScreen.kt (517) | ui/screen/JwWebViewLoginScreen.swift (WKWebView) | D6 |
| imports/ImportReceiverActivity.kt | App onOpenURL + CFBundleDocumentTypes(平台差异#4) | D6 |

## widget/(14 文件)

| WidgetContent.kt | SleepyWidget/WidgetContent.swift(共享数据模型) | D7 |
| WidgetTableResolver.kt | SleepyWidget/WidgetTableResolver.swift | D7 |
| RemoteViewsWidgetHelper.kt | 色彩/布局计算函数并入各 WidgetView(差异#5) | D7 |
| WidgetBitmapRenderers.kt (616) | 5 个 SwiftUI WidgetView,排版逻辑逐函数 | D7 |
| TodayWidget.kt | SleepyWidget/TodayWidget.swift | D7 |
| TwoDayWidget.kt | SleepyWidget/TwoDayWidget.swift | D7 |
| WeekListWidget.kt | SleepyWidget/WeekListWidget.swift | D7 |
| WeekViewWidget.kt | SleepyWidget/WeekViewWidget.swift | D7 |
| WeekGridWidgetProvider.kt (695) | SleepyWidget/WeekGridWidget.swift | D7 |
| WidgetUpdater.kt | WidgetCenter reload 封装(差异#6) | D7 |
| WidgetUpdateWorker.kt | TimelineRefreshStrategy 并入 WidgetBundle(差异#6) | D7 |
| PinWidgetActivity.kt | 静态 gallery 描述(差异#7) | D7 |
| WeekGridPreviewActivity.kt | 静态 gallery 预览快照 | D7 |
| WidgetRenderActivity.kt | 不需要(调试用渲染入口) | D7 |
| notification/CourseNotificationScheduler.kt (539) | util/CourseNotificationScheduler.swift (UNUserNotificationCenter,差异#1) | D7 |
| notification/FluidCloudService.kt | 🚫 平台跳过(差异#3) | — |

## 根(2)

| SleepyApp.kt | SleepyApp.swift | D8 |
| MainActivity.kt (282) | MainActivity.swift(导航壳+onOpenURL) | D8 |

## 测试(11 文件 → SleepyTests/)

| AppPrefsIsolationTest.kt | AppPrefsIsolationTests.swift | 随D1 |
| CourseColorUtilTest.kt | CourseColorUtilTests.swift | 随D1 |
| util/DateUtilsTest.kt | DateUtilsTests.swift | 随D1 |
| util/VersionUtilsTest.kt | VersionUtilsTests.swift | 随D1 |
| util/UpdateInfoParseTest.kt | UpdateInfoParseTests.swift | 随D1 |
| data/entity/SmartPeriodConfigTest.kt | SmartPeriodConfigTests.swift | 随D1 |
| data/jw/JwParserTest.kt | JwParserTests.swift | 随D2 |
| data/jw/JwNewZfParserTest.kt | JwNewZfParserTests.swift | 随D2 |
| data/jw/JwWiseduParserTest.kt | JwWiseduParserTests.swift | 随D2 |
| data/parser/ExportImportRoundTripTest.kt | ExportImportRoundTripTests.swift | 随D3 |
| StringsKeyParityTest.kt | StringsKeyParityTests.swift(五语言389键) | 随D1 |
