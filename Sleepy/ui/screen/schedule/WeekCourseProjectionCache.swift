import Foundation

/// Immutable course projections are shared by repeated SwiftUI body evaluations.
/// Four pages cover the visible neighbors and a pinned drag source. Content,
/// rather than row IDs/counts, invalidates same-ID course and timetable edits.
final class WeekCourseProjectionCache {
    static let shared = WeekCourseProjectionCache()

    struct Input: Equatable {
        let tableId: Int64
        let startDate: String
        let maxWeek: Int
        let week: Int
        let courses: [CourseEntity]
        let transfers: [HolidayTransferEntry]
        let timeJson: String?
        let calendar: Calendar?
    }

    private struct Entry {
        let input: Input
        let courses: [CourseEntity]
    }
    private let capacity: Int
    private let lock = NSLock()
    private var entries: [Entry] = []

    init(capacity: Int = 4) { self.capacity = max(1, capacity) }

    func value(for input: Input, make: () -> [CourseEntity]) -> [CourseEntity] {
        lock.lock()
        if let index = entries.firstIndex(where: { $0.input == input }) {
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
            lock.unlock()
            return entry.courses
        }
        lock.unlock()

        // Keep computation outside the lock. A concurrent result for another
        // snapshot must never replace this snapshot's key or be returned for it.
        let result = make()
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries.first(where: { $0.input == input }) { return entry.courses }
        entries.insert(Entry(input: input, courses: result), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
        return result
    }
}
