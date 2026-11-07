import XCTest
@testable import Sleepy

final class CourseDropCandidateGeometryTests: XCTestCase {
    private let timeJson = """
        [{"node":1,"start":"08:00","end":"08:45"},
         {"node":2,"start":"09:00","end":"09:45"},
         {"node":3,"start":"11:00","end":"11:45"},
         {"node":4,"start":"14:00","end":"14:45"}]
        """

    private func course(id: Int64 = 1, start: String = "08:00", end: String = "08:50") -> CourseEntity {
        CourseEntity(groupId: "drag", tableId: 1, courseName: "自定义时间", day: 1,
            startNode: 1, step: 1, startWeek: 1, endWeek: 2, color: "#123456",
            ownTime: true, startTime: start, endTime: end, id: id)
    }

    func testNewCourseEndingInBreakMatchesFinalLayoutIncludingPlaceholderMinimum() throws {
        let slots = TimeTableUtils.renderSlots(timeJson: timeJson)
        var source = course()
        source.endWeek = 1 // 空目标页：原行仅在源周出现。
        let config = CourseGridRowLayout.Configuration()
        let current = CourseGridRowLayout(courses: [], timeJson: timeJson, baseSlots: slots, configuration: config)
        XCTAssertFalse(current.renderPlan.slots.contains(where: \.isPlaceholder))
        let page = CourseDropCandidateLayout(week: 2, courses: [], timeJson: timeJson,
                                            baseSlots: slots, configuration: config,
                                            startDate: "2026-09-07", maxWeek: 4, allCourses: [source])
        let destination = CourseOccurrenceDestination(startNode: 1, endNode: 1,
            startTime: "08:00", endTime: "08:50", usesOwnTime: true)
        let candidate = try XCTUnwrap(page.layout(source: source, sourceOccurrence: .init(week: 1, day: 1), day: 2, destination: destination))
        var moved = source
        moved.day = 2
        let final = CourseGridRowLayout(courses: [moved], timeJson: timeJson, baseSlots: slots, configuration: config)
        let preview = try XCTUnwrap(candidate.timedCardBounds(start: destination.startTime, end: destination.endTime))
        let landed = try XCTUnwrap(final.timedCardBounds(start: moved.startTime, end: moved.endTime))
        XCTAssertEqual(candidate.renderPlan.slots.filter(\.isPlaceholder).count, 1)
        XCTAssertEqual(preview.top, landed.top, accuracy: 0.001)
        XCTAssertEqual(preview.height, landed.height, accuracy: 0.001)
        XCTAssertEqual(preview.height, 52 * 1.36 - 4, accuracy: 0.001)
        XCTAssertNotEqual(current.timedCardBounds(start: moved.startTime, end: moved.endTime)?.height, preview.height)
        let grid = CourseDropGrid(frame: CGRect(x: 10, y: 100, width: 300, height: 208),
            days: [1, 2], timeWidth: 40, columnWidth: 100, gap: 5, rows: [], candidateLayout: page)
        let rect = try XCTUnwrap(grid.candidateTimedProjection(source: source, sourceOccurrence: .init(week: 1, day: 1),
            day: 2, destination: destination, column: CGRect(x: 160, y: 100, width: 100, height: 48)))
        XCTAssertEqual(rect.minY, 100 + landed.top)
        XCTAssertEqual(rect.minX, 160)
        XCTAssertEqual(rect.width, 100)
        XCTAssertEqual(rect.height, landed.height, accuracy: 0.001)
    }

    func testSameWeekMoveRemovesOldPlaceholderAndUsesAdaptiveHeightAndLongBreakRules() throws {
        let slots = TimeTableUtils.renderSlots(timeJson: timeJson)
        var source = course(start: "11:00", end: "11:50")
        source.startNode = 3
        source.isIrregularTime = true
        let config = CourseGridRowLayout.Configuration(contentScale: 1.2, verticalScale: 0.9,
            adaptive: true, availableGridHeight: 250, longBreakSpacing: true, fontScale: 1.3,
            expandedPlaceholders: ["08:45-08:50"])
        let page = CourseDropCandidateLayout(week: 1, courses: [source], timeJson: timeJson,
                                            baseSlots: slots, configuration: config,
                                            startDate: "2026-09-07", maxWeek: 4, allCourses: [source])
        let destination = CourseOccurrenceDestination(startNode: 1, endNode: 1,
            startTime: "08:00", endTime: "08:50", usesOwnTime: true)
        let candidate = try XCTUnwrap(page.layout(source: source, sourceOccurrence: .init(week: 1, day: 1), day: 2, destination: destination))
        var moved = source
        moved.day = 2
        moved.startNode = 1
        moved.startTime = "08:00"
        moved.endTime = "08:50"
        let final = CourseGridRowLayout(courses: [moved], timeJson: timeJson, baseSlots: slots, configuration: config)
        XCTAssertEqual(candidate.renderPlan.slots.filter(\.isPlaceholder).map(\.timeString), ["08:45-08:50"])
        XCTAssertEqual(candidate.mealBreakAfterRows, final.mealBreakAfterRows)
        XCTAssertFalse(candidate.mealBreakAfterRows.isEmpty)
        XCTAssertEqual(candidate.rowHeight, final.rowHeight)
        for index in 0...final.renderPlan.slots.count {
            XCTAssertEqual(candidate.yOfRows(Double(index)), final.yOfRows(Double(index)), accuracy: 0.001)
        }
        let preview = try XCTUnwrap(candidate.timedCardBounds(start: moved.startTime, end: moved.endTime))
        let landed = try XCTUnwrap(final.timedCardBounds(start: moved.startTime, end: moved.endTime))
        XCTAssertEqual(preview.height, landed.height, accuracy: 0.001)
    }

