import XCTest
@testable import Sleepy

final class CourseCustomTimeContractTests: XCTestCase {
    private let json = """
        [{"node":1,"start":"08:00","end":"08:45"},
         {"node":2,"start":"09:00","end":"09:45"},
         {"node":3,"start":"19:00","end":"19:45"}]
        """

    private func course() -> CourseEntity {
        CourseEntity(groupId: "custom", tableId: 1, courseName: "自定义时间", day: 1,
            startNode: 1, step: 1, startWeek: 1, endWeek: 1, color: "#123456",
            isIrregularTime: true, ownTime: false, startTime: "09:00", endTime: "09:50", id: 1)
    }

    func testIrregularOnlyNormalizesNodesButPreservesEdgeAndInvalidTime() {
        let original = course()
        let normalized = original.normalizeNode(timeJson: json)
        XCTAssertEqual(normalized.startNode, 2)
        XCTAssertEqual(normalized.step, 1)
        XCTAssertFalse(normalized.ownTime)
        var edge = original
        edge.isIrregularNode = true
        edge.startNode = 0
        edge.step = 3
        XCTAssertEqual(edge.normalizeNode(timeJson: json).startNode, 0)
        XCTAssertEqual(edge.normalizeNode(timeJson: json).step, 3)
        var invalid = original
        invalid.startTime = " "
        XCTAssertEqual(invalid.normalizeNode(timeJson: json).startNode, 1)
        var standard = original
        standard.isIrregularTime = false
        XCTAssertEqual(standard.normalizeNode(timeJson: json).startNode, 1)
    }

    func testIrregularOnlyPlaceholderAndBoundsMatchLegacyOwnTime() throws {
        let modern = course()
        var legacy = modern
        legacy.ownTime = true
        legacy.isIrregularTime = false
        let slots = TimeTableUtils.renderSlots(timeJson: json)
        let actual = CourseGridRowLayout(courses: [modern.normalizeNode(timeJson: json)], timeJson: json,
                                        baseSlots: slots, configuration: .init())
        let expected = CourseGridRowLayout(courses: [legacy.normalizeNode(timeJson: json)], timeJson: json,
                                          baseSlots: slots, configuration: .init())
        XCTAssertEqual(actual.renderPlan.slots.filter(\.isPlaceholder).map(\.timeString), ["09:45-09:50"])
        XCTAssertEqual(actual.renderPlan.slotWeights, expected.renderPlan.slotWeights)
        let actualBounds = try XCTUnwrap(actual.timedCardBounds(start: modern.startTime, end: modern.endTime))
        let expectedBounds = try XCTUnwrap(expected.timedCardBounds(start: legacy.startTime, end: legacy.endTime))
        XCTAssertEqual(actualBounds.top, expectedBounds.top, accuracy: 0.001)
        XCTAssertEqual(actualBounds.height, expectedBounds.height, accuracy: 0.001)
        XCTAssertEqual(actualBounds.height, 52 * 1.36 - 4, accuracy: 0.001)
    }

    func testIrregularOnlyEveningTimeControlsViewportInsteadOfStoredNode() {
        var evening = course()
        evening.startTime = "19:00"
        evening.endTime = "19:45"
        let slots = TimeTableUtils.renderSlots(timeJson: json).map(TimetableViewportPolicy.SlotRef.init)
        let visible = TimetableViewportPolicy.selectVisibleSlots(allCourses: [evening], timeSlots: slots,
            visibleDays: [1], timeJson: json, autoHideEmptyEvening: true)
        XCTAssertEqual(visible.slots.count, 3)
        var morning = course()
        morning.startNode = 3
        let collapsed = TimetableViewportPolicy.selectVisibleSlots(allCourses: [morning], timeSlots: slots,
            visibleDays: [1], timeJson: json, autoHideEmptyEvening: true)
        XCTAssertEqual(collapsed.slots.count, 2)
    }
}
