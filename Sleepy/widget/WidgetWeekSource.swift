// WidgetWeekSource.swift — ← widget/WidgetWeekDataLoader.kt
// 小部件统一读取课表并计算展示日,避免各 provider 各自判定"今天之后最近一节有课的天"。
//
// v2 (用户 2026-09-20 改向):
//   - display.targetDate 是 widget 应该呈现的"今天"(可能是被自动跳到的那一天)。
//   - dateFor(dayOfWeek) 给的是展示周里 dayOfWeek 的真实日期(基于 targetWeek 计算)。
//
// ★ 平台差异 (WidgetBindingStore.swift 头注同源): Android per-appWidgetId → iOS per-kind。
//   此处 appWidgetId 参数 = kind 字符串 (iOS 等价粒度, 详见 WidgetBindingStore)。

import Foundation

struct WidgetWeekSource {
    let table: TimeTableEntity
    let courses: [CourseEntity]
    let display: WeekDisplayContext
    /// ← Kotlin WidgetWeekSource.transfers (v1.0.61): 调休映射随 source 携带,
    /// coursesOn / 装载器按日期反向查共用 (Android source.transfers 同源)。
    let transfers: [HolidayTransferEntry]

    func coursesFor(dayOfWeek: Int, week: Int? = nil) -> [CourseEntity] {
        let w = week ?? display.targetWeek
        return courses
            .filter { $0.day == dayOfWeek && $0.inWeek(w) }
            .sorted { $0.startNode < $1.startNode }
    }

    /// ← Kotlin WidgetWeekSource.coursesOn (v1.0.61 口径, 调休按日期反向查):
    /// AFTER_END 且非补班日 → 清空; BEFORE_START 且无映射命中该日 → 按周1 自然星期预习;
    /// 其余走 HolidayTransferOps.coursesForDate (补班日=sourceDate 的课, 放假日=无课)。
    /// fixedDate 定日课 iOS 实体无此字段 (上游缺口, 移植时恒空)。
    func coursesOn(_ date: Date, previewBeforeStart: Bool = false) -> [CourseEntity] {
        let key = HolidayTransferOps.dayKey(date)
        if previewBeforeStart && display.semesterStatus == .afterEnd &&
            !transfers.contains(where: { HolidayTransferOps.dayKey($0.targetDate) == key }) {
            return []
        }
        if previewBeforeStart && !transfers.contains(where: {
            HolidayTransferOps.dayKey($0.sourceDate) == key || HolidayTransferOps.dayKey($0.targetDate) == key
        }) && DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: date) == .beforeStart {
            return coursesFor(dayOfWeek: DateUtils.todayDayOfWeek(today: date), week: 1)
        }
        return HolidayTransferOps.coursesForDate(
            date, startDate: table.startDate, maxWeek: table.maxWeek,
            courses: courses, transfers: transfers
        ).sorted { $0.startNode < $1.startNode }
    }

    /// ← Kotlin WidgetWeekSource.dateFor: 学期前(NORMAL) 显示学期所在周(周1),
    /// 其余按 targetDate 所在周的星期。
    func dateFor(dayOfWeek: Int) -> Date {
        if display.semesterStatus == .beforeStart && display.status == .normal {
            return DateUtils.dateOfWeek(startDate: table.startDate, week: 1, dayOfWeek: dayOfWeek)
                ?? DateUtils.dateOfWeekDay(ref: display.targetDate, dayOfWeek: dayOfWeek)
        }
        return DateUtils.dateOfWeekDay(ref: display.targetDate, dayOfWeek: dayOfWeek)
    }

    /// 返回 widget 应展示的"今天"语义日期:
    /// - NORMAL 档:原 today
    /// - NEAREST_BUSY_DAY 档:被自动跳到的最近有课那一天
    func resolvedToday(_ now: Date = Date()) -> Date {
        if display.status == .nearestBusyDay { return display.targetDate }
        return now
    }
}

enum WidgetWeekDataLoader {

    /// 解析 → (table, courses, display) 三元组;无表 → nil (对齐 Android runBlocking + nullable)
    /// - Parameter appWidgetId: iOS = widget kind 字符串(per-kind 粒度)
    static func resolve(_ appWidgetId: String) async -> WidgetWeekSource? {
        guard let repo = WidgetLoader.makeRepo() else { return nil }
        // ← WidgetTableResolver.resolveBoundTable(id) ?: resolveCurrentTable() ?: return null
        guard let table = WidgetBindingStore.resolveBoundTable(appWidgetId, repo: repo)
                ?? WidgetTableResolver.resolveCurrentTable(repo) else { return nil }
        let courses = (try? repo.getCourses(table.id)) ?? []
        let now = Date()
        let transfers = AppPrefs.shared.getHolidayTransfers(table.id)
        let display = WeekDisplayResolver.resolve(
            startDate: table.startDate,
            maxWeek: table.maxWeek,
            now: now,
            courses: courses,
            timeJson: table.timeJson,
            enabled: AppPrefs.shared.isNearestBusyDay(),
            transfers: transfers
        )
        return WidgetWeekSource(table: table, courses: courses, display: display,
                                transfers: transfers)
    }
}
