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

    func testNoTimesJsonConfirmsWithLegacyMergedDefaults() throws {
        let json = """
        {"name":"测试导入表","startDate":"2026-08-24","courses":[{"name":"编译原理","teacher":"陈老师","position":"教3-401","day":4,"startNode":7,"step":2,"startWeek":1,"endWeek":16,"type":0}]}
        """
        let parsed = try ScheduleParser.parse(json, defaultTableId: 0).get()
        XCTAssertTrue(parsed.timeJson.isEmpty)
        XCTAssertEqual(parsed.nodesPerDay, 8)
        let merged = TimeTableUtils.mergeMostComplete(currentJson: "", incomingJson: parsed.timeJson,
            requiredNodeCount: max(parsed.nodesPerDay, parsed.courses.map { $0.startNode + $0.step - 1 }.max() ?? 0))
        let rows = TimeTableUtils.initialManualRows(timeJson: merged).rows
        XCTAssertEqual(rows.count, 8)
        XCTAssertEqual(rows[0].start, "08:00")
        XCTAssertEqual(rows[0].end, "09:40")
        XCTAssertEqual(rows[1].start, rows[0].start)
        XCTAssertEqual(rows[1].end, rows[0].end)
        XCTAssertNil(TimeTableUtils.firstMissingCourseNode(courses: parsed.courses, rows: rows))
        XCTAssertTrue(rows.allSatisfy { !$0.start.isBlank && !$0.end.isBlank })
        XCTAssertEqual(CourseImportPolicy.validateConfirmationRows(rows), .valid)
        XCTAssertEqual(TimeTableUtils.validatePeriodRows(rows),
                       .overlap(prevNode: 1, prevEnd: "09:40", nextNode: 2, nextStart: "08:00"),
                       "Bell-schedule editing must retain its strict overlap check")
    }

    func testConfirmationRejectsOutOfDayAndReversedClocks() {
        XCTAssertEqual(CourseImportPolicy.validateConfirmationRows([
            .init(node: 1, start: "23:00", end: "24:00")]),
            .invalidFormat(node: 1, rawStart: "23:00", rawEnd: "24:00"))
        XCTAssertEqual(CourseImportPolicy.validateConfirmationRows([
            .init(node: 1, start: "09:40", end: "08:00")]),
            .endBeforeStart(node: 1, start: "09:40", end: "08:00"))
    }
}
