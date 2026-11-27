// WatchAgendaCore.swift — 表盘小组件共享议程核 (2026-11 watch 小组件扩展)
//
// 纯 Foundation — 禁 UIKit/WidgetKit/app-only API: 三 target 共源编译
//   Sleepy (iOS, 供 SleepyTests 单测) / SleepyWatch (手表 App) /
//   SleepyWatchWidgets (extension)。
//
// 普通课按教学来源日选取，定日课只在自然日出现。时段按实际上课日解析。
// 未开学的预习模式只由 App 周视图显式请求，表盘不显示预习课。

import Foundation

enum WatchAgendaCore {

    // MARK: - 视图模型

    /// 单节课快照 — 6 个表盘 kind 共用的最小字段集
    struct ClassItem: Equatable {
        let courseName: String
        let room: String
        /// 节次短串(node 模式) 或 时间区间(time 模式) ← slotLabel
        let startLabel: String
        let startMin: Int   // 当日分钟
        let endMin: Int
        let startDate: Date // 当日 00:00 + startMin
        let endDate: Date

        /// 距开课分钟 (≥0) — 现有「下一节」口径
        func minutesUntil(from now: Date) -> Int {
            max(0, Int(startDate.timeIntervalSince(now) / 60))
        }

        /// 进行中进度 0...1 (课外钳制) — 「正在上的课」进度环/条
        func progress(at now: Date) -> Double {
            let total = endDate.timeIntervalSince(startDate)
            guard total > 0 else { return 0 }
            return min(1, max(0, now.timeIntervalSince(startDate) / total))
        }
    }

    // MARK: - 某日议程

    /// The phone's civil dates identify courses and bell rules. Emit real Watch-local
    /// instants from those wall clocks so timeline entries work on DST transitions.
    static func dayItems(table: TimeTableEntity, courses: [CourseEntity], date: Date,
                         period: PeriodTableEntity? = nil) -> [ClassItem] {
        dayItems(table: table, courses: courses, date: date,
                 displayMode: AppPrefs.shared.getDisplayMode(),
                 transfers: HolidayTransferHelper.transfers(for: table.id), period: period)
    }

    // Widget extensions can supply the preferences from their shared snapshot.
    static func dayItems(table: TimeTableEntity, courses: [CourseEntity], date: Date,
                         displayMode: String, transfers: [HolidayTransferEntry],
                         period: PeriodTableEntity? = nil, timeZone: TimeZone = .current) -> [ClassItem] {
        let clock = CourseReminderCalendar(timeZone: timeZone)
        guard let day = clock.civilDay(containing: date) else { return [] }
        let effective = table.hydratedWith(period, forDateKey: HolidayTransferOps.dayKey(day))
        let bells = ReminderBellTimes(effective.timeJson)
        return coursesOnCivilDay(day, table: table, courses: courses, transfers: transfers)
            .compactMap { course in
                makeItem(course, bells: bells, displayMode: displayMode, day: day, clock: clock)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Keep fixed dates and holiday transfers consistent across the phone, Watch app and complications.
    static func coursesOnCivilDay(_ day: Date, table: TimeTableEntity, courses: [CourseEntity],
                                  transfers: [HolidayTransferEntry], previewBeforeStart: Bool = false) -> [CourseEntity] {
        let stored = courses.filter { $0.tableId == table.id }
        let actual = CourseOccurrences.coursesForDate(day, startDate: table.startDate, maxWeek: table.maxWeek,
                                                     courses: stored, transfers: transfers)
        guard previewBeforeStart,
              let firstDay = CourseOccurrences.date(startDate: table.startDate, week: 1, day: 1),
              day < firstDay,
              let source = HolidayTransferOps.courseDateForDate(day, transfers), source == day
        else { return actual }
        let weekday = CourseOccurrences.day(day)
        return (actual + stored.filter { $0.fixedDate == nil && $0.day == weekday && $0.inWeek(1) })
            .sorted { $0.startNode < $1.startNode }
    }

    static func nextClass(in items: [ClassItem], now: Date) -> ClassItem? {
        items.first { $0.startDate > now }
    }

    static func currentClass(in items: [ClassItem], now: Date) -> ClassItem? {
        items.first { $0.startDate <= now && now < $0.endDate }
    }

    // MARK: - 学期 / 周信息

    static func semesterStatus(table: TimeTableEntity, date: Date) -> DateUtils.SemesterStatus {
        guard let day = CourseReminderCalendar(timeZone: .current).civilDay(containing: date),
              let first = CourseOccurrences.date(startDate: table.startDate, week: 1, day: 1)
        else { return .inRange }
        if day < first { return .beforeStart }
        let week = CourseOccurrences.week(startDate: table.startDate, date: day) ?? 1
        return week > table.maxWeek ? .afterEnd : .inRange
    }

    /// 周信息: week 1-based; ratio = week/maxWeek clamp 0...1 (maxWeek ≤ 0 → 0)
    static func weekInfo(table: TimeTableEntity, date: Date) -> (week: Int, maxWeek: Int, ratio: Double) {
        let day = CourseReminderCalendar(timeZone: .current).civilDay(containing: date)
        let week = day.flatMap { CourseOccurrences.week(startDate: table.startDate, date: $0) } ?? 1
        let maxWeek = table.maxWeek
        let ratio = maxWeek > 0 ? min(1, max(0, Double(week) / Double(maxWeek))) : 0
        return (week, maxWeek, ratio)
    }

    // MARK: - 内部

    static func item(for course: CourseEntity, bells: ReminderBellTimes, now: Date,
                     timeZone: TimeZone = .current) -> ClassItem? {
        let clock = CourseReminderCalendar(timeZone: timeZone)
        guard let day = clock.civilDay(containing: now) else { return nil }
        return makeItem(course, bells: bells, displayMode: "time", day: day, clock: clock)
    }

    private static func makeItem(_ course: CourseEntity, bells: ReminderBellTimes, displayMode: String,
                                 day: Date, clock: CourseReminderCalendar) -> ClassItem? {
        let bounds = bells.bounds(for: course)
        guard let start = bounds.start, let end = bounds.end, end > start,
              let startDate = clock.instant(on: day, wallSeconds: start),
              let endDate = clock.instant(on: day, wallSeconds: end), endDate > startDate else { return nil }
        return ClassItem(
            courseName: course.courseName,
            room: course.room,
            startLabel: label(for: course, bounds: bounds, displayMode: displayMode),
            startMin: start / 60,
            endMin: end / 60,
            startDate: startDate,
            endDate: endDate)
    }

    static func slotLabel(_ course: CourseEntity, table: TimeTableEntity, displayMode: String) -> String {
        label(for: course, bounds: ReminderBellTimes(table.timeJson).bounds(for: course), displayMode: displayMode)
    }

    private static func label(for course: CourseEntity, bounds: (start: Int?, end: Int?), displayMode: String) -> String {
        if displayMode == "node" { return course.nodeString(isShort: true) }
        if course.ownTime || course.isIrregularTime {
            return bounds.start != nil && bounds.end != nil ? "\(course.startTime)–\(course.endTime)" : ""
        }
        if course.isIrregularNode { return course.nodeString() }
        guard let start = bounds.start, let end = bounds.end else { return "" }
        func clock(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 3600, seconds / 60 % 60) }
        return "\(clock(start))–\(clock(end))"
    }
}
