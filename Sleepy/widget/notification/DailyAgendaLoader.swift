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

/// ← loadDailyAgenda(context, targetDate):
/// 每表独立提醒: 聚合所有开启提醒的课表; 若全部被节假日策略豁免则整体静默。
/// 取课走反向查 ← HolidayTransferHelper.courseDateForDate:
/// 补班日 = sourceDate(上被挪走那天的课), 放假日 = nil(无课)。
func loadDailyAgenda(repository: ScheduleRepository, targetDate: Date) async throws -> LoadedDailyAgenda {
    let tables = try repository.getAllTables().map { t -> TimeTableEntity in
        var pt: PeriodTableEntity? = nil
        if let pid = t.periodTableId { pt = try? repository.getPeriodTable(pid) }
        return t.hydratedWith(pt)
    }
    let enabledTables = tables.filter { $0.reminderEnabled }
    var activeTables: [TimeTableEntity] = []
    for t in enabledTables {
        if await HolidayReminderPolicyAdapter.decide(date: targetDate, tableId: t.id).allowReminder {
            activeTables.append(t)
        }
    }
    let suppressed = !enabledTables.isEmpty && activeTables.isEmpty

    let summaries: [DailyTableCourses] = activeTables.map { table -> DailyTableCourses in
        // 取课走反向查: 补班日=sourceDate 的课, 放假日=nil(无课)
        guard let sourceDate = HolidayTransferHelper.courseDateForDate(table.id, targetDate) else {
            return DailyTableCourses(table: table, courses: [])
        }
        // 周次/学期判定 ← 原 sourceDate ?: targetDate (放假日 courses 恒空, 该值不参与取课)
        let week = DateUtils.currentWeek(startDate: table.startDate, today: sourceDate)
        let inSemester = DateUtils.semesterStatus(
            startDate: table.startDate, maxWeek: table.maxWeek, today: sourceDate) == .inRange
        let courses: [CourseEntity] = inSemester
            ? ((try? repository.getCoursesByDay(table.id, day: DateUtils.todayDayOfWeek(today: sourceDate)))
                ?? []).filter { $0.inWeek(week) }
            : []
        return DailyTableCourses(table: table, courses: courses)
    }
    let agenda = buildDailyAgenda(
        date: targetDate,
        summary: buildDailyScheduleSummary(summaries),
        sourceTables: enabledTables)
    return LoadedDailyAgenda(agenda: agenda, suppressed: suppressed)
}
