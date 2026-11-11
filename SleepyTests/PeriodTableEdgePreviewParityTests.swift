import XCTest
@testable import Sleepy

final class PeriodTableEdgePreviewParityTests: XCTestCase {
    private typealias Row = TimeTableUtils.TimeSlotRow
    private func json(_ rows: [Row]) -> String { TimeTableUtils.buildTimeJsonFromRows(rows) }
    private func course(_ node: Int, edge: Bool) -> CourseEntity {
        CourseEntity(groupId: "preview", tableId: 1, courseName: "边缘课", day: 1, startNode: node,
            step: 1, startWeek: 1, endWeek: 16, color: "", isIrregularNode: edge)
    }
    private var old: String { json([Row(node: 1, start: "08:00", end: "08:45"),
        Row(node: 2, start: "09:00", end: "09:45"), Row(node: 3, start: "12:00", end: "12:45", edgeClass: .after)]) }
    private func next(edgeStart: String = "12:00", edgeEnd: String = "12:45") -> String {
        json([Row(node: 1, start: "08:00", end: "08:45"), Row(node: 2, start: "09:00", end: "09:45"),
              Row(node: 3, start: "10:00", end: "10:45"), Row(node: 4, start: edgeStart, end: edgeEnd, edgeClass: .after)])
    }

    func testEdgeRenumberWithoutClockChangeIsUnchangedInPreview() {
        let preview = TimeTableUtils.previewPeriodTableChange(oldTimeJson: old, newTimeJson: next(), courses: [course(3, edge: true)])
        XCTAssertTrue(preview.changedCourses.isEmpty)
        XCTAssertEqual(preview.unchangedCount, 1)
    }

    func testEdgeClockChangePreviewUsesMigratedDestinationAndStandardCoursesKeepOrdinals() {
        let preview = TimeTableUtils.previewPeriodTableChange(oldTimeJson: old,
            newTimeJson: next(edgeStart: "13:00", edgeEnd: "13:45"), courses: [course(3, edge: true), course(2, edge: false)])
        XCTAssertEqual(preview.unchangedCount, 1)
        XCTAssertEqual(preview.changedCourses.count, 1)
        XCTAssertEqual(preview.changedCourses.first?.oldTime, "12:00-12:45")
        XCTAssertEqual(preview.changedCourses.first?.newTime, "13:00-13:45")
        XCTAssertEqual(preview.changedCourses.first?.changedNodes, [3])
    }

    func testDeletedEdgePreviewRetainsItsPreviousClockWithoutReattachingToRemainingNeighbour() {
        let before = json([Row(node: 3, start: "12:00", end: "12:45", edgeClass: .after),
                           Row(node: 4, start: "13:00", end: "13:45", edgeClass: .after)])
        let after = json([Row(node: 5, start: "13:00", end: "13:45", edgeClass: .after)])
        let preview = TimeTableUtils.previewPeriodTableChange(oldTimeJson: before, newTimeJson: after,
                                                              courses: [course(3, edge: true), course(4, edge: true)])
        XCTAssertEqual(preview.unchangedCount, 2)
        XCTAssertTrue(preview.changedCourses.isEmpty)
    }

    func testActualManualEdgeDeletionPreviewMatchesPreservedCourseClocks() {
        let rows = [Row(node: 1, start: "08:00", end: "08:45"),
                    Row(node: 2, start: "09:00", end: "09:45"),
                    Row(node: 3, start: "12:00", end: "12:45", edgeClass: .after),
                    Row(node: 4, start: "13:00", end: "13:45", edgeClass: .after)]
        let nextRows = TimeTableUtils.removeAndRenumber(rows, node: 3)
        XCTAssertEqual(nextRows.last?.node, 3)
        let preview = TimeTableUtils.previewPeriodTableChange(oldTimeJson: json(rows), newTimeJson: json(nextRows),
            courses: [course(3, edge: true), course(4, edge: true)])
        XCTAssertTrue(preview.changedCourses.isEmpty)
        XCTAssertEqual(preview.unchangedCount, 2)
    }
}
