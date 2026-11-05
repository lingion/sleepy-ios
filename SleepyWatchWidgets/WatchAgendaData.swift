// WatchAgendaData.swift — 5 个新 kind 的快照装载 (2026-11 watch 小组件扩展)
//
// extension 进程独立 → 纯函数直读手表本地 GRDB (App Group 同容器),
// 同现有 WatchComplicationData 模式; 业务口径全在 WatchAgendaCore。
//
// 视图分层原则: 快照只带数据; 「假期中/无课/已结束」等兜底的优先级由视图按
// 内容-first 决定 (如补班日 inSemester=false 但有课 → 先显示课, 不误报假期)。

import Foundation

/// 「正在上的课」
struct WatchCurrentSnapshot {
    let items: [WatchAgendaCore.ClassItem]  // 今日全部 (boundary 用)
    let current: WatchAgendaCore.ClassItem?
    let next: WatchAgendaCore.ClassItem?
    let inSemester: Bool
}

/// 「今日课程一览」
struct WatchTodaySnapshot {
    let items: [WatchAgendaCore.ClassItem]
    let current: WatchAgendaCore.ClassItem?
    let remaining: [WatchAgendaCore.ClassItem]  // 未开始 (startDate > now)
    let hasAnyClass: Bool                       // 区分「已结束」与「无课」
    let inSemester: Bool
}

/// 「今日概览」
struct WatchOverviewSnapshot {
    let week: Int
    let maxWeek: Int
    let totalCount: Int                        // 今日全部节数
    let first: WatchAgendaCore.ClassItem?
    let last: WatchAgendaCore.ClassItem?
    let inSemester: Bool
}

/// 「明日课程」
struct WatchTomorrowSnapshot {
    let items: [WatchAgendaCore.ClassItem]
    let inSemester: Bool                       // 明日学期状态 (非今日)
}

/// 「第 N 周 · 学期进度」
struct WatchWeekSnapshot {
    let week: Int
    let maxWeek: Int
    let ratio: Double
    let inSemester: Bool
}

enum WatchAgendaData {

    static func loadCurrentClass(now: Date = Date()) -> WatchCurrentSnapshot {
        guard let ctx = context() else {
            return WatchCurrentSnapshot(items: [], current: nil, next: nil, inSemester: false)
        }
        let items = WatchAgendaCore.dayItems(table: ctx.table, courses: ctx.courses, date: now)
        return WatchCurrentSnapshot(
            items: items,
            current: WatchAgendaCore.currentClass(in: items, now: now),
            next: WatchAgendaCore.nextClass(in: items, now: now),
            inSemester: WatchAgendaCore.semesterStatus(table: ctx.table, date: now) == .inRange)
    }

    static func loadTodayList(now: Date = Date()) -> WatchTodaySnapshot {
        guard let ctx = context() else {
            return WatchTodaySnapshot(items: [], current: nil, remaining: [],
                                      hasAnyClass: false, inSemester: false)
        }
        let items = WatchAgendaCore.dayItems(table: ctx.table, courses: ctx.courses, date: now)
        return WatchTodaySnapshot(
            items: items,
            current: WatchAgendaCore.currentClass(in: items, now: now),
            remaining: items.filter { $0.startDate > now },
            hasAnyClass: !items.isEmpty,
            inSemester: WatchAgendaCore.semesterStatus(table: ctx.table, date: now) == .inRange)
    }

    static func loadOverview(now: Date = Date()) -> WatchOverviewSnapshot {
        guard let ctx = context() else {
            return WatchOverviewSnapshot(week: 1, maxWeek: 1, totalCount: 0,
                                         first: nil, last: nil, inSemester: false)
        }
        let info = WatchAgendaCore.weekInfo(table: ctx.table, date: now)
        let items = WatchAgendaCore.dayItems(table: ctx.table, courses: ctx.courses, date: now)
        return WatchOverviewSnapshot(
            week: info.week, maxWeek: info.maxWeek,
            totalCount: items.count, first: items.first, last: items.last,
            inSemester: WatchAgendaCore.semesterStatus(table: ctx.table, date: now) == .inRange)
    }

    static func loadTomorrow(now: Date = Date()) -> WatchTomorrowSnapshot {
        let cal = Calendar(identifier: .gregorian)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        guard let ctx = context() else { return WatchTomorrowSnapshot(items: [], inSemester: false) }
        return WatchTomorrowSnapshot(
            items: WatchAgendaCore.dayItems(table: ctx.table, courses: ctx.courses, date: tomorrow),
            inSemester: WatchAgendaCore.semesterStatus(table: ctx.table, date: tomorrow) == .inRange)
    }

    static func loadWeek(now: Date = Date()) -> WatchWeekSnapshot {
        guard let ctx = context() else {
            return WatchWeekSnapshot(week: 1, maxWeek: 1, ratio: 0, inSemester: false)
        }
        let info = WatchAgendaCore.weekInfo(table: ctx.table, date: now)
        return WatchWeekSnapshot(
            week: info.week, maxWeek: info.maxWeek, ratio: info.ratio,
            inSemester: WatchAgendaCore.semesterStatus(table: ctx.table, date: now) == .inRange)
    }

    // MARK: - 内部

    /// ← WatchComplicationData.load 同源: 默认表 + 全量课程
    private static func context() -> (table: TimeTableEntity, courses: [CourseEntity])? {
        let repo = ScheduleRepository(AppDatabase.getShared())
        guard let table = WidgetTableResolver.resolveCurrentTable(repo) else { return nil }
        let courses = (try? repo.getCourses(table.id)) ?? []
        return (table, courses)
    }
}
