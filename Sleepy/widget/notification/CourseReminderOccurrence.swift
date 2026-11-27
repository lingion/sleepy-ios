import Foundation

enum CourseReminderLoadError: Error { case unavailable }

/// The database stores a civil day and a wall clock, not Shanghai instants.
/// Use its existing civil-day anchor for table lookups, and the device zone
/// only to translate those date and clock components into delivery instants.
struct CourseReminderCalendar {
    private let wallCalendar: Calendar
    private let civilCalendar = CourseOccurrences.calendar

    init(timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        wallCalendar = calendar
    }

    func civilDay(containing instant: Date) -> Date? {
        civilCalendar.date(from: wallCalendar.dateComponents([.year, .month, .day], from: instant))
    }

    func days(startingAt instant: Date, count: Int) -> [Date] {
        guard let first = civilDay(containing: instant) else { return [] }
        return (0..<max(0, count)).compactMap { civilCalendar.date(byAdding: .day, value: $0, to: first) }
    }

    func instant(on civilDay: Date, wallSeconds: Int) -> Date? {
        guard (0..<86_400).contains(wallSeconds) else { return nil }
        var parts = civilCalendar.dateComponents([.year, .month, .day], from: civilDay)
        parts.hour = wallSeconds / 3600
        parts.minute = wallSeconds / 60 % 60
        parts.second = wallSeconds % 60
        // Adding elapsed seconds to local midnight would shift every clock
        // after a daylight-saving transition. Build from wall components.
        guard let instant = wallCalendar.date(from: parts),
              self.civilDay(containing: instant) == civilCalendar.startOfDay(for: civilDay) else { return nil }
        return instant
    }

    func timeText(for instant: Date) -> String {
        let parts = wallCalendar.dateComponents([.hour, .minute], from: instant)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// Read bell times as wall-clock values. TimeTableUtils.parseNodes projects
/// them onto today's Date for display, which must not affect reminder math.
struct ReminderBellTimes {
    private let nodes: [Int: (start: Int, end: Int)]

    init(_ timeJson: String) {
        var parsed: [Int: (start: Int, end: Int)] = [:]
        for row in TimeTableUtils.strictPeriodRows(timeJson) ?? [] {
            guard parsed[row.node] == nil,
                  let start = TimeTableUtils.parsePeriodClock(row.start),
                  let end = TimeTableUtils.parsePeriodClock(row.end) else {
                nodes = [:]
                return
            }
            parsed[row.node] = (start * 60, end * 60)
        }
        nodes = parsed
    }

    static func clockText(_ seconds: Int) -> String {
        let hhmm = String(format: "%02d:%02d", seconds / 3600, seconds / 60 % 60)
        let remainder = seconds % 60
        return remainder == 0 ? hhmm : hhmm + String(format: ":%02d", remainder)
    }

    func bounds(for course: CourseEntity) -> (start: Int?, end: Int?) {
        if course.ownTime || course.isIrregularTime {
            return (TimeTableUtils.hmToSeconds(course.startTime.trimmingCharacters(in: .whitespaces)),
                    TimeTableUtils.hmToSeconds(course.endTime.trimmingCharacters(in: .whitespaces)))
        }
        return nodeBounds(for: course)
    }

    func nodeBounds(for course: CourseEntity) -> (start: Int?, end: Int?) {
        guard course.step > 0 else { return (nil, nil) }
        let (last, overflow) = course.startNode.addingReportingOverflow(course.step - 1)
        return (nodes[course.startNode]?.start, overflow ? nil : nodes[last]?.end)
    }
}

/// A dated occurrence, shared by notifications and Live Activities. A transferred
/// or repeated class keeps its own identity even when it uses the same DB row.
struct CourseReminderOccurrence: Equatable {
    let tableId: Int64
    let courseId: Int64
    let tableName: String
    let name: String
    let room: String
    let start: Date
    let end: Date
    var teacher: String = ""
    var startNode: Int = 0

    var identifier: String {
        "\(tableId)_\(courseId)_\(Int64(start.timeIntervalSince1970))"
    }

    var notificationIdentifier: String { "sleepy_bc_2000_" + identifier }

    func reminderDate(leadMinutes: Int) -> Date {
        start.addingTimeInterval(-Double(min(999, max(0, leadMinutes))) * 60)
    }

    static func notificationDateComponents(
        for date: Date,
        timeZone: TimeZone = Calendar.autoupdatingCurrent.timeZone
    ) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar
        components.timeZone = timeZone
        return components
    }

    static func ordered(_ items: [Self]) -> [Self] {
        var seen = Set<String>()
        return items.filter { $0.end > $0.start && seen.insert($0.identifier).inserted }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            return $0.identifier < $1.identifier
        }
    }
}

#if !WIDGET_EXT && !WATCH_WIDGET_EXT
enum CourseReminderLoader {
    static func load(tables: [TimeTableEntity], dataSource: NotificationSchedulerBeforeClassDataSource,
                     from date: Date, days: Int, calendar: CourseReminderCalendar) async throws -> [CourseReminderOccurrence] {
        let dateDays = calendar.days(startingAt: date, count: days)
        var result: [CourseReminderOccurrence] = []
        for table in tables where table.reminderEnabled {
            let period = try dataSource.boundPeriodTable(for: table)
            for day in dateDays {
                guard await dataSource.allowsReminder(tableId: table.id, date: day) else { continue }
                let courses = try dataSource.coursesOn(table: table, date: day)
                guard !courses.isEmpty else { continue }
                let effective = table.hydratedWith(period, forDateKey: HolidayTransferOps.dayKey(day))
                let bells = ReminderBellTimes(effective.timeJson)
                for course in courses where course.tableId == table.id {
                    let times = bells.bounds(for: course)
                    guard course.step > 0, let startSecond = times.start, let endSecond = times.end, endSecond > startSecond,
                          let start = calendar.instant(on: day, wallSeconds: startSecond),
                          let end = calendar.instant(on: day, wallSeconds: endSecond), end > start else { continue }
                    result.append(.init(tableId: table.id, courseId: course.id, tableName: table.name,
                                        name: course.courseName, room: course.room, start: start, end: end,
                                        teacher: course.teacher, startNode: course.startNode))
                }
            }
        }
        return CourseReminderOccurrence.ordered(result)
    }
}
#endif
