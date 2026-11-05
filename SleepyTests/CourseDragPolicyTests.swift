import XCTest
@testable import Sleepy

final class CourseDragPolicyTests: XCTestCase {
    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.firstWeekday = 2
        return cal
    }
    
    @MainActor
    func testOwnTimeLiftKeepsFractionalStartOnSameRow() throws {
        let context = CourseDragContext()
        let grid = CourseDropGrid(frame: CGRect(x: 0, y: 100, width: 300, height: 104),
            days: [1, 2], timeWidth: 40, columnWidth: 100, gap: 4,
            rows: [.init(node: 1, top: 0, bottom: 48), .init(node: 2, top: 52, bottom: 100)])
        context.grids[1] = grid
        let course = CourseEntity(groupId: "short", tableId: 1, courseName: "短课", day: 1, startNode: 1,
                                  step: 1, startWeek: 1, endWeek: 20, color: "#FF123456",
                                  ownTime: true, startTime: "08:35", endTime: "08:40")
        let frame = CGRect(x: 44, y: 140.44, width: 100, height: 12)
        _ = context.begin(course, week: 1, frame: frame, touch: CGPoint(x: 94, y: 146.44),
            table: TimeTableEntity(name: "拖动", startDate: "2026-09-07", id: 1),
            allCourses: [course], transfers: [])
        let source = try XCTUnwrap(context.source)
        XCTAssertEqual(grid.target(at: CGPoint(x: 94, y: 146.44), step: 1,
                                   grabOffsetY: source.snapOffsetY)?.node, 1)
        let horizontal = grid.target(at: CGPoint(x: 198, y: 146.44), step: 1,
                                     grabOffsetY: source.snapOffsetY)
        XCTAssertEqual(horizontal?.node, 1)
        XCTAssertEqual(horizontal?.day, 2)
    }

    @MainActor
    func testLiftCapturesRawIdentitySeparatelyFromCrossWeekProjection() throws {
        let context = CourseDragContext()
        let table = TimeTableEntity(name: "身份", startDate: "2026-09-07", maxWeek: 4, id: 1)
        let original = CourseEntity(groupId: "identity", tableId: 1, courseName: "课程", day: 2,
            startNode: 4, step: 2, startWeek: 1, endWeek: 4, type: 1, color: "#123456",
            ownTime: true, startTime: "08:35", endTime: "08:40", id: 42)
        let transfers = [HolidayTransferEntry(
            sourceDate: try XCTUnwrap(DateUtils.dateOfWeek(startDate: table.startDate, week: 1, dayOfWeek: 2)),
            targetDate: try XCTUnwrap(DateUtils.dateOfWeek(startDate: table.startDate, week: 6, dayOfWeek: 7)),
            segmentId: "lift")]
        let projection = try XCTUnwrap(renderCoursesForWeek(table, week: 6, courses: [original],
            transfers: transfers, timeJson: table.timeJson, calendar: utcCalendar()).first)
        XCTAssertNotNil(context.begin(projection, week: 6, frame: .zero, touch: nil,
            table: table, allCourses: [original], transfers: transfers))
        let captured = try XCTUnwrap(context.source)
        XCTAssertEqual(captured.occurrence, .init(week: 1, day: 2))
        XCTAssertEqual(captured.displayWeek, 6)
        XCTAssertEqual(captured.displayDay, 7)
        XCTAssertEqual(captured.course.day, 2)
        XCTAssertEqual(captured.course.startNode, 4)
        XCTAssertEqual(captured.course.step, 2)
        XCTAssertEqual(captured.renderedCourse.day, 7)
        context.grids = [:] // 源页销毁后身份仍完整。
        XCTAssertEqual(context.source?.occurrence, captured.occurrence)
        context.end()
        XCTAssertNil(context.source)
        XCTAssertNil(context.provider)
        XCTAssertNil(context.sessionToken)
        XCTAssertNil(context.begin(projection, week: 6, frame: .zero, touch: nil,
            table: table, allCourses: [original], transfers: []))
        var wrongTable = original
        wrongTable.tableId = 2
        XCTAssertNil(context.begin(projection, week: 6, frame: .zero, touch: nil,
            table: table, allCourses: [wrongTable], transfers: transfers))
    }

    func testTimedProjectionUsesDurationInsteadOfWholePeriodHeight() {
        let grid = CourseDropGrid(frame: CGRect(x: 0, y: 100, width: 300, height: 104),
            days: [1, 2], timeWidth: 40, columnWidth: 100, gap: 4,
            rows: [.init(node: 1, top: 0, bottom: 48), .init(node: 2, top: 52, bottom: 100)],
            timeRows: [.init(node: 1, startMinute: 480, endMinute: 525, top: 0, height: 52, gapAfter: 4),
                       .init(node: 2, startMinute: 540, endMinute: 585, top: 52, height: 52, gapAfter: 4)])
        let column = CGRect(x: 44, y: 100, width: 100, height: 48)
        let short = grid.timedProjection(start: "08:00", end: "08:20", column: column)
        XCTAssertEqual(short?.minY, 100)
        XCTAssertEqual(short?.height ?? 0, 52 * 20 / 45 - 4, accuracy: 0.01)
        XCTAssertEqual(grid.timedProjection(start: "08:00", end: "09:45", column: column)?.height, 100)
        XCTAssertNil(grid.timedProjection(start: "09:00", end: "10:00", column: column))
    }

    func testGrabOffsetKeepsMultiPeriodCourseInPlaceAndOnHorizontalMove() {
        let grid = CourseDropGrid(frame: CGRect(x: 0, y: 0, width: 300, height: 220),
            days: [1, 2], timeWidth: 40, columnWidth: 100, gap: 4,
            rows: [.init(node: 1, top: 0, bottom: 48),
                   .init(node: 2, top: 52, bottom: 100),
                   .init(node: 3, top: 104, bottom: 152),
                   .init(node: 4, top: 156, bottom: 204)])
        for grabY: CGFloat in [10, 50, 95] {
            let same = grid.target(at: CGPoint(x: 90, y: grabY), step: 2, grabOffsetY: grabY)
            XCTAssertEqual(same?.node, 1)
            XCTAssertEqual(same?.day, 1)
            let moved = grid.target(at: CGPoint(x: 194, y: grabY), step: 2, grabOffsetY: grabY)
            XCTAssertEqual(moved?.node, 1)
            XCTAssertEqual(moved?.day, 2)
        }
    }

    func testDropUsesVisibleDaysWeightedRowsAndRejectsOverflow() {
        let grid = CourseDropGrid(frame: CGRect(x: 10, y: 100, width: 300, height: 250),
            days: [2, 4, 7], timeWidth: 40, columnWidth: 80, gap: 5,
            rows: [.init(node: 1, top: 0, bottom: 45),
                   .init(node: 2, top: 50, bottom: 115),
                   .init(node: 3, top: 145, bottom: 245)])
        let hit = grid.target(at: CGPoint(x: 150, y: 152), step: 2)
        XCTAssertEqual(hit?.day, 4)
        XCTAssertEqual(hit?.node, 2)
        XCTAssertEqual(hit?.rect, CGRect(x: 140, y: 150, width: 80, height: 195))
        XCTAssertNil(grid.target(at: CGPoint(x: 35, y: 150), step: 1))
        XCTAssertNil(grid.target(at: CGPoint(x: 150, y: 90), step: 1))
        XCTAssertNil(grid.target(at: CGPoint(x: 150, y: 260), step: 2))
    }

    func testDwellRepeatsEveryHalfSecondAndResetsOnExit() {
        var paging = CourseDragEdgePaging()
        XCTAssertNil(paging.update(direction: 1, now: 0, week: 1, maxWeek: 20))
        XCTAssertNil(paging.update(direction: 1, now: 0.499, week: 1, maxWeek: 20))
        XCTAssertEqual(paging.update(direction: 1, now: 0.5, week: 1, maxWeek: 20), 2)
        XCTAssertEqual(paging.update(direction: 1, now: 1, week: 2, maxWeek: 20), 3)
        XCTAssertNil(paging.update(direction: 0, now: 1.1, week: 3, maxWeek: 20))
        XCTAssertNil(paging.update(direction: 1, now: 2, week: 3, maxWeek: 20))
        XCTAssertEqual(paging.update(direction: 1, now: 2.5, week: 3, maxWeek: 20), 4)
    }

    func testChangingEdgeRestartsDwellAndSemesterBoundsHold() {
        var paging = CourseDragEdgePaging()
        XCTAssertNil(paging.update(direction: 1, now: 0, week: 2, maxWeek: 3))
        XCTAssertNil(paging.update(direction: -1, now: 0.4, week: 2, maxWeek: 3))
        XCTAssertNil(paging.update(direction: -1, now: 0.5, week: 2, maxWeek: 3))
        XCTAssertEqual(paging.update(direction: -1, now: 1, week: 2, maxWeek: 3), 1)
        XCTAssertNil(paging.update(direction: -1, now: 2, week: 1, maxWeek: 3))
        XCTAssertNil(paging.update(direction: 1, now: 3, week: 3, maxWeek: 3))
        XCTAssertNil(paging.update(direction: 1, now: 4, week: 3, maxWeek: 3))
    }

    func testEdgeUsesBothOuterEdgesAndRequiresMovement() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 600)
        XCTAssertEqual(CourseDragEdgePaging.direction(at: CGPoint(x: 5, y: 40), origin: CGPoint(x: 5, y: 40), bounds: bounds), 0)
        XCTAssertEqual(CourseDragEdgePaging.direction(at: CGPoint(x: 5, y: 40), origin: CGPoint(x: 200, y: 40), bounds: bounds), -1)
        XCTAssertEqual(CourseDragEdgePaging.direction(at: CGPoint(x: 395, y: 40), origin: CGPoint(x: 200, y: 40), bounds: bounds), 1)
        XCTAssertEqual(CourseDragEdgePaging.direction(at: CGPoint(x: 395, y: -1), origin: CGPoint(x: 200, y: 40), bounds: bounds), 0)
    }
}