    func testCrossWeekMoveKeepsRecurringSourceInTargetWeek() throws {
        let source = course()
        let page = CourseDropCandidateLayout(week: 2, courses: [source], timeJson: timeJson,
            baseSlots: TimeTableUtils.renderSlots(timeJson: timeJson), configuration: .init(),
            startDate: "2026-09-07", maxWeek: 4, allCourses: [source])
        let destination = CourseOccurrenceDestination(startNode: 2, endNode: 2,
            startTime: "09:00", endTime: "09:50", usesOwnTime: true)
        let candidate = try XCTUnwrap(page.layout(source: source, sourceOccurrence: .init(week: 1, day: 1), day: 2, destination: destination))
        XCTAssertEqual(candidate.renderPlan.slots.filter(\.isPlaceholder).map(\.timeString),
                       ["08:45-08:50", "09:45-09:50"])
    }

    func testEdgeCourseMoveClearsEdgeMetadataBeforeNormalizingLikePersistence() throws {
        var source = course(start: "07:00", end: "07:50")
        source.endWeek = 1 // 空目标页不含第二次边缘课。
        source.isIrregularNode = true
        source.startNode = 0
        source.step = 4
        let slots = TimeTableUtils.renderSlots(timeJson: timeJson)
        let config = CourseGridRowLayout.Configuration(longBreakSpacing: true)
        let page = CourseDropCandidateLayout(week: 2, courses: [], timeJson: timeJson,
                                            baseSlots: slots, configuration: config,
                                            startDate: "2026-09-07", maxWeek: 4, allCourses: [source])
        let destination = CourseOccurrenceDestination(startNode: 3, endNode: 3,
            startTime: "11:00", endTime: "11:50", usesOwnTime: true)
        let candidate = try XCTUnwrap(page.layout(source: source, sourceOccurrence: .init(week: 1, day: 1), day: 2, destination: destination))
        var persisted = source
        persisted.day = 2
        persisted.startNode = 3
        persisted.isIrregularNode = false
        persisted.startTime = "11:00"
        persisted.endTime = "11:50"
        let rendered = persisted.normalizeNode(timeJson: timeJson)
        XCTAssertEqual(rendered.step, 1)
        let final = CourseGridRowLayout(courses: [rendered], timeJson: timeJson,
                                        baseSlots: slots, configuration: config)
        XCTAssertFalse(final.mealBreakAfterRows.isEmpty)
        XCTAssertEqual(candidate.mealBreakAfterRows, final.mealBreakAfterRows)
        XCTAssertEqual(candidate.yOfRows(4), final.yOfRows(4), accuracy: 0.001)
    }

    func testMovingLastEveningOccurrenceCollapsesSlotsAndMatchesFinalAdaptiveHeight() throws {
        try assertEveningMove(sourceEndWeek: 1, sourceType: 0, expectedCount: 3)
        // 单周课区间覆盖第 2 周，但该周没有实际上课，仍须收起。
        try assertEveningMove(sourceEndWeek: 2, sourceType: 1, expectedCount: 3)
    }

    func testMovingOneOccurrenceKeepsEveningWhenOtherWeeksStillHaveClass() throws {
        try assertEveningMove(sourceEndWeek: 2, sourceType: 0, expectedCount: 4)
        try assertEveningMove(sourceEndWeek: 3, sourceType: 1, expectedCount: 4)
    }

