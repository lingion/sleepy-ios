import ActivityKit
import Foundation

@available(iOS 16.1, *)
public struct SleepyClassActivityAttributes: ActivityAttributes {
    public struct Entry: Codable, Hashable {
        public let name: String
        public let room: String
        public let start: Date
        public let end: Date

        public init(name: String, room: String, start: Date, end: Date) {
            self.name = name
            self.room = room
            self.start = start
            self.end = end
        }
    }

    public struct ContentState: Codable, Hashable {
        public let tableName: String
        public let entries: [Entry]
        // Optional fields keep previously running activities decodable after an app update.
        public var phase: String?
        public var tableId: Int64?
        public var courseId: Int64?
        public var reminderStart: Date?

        public init(tableName: String, entries: [Entry]) {
            self.tableName = tableName
            self.entries = entries
        }

        init(selection: ClassDayActivityCore.Selection) {
            tableName = Self.bounded(selection.current.tableName)
            entries = ([selection.current] + [selection.next].compactMap { $0 }).map {
                Entry(name: Self.bounded($0.name), room: Self.bounded($0.room), start: $0.start, end: $0.end)
            }
            phase = selection.phase.rawValue
            tableId = selection.current.tableId
            courseId = selection.current.courseId
        }

        init(course: CourseReminderOccurrence, reminderStart: Date, scheduled: Bool) {
            tableName = Self.bounded(course.tableName)
            entries = [Entry(name: Self.bounded(course.name), room: Self.bounded(course.room),
                             start: course.start, end: course.end)]
            tableId = course.tableId
            courseId = course.courseId
            self.reminderStart = reminderStart
            // Keep the scheduled marker after activation so notification dedup
            // never mistakes a foreground start for an accepted system alert.
            phase = scheduled ? "scheduled" : "course"
        }

        var occurrenceIdentifier: String? {
            guard let tableId, let courseId, let entry = entries.first else { return nil }
            return "\(tableId)_\(courseId)_\(Int64(entry.start.timeIntervalSince1970))"
        }

        var usesFixedCourseTimes: Bool { phase == "scheduled" || phase == "course" }

        // Combined attributes and state must fit ActivityKit's 4 KB limit, including local requests.
        private static func bounded(_ value: String) -> String {
            var result = ""
            var byteCount = 0
            for scalar in value.unicodeScalars {
                let count = String(scalar).utf8.count
                guard byteCount + count <= 96 else { break }
                result.unicodeScalars.append(scalar)
                byteCount += count
            }
            return result == value ? result : result + "…"
        }
    }

    public init() {}
}
