import XCTest
@testable import Sleepy

final class CourseImportPolicyTests: XCTestCase {
    private var times: String { TimeTableUtils.buildTimeJsonFromRows([
        .init(node: 1, start: "08:00", end: "08:45"), .init(node: 2, start: "08:55", end: "09:40")]) }
    private func course(_ name: String, node: Int = 1, type: Int = 0) -> CourseEntity {
        CourseEntity(groupId: name, tableId: 42, courseName: name, day: 1, startNode: node, step: 1,
                     startWeek: 1, endWeek: 20, type: type, color: "#FF6750A4")
    }
    func testOppositeParityAndEmptyParityRangeDoNotConflict() {
        XCTAssertFalse(CourseImportPolicy.conflicts(course("Odd", type: 1), course("Even", type: 2), timeJson: times))
        XCTAssertTrue(CourseImportPolicy.conflicts(course("Odd", type: 1), course("Every"), timeJson: times))
        var odd = course("Odd", type: 1); odd.startWeek = 2; odd.endWeek = 2
        XCTAssertFalse(CourseImportPolicy.conflicts(odd, course("Every"), timeJson: times))
    }
    func testCustomAndIrregularTimesOverrideNodesAndTouchingEndpointsDoNotOverlap() {
        var own = course("Custom", node: 15); own.ownTime = true; own.startTime = "08:30"; own.endTime = "08:55"
        XCTAssertTrue(CourseImportPolicy.conflicts(own, course("First"), timeJson: times))
        XCTAssertFalse(CourseImportPolicy.conflicts(own, course("Second", node: 2), timeJson: times))
        own.ownTime = false; own.isIrregularTime = true
        XCTAssertTrue(CourseImportPolicy.conflicts(own, course("First"), timeJson: times))
    }
    func testConflictSwitchFiltersOnlyAgainstOriginalCourses() {
        let incoming = [course("Overlap"), course("Free", node: 2)]
        XCTAssertEqual(CourseImportPolicy.selectIncoming(incoming: incoming, existing: [course("Original")], appendConflicts: false, timeJson: times), [incoming[1]])
        XCTAssertEqual(CourseImportPolicy.selectIncoming(incoming: incoming, existing: [course("Original")], appendConflicts: true, timeJson: times), incoming)
        XCTAssertEqual(CourseImportPolicy.selectIncoming(incoming: [course("A"), course("B")], existing: [], appendConflicts: false, timeJson: times).count, 2)
        XCTAssertTrue(CourseImportPolicy.selectIncoming(incoming: [course("New")], existing: [course("Old")], appendConflicts: false, timeJson: times).isEmpty)
    }
    func testMalformedNodeSpanDoesNotOverflowConflictPreview() {
        var malformed = course("Bad", node: Int.max); malformed.step = 2
        XCTAssertFalse(CourseImportPolicy.conflicts(malformed, course("Normal"), timeJson: times))
        malformed.step = 0
        XCTAssertFalse(CourseImportPolicy.conflicts(malformed, course("Normal"), timeJson: times))
    }
    func testMergePreservesExistingAndEdgeSlotsAndOnlyFillsMissingNodes() {
        let original: [TimeTableUtils.TimeSlotRow] = [.init(node: 0, start: "07:00", end: "07:40", edgeClass: .before), .init(node: 1, start: "08:00", end: "08:45")]
        let current = TimeTableUtils.buildTimeJsonFromRows(original)
        let incoming = TimeTableUtils.buildTimeJsonFromRows([.init(node: 1, start: "10:00", end: "10:45"), .init(node: 2, start: "10:55", end: "11:40")])
        let result = TimeTableUtils.parseTimeSlotRows(CourseImportPolicy.mergeTimeJson(current: current, incoming: incoming, requiredNodes: 2))
        XCTAssertEqual(result.filter { $0.node <= 1 }, original)
        XCTAssertEqual(result.first { $0.node == 2 }?.start, "10:55")
        XCTAssertEqual(CourseImportPolicy.mergeTimeJson(current: current, incoming: "", requiredNodes: 1), current)
    }
}