    func testSemesterOnlyOccurrenceChangeInvalidatesCandidateSnapshot() {
        var source = course(start: "19:00", end: "19:45")
        source.endWeek = 1
        let slots = TimeTableUtils.renderSlots(timeJson: timeJson)
        let before = CourseDropCandidateLayout(week: 2, courses: [], timeJson: timeJson,
            baseSlots: slots, configuration: .init(), startDate: "2026-09-07", maxWeek: 4,
            allCourses: [source], timeSlots: slots,
            autoHideEmptyEvening: true)
        var after = before
        source.endWeek = 3
        after.allCourses = [source]
        XCTAssertNotEqual(before, after)
        after = before
        after.eveningStartMinutes = 20 * 60
        XCTAssertNotEqual(before, after)
        after = before
        after.visibleDays = [2]
        XCTAssertNotEqual(before, after)
    }

    func testHolidayCandidateRemovesCapturedProjectionButKeepsOtherOccurrenceOfSameRow() throws {
        var source = course(start: "11:00", end: "11:50")
        source.startNode = 3
        source.endWeek = 4
        let transfers = [try transfer(1, 1, 2, 7), try transfer(3, 2, 2, 6)]
        let page = candidatePage(source, week: 2, transfers: transfers)
        XCTAssertEqual(page.courses.map(\.day).sorted(), [1, 7])
        let destination = CourseOccurrenceDestination(startNode: 1, endNode: 1,
            startTime: "08:00", endTime: "08:50", usesOwnTime: true)
        let next = try XCTUnwrap(page.snapshot(source: source, sourceOccurrence: .init(week: 1, day: 1),
            day: 6, destination: destination))
        XCTAssertEqual(next.targetOccurrence, .init(week: 3, day: 2))
        XCTAssertEqual(next.courses.map(\.day).sorted(), [1, 6])
        XCTAssertEqual(next.courses.filter { $0.day == 1 }.map(\.startTime), ["11:00"])
        XCTAssertEqual(next.courses.filter { $0.day == 6 }.map(\.startTime), ["08:00"])
        XCTAssertFalse(next.allCourses.contains { $0.day == 1 && $0.inWeek(1) })
        for week in 2...4 {
            XCTAssertEqual(next.allCourses.filter { $0.day == 1 && $0.inWeek(week) }.count, 1)
        }
        let inserted = try XCTUnwrap(next.allCourses.first { $0.day == 2 })
        XCTAssertEqual(inserted.startWeek, 3)
        XCTAssertEqual(inserted.endWeek, 3)
        let layout = try XCTUnwrap(page.layout(source: source, sourceOccurrence: .init(week: 1, day: 1),
            day: 6, destination: destination))
        XCTAssertEqual(layout.renderPlan.slots.filter(\.isPlaceholder).map(\.timeString),
            ["08:45-08:50", "11:45-11:50"])
    }

    func testHolidayCandidateRejectsEmptyColumnAndMismatchedCapturedIdentity() throws {
        let source = course()
        let page = candidatePage(source, week: 1, transfers: [try transfer(1, 2, 2, 7)])
        let destination = CourseOccurrenceDestination(startNode: 1, endNode: 1,
            startTime: "08:00", endTime: "08:50", usesOwnTime: true)
        XCTAssertNil(page.snapshot(source: source, sourceOccurrence: .init(week: 1, day: 1), day: 2, destination: destination))
        XCTAssertNil(page.snapshot(source: source, sourceOccurrence: .init(week: 1, day: 3), day: 3, destination: destination))
        XCTAssertNil(page.snapshot(source: source, sourceOccurrence: .init(week: 3, day: 1), day: 3, destination: destination))
    }

    func testExtendedDisplayCandidateUsesOddSourceWeekAndEvenTrueTarget() throws {
        var source = course()
        source.endWeek = 4
        source.type = 1
        let transfers = [try transfer(1, 1, 6, 7), try transfer(4, 2, 6, 6)]
        let page = candidatePage(source, week: 6, transfers: transfers)
        XCTAssertEqual(page.courses.map(\.day), [7])
        let destination = CourseOccurrenceDestination(startNode: 2, endNode: 2,
            startTime: "09:00", endTime: "09:50", usesOwnTime: true)
        let next = try XCTUnwrap(page.snapshot(source: source, sourceOccurrence: .init(week: 1, day: 1),
            day: 6, destination: destination))
        XCTAssertEqual(next.targetOccurrence, .init(week: 4, day: 2))
        XCTAssertEqual(next.courses.map(\.day), [6])
        XCTAssertEqual(next.allCourses.filter { $0.day == 1 && $0.inWeek(3) }.count, 1)
        XCTAssertFalse(next.allCourses.contains { $0.day == 1 && $0.inWeek(2) })
        XCTAssertNil(page.snapshot(source: source, sourceOccurrence: .init(week: 2, day: 1), day: 6, destination: destination))
        XCTAssertNil(page.snapshot(source: source, sourceOccurrence: .init(week: 1, day: 1), day: 5, destination: destination))
    }

