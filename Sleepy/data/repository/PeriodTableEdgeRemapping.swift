import Foundation

/// Edge clocks may change with the draft; order within each direction carries their identity.
func remapRenumberedEdgeCourses(_ courses: [CourseEntity], oldTimeJson: String,
                               newTimeJson: String) -> [CourseEntity] {
    let previousEdges = TimeTableUtils.parseTimeSlotRows(oldTimeJson).filter { $0.edgeClass != nil }
    guard !previousEdges.isEmpty else { return courses }
    let nextRows = TimeTableUtils.parseTimeSlotRows(newTimeJson)
    let nextEdges = nextRows.filter { $0.edgeClass != nil }
    var identities: [Int: Int] = [:]
    for direction in [TimeTableUtils.EdgeClass.before, .after] {
        let previous = previousEdges.filter { $0.edgeClass == direction }.sorted { $0.node < $1.node }
        let next = nextEdges.filter { $0.edgeClass == direction }.sorted { $0.node < $1.node }
        if previous.count == next.count {
            for (old, updated) in zip(previous, next) { identities[old.node] = updated.node }
        } else {
            // Deleting an edge must not attach its course to the neighbouring edge.
            for old in previous {
                let matches = next.filter { $0.start == old.start && $0.end == old.end }
                if matches.count == 1 { identities[old.node] = matches[0].node }
            }
        }
    }
    // An orphan must stay outside every current slot and course span on its original side.
    // Reuse its old anchor when it is still free, and keep occurrences of one deleted span together.
    var minimumNode = min(0, nextRows.map(\.node).min() ?? 0,
                          previousEdges.map(\.node).min() ?? 0, courses.map(\.startNode).min() ?? 0)
    var maximumNode = max(0, nextRows.map(\.node).max() ?? 0, previousEdges.map(\.node).max() ?? 0)
    for course in courses where course.step > 0 {
        let (end, overflow) = course.startNode.addingReportingOverflow(course.step - 1)
        if !overflow { maximumNode = max(maximumNode, end) }
    }
    var orphanAnchors: [String: Int] = [:]

    return courses.map { course in
        guard course.isIrregularNode, course.step > 0 else { return course }
        let (oldEnd, overflow) = course.startNode.addingReportingOverflow(course.step - 1)
        guard !overflow else { return course }
        var migrated = course
        if let start = identities[course.startNode], let end = identities[oldEnd] {
            let (distance, distanceOverflow) = end.subtractingReportingOverflow(start)
            if !distanceOverflow, distance == course.step - 1 {
                migrated.startNode = start
                return migrated
            }
        }
        guard let direction = previousEdges.first(where: { $0.node == course.startNode })?.edgeClass else {
            return course
        }
        // Deleting a slot must not change its courses to a surviving slot's clocks.
        if !course.ownTime && !course.isIrregularTime,
           let time = TimeTableUtils.effectiveCourseTime(isIrregularTime: false,
               startTime: "", endTime: "", startNode: course.startNode, step: course.step, timeJson: oldTimeJson) {
            migrated.ownTime = true
            migrated.isIrregularTime = true
            migrated.startTime = time.0
            migrated.endTime = time.1
        }
        guard nextRows.contains(where: { (course.startNode...oldEnd).contains($0.node) }) else { return migrated }
        let key = "\(course.startNode):\(course.step)"
        if let anchor = orphanAnchors[key] {
            migrated.startNode = anchor
        } else if direction == .before {
            let (anchor, overflow) = minimumNode.subtractingReportingOverflow(course.step)
            if !overflow {
                migrated.startNode = anchor
                minimumNode = anchor
                orphanAnchors[key] = anchor
            }
        } else {
            let (anchor, startOverflow) = maximumNode.addingReportingOverflow(1)
            let (end, endOverflow) = anchor.addingReportingOverflow(course.step - 1)
            if !startOverflow && !endOverflow {
                migrated.startNode = anchor
                maximumNode = end
                orphanAnchors[key] = anchor
            }
        }
        return migrated
    }
}
