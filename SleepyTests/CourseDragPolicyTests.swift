import XCTest
@testable import Sleepy

final class CourseDragPolicyTests: XCTestCase {
    @MainActor
    func testLongPressSessionBeginsImmediatelyEndsAndRenewsIdentity() throws {
        let context = CourseDragContext()
        let table = TimeTableEntity(name: "拖动", startDate: "2026-09-07", id: 1)
        let course = CourseEntity(groupId: "lift", tableId: 1, courseName: "课程", day: 1,
            startNode: 1, step: 2, startWeek: 1, endWeek: 20, color: "#123456", id: 42)
        let frame = CGRect(x: 44, y: 100, width: 100, height: 100)
        let oldToken = try XCTUnwrap(context.begin(course, week: 1, frame: frame, touch: CGPoint(x: 70, y: 125),
            table: table, allCourses: [course], transfers: []))
        XCTAssertTrue(context.sessionToken === oldToken)
        XCTAssertEqual(context.source?.origin, CGPoint(x: 70, y: 125))
        XCTAssertEqual(context.source?.grabOffsetY, 25)
        XCTAssertEqual(context.source?.cardCenterX, 94)
        XCTAssertFalse(context.permitsCourseActivation)
        context.projection = frame
        context.end()
        XCTAssertNil(context.source)
        XCTAssertNil(context.projection)
        XCTAssertNil(context.sessionToken)
        context.end()
        XCTAssertNil(context.source)
        XCTAssertNil(context.projection)
        XCTAssertNil(context.sessionToken)
        XCTAssertTrue(context.permitsCourseActivation)
        let currentToken = try XCTUnwrap(context.begin(course, week: 1, frame: frame, touch: CGPoint(x: 90, y: 160),
            table: table, allCourses: [course], transfers: []))
        XCTAssertTrue(context.sessionToken === currentToken)
        XCTAssertFalse(currentToken === oldToken)
        XCTAssertEqual(context.source?.origin, CGPoint(x: 90, y: 160))
        XCTAssertEqual(context.source?.grabOffsetY, 60)
        XCTAssertEqual(context.source?.cardCenterX, 94)
    }

