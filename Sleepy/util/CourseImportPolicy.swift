import Foundation

/// Android v1.0.63: preview and commit share the same time and conflict policy.
enum CourseImportPolicy {
    /// Appending courses never edits a bell schedule shared by other timetables.
    static func timeJsonForAppend(current: String, incoming: String, requiredNodes: Int, bound: Bool) -> String {
        bound ? current : mergeTimeJson(current: current, incoming: incoming, requiredNodes: requiredNodes)
    }

    struct MissingPeriod: LocalizedError {
        let node: Int64
        var errorDescription: String? { L10n.format("slot_time_required", node) }
    }

    static func requirePeriodCoverage(_ courses: [CourseEntity], timeJson: String) throws {
        if let node = TimeTableUtils.firstMissingCourseNode(courses: courses, rows: TimeTableUtils.parseTimeSlotRows(timeJson)) {
            throw MissingPeriod(node: node)
        }
    }

    static func mergeTimeJson(current: String, incoming: String, requiredNodes: Int) -> String {
        let currentRows = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : TimeTableUtils.parseTimeSlotRows(current)
        let incomingRows = incoming.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : TimeTableUtils.parseTimeSlotRows(incoming)
        let extended = TimeTableUtils.mergeMostComplete(currentJson: incoming, incomingJson: current, requiredNodeCount: requiredNodes)
        var byNode: [Int: TimeTableUtils.TimeSlotRow] = [:]
        for row in TimeTableUtils.parseTimeSlotRows(extended) + incomingRows + currentRows { byNode[row.node] = row }
        let rows = byNode.values.sorted { $0.node < $1.node }
        return rows == currentRows.sorted { $0.node < $1.node } ? current : TimeTableUtils.buildTimeJsonFromRows(rows)
    }

    static func conflicts(_ a: CourseEntity, _ b: CourseEntity, timeJson: String = "") -> Bool {
        guard a.day == b.day, a.step > 0, b.step > 0 else { return false }
        let aEnd = a.startNode.addingReportingOverflow(a.step - 1)
        let bEnd = b.startNode.addingReportingOverflow(b.step - 1)
        guard !aEnd.overflow, !bEnd.overflow else { return false }
        let lower = max(a.startWeek, b.startWeek), upper = min(a.endWeek, b.endWeek)
        guard lower <= upper, (lower...upper).contains(where: { a.inWeek($0) && b.inWeek($0) }) else { return false }
        func interval(_ course: CourseEntity) -> (String, String)? {
            guard let times = TimeTableUtils.effectiveCourseTime(isIrregularTime: course.ownTime || course.isIrregularTime,
                startTime: course.startTime, endTime: course.endTime, startNode: course.startNode, step: course.step, timeJson: timeJson),
                  TimeTableUtils.hmMinutes(String(times.0.prefix(5))) != nil,
                  TimeTableUtils.hmMinutes(String(times.1.prefix(5))) != nil, times.0 < times.1 else { return nil }
            return times
        }
        if let first = interval(a), let second = interval(b) { return first.0 < second.1 && second.0 < first.1 }
        return a.startNode <= bEnd.partialValue && b.startNode <= aEnd.partialValue
    }

    static func selectIncoming(incoming: [CourseEntity], existing: [CourseEntity], appendConflicts: Bool, timeJson: String) -> [CourseEntity] {
        appendConflicts ? incoming : incoming.filter { candidate in !existing.contains { conflicts(candidate, $0, timeJson: timeJson) } }
    }
}
