import XCTest
@testable import Sleepy

final class TimeSlotReorderParityTests: XCTestCase {
    private typealias Row = TimeTableUtils.TimeSlotRow

    private func row(_ node: Int, _ start: String = "", _ end: String = "") -> Row {
        Row(node: node, start: start, end: end)
    }

    private func course(_ node: Int, _ step: Int = 2, ownTime: Bool = false) -> CourseEntity {
        CourseEntity(groupId: "reorder", tableId: 1, courseName: "课程", day: 1,
            startNode: node, step: step, startWeek: 1, endWeek: 16, color: "", ownTime: ownTime)
    }

    func testMoveRenumbersStandardRowsAndRetainsEdgeAnchorsAndPhysicalSlots() {
        let rows = [row(1, "08:00", "08:45"), row(2), row(3, "10:00", "10:45"),
                    Row(node: 4, start: "12:00", end: "12:45", edgeClass: .after),
                    Row(node: 0, start: "07:00", end: "07:45", edgeClass: .before),
                    Row(node: -1, start: "06:00", end: "06:45", edgeClass: .before)]
        let moved = TimeTableUtils.reorderTimeSlotRows(rows, fromIndex: 1, toIndex: 2)
        XCTAssertEqual(moved.map(\.node), [1, 2, 3, 4, 0, -1])
        XCTAssertEqual(moved.prefix(3).map(\.start), ["08:00", "10:00", ""])
        XCTAssertEqual(moved.prefix(3).map(\.end), ["08:45", "10:45", ""])
        XCTAssertEqual(Array(moved.suffix(3)), Array(rows.suffix(3)))
        XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 1, toIndex: 2))
        XCTAssertEqual(TimeTableUtils.parseTimeSlotRows(TimeTableUtils.buildTimeJsonFromRows(moved)), moved)
    }

    func testEdgeRowsCannotBeDragSourcesOrTargets() {
        let rows = [row(1), row(2), Row(node: 3, start: "", end: "", edgeClass: .after),
                    Row(node: 0, start: "", end: "", edgeClass: .before), row(-1)]
        for edgeIndex in 2...4 {
            for (from, to) in [(edgeIndex, 0), (0, edgeIndex), (edgeIndex, edgeIndex)] {
                XCTAssertFalse(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: from, toIndex: to))
                XCTAssertEqual(TimeTableUtils.reorderTimeSlotRows(rows, fromIndex: from, toIndex: to), rows)
            }
        }
    }

    func testInvalidIndicesAndSamePositionDoNotChangeRows() {
        let rows = [row(1), row(2)]
        for (from, to) in [(-1, 0), (0, 2), (2, 0), (1, 1)] {
            XCTAssertEqual(TimeTableUtils.reorderTimeSlotRows(rows, fromIndex: from, toIndex: to), rows)
        }
        XCTAssertFalse(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: -1, toIndex: 0))
        XCTAssertFalse(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 0, toIndex: 2))
        XCTAssertFalse(TimeTableUtils.canReorderTimeSlot([], fromIndex: 0, toIndex: 0))
    }

    func testFilledRowsCannotBreakStartTimeOrder() {
        let rows = [row(1, "08:00", "08:45"), row(2, "09:00", "09:45"), row(3, "10:00", "10:45")]
        XCTAssertFalse(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 2, toIndex: 0))
        XCTAssertFalse(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 0, toIndex: 2))
        XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 1, toIndex: 1))
    }

    func testBlankTailCanMoveToEveryPositionWithoutCourses() {
        let rows = [row(1, "08:00", "08:45"), row(2, "09:00", "09:45"), row(3, "10:00", "10:45"), row(4)]
        for target in rows.indices {
            XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 3, toIndex: target))
        }
    }

    func testBlankNonTailRowFollowsProductionContractRatherThanStaleTailOnlyComment() {
        let rows = [row(1, "08:00", "08:45"), row(2), row(3, "10:00", "10:45")]
        XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 1, toIndex: 2))
        XCTAssertEqual(TimeTableUtils.reorderTimeSlotRows(rows, fromIndex: 1, toIndex: 2).map(\.start), ["08:00", "10:00", ""])
    }

    func testOrderValidationRejectsPartialBlankMalformedAndNonpositiveIntervals() {
        for invalid in [row(1, "", "09:00"), row(1, "08:00", ""), row(1, "8:00", "09:00"),
                        row(1, "24:00", "25:00"), row(1, "08:00", "08:00"), row(1, "09:00", "08:00")] {
            XCTAssertFalse(TimeTableUtils.isTimeSlotOrderValid([invalid]))
        }
        XCTAssertTrue(TimeTableUtils.isTimeSlotOrderValid([row(1), row(2, "08:00", "08:45"), row(3, "08:00", "09:00")]))
    }

    func testForwardMoveRejectsSplitCourseUsingCorrectInversePermutation() {
        // New order [old2, old3, old1, old4] places old1 and old2 at nodes 3 and 1.
        // Android 1.0.63 mistakenly reads the inverse direction and accepts this move.
        let rows = (1...4).map { row($0) }
        XCTAssertFalse(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 0, toIndex: 2, courses: [course(1)]))
    }

    func testBackwardMoveRetainsContiguousCourseUsingCorrectInversePermutation() {
        // New order [old4, old1, old2, old3] keeps old1 and old2 together at nodes 2 and 3.
        let rows = (1...4).map { row($0) }
        XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 3, toIndex: 0, courses: [course(1)]))
    }

    func testOwnTimeSinglePeriodAndMissingNodesRetainTheirExistingExemptions() {
        let rows = (1...4).map { row($0) }
        XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 0, toIndex: 2, courses: [course(1, ownTime: true)]))
        XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 0, toIndex: 2, courses: [course(1, 1)]))
        XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(rows, fromIndex: 0, toIndex: 2, courses: [course(4, 3)]))
    }

    func testDuplicateNodeInputFailsClosedInsteadOfTrapping() {
        XCTAssertFalse(TimeTableUtils.canReorderTimeSlot([row(1), row(1)], fromIndex: 0, toIndex: 1))
    }

    func testReorderedDraftSavesRemapsByTimeAndRestoresAsOneUndoUnit() throws {
        let history = Sleepy.UndoManager.shared
        let previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(5)
        defer { history.clear(); history.applyMaxDepth(previousDepth) }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let originalRows = [row(1, "08:00", "08:45"), row(2), row(3, "10:00", "10:45")]
        let tableId = try repo.insertTable(TimeTableEntity(name: "重排课表", startDate: "2026-09-07",
            nodesPerDay: 3, timeJson: TimeTableUtils.buildTimeJsonFromRows(originalRows)))
        var originalCourse = course(3, 1)
        originalCourse.tableId = tableId
        let courseId = try repo.insertCourse(originalCourse)
        history.clear()

        XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(originalRows, fromIndex: 1, toIndex: 2,
                                                       courses: try repo.getCourses(tableId)))
        var draft = TimeTableUtils.reorderTimeSlotRows(originalRows, fromIndex: 1, toIndex: 2)
        draft[2].start = "11:00"
        draft[2].end = "11:45"
        // A drag publishes form state only. The existing Save action commits the draft.
        XCTAssertEqual(try repo.getTable(tableId)?.timeJson, TimeTableUtils.buildTimeJsonFromRows(originalRows))
        XCTAssertFalse(history.hasSnapshot)
        var table = try XCTUnwrap(repo.getTable(tableId))
        table.timeJson = TimeTableUtils.buildTimeJsonFromRows(draft)
        try repo.updateTableRemappingCourses(table)

        let reopened = ScheduleRepository(db)
        XCTAssertEqual(TimeTableUtils.parseTimeSlotRows(try XCTUnwrap(reopened.getTable(tableId)).timeJson), draft)
        XCTAssertEqual(try reopened.getCourse(courseId)?.startNode, 2)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try repo.getTable(tableId)?.timeJson, TimeTableUtils.buildTimeJsonFromRows(originalRows))
        XCTAssertEqual(try repo.getCourse(courseId)?.startNode, 3)
        XCTAssertFalse(try repo.restoreLastSnapshot())
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try repo.getTable(tableId)?.timeJson, table.timeJson)
        XCTAssertEqual(try repo.getCourse(courseId)?.startNode, 2)
    }

    func testStandardReorderSavesAppendedBeforeEdgesAndTheirCoursesAcrossUndoRedo() throws {
        let history = Sleepy.UndoManager.shared
        let previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(5)
        defer { history.clear(); history.applyMaxDepth(previousDepth) }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let standardRows = [row(1, "08:00", "08:45"), row(2), row(3, "10:00", "10:45")]
        var originalJson = TimeTableUtils.buildTimeJsonFromRows(standardRows)
        originalJson = TimeTableUtils.insertEdgeNode(timeJson: originalJson, edgeClass: .before,
                                                    start: "07:00", end: "07:45")
        originalJson = TimeTableUtils.insertEdgeNode(timeJson: originalJson, edgeClass: .before,
                                                    start: "06:00", end: "06:45")
        let originalRows = TimeTableUtils.parseTimeSlotRows(originalJson)
        XCTAssertEqual(originalRows.map(\.node), [1, 2, 3, 0, -1])
        let tableId = try repo.insertTable(TimeTableEntity(name: "边缘节次重排", startDate: "2026-09-07",
            nodesPerDay: 3, timeJson: originalJson))
        var edgeCourseIds: [Int64] = []
        for node in [0, -1] {
            var edgeCourse = course(node, 1)
            edgeCourse.tableId = tableId
            edgeCourseIds.append(try repo.insertCourse(edgeCourse))
        }
        var standardCourse = course(3, 1)
        standardCourse.tableId = tableId
        let standardCourseId = try repo.insertCourse(standardCourse)
        history.clear()

        XCTAssertTrue(TimeTableUtils.canReorderTimeSlot(originalRows, fromIndex: 1, toIndex: 2,
                                                       courses: try repo.getCourses(tableId)))
        var draft = TimeTableUtils.reorderTimeSlotRows(originalRows, fromIndex: 1, toIndex: 2)
        draft[2].start = "11:00"
        draft[2].end = "11:45"
        var table = try XCTUnwrap(repo.getTable(tableId))
        table.timeJson = TimeTableUtils.buildTimeJsonFromRows(draft)
        try repo.updateTableRemappingCourses(table)

        let reopened = ScheduleRepository(db)
        let savedRows = TimeTableUtils.parseTimeSlotRows(try XCTUnwrap(reopened.getTable(tableId)).timeJson)
        XCTAssertEqual(savedRows, draft)
        XCTAssertEqual(Array(savedRows.suffix(2)), Array(originalRows.suffix(2)))
        XCTAssertEqual(try reopened.getCourse(edgeCourseIds[0])?.startNode, 0)
        XCTAssertEqual(try reopened.getCourse(edgeCourseIds[1])?.startNode, -1)
        XCTAssertEqual(try reopened.getCourse(standardCourseId)?.startNode, 2)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try repo.getTable(tableId)?.timeJson, originalJson)
        XCTAssertEqual(try repo.getCourse(standardCourseId)?.startNode, 3)
        XCTAssertEqual(try repo.getCourse(edgeCourseIds[0])?.startNode, 0)
        XCTAssertEqual(try repo.getCourse(edgeCourseIds[1])?.startNode, -1)
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try repo.getTable(tableId)?.timeJson, table.timeJson)
        XCTAssertEqual(try repo.getCourse(standardCourseId)?.startNode, 2)
        XCTAssertEqual(try repo.getCourse(edgeCourseIds[0])?.startNode, 0)
        XCTAssertEqual(try repo.getCourse(edgeCourseIds[1])?.startNode, -1)
    }

    @MainActor
    func testExplicitNonselectedTableLoadsItsOwnCourseSpans() throws {
        let history = Sleepy.UndoManager.shared
        let previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(0)
        defer { history.clear(); history.applyMaxDepth(previousDepth) }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let selected = try repo.insertTable(TimeTableEntity(name: "当前", startDate: "2026-09-07", isDefault: true))
        let edited = try repo.insertTable(TimeTableEntity(name: "编辑目标", startDate: "2026-09-07"))
        var currentCourse = course(3, 1)
        currentCourse.tableId = selected
        _ = try repo.insertCourse(currentCourse)
        var editedCourse = course(1)
        editedCourse.tableId = edited
        _ = try repo.insertCourse(editedCourse)
        let viewModel = ScheduleViewModel(repo: repo)
        let editingCourses = try viewModel.getCoursesForEditing(edited)
        XCTAssertEqual(editingCourses.count, 1)
        XCTAssertTrue(editingCourses.allSatisfy { $0.tableId == edited })
        XCTAssertFalse(TimeTableUtils.canReorderTimeSlot((1...4).map { row($0) }, fromIndex: 0, toIndex: 2,
                                                        courses: editingCourses))
    }
}
