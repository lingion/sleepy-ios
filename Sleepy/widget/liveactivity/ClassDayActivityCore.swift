import Foundation

enum ClassDayActivityCore {
    typealias Course = CourseReminderOccurrence

    enum Phase: String, Codable { case upcoming, ongoing }

    struct Selection: Equatable {
        let current: Course
        let next: Course?
        let phase: Phase
        var refreshAt: Date { phase == .upcoming ? current.start : current.end }
    }

    static func isEnabled(prefs: AppPrefs) -> Bool {
        prefs.isReminderEnabled() && prefs.isBeforeClassEnabled()
            && prefs.isBeforeClassFluidEnabled()
    }

    static func selection(from courses: [Course], now: Date, leadMinutes: Int) -> Selection? {
        let sorted = validCourses(courses)
        let running = sorted.first { $0.start <= now && now < $0.end }
        let lead = Double(min(999, max(0, leadMinutes))) * 60
        guard let current = running ?? sorted.first(where: {
            $0.start > now && $0.start.timeIntervalSince(now) <= lead
        }) else { return nil }
        return Selection(current: current, next: sorted.first { $0.start > current.start && $0.end > now },
                         phase: current.start > now ? .upcoming : .ongoing)
    }

    static func nextRefreshDate(from courses: [Course], now: Date, leadMinutes: Int) -> Date? {
        let lead = Double(min(999, max(0, leadMinutes))) * 60
        return validCourses(courses).flatMap { [$0.start.addingTimeInterval(-lead), $0.start, $0.end] }
            .filter { $0 > now }.min()
    }

    /// Three is our conservative app budget, not a published system limit.
    /// Older systems can only start the current course from the foreground.
    static func activityPlan(from courses: [Course], now: Date, leadMinutes: Int,
                             supportsScheduling: Bool, budget: Int = 3) -> [Course] {
        guard budget > 0 else { return [] }
        let sorted = CourseReminderOccurrence.ordered(courses).filter {
            $0.end > now && $0.end.timeIntervalSince(max(now, $0.reminderDate(leadMinutes: leadMinutes))) <= 8 * 3600
        }
        let current = selection(from: sorted, now: now, leadMinutes: leadMinutes)?.current
        var result = current.map { [$0] } ?? []
        if supportsScheduling {
            result += sorted.filter {
                $0.identifier != current?.identifier && $0.reminderDate(leadMinutes: leadMinutes) > now
            }.prefix(max(0, budget - result.count))
        }
        return result
    }

    private static func validCourses(_ courses: [Course]) -> [Course] {
        courses.filter { $0.end > $0.start }.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.tableId != $1.tableId { return $0.tableId < $1.tableId }
            return $0.courseId < $1.courseId
        }
    }

    static let gapThresholdMin = 60
    static func segments(from items: [WatchAgendaCore.ClassItem]) -> [[WatchAgendaCore.ClassItem]] {
        var result: [[WatchAgendaCore.ClassItem]] = []
        var current: [WatchAgendaCore.ClassItem] = []
        for item in items.sorted(by: { $0.startMin < $1.startMin }) {
            if let end = current.map(\.endMin).max(), item.startMin - end > gapThresholdMin {
                result.append(current)
                current = []
            }
            current.append(item)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Returns the unfinished suffix, including the next course during a break.
    static func activeSegment(from items: [WatchAgendaCore.ClassItem], now: Date) -> [WatchAgendaCore.ClassItem]? {
        let minute = minutesOfDay(now)
        return segments(from: items).map { $0.filter { $0.endMin > minute } }.first { !$0.isEmpty }
    }

    static func minutesOfDay(_ date: Date) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }
}
