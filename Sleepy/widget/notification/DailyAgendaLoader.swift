// DailyAgendaLoader.swift — ← widget/notification/DailyAgendaLoader.kt (v1.0.62 B5)
// 通知与议程页共用的「现读现算」入口: 不落任何序列化课程快照, 每次调用都按
// 当前库内实况构建 (原版本 侧同款语义 — 接收器每次现算)。
// 纯 Foundation 逻辑(三 target 共源编译); HolidayReminderPolicyAdapter/HolidayManager
// 内部的网络/缓存路径与 ReminderScreen 现有调用同源, 不新增平台分支。

import Foundation

/// ← LoadedDailyAgenda: agenda = 合并结果; suppressed = 有开启提醒的表但全部被
/// 节假日策略豁免 → 通知整体静默 (原版本 接收器直接 return 不发)。
struct LoadedDailyAgenda {
    let agenda: DailyAgenda
    let suppressed: Bool
}

/// Aggregate the effective reminder tables for a single timetable civil day.
func loadDailyAgenda(repository: ScheduleRepository, targetDate: Date,
                     allowsReminder: (Date, Int64) async -> Bool = { date, id in
                         await HolidayReminderPolicyAdapter.decide(date: date, tableId: id).allowReminder
                     },
                     transfersFor: (Int64) -> [HolidayTransferEntry] = HolidayTransferHelper.transfers(for:)) async throws -> LoadedDailyAgenda {
    let enabledTables = try repository.getReminderTables().filter(\.reminderEnabled)
    let dateKey = HolidayTransferOps.dayKey(targetDate)
    var summaries: [DailyTableCourses] = []
    for table in enabledTables {
        guard await allowsReminder(targetDate, table.id) else { continue }
        let period = try table.periodTableId.flatMap { try repository.getPeriodTable($0) }
        // A fixed-date course stays on its natural day, even outside the term.
        // Recurring courses use the transfer source's weekday and teaching week.
        let courses = CourseOccurrences.coursesForDate(targetDate, startDate: table.startDate,
            maxWeek: table.maxWeek, courses: try repository.getCourses(table.id),
            transfers: transfersFor(table.id))
        summaries.append(DailyTableCourses(table: table.hydratedWith(period, forDateKey: dateKey), courses: courses))
    }
    let suppressed = !enabledTables.isEmpty && summaries.isEmpty
    let agenda = buildDailyAgenda(
        date: targetDate,
        summary: buildDailyScheduleSummary(summaries),
        sourceTables: enabledTables)
    return LoadedDailyAgenda(agenda: agenda, suppressed: suppressed)
}