    func testCandidateRejectsRawRangeOutsideRealSemesterEvenWhenRowContainsWeek() {
        var source = course()
        source.endWeek = 9
        let page = candidatePage(source, week: 2, transfers: [])
        let destination = CourseOccurrenceDestination(startNode: 1, endNode: 1,
            startTime: "08:00", endTime: "08:50", usesOwnTime: true)
        XCTAssertNil(page.snapshot(source: source, sourceOccurrence: .init(week: 5, day: 1),
            day: 2, destination: destination))
    }

    private func transfer(_ sourceWeek: Int, _ sourceDay: Int, _ week: Int, _ day: Int) throws -> HolidayTransferEntry {
        HolidayTransferEntry(sourceDate: try XCTUnwrap(DateUtils.dateOfWeek(startDate: "2026-09-07", week: sourceWeek, dayOfWeek: sourceDay)),
            targetDate: try XCTUnwrap(DateUtils.dateOfWeek(startDate: "2026-09-07", week: week, dayOfWeek: day)), segmentId: "candidate")
    }

    private func candidatePage(_ source: CourseEntity, week: Int, transfers: [HolidayTransferEntry]) -> CourseDropCandidateLayout {
        let table = TimeTableEntity(name: "候选", startDate: "2026-09-07", maxWeek: 4)
        return CourseDropCandidateLayout(week: week,
            courses: renderCoursesForWeek(table, week: week, courses: [source], transfers: transfers, timeJson: timeJson),
            timeJson: timeJson, baseSlots: TimeTableUtils.renderSlots(timeJson: timeJson), configuration: .init(),
            startDate: table.startDate, maxWeek: table.maxWeek, transfers: transfers, allCourses: [source])
    }

    private func assertEveningMove(sourceEndWeek: Int, sourceType: Int, expectedCount: Int) throws {
        let json = """
            [{"node":1,"start":"08:00","end":"08:45"},
             {"node":2,"start":"09:00","end":"09:45"},
             {"node":3,"start":"14:00","end":"14:45"},
             {"node":4,"start":"19:00","end":"19:45"}]
            """
        var source = course(start: "19:00", end: "19:45")
        source.startNode = 4
        source.endWeek = sourceEndWeek
        source.type = sourceType
        let slots = TimeTableUtils.renderSlots(timeJson: json)
        let config = CourseGridRowLayout.Configuration(adaptive: true, availableGridHeight: 180)
        let page = CourseDropCandidateLayout(week: 2, courses: source.inWeek(2) ? [source] : [],
            timeJson: json, baseSlots: slots, configuration: config,
            startDate: "2026-09-07", maxWeek: 4,
            allCourses: [source], timeSlots: slots, visibleDays: [1, 2],
            autoHideEmptyEvening: true, eveningStartMinutes: 18 * 60)
        let destination = CourseOccurrenceDestination(startNode: 1, endNode: 1,
            startTime: "08:00", endTime: "08:45", usesOwnTime: true)
        let preview = try XCTUnwrap(page.layout(source: source, sourceOccurrence: .init(week: 1, day: 1), day: 2, destination: destination))
        var moved = source
        moved.day = 2
        moved.startWeek = 2
        moved.endWeek = 2
        moved.type = 0
        moved.startNode = 1
        moved.startTime = "08:00"
        moved.endTime = "08:45"
        var finalSemester = [moved]
        if sourceEndWeek >= 2 {
            for week in 2...sourceEndWeek where source.inWeek(week) {
                var remaining = source
                remaining.startWeek = week
                remaining.endWeek = week
                finalSemester.append(remaining)
            }
        }
        let selected = TimetableViewportPolicy.selectVisibleSlots(allCourses: finalSemester,
            timeSlots: slots.map(TimetableViewportPolicy.SlotRef.init), visibleDays: [1, 2],
            timeJson: json, autoHideEmptyEvening: true, eveningStartMinutes: 18 * 60)
        let finalSlots = selected.slots.compactMap { ref in slots.first { $0.nodeStart == ref.nodeStart } }
        let final = CourseGridRowLayout(courses: finalSemester.filter { $0.inWeek(2) }, timeJson: json,
                                        baseSlots: finalSlots, configuration: config)
        XCTAssertEqual(preview.renderPlan.slots.count, expectedCount)
        XCTAssertEqual(preview.rowHeight, expectedCount == 3 ? 56 : 45)
        XCTAssertEqual(preview.rowHeight, final.rowHeight)
        let previewBounds = try XCTUnwrap(preview.timedCardBounds(start: moved.startTime, end: moved.endTime))
        let finalBounds = try XCTUnwrap(final.timedCardBounds(start: moved.startTime, end: moved.endTime))
        XCTAssertEqual(previewBounds.height, finalBounds.height, accuracy: 0.001)
    }
}
