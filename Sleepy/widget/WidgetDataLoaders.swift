// WidgetDataLoaders.swift — ← 各 Receiver.loadDataSync (TodayWidget/WeekListWidget/
// TwoDayWidget/WeekViewWidget.kt companion) + WeekGridWidgetProvider.loadWeekData
//
// TimelineProvider 在后台拉数据 → 组装 WidgetData/WeekData/TwoDayData 喂给 SwiftUI 视图。
// 数据加载逻辑逐行对齐 Android;App 单例(SleepyApp.get())→ 直接 AppDatabase.getShared()
// (widget extension 进程独立,单例在 extension 内自建,共享容器数据库见 AppGroupResolver)。
//
// widgetURL 深链: Android PendingIntent(MainActivity) → widgetURL(sleepy://open)
// (平台差异表#4: MainActivity Intent → iOS URL scheme,onOpenURL 统一处理)。

import Foundation
import WidgetKit

/// 共享取 DB 依赖 — 各 loader 用同一入口,失败回退空数据(对齐 Android try/catch 回退)
enum WidgetLoader {
    static func makeRepo() -> ScheduleRepository? {
        ScheduleRepository(AppDatabase.getShared())
    }

    // ← WidgetEditViewModel.reload / WidgetManagementViewModel.reload 的取表序列:
    //   先查 per-widget 绑定(表仍存在),否则 WidgetTableResolver.resolveCurrentTable。
    //   kind 传 nil = 走全局默认(无绑定语义)。
    static func tableFor(kind: String?, repo: ScheduleRepository) -> TimeTableEntity? {
        if let kind = kind,
           let bound = WidgetBindingStore.resolveBoundTable(kind, repo: repo) {
            return bound
        }
        return WidgetTableResolver.resolveCurrentTable(repo)
    }
}

// MARK: - Today ← TodayWidget.loadDataSync (v1.0.61 对齐, async)

/// Today 专用装载器 — 逐行对齐 Android TodayWidget.kt:443-500 loadDataSync:
/// now 单钟贯穿 → 导航锚定日 (TodayDateNavStore.target) → 手动导航态禁用
/// autoNearestBusyDay → NEAREST_BUSY_DAY 自动跳日 (WidgetWeekDataLoader.resolve
/// 的 display.targetDate) → 调休日期取课 (coursesForDate, Android coursesOn 同源)
/// → courseDateForDate 学期状态 → isGrey (HolidayManager.shouldGrey) →
/// weekDisplayStatus (statusForSelectedDate)。
/// Android runBlocking → iOS async (与 TwoDay/WeekList loader 同模式)。
enum TodayWidgetLoader {
    static func loadData(kind: String) async -> WidgetData {
        // now 只取一次贯穿全程 (Android 注释: 两次 now() 跨午夜 = 单次渲染口径分裂)
        let today = Date()
        let prefs = AppPrefs.shared
        let isDark = prefs.isDarkMode()
        let themeKey = prefs.getThemeKey()
        let themeMode = prefs.getThemeMode()
        // 导航锚定日 (无导航态 → today; iOS 无翻页 UI 入口, Store 语义仍对齐)
        let manualNavigation = TodayDateNavStore.hasNavigation(kind)
        let target = TodayDateNavStore.target(kind, today)
        let autoNearestBusyDay = !manualNavigation
        let fallback = WidgetData(date: target, courses: [], timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                                  hasTable: false, isDark: isDark, themeKey: themeKey, themeMode: themeMode,
                                  isToday: Calendar.current.isDate(target, inSameDayAs: today))
        guard let source = await WidgetWeekDataLoader.resolve(kind) else { return fallback }
        let table = source.table
        let effectiveTarget: Date
        if autoNearestBusyDay, source.display.status == .nearestBusyDay {
            effectiveTarget = source.display.targetDate
        } else {
            effectiveTarget = target
        }
        // 学期状态按"课实际来自哪天"判 (Android courseDateForDate ?: effectiveTarget)
        let status = DateUtils.semesterStatus(
            startDate: table.startDate, maxWeek: table.maxWeek,
            today: HolidayTransferHelper.courseDateForDate(table.id, effectiveTarget) ?? effectiveTarget)
        let visible = source.coursesOn(effectiveTarget)
        return WidgetData(
            date: effectiveTarget,
            courses: visible,
            timeJson: table.timeJson,
            hasTable: true,
            isDark: isDark,
            themeKey: themeKey,
            themeMode: themeMode,
            semesterStatus: status,
            isToday: Calendar.current.isDate(effectiveTarget, inSameDayAs: today),
            isGrey: await HolidayManager.shouldGrey(effectiveTarget, tableId: table.id),
            weekDisplayStatus: WeekDisplayResolver.statusForSelectedDate(
                context: source.display, selectedDate: effectiveTarget)
        )
    }
}

