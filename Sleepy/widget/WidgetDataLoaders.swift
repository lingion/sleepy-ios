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

// MARK: - Today ← TodayWidgetReceiver.loadDataSync

enum TodayWidgetLoader {
    static func loadDataSync(kind: String? = nil) -> WidgetData {
        let today = Date()
        let dayOfWeek = DateUtils.todayDayOfWeek(today: today)
        let prefs = AppPrefs.shared
        let isDark = prefs.isDarkMode()
        let themeKey = prefs.getThemeKey()
        let themeMode = prefs.getThemeMode()
        do {
            guard let repo = WidgetLoader.makeRepo(),
                  let table = WidgetLoader.tableFor(kind: kind, repo: repo) else {
                return WidgetData(date: today, courses: [], timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                                  hasTable: false, isDark: isDark, themeKey: themeKey, themeMode: themeMode)
            }
            let week = DateUtils.currentWeek(startDate: table.startDate, today: today)
            let status = DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: today)
            let all = try repo.getCoursesByDay(table.id, day: dayOfWeek)
            let visible = all.filter { $0.inWeek(week) }.sorted { $0.startNode < $1.startNode }
            return WidgetData(date: today, courses: visible, timeJson: table.timeJson,
                              hasTable: true, isDark: isDark, themeKey: themeKey, themeMode: themeMode, semesterStatus: status)
        } catch {
            return WidgetData(date: today, courses: [], timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                              hasTable: false, isDark: isDark, themeKey: themeKey, themeMode: themeMode)
        }
    }
}

// MARK: - WeekList / WeekView ← WeekListWidget.loadDataSync (两者完全一致)

enum WeekListWidgetLoader {
    static func loadDataSync(kind: String? = nil) -> WeekData {
        let today = Date()
        let prefs = AppPrefs.shared
        let isDark = prefs.isDarkMode()
        let themeKey = prefs.getThemeKey()
        let themeMode = prefs.getThemeMode()
        do {
            guard let repo = WidgetLoader.makeRepo(),
                  let table = WidgetLoader.tableFor(kind: kind, repo: repo) else {
                return WeekData(days: [], hasTable: false, isDark: isDark, themeKey: themeKey, themeMode: themeMode)
            }
            let week = DateUtils.currentWeek(startDate: table.startDate, today: today)
            let status = DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: today)
            let days = try (1...7).map { dayOfWeek -> DayData in
                let date = DateUtils.dateOfWeekDay(ref: today, dayOfWeek: dayOfWeek)
                let all = try repo.getCoursesByDay(table.id, day: dayOfWeek)
                let visible = all.filter { $0.inWeek(week) }.sorted { $0.startNode < $1.startNode }
                return DayData(date: date, dayOfWeek: dayOfWeek, courses: visible, timeJson: table.timeJson)
            }
            return WeekData(days: days, hasTable: true, isDark: isDark, themeKey: themeKey, themeMode: themeMode, semesterStatus: status)
        } catch {
            return WeekData(days: [], hasTable: false, isDark: isDark, themeKey: themeKey, themeMode: themeMode)
        }
    }
}

// TwoDay 装载器不在本文件: v1.0.61 对齐后由 TwoDayWidgetView.swift 的
// TwoDayWidgetDataLoader.loadData (async) 逐行承担 —— 旧同步枚举 (写死 today/+86400、
// 无调休映射、isGrey 恒 false、无 weekDisplayStatus) 已无任何调用方, 作为错位漂移源删除。

// MARK: - WeekGrid ← WeekGridWidgetProvider.loadWeekData

enum WeekGridWidgetLoader {
    static func loadWeekData(kind: String? = nil) -> WeekData {
        let today = Date()
        let prefs = AppPrefs.shared
        let isDark = prefs.isDarkMode()
        let themeKey = prefs.getThemeKey()
        let themeMode = prefs.getThemeMode()
        let showDate = prefs.isShowDate()
        let visibleDays = prefs.getVisibleDays()
        do {
            guard let repo = WidgetLoader.makeRepo(),
                  let table = WidgetLoader.tableFor(kind: kind, repo: repo) else {
                return WeekData(days: [], hasTable: false, isDark: isDark, themeKey: themeKey, themeMode: themeMode,
                                showDate: showDate, visibleDays: visibleDays)
            }
            let week = DateUtils.currentWeek(startDate: table.startDate, today: today)
            let status = DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: today)
            let days = try (1...7).map { dow -> DayData in
                let all = try repo.getCoursesByDay(table.id, day: dow)
                let visible = all.filter { $0.inWeek(week) }.sorted { $0.startNode < $1.startNode }
                let date = DateUtils.dateOfWeekDay(ref: today, dayOfWeek: dow)
                return DayData(date: date, dayOfWeek: dow, courses: visible, timeJson: table.timeJson)
            }
            return WeekData(days: days, hasTable: true, isDark: isDark, themeKey: themeKey, themeMode: themeMode,
                            showDate: showDate, visibleDays: visibleDays, semesterStatus: status)
        } catch {
            return WeekData(days: [], hasTable: false, isDark: isDark, themeKey: themeKey, themeMode: themeMode,
                            showDate: showDate, visibleDays: visibleDays)
        }
    }
}
