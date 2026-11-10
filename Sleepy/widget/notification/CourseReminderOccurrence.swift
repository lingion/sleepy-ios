import Foundation

enum CourseReminderLoadError: Error { case unavailable }

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

    static func notificationDateComponents(for date: Date) -> DateComponents {
        let calendar = CourseOccurrences.calendar
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
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

enum CourseReminderLoader {
    static func load(tables: [TimeTableEntity], dataSource: NotificationSchedulerBeforeClassDataSource,
                     from date: Date, days: Int) async throws -> [CourseReminderOccurrence] {
        let calendar = CourseOccurrences.calendar
        let firstDay = calendar.startOfDay(for: date)
        var result: [CourseReminderOccurrence] = []
        for table in tables where table.reminderEnabled {
            for offset in 0..<max(0, days) {
                guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                      await dataSource.allowsReminder(tableId: table.id, date: day) else { continue }
                var courses = try dataSource.coursesForDay(tableId: table.id, dayOfWeek: CourseOccurrences.day(day))
                    .filter { $0.fixedDate == HolidayTransferOps.dayKey(day) }
                if let source = dataSource.courseDateForDate(tableId: table.id, date: day),
                   let week = CourseOccurrences.week(startDate: table.startDate, date: source),
                   week > 0, week <= table.maxWeek {
                    courses += try dataSource.coursesForDay(tableId: table.id, dayOfWeek: CourseOccurrences.day(source))
                        .filter { $0.fixedDate == nil && $0.inWeek(week) }
                }
                for course in courses {
                    guard course.step > 0, course.startNode <= Int.max - course.step,
                        let times = TimeTableUtils.effectiveCourseTime(
                        isIrregularTime: course.ownTime || course.isIrregularTime,
                        startTime: course.startTime, endTime: course.endTime,
                        startNode: course.startNode, step: course.step, timeJson: table.timeJson),
                        let startSecond = TimeTableUtils.hmToSeconds(times.0),
                        let endSecond = TimeTableUtils.hmToSeconds(times.1), endSecond > startSecond,
                        let start = calendar.date(byAdding: .second, value: startSecond, to: day),
                        let end = calendar.date(byAdding: .second, value: endSecond, to: day) else { continue }
                    result.append(.init(tableId: table.id, courseId: course.id, tableName: table.name,
                                        name: course.courseName, room: course.room, start: start, end: end,
                                        teacher: course.teacher, startNode: course.startNode))
                }
            }
        }
        return CourseReminderOccurrence.ordered(result)
    }
}
