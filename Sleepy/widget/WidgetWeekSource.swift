// WidgetWeekSource.swift — ← widget/WidgetWeekDataLoader.kt
// 小部件统一读取课表并计算展示日,避免各 provider 各自判定"今天之后最近一节有课的天"。
//
// v2 (用户 2026-09-20 改向):
//   - display.targetDate 是 widget 应该呈现的"今天"(可能是被自动跳到的那一天)。
//   - dateFor(dayOfWeek) 给的是展示周里 dayOfWeek 的真实日期(基于 targetWeek 计算)。
//
// ★ 平台差异 (WidgetBindingStore.swift 头注同源): 原版本 per-appWidgetId → iOS per-kind。
//   此处 appWidgetId 参数 = kind 字符串 (iOS 等价粒度, 详见 WidgetBindingStore)。

import Foundation

struct WidgetWeekSource {
    let table: TimeTableEntity
    let courses: [CourseEntity]
    let display: WeekDisplayContext
    /// ← Kotlin WidgetWeekSource.transfers (v1.0.61): 调休映射随 source 携带,
    /// coursesOn / 装载器按日期反向查共用 (原版本 source.transfers 同源)。
    let transfers: [HolidayTransferEntry]

    var periodTable: PeriodTableEntity? = nil
    /// Non-nil when the display resolver returns timetable civil days rather than device instants.
    var wallTimeZone: TimeZone? = nil

    static func resolve(table: TimeTableEntity, courses: [CourseEntity], period: PeriodTableEntity?,
                        transfers: [HolidayTransferEntry], now: Date, nearestBusyDay: Bool,
                        timeZone: TimeZone = .current) -> WidgetWeekSource {
        let day = CourseReminderCalendar(timeZone: timeZone).civilDay(containing: now) ?? now
        let effective = table.hydratedWith(period, forDateKey: HolidayTransferOps.dayKey(day))
        let display = WeekDisplayResolver.resolve(startDate: table.startDate, maxWeek: table.maxWeek, now: now,
            courses: courses, timeJson: effective.timeJson, enabled: nearestBusyDay,
            transfers: transfers, civilTimeZone: timeZone)
        return WidgetWeekSource(table: table.hydratedWith(period), courses: courses, display: display,
                                transfers: transfers, periodTable: period, wallTimeZone: timeZone)
    }

    func civilDay(onDisplayDate date: Date) -> Date {
        guard let zone = wallTimeZone else { return date }
        return CourseReminderCalendar(timeZone: zone).civilDay(containing: date) ?? date
    }

    func localDate(onCivilDay day: Date) -> Date {
        guard let zone = wallTimeZone else { return day }
        return CourseReminderCalendar(timeZone: zone).instant(on: day, wallSeconds: 0) ?? day
    }

    func table(onDisplayDate date: Date) -> TimeTableEntity { table(on: civilDay(onDisplayDate: date)) }

    func coursesOnDisplayDate(_ date: Date, previewBeforeStart: Bool = false) -> [CourseEntity] {
        coursesOn(civilDay(onDisplayDate: date), previewBeforeStart: previewBeforeStart)
    }

    func semesterStatus(onDisplayDate date: Date, usesTransfer: Bool = false) -> DateUtils.SemesterStatus {
        let civil = civilDay(onDisplayDate: date)
        let day = usesTransfer ? (HolidayTransferOps.courseDateForDate(civil, transfers) ?? civil) : civil
        if wallTimeZone != nil {
            return WeekDisplayResolver.civilSemesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, day: day)
        }
        return DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: day)
    }

    func table(on date: Date) -> TimeTableEntity {
        table.hydratedWith(periodTable, forDateKey: HolidayTransferOps.dayKey(date))
    }

    func coursesFor(dayOfWeek: Int, week: Int? = nil) -> [CourseEntity] {
        let w = week ?? display.targetWeek
        return courses
            .filter { $0.day == dayOfWeek && $0.inWeek(w) }
            .sorted { $0.startNode < $1.startNode }
    }

    /// Calendar inputs in this method use timetable civil keys, not host timezone.
    func coursesOn(_ date: Date, previewBeforeStart: Bool = false) -> [CourseEntity] {
        let key = HolidayTransferOps.dayKey(date)
        let actual = HolidayTransferOps.coursesForDate(date, startDate: table.startDate, maxWeek: table.maxWeek,
                                                       courses: courses, transfers: transfers)
        guard previewBeforeStart, !transfers.contains(where: {
            HolidayTransferOps.dayKey($0.sourceDate) == key || HolidayTransferOps.dayKey($0.targetDate) == key
        }), WeekDisplayResolver.civilSemesterStatus(startDate: table.startDate,
                    maxWeek: table.maxWeek, day: date) == .beforeStart else { return actual }
        let weekday = CourseOccurrences.day(date)
        return (actual + courses.filter { $0.fixedDate == nil && $0.day == weekday && $0.inWeek(1) })
            .sorted { $0.startNode < $1.startNode }
    }

    /// ← Kotlin WidgetWeekSource.dateFor: 学期前(NORMAL) 显示学期所在周(周1),
    /// 其余按 targetDate 所在周的星期。
    func dateFor(dayOfWeek: Int) -> Date {
        if wallTimeZone != nil {
            let cal = CourseOccurrences.calendar
            let anchor = display.semesterStatus == .beforeStart && display.status == .normal
                ? (CourseOccurrences.date(startDate: table.startDate, week: 1, day: 1) ?? display.targetDate)
                : display.targetDate
            let offset = dayOfWeek - CourseOccurrences.day(anchor)
            return localDate(onCivilDay: cal.date(byAdding: .day, value: offset, to: anchor) ?? anchor)
        }
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
        if display.status == .nearestBusyDay { return localDate(onCivilDay: display.targetDate) }
        return now
    }
}

enum WidgetWeekDataLoader {

    /// 解析 → (table, courses, display) 三元组;无表 → nil (对齐 原 runBlocking + nullable)
    /// - Parameter appWidgetId: iOS = widget kind 字符串(per-kind 粒度)
    static func resolve(_ appWidgetId: String, repository: ScheduleRepository? = nil,
                        now: Date = AppClock.now,
                        overrideTableId: Int64? = nil) async -> WidgetWeekSource? {
        guard let repo = repository ?? WidgetLoader.makeRepo() else { return nil }
        // ← 原版本 WidgetWeekDataLoader.kt:66: runCatching { CourseHueStore.refresh(app) }
        //   widget 进程与 App 进程分离 → 装载点自刷持久色相快照, 保证 widget 与 App 同色。
        await CourseHueStore.shared.refresh(
            mode: AppPrefs.shared.getCourseColorMode(),
            dao: repo.database.courseColorDao)
        // ← WidgetTableResolver.resolveBoundTable(id) ?: resolveCurrentTable() ?: return null
        guard let table = (overrideTableId.flatMap { WidgetTableResolver.resolveExplicitTable($0, repo: repo) })
                ?? WidgetTableResolver.resolveBoundTable(appWidgetId, repo: repo)
                ?? WidgetTableResolver.resolveCurrentTable(repo) else { return nil }
        let period = table.periodTableId.flatMap { try? repo.getPeriodTable($0) }
        let courses = (try? repo.getCourses(table.id)) ?? []
        let transfers = AppPrefs.shared.getHolidayTransfers(table.id)
        return WidgetWeekSource.resolve(table: table, courses: courses, period: period, transfers: transfers,
            now: now, nearestBusyDay: AppPrefs.shared.isNearestBusyDay())
    }
}
