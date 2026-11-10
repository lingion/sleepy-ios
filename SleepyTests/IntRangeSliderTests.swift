import XCTest
@testable import Sleepy

final class IntRangeSliderTests: XCTestCase {
    func testMovingEitherEndpointCannotCrossOrEscapeDomain() {
        let range = IntSliderRange(start: 3, end: 6, minimum: 1, maximum: 12)
        XCTAssertEqual(range.movingStart(to: 10, minimum: 1), IntSliderRange(start: 6, end: 6, minimum: 1, maximum: 12))
        XCTAssertEqual(range.movingStart(to: -2, minimum: 1).start, 1)
        XCTAssertEqual(range.movingEnd(to: 1, maximum: 12), IntSliderRange(start: 3, end: 3, minimum: 1, maximum: 12))
        XCTAssertEqual(range.movingEnd(to: 20, maximum: 12).end, 12)
    }

    func testGhostRequiresBothOpeningValuesAndDisappearsWhenRestored() {
        let range = IntSliderRange(start: 4, end: 8, minimum: 1, maximum: 16)
        XCTAssertNil(IntSliderRange.ghost(current: range, initialStart: nil, initialEnd: 8, minimum: 1, maximum: 16))
        XCTAssertNil(IntSliderRange.ghost(current: range, initialStart: 4, initialEnd: nil, minimum: 1, maximum: 16))
        XCTAssertNil(IntSliderRange.ghost(current: range, initialStart: 4, initialEnd: 8, minimum: 1, maximum: 16))
        XCTAssertEqual(IntSliderRange.ghost(current: range, initialStart: 2, initialEnd: 6, minimum: 1, maximum: 16),
                       IntSliderRange(start: 2, end: 6, minimum: 1, maximum: 16))
    }

    func testDisplayAndGhostShareClampingForDirtyImportedValues() {
        let shown = IntSliderRange(start: -3, end: 28, minimum: 1, maximum: 12)
        XCTAssertEqual(shown.start, 1)
        XCTAssertEqual(shown.end, 12)
        XCTAssertNil(IntSliderRange.ghost(current: shown, initialStart: -3, initialEnd: 28, minimum: 1, maximum: 12))
        let inverted = IntSliderRange(start: 8, end: 2, minimum: 1, maximum: 12)
        XCTAssertEqual(inverted.start, 8)
        XCTAssertEqual(inverted.end, 8)
    }

    func testOneStopDomainAlwaysShowsItsOnlyValue() {
        let range = IntSliderRange(start: 8, end: 20, minimum: 1, maximum: 1)
        XCTAssertEqual(range.start, 1)
        XCTAssertEqual(range.end, 1)
        XCTAssertNil(IntSliderRange.ghost(current: range, initialStart: 2, initialEnd: 4, minimum: 1, maximum: 1))
    }

    func testCoincidentThumbsWaitForDirectionEvenWhenTouchStartsOffCenter() {
        XCTAssertNil(IntSliderRange.thumb(at: 105, startX: 100, endX: 100, translation: 0, rightToLeft: false))
        XCTAssertEqual(IntSliderRange.thumb(at: 105, startX: 100, endX: 100, translation: -20, rightToLeft: false), .start)
        XCTAssertEqual(IntSliderRange.thumb(at: 95, startX: 100, endX: 100, translation: 20, rightToLeft: false), .end)
        XCTAssertEqual(IntSliderRange.thumb(at: 105, startX: 100, endX: 100, translation: 20, rightToLeft: true), .start)
        XCTAssertEqual(IntSliderRange.thumb(at: 95, startX: 100, endX: 100, translation: -20, rightToLeft: true), .end)
    }

    func testExistingCourseOpeningRangesSurviveDraftChanges() {
        let course = CourseEntity(groupId: "edit", tableId: 1, courseName: "Math", day: 2,
            startNode: 3, step: 2, startWeek: 4, endWeek: 12, color: "#FF6750A4")
        var block = AddCourseScreen.initialMeetingBlock(course)
        block.startNode = 7
        block.step = 1
        block.startWeek = 6
        block.endWeek = 10
        XCTAssertEqual(block.initialStartNode, 3)
        XCTAssertEqual(block.initialStep, 2)
        XCTAssertEqual(block.initialStartWeek, 4)
        XCTAssertEqual(block.initialEndWeek, 12)
    }

    func testNewAndQuickAddBlocksDoNotInventGhostBaselines() throws {
        let plain = AddCourseScreen.initialMeetingBlock(nil)
        XCTAssertNil(plain.initialStartNode)
        XCTAssertNil(plain.initialStep)
        XCTAssertNil(plain.initialStartWeek)
        XCTAssertNil(plain.initialEndWeek)
        let table = TimeTableEntity(name: "Schedule", startDate: "2026-11-02", maxWeek: 16,
            nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON, id: 7)
        let slot = CourseAddSlot(tableId: 7, week: 3, day: 2, node: 4, step: 2)
        let quick = try XCTUnwrap(AddCourseScreen.quickAddMeetingBlock(slot, table: table))
        XCTAssertNil(quick.initialStartNode)
        XCTAssertNil(quick.initialStep)
        XCTAssertNil(quick.initialStartWeek)
        XCTAssertNil(quick.initialEndWeek)
    }
}