// WeekList / WeekView 装载器不在本文件: v1.0.61 对齐后由 WeekListWidgetView.swift 的
// WeekListWidgetDataLoader.loadData (async) 逐行承担 (两者共用 — Android 注释
// 「WeekViewWidget.loadDataSync 与 WeekListWidget 完全一致」) —— 旧同步枚举
// (无 resolve 展示周 / 无 AFTER_END 清空 / 无调休映射 / isGrey 恒 false /
// 无 compactWindow / 无 weekDisplayStatus) 已无任何调用方, 作为错位漂移源删除
// (同 TwoDayWidgetLoader 先例)。

// TwoDay 装载器不在本文件: v1.0.61 对齐后由 TwoDayWidgetView.swift 的
// TwoDayWidgetDataLoader.loadData (async) 逐行承担 —— 旧同步枚举 (写死 today/+86400、
// 无调休映射、isGrey 恒 false、无 weekDisplayStatus) 已无任何调用方, 作为错位漂移源删除。

// MARK: - WeekGrid ← WeekGridWidgetProvider.loadWeekData (v1.0.61 对齐, async)

enum WeekGridWidgetLoader {
    /// 逐行对齐 Android loadWeekData (WeekGridWidgetProvider.kt:1013-1064):
    /// WidgetWeekDataLoader.resolve → dateFor(dow)/coursesOn(previewBeforeStart)
    /// 调休按日期取课 → isGrey → AFTER_END 有课改 IN_RANGE → weekDisplayStatus +
    /// nearestBusyTargetDate; 无表/异常回退 hasTable=false 空数据。
    static func loadWeekData(kind: String? = nil) async -> WeekData {
        let prefs = AppPrefs.shared
        let isDark = prefs.isDarkMode()
        let themeKey = prefs.getThemeKey()
        let themeMode = prefs.getThemeMode()
        let showDate = prefs.isShowDate()
        let visibleDays = prefs.getVisibleDays()
        func empty() -> WeekData {
            WeekData(days: [], hasTable: false, isDark: isDark, themeKey: themeKey,
                     themeMode: themeMode, showDate: showDate, visibleDays: visibleDays)
        }
        guard let source = await WidgetWeekDataLoader.resolve(kind ?? "") else { return empty() }
        let table = source.table
        // ← Android L1029: 学期前: 第 1 周课照常显示(预习); 学期后: 课程清空, renderer 画状态行
        var days: [DayData] = []
        for dow in 1...7 {
            let date = source.dateFor(dayOfWeek: dow)
            let courses = source.coursesOn(date, previewBeforeStart: true)
            days.append(DayData(date: date, dayOfWeek: dow, courses: courses,
                                timeJson: table.timeJson,
                                isGrey: await HolidayManager.shouldGrey(date, tableId: table.id)))
        }
        // ← Android L1046: 任一天有课且学期后 → IN_RANGE (补班日课程照常渲染)
        let status = days.contains(where: { !$0.courses.isEmpty }) && source.display.semesterStatus == .afterEnd
            ? DateUtils.SemesterStatus.inRange : source.display.semesterStatus
        return WeekData(days: days, hasTable: true, isDark: isDark, themeKey: themeKey,
                        themeMode: themeMode, showDate: showDate, visibleDays: visibleDays,
                        semesterStatus: status,
                        weekDisplayStatus: source.display.status,
                        nearestBusyTargetDate: source.display.status == .nearestBusyDay
                            ? source.display.targetDate : nil)
    }
}