    @MainActor
    func testStationaryLongHoldReleaseIsConsumedAndNextTapRemainsEligible() {
        let context = CourseDragContext()
        context.recordCourseTouchDuration(0.05)
        XCTAssertTrue(context.permitsCourseTap)
        context.recordCourseTouchDuration(1.2)
        XCTAssertFalse(context.permitsCourseTap)
        XCTAssertTrue(context.permitsCourseActivation, "Keyboard and accessibility activation do not inherit touch duration")
        context.recordCourseTouchDuration(nil)
        XCTAssertTrue(context.permitsCourseTap)
        context.recordCourseTouchDuration(0.05)
        XCTAssertTrue(context.permitsCourseTap)
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
            transfers: transfers, timeJson: table.timeJson).first)
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

    func testDropRejectsSpanAcrossAMissingMiddleNode() {
        let grid = CourseDropGrid(frame: CGRect(x: 0, y: 100, width: 300, height: 200),
            days: [2, 4], timeWidth: 40, columnWidth: 100, gap: 4,
            rows: [.init(node: 1, top: 0, bottom: 45), .init(node: 3, top: 100, bottom: 145)])
        XCTAssertNil(grid.target(at: CGPoint(x: 90, y: 105), step: 3))
        XCTAssertEqual(grid.target(at: CGPoint(x: 90, y: 105), step: 1)?.node, 1)
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

    func testEdgePreviewFadesAfter35PercentAndResetsAfterEachPage() {
        var paging = CourseDragEdgePaging()
        XCTAssertNil(paging.update(direction: 1, now: 10, week: 2, maxWeek: 4))
        XCTAssertEqual(paging.feedback(direction: 1, now: 10.1, week: 2, maxWeek: 4).opacity, 0)
        let visible = paging.feedback(direction: 1, now: 10.3, week: 2, maxWeek: 4)
        XCTAssertEqual(visible.targetWeek, 3)
        XCTAssertEqual(visible.progress, 0.6, accuracy: 0.001)
        XCTAssertGreaterThan(visible.opacity, 0)
        XCTAssertGreaterThan(visible.scale, 1)
        XCTAssertEqual(paging.update(direction: 1, now: 10.5, week: 2, maxWeek: 4), 3)
        XCTAssertEqual(paging.feedback(direction: 1, now: 10.5, week: 3, maxWeek: 4).opacity, 0)
        XCTAssertNil(paging.update(direction: 0, now: 10.6, week: 3, maxWeek: 4))
        XCTAssertEqual(paging.feedback(direction: 0, now: 10.6, week: 3, maxWeek: 4), .init())
        let blocked = paging.feedback(direction: 1, now: 11, week: 4, maxWeek: 4)
        XCTAssertTrue(blocked.blocked)
        XCTAssertEqual(blocked.targetWeek, 4)
        XCTAssertEqual(blocked.opacity, 0.35)
        XCTAssertEqual(blocked.scale, 1)
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: 395, fingerX: 395,
            originX: 387, width: 400), 1, "Android uses an 8pt movement guard")
    }

    func testFloatingResizeIncludesConsecutiveEdgePeriodsButCannotCrossMissingNodes() {
        let rows: [QuickAddRow] = [1, 2, 3, 4, 8].enumerated().map {
            .init(node: $0.element, top: CGFloat($0.offset * 50), bottom: CGFloat($0.offset * 50 + 46))
        }
        let initial = QuickAddRange(day: 2, startNode: 2, endNode: 3)
        let extended = CourseFloatResizePolicy.resized(initial, top: false, position: 300, rows: rows)
        XCTAssertEqual(extended, .init(day: 2, startNode: 2, endNode: 4))
        XCTAssertEqual(CourseFloatResizePolicy.resized(extended, top: true, position: 0, rows: rows),
            .init(day: 2, startNode: 1, endNode: 4))
        XCTAssertEqual(CourseFloatResizePolicy.resized(.init(day: 2, startNode: 8, endNode: 8),
            top: true, position: 0, rows: rows), .init(day: 2, startNode: 8, endNode: 8))
    }

    func testUnmeasuredDestinationWaitsWithoutConsumingTheDwell() {
        var paging = CourseDragEdgePaging()
        XCTAssertNil(paging.update(direction: -1, now: 0, week: 3, maxWeek: 20,
                                   destinationReady: false))
        XCTAssertNil(paging.update(direction: -1, now: 0.5, week: 3, maxWeek: 20,
                                   destinationReady: false))
        XCTAssertNil(paging.update(direction: -1, now: 0.8, week: 3, maxWeek: 20,
                                   destinationReady: false))
        XCTAssertEqual(paging.update(direction: -1, now: 0.9, week: 3, maxWeek: 20,
                                    destinationReady: true), 2)
        // A delayed measurement permits one page, never a burst of queued pages.
        XCTAssertNil(paging.update(direction: -1, now: 0.9, week: 2, maxWeek: 20))
        XCTAssertNil(paging.update(direction: -1, now: 1.399, week: 2, maxWeek: 20))
        XCTAssertEqual(paging.update(direction: -1, now: 1.401, week: 2, maxWeek: 20), 1)
        XCTAssertNil(paging.update(direction: -1, now: 2.4, week: 1, maxWeek: 20))
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

    func testEdgeUsesOutwardFingerOrCenterWithoutUsingCardBounds() {
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: 30, fingerX: 5, originX: 200, width: 400), -1)
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: 5, fingerX: 30, originX: 200, width: 400), -1)
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: 370, fingerX: 395, originX: 200, width: 400), 1)
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: 395, fingerX: 370, originX: 200, width: 400), 1)
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: 200, fingerX: 395, originX: 200, width: 400), 0)
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: 384, fingerX: nil, originX: 200, width: 400), 0)
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: 395, fingerX: nil, originX: 200, width: 400), 1)
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: -5, fingerX: -15, originX: 200, width: 400), -1)
        XCTAssertEqual(CourseDragEdgePaging.direction(centerX: 60, fingerX: 55, originX: 250,
                                                     width: 400, minimumX: 50), -1)
    }
}
