import XCTest
@testable import Sleepy

final class CourseGeometryAuditTests: XCTestCase {
    func testStandardCourseCountsNodesRatherThanPlaceholderRows() throws {
        let json = """
        [{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"}]
        """
        let irregular = CourseEntity(groupId: "g", tableId: 1, courseName: "I", day: 2,
            startNode: 1, step: 1, startWeek: 1, endWeek: 1, color: "#123456",
            ownTime: true, startTime: "08:00", endTime: "08:50", id: 1)
        let layout = CourseGridRowLayout(courses: [irregular], timeJson: json,
            baseSlots: TimeTableUtils.renderSlots(timeJson: json), configuration: .init())
        let slots = layout.renderPlan.slots
        XCTAssertEqual(slots.map(\.isPlaceholder), [false, true, false])
        XCTAssertEqual(CourseGridRowLayout.standardRowRange(startNode: 1, step: 2, slots: slots), 0..<3)
        let bounds = try XCTUnwrap(CourseGridRowLayout.standardCardBounds(startNode: 1, step: 2,
            slots: slots, yOfRows: layout.yOfRows, gapAfterRow: layout.gapAfterRow))
        XCTAssertEqual(bounds.top, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 118.72, accuracy: 0.001)
        let single = try XCTUnwrap(CourseGridRowLayout.standardCardBounds(startNode: 1, step: 1,
            slots: slots, yOfRows: layout.yOfRows, gapAfterRow: layout.gapAfterRow))
        XCTAssertEqual(single.height, 48, accuracy: 0.001)
    }

    func testTinyCustomCourseBeforeMealBreakRetainsPositiveMinimumHeight() throws {
        let json = """
        [{"node":1,"start":"11:00","end":"11:45"},{"node":2,"start":"14:00","end":"14:45"}]
        """
        let source = CourseEntity(groupId: "g", tableId: 1, courseName: "I", day: 1,
            startNode: 1, step: 1, startWeek: 1, endWeek: 1, color: "#123456",
            ownTime: true, startTime: "11:44", endTime: "11:45", id: 1)
        let layout = CourseGridRowLayout(courses: [source], timeJson: json,
            baseSlots: TimeTableUtils.renderSlots(timeJson: json), configuration: .init(longBreakSpacing: true))
        XCTAssertEqual(layout.mealBreakAfterRows, [0])
        let bounds = try XCTUnwrap(layout.timedCardBounds(start: "11:44", end: "11:45"))
        XCTAssertEqual(bounds.top, 52.0 * 44 / 45, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 11.6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(layout.timedCardBounds(start: "11:00", end: "11:45")).height, 48, accuracy: 0.001)
    }
}
