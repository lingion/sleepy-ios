import XCTest
import GRDB
@testable import Sleepy

final class CourseOccurrenceMoveTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: ScheduleRepository!
    private var tableId: Int64!
    private var notifications = 0

    override func setUpWithError() throws {
        db = try AppDatabase.inMemory()
        repo = ScheduleRepository(db)
        tableId = try db.timeTableDao.insert(TimeTableEntity(name: "移动测试", startDate: "2026-09-07", maxWeek: 20))
        notifications = 0
        repo.onDataChangedHook = { [weak self] in self?.notifications += 1 }
        Sleepy.UndoManager.shared.clear()
    }

    override func tearDown() {
        Sleepy.UndoManager.shared.clear()
        repo = nil
        db = nil
        super.tearDown()
    }

    private func seed(type: Int = 0, first: Int = 1, last: Int = 9,
                      ownTime: Bool = false, start: String = "", end: String = "") throws -> CourseEntity {
        var course = CourseEntity(groupId: "existing-group", tableId: tableId, courseName: "数据库",
                                  teacher: "教师", room: "A101", note: "原始备注", day: 2, startNode: 1,
                                  step: 2, startWeek: first, endWeek: last, type: type, color: "#FF123456",
                                  colorMode: CourseColorMode.CUSTOM, ownTime: ownTime,
                                  startTime: start, endTime: end, alias: "DB", credit: 3.5, level: 2)
        course.id = try db.courseDao.insert(course)
        return course
    }

    private func encoded(_ rows: [CourseEntity]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(rows.sorted { $0.id < $1.id })
    }

    private func move(_ course: CourseEntity, from: Int, to: Int, day: Int = 4, node: Int = 5) throws -> Bool {
        try repo.moveCourseOccurrence(courseId: course.id, sourceWeek: from, targetWeek: to,
                                      targetDay: day, targetNode: node)
    }

    func testSplitsEveryOddEvenAndExplicitRangesWithoutChangingOtherOccurrences() throws {
        for (type, sourceWeek) in [(0, 5), (1, 5), (2, 6), (3, 5)] {
            let original = try seed(type: type)
            XCTAssertTrue(try move(original, from: sourceWeek, to: 12))
            let rows = try repo.getCourses(tableId).filter { $0.courseName == original.courseName }
            for week in 1...20 {
                let atSource = rows.filter { $0.day == 2 && $0.inWeek(week) }
                XCTAssertEqual(atSource.count, original.inWeek(week) && week != sourceWeek ? 1 : 0,
                               "type=\(type), week=\(week)")
                XCTAssertEqual(rows.filter { $0.day == 4 && $0.inWeek(week) }.count, week == 12 ? 1 : 0)
            }
            XCTAssertEqual(rows.count, 3, "保留最多两个原区间，不展开整个学期")
            let moved = try XCTUnwrap(rows.first { $0.day == 4 })
            var expected = original
            expected.id = moved.id
            expected.day = 4
            expected.startNode = 5
            expected.startWeek = 12
            expected.endWeek = 12
            expected.type = 0
            XCTAssertEqual(try encoded([moved]), try encoded([expected]), "复制原库全部元数据")
            try db.courseDao.deleteByTableId(tableId)
        }
    }

    func testFirstLastAndOnlyOccurrenceLeaveNoPhantomParityRows() throws {
        for (type, first, last, source) in [(1, 2, 8, 3), (1, 2, 8, 7), (2, 1, 7, 2), (2, 1, 7, 6), (1, 2, 4, 3), (0, 5, 5, 5)] {
            let original = try seed(type: type, first: first, last: last)
            XCTAssertTrue(try move(original, from: source, to: 20, day: 7, node: 11))
            let rows = try repo.getCourses(tableId)
            XCTAssertTrue(rows.allSatisfy { row in (1...20).contains { row.inWeek($0) } })
            for week in 1...20 {
                XCTAssertEqual(rows.filter { $0.day == 2 && $0.inWeek(week) }.count,
                               original.inWeek(week) && week != source ? 1 : 0)
            }
            XCTAssertEqual(rows.filter { $0.day == 7 && $0.inWeek(20) }.count, 1)
            try db.courseDao.deleteByTableId(tableId)
        }
    }

    func testCrossWeekSamePositionIsNotNoOpAndKeepsExistingTargetOccurrence() throws {
        let original = try seed()
        XCTAssertTrue(try move(original, from: 3, to: 4, day: 2, node: 1))
        let rows = try repo.getCourses(tableId)
        XCTAssertEqual(rows.filter { $0.inWeek(3) }.count, 0)
        XCTAssertEqual(rows.filter { $0.inWeek(4) }.count, 2, "目标周已有实例不能被覆盖")
        XCTAssertEqual(rows.filter { $0.inWeek(5) }.count, 1)
        XCTAssertEqual(notifications, 1)
    }

    func testSameWeekMoveOnlyChangesSelectedOccurrenceAndRejectsStaleReplay() throws {
        let original = try seed()
        XCTAssertTrue(try move(original, from: 5, to: 5))
        let rows = try repo.getCourses(tableId)
        XCTAssertEqual(rows.filter { $0.day == 2 && $0.inWeek(5) }.count, 0)
        XCTAssertEqual(rows.filter { $0.day == 4 && $0.inWeek(5) }.count, 1)
        XCTAssertEqual(rows.filter { $0.day == 2 && $0.inWeek(6) }.count, 1)
        XCTAssertThrowsError(try move(original, from: 5, to: 6))
        XCTAssertTrue(try repo.restoreLastSnapshot(), "失效重放不覆盖上次成功动作的快照")
        XCTAssertEqual(try encoded(repo.getAllCourses()), try encoded([original]))
    }

    func testMalformedOrMissingTargetSlotsRejectWithoutUsingDefaultTimes() throws {
        let original = try seed()
        var table = try XCTUnwrap(repo.getTable(tableId))
        for json in ["bad-json", "[]", "[{\"node\":5,\"start\":\"12:00\",\"end\":\"12:45\"}]"] {
            table.timeJson = json
            try db.timeTableDao.update(table)
            XCTAssertThrowsError(try move(original, from: 3, to: 12, node: 5))
            XCTAssertFalse(repo.canUndo)
            XCTAssertEqual(try encoded(repo.getAllCourses()), try encoded([original]))
        }
    }

    func testSuccessfulMovesWithinExistingBatchKeepTheFirstSnapshot() throws {
        let original = try seed()
        let other = try seed(type: 2)
        let before = try encoded(repo.getAllCourses())
        Sleepy.UndoManager.shared.beginBatch()
        defer { Sleepy.UndoManager.shared.endBatch() }
        XCTAssertTrue(try move(original, from: 3, to: 12))
        XCTAssertTrue(try move(other, from: 4, to: 13))
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try encoded(repo.getAllCourses()), before)
    }

    func testSameWeekSamePositionIsNoOpAndPreservesRedo() throws {
        let original = try seed()
        XCTAssertTrue(try move(original, from: 3, to: 4))
        XCTAssertTrue(try repo.restoreLastSnapshot())
        let before = try encoded(repo.getAllCourses())
        notifications = 0
        XCTAssertFalse(try move(original, from: 3, to: 3, day: 2, node: 1))
        XCTAssertEqual(try encoded(repo.getAllCourses()), before)
        XCTAssertTrue(repo.canRedo)
        XCTAssertFalse(repo.canUndo)
        XCTAssertEqual(notifications, 0)
    }

    func testInvalidAndStaleInputsRejectWithoutWritingOrCapturing() throws {
        let original = try seed(type: 1)
        let before = try encoded(repo.getAllCourses())
        for (source, target, day, node) in [(0, 3, 2, 1), (2, 3, 2, 1), (11, 3, 2, 1),
                                          (3, 0, 2, 1), (3, 21, 2, 1), (3, 3, 0, 1), (3, 3, 8, 1),
                                          (3, 3, 2, 0), (3, 3, 2, 12), (3, 3, 2, Int.max)] {
            XCTAssertThrowsError(try move(original, from: source, to: target, day: day, node: node))
        }
        XCTAssertThrowsError(try repo.moveCourseOccurrence(courseId: Int64.max, sourceWeek: 3,
                                                          targetWeek: 4, targetDay: 2, targetNode: 1))
        XCTAssertEqual(try encoded(repo.getAllCourses()), before)
        XCTAssertFalse(repo.canUndo)
        XCTAssertFalse(repo.canRedo)
        XCTAssertEqual(notifications, 0)
    }

    func testTransactionRollbackPreservesRowsAndExistingRedoSnapshot() throws {
        let original = try seed()
        XCTAssertTrue(try move(original, from: 3, to: 12))
        let moved = try encoded(repo.getAllCourses())
        XCTAssertTrue(try repo.restoreLastSnapshot())
        let before = try encoded(repo.getAllCourses())
        try db.dbQueue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER reject_move BEFORE INSERT ON courses WHEN NEW.day = 4
                BEGIN SELECT RAISE(ABORT, 'injected target insert failure'); END
                """)
        }
        notifications = 0
        XCTAssertThrowsError(try move(original, from: 5, to: 15))
        XCTAssertEqual(try encoded(repo.getAllCourses()), before)
        XCTAssertFalse(repo.canUndo)
        XCTAssertTrue(repo.canRedo)
        XCTAssertEqual(notifications, 0)
        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER reject_move") }
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try encoded(repo.getAllCourses()), moved)
    }

    func testCommitFailureDoesNotPublishUndoSnapshot() throws {
        let original = try seed()
        let before = try encoded(repo.getAllCourses())
        try db.dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE delayed_failure (
                    tableId INTEGER REFERENCES time_tables(id) DEFERRABLE INITIALLY DEFERRED
                );
                CREATE TRIGGER reject_commit AFTER INSERT ON courses WHEN NEW.day = 4
                BEGIN INSERT INTO delayed_failure(tableId) VALUES (-999); END;
                """)
        }
        XCTAssertThrowsError(try move(original, from: 5, to: 12))
        XCTAssertEqual(try encoded(repo.getAllCourses()), before)
        XCTAssertFalse(repo.canUndo)
        XCTAssertFalse(repo.canRedo)
        XCTAssertEqual(notifications, 0)
    }

    func testUndoRedoRestoresEntireMoveInOneStepIncludingOtherCoursesAndTables() throws {
        let original = try seed(type: 1)
        let otherTable = try db.timeTableDao.insert(TimeTableEntity(name: "无关课表", startDate: "2026-01-05", isDefault: true))
        var unrelated = original
        unrelated.id = 0
        unrelated.tableId = otherTable
        _ = try db.courseDao.insert(unrelated)
        let before = try encoded(repo.getAllCourses())
        XCTAssertTrue(try move(original, from: 5, to: 12))
        let after = try encoded(repo.getAllCourses())
        XCTAssertNotEqual(before, after)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try encoded(repo.getAllCourses()), before)
        XCTAssertEqual(try repo.getDefaultTable()?.id, otherTable)
        XCTAssertFalse(try repo.restoreLastSnapshot(), "一次移动只有一个撤销快照")
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try encoded(repo.getAllCourses()), after)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try encoded(repo.getAllCourses()), before)
    }

    func testOwnTimeUsesBoundPeriodTableAndPreservesMinuteDurationAndStep() throws {
        let periodId = try db.periodTableDao.insert(PeriodTableEntity(name: "绑定作息", nodesPerDay: 4,
            timeJson: """
            [{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"},
             {"node":3,"start":"14:10","end":"14:55"},{"node":4,"start":"15:05","end":"15:50"}]
            """))
        var table = try XCTUnwrap(repo.getTable(tableId))
        table.periodTableId = periodId
        try db.timeTableDao.update(table)
        let original = try seed(ownTime: true, start: "08:15", end: "09:52")
        XCTAssertTrue(try move(original, from: 3, to: 12, node: 3))
        let moved = try XCTUnwrap(repo.getCourses(tableId).first { $0.day == 4 })
        XCTAssertEqual(moved.startTime, "14:10")
        XCTAssertEqual(moved.endTime, "15:47")
        XCTAssertEqual(moved.step, 2)
        XCTAssertTrue(moved.ownTime)
        XCTAssertEqual(try repo.getCourse(original.id)?.startTime, "08:15")
        XCTAssertThrowsError(try move(original, from: 1, to: 12, node: 5), "绑定表只有四节，不能回退兼容列")
    }

    func testOwnTimeNoOpUsesNormalizedSourcePosition() throws {
        let original = try seed(ownTime: true, start: "10:00", end: "11:35")
        let table = try XCTUnwrap(repo.getTable(tableId))
        let node = original.normalizeNode(timeJson: table.timeJson).startNode
        XCTAssertNotEqual(node, original.startNode)
        XCTAssertFalse(try move(original, from: 3, to: 3, day: original.day, node: node))
        XCTAssertFalse(repo.canUndo)
        XCTAssertEqual(try encoded(repo.getAllCourses()), try encoded([original]))
    }

    func testInvalidOwnTimesAndMidnightOverflowReject() throws {
        var table = try XCTUnwrap(repo.getTable(tableId))
        table.nodesPerDay = 2
        table.timeJson = """
            [{"node":1,"start":"23:00","end":"23:25"},{"node":2,"start":"23:30","end":"23:55"}]
            """
        try db.timeTableDao.update(table)
        for (start, end) in [("bad", "09:00"), ("09:00", "08:00"), ("08:00", "08:00"), ("08:00", "10:00")] {
            let original = try seed(ownTime: true, start: start, end: end)
            XCTAssertThrowsError(try move(original, from: 3, to: 12, node: 1))
            XCTAssertEqual(try encoded(repo.getAllCourses()), try encoded([original]))
            XCTAssertFalse(repo.canUndo)
            try db.courseDao.deleteByTableId(tableId)
        }
    }

    func testOwnTimeShortCourseFitsLastSlotDespiteStoredStep() throws {
        let original = try seed(ownTime: true, start: "08:00", end: "08:30")
        XCTAssertTrue(try move(original, from: 3, to: 12, node: 12))
        let moved = try XCTUnwrap(repo.getCourses(tableId).first { $0.day == 4 })
        XCTAssertEqual(moved.startTime, "21:45")
        XCTAssertEqual(moved.endTime, "22:15")
        XCTAssertEqual(moved.step, original.step, "保留数据库元数据，不写入渲染节数")
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try encoded(repo.getAllCourses()), try encoded([original]))
    }

    func testOwnTimeRejectsEndBeyondGridBeforeMidnightWithoutChangingHistory() throws {
        let original = try seed(ownTime: true, start: "08:00", end: "10:00")
        XCTAssertTrue(try move(original, from: 3, to: 12, node: 5))
        XCTAssertTrue(try repo.restoreLastSnapshot())
        notifications = 0
        XCTAssertThrowsError(try move(original, from: 3, to: 12, node: 11))
        XCTAssertEqual(try encoded(repo.getAllCourses()), try encoded([original]))
        XCTAssertFalse(repo.canUndo)
        XCTAssertTrue(repo.canRedo)
        XCTAssertEqual(notifications, 0)
    }

    func testOwnTimeTargetDurationCanCoverMoreNodesThanSource() throws {
        let original = try seed(ownTime: true, start: "10:00", end: "13:00")
        let table = try XCTUnwrap(repo.getTable(tableId))
        XCTAssertEqual(original.normalizeNode(timeJson: table.timeJson).step, 2)
        XCTAssertTrue(try move(original, from: 3, to: 12, node: 9))
        let moved = try XCTUnwrap(repo.getCourses(tableId).first { $0.day == 4 })
        XCTAssertEqual(moved.startTime, "19:00")
        XCTAssertEqual(moved.endTime, "22:00")
        XCTAssertEqual(moved.normalizeNode(timeJson: table.timeJson).step, 4)
        XCTAssertEqual(moved.step, original.step)
    }

    func testIrregularTimeWithoutOwnTimeUsesDurationAndPreservesMetadata() throws {
        var original = try seed(start: "08:00", end: "08:30")
        original.isIrregularTime = true
        try db.courseDao.update(original)
        XCTAssertTrue(try move(original, from: 3, to: 12, node: 12))
        let moved = try XCTUnwrap(repo.getCourses(tableId).first { $0.day == 4 })
        var expected = original
        expected.id = moved.id
        expected.startWeek = 12
        expected.endWeek = 12
        expected.day = 4
        expected.startNode = 12
        expected.startTime = "21:45"
        expected.endTime = "22:15"
        XCTAssertEqual(try encoded([moved]), try encoded([expected]))
    }

    func testDestinationResolutionIsIndependentOfOwnTimeStoredOrRenderedStep() throws {
        var original = try seed(ownTime: true, start: "10:00", end: "13:00")
        original.step = 1
        let table = try XCTUnwrap(repo.getTable(tableId))
        let rendered = original.normalizeNode(timeJson: table.timeJson)
        XCTAssertEqual(rendered.step, 2)
        let destination = try CourseOccurrenceDestination.resolve(source: original, targetNode: 9, table: table)
        XCTAssertEqual(destination, try CourseOccurrenceDestination.resolve(source: rendered, targetNode: 9, table: table))
        XCTAssertEqual(destination.startNode, 9)
        XCTAssertEqual(destination.endNode, 12)
        XCTAssertEqual(destination.step, 4)
        XCTAssertEqual(destination.startTime, "19:00")
        XCTAssertEqual(destination.endTime, "22:00")
        XCTAssertTrue(destination.usesOwnTime)
    }

    func testDestinationAllowsExactGridEndButRejectsOneSecondOverflowForBothTimeFlags() throws {
        let table = try XCTUnwrap(repo.getTable(tableId))
        for ownTime in [true, false] {
            var original = try seed(ownTime: ownTime, start: "08:00:15", end: "08:45:15")
            original.isIrregularTime = !ownTime
            let exact = try CourseOccurrenceDestination.resolve(source: original, targetNode: 12, table: table)
            XCTAssertEqual(exact.endTime, "22:30")
            original.endTime = "08:45:16"
            XCTAssertThrowsError(try CourseOccurrenceDestination.resolve(source: original, targetNode: 12, table: table))
            original.endTime = "08:30:16"
            let seconds = try CourseOccurrenceDestination.resolve(source: original, targetNode: 12, table: table)
            XCTAssertEqual(seconds.endTime, "22:15:01")
        }
    }

    func testDestinationStandardCourseRequiresEverySlotAndKeepsFullStep() throws {
        let original = try seed()
        var table = try XCTUnwrap(repo.getTable(tableId))
        let destination = try CourseOccurrenceDestination.resolve(source: original, targetNode: 11, table: table)
        XCTAssertEqual(destination.step, 2)
        XCTAssertEqual(destination.startTime, "20:50")
        XCTAssertEqual(destination.endTime, "22:30")
        XCTAssertFalse(destination.usesOwnTime)
        XCTAssertThrowsError(try CourseOccurrenceDestination.resolve(source: original, targetNode: 12, table: table))
        table.timeJson = """
            [{"node":1,"start":"08:00","end":"08:45"},
             {"node":3,"start":"10:00","end":"10:45"}]
            """
        table.nodesPerDay = 3
        XCTAssertThrowsError(try CourseOccurrenceDestination.resolve(source: original, targetNode: 1, table: table))
    }

    private func useFractionalTimeGrid() throws -> TimeTableEntity {
        var table = try XCTUnwrap(repo.getTable(tableId))
        table.nodesPerDay = 2
        table.timeJson = """
            [{"node":1,"start":"08:00","end":"08:45"},
             {"node":2,"start":"09:00","end":"09:45"}]
            """
        try db.timeTableDao.update(table)
        return table
    }

    func testExplicitStartPreservesFractionalTimeOnHorizontalMove() throws {
        let table = try useFractionalTimeGrid()
        for ownTime in [true, false] {
            var original = try seed(ownTime: ownTime, start: "08:35", end: "08:40")
            original.isIrregularTime = !ownTime
            try db.courseDao.update(original)
            let destination = try CourseOccurrenceDestination.resolve(source: original, targetNode: 1,
                table: table, targetStartTime: "08:35")
            XCTAssertEqual(destination.startTime, "08:35")
            XCTAssertEqual(destination.endTime, "08:40")
            XCTAssertEqual(destination.step, 1)
            XCTAssertTrue(try repo.moveCourseOccurrence(courseId: original.id, sourceWeek: 3,
                targetWeek: 3, targetDay: 4, targetNode: 1, targetStartTime: "08:35"))
            let moved = try XCTUnwrap(repo.getCourses(tableId).first { $0.day == 4 })
            XCTAssertEqual(moved.startTime, "08:35")
            XCTAssertEqual(moved.endTime, "08:40")
            XCTAssertEqual(moved.step, original.step)
            XCTAssertTrue(try repo.restoreLastSnapshot())
            XCTAssertEqual(try encoded(repo.getAllCourses()), try encoded([original]))
            try db.courseDao.deleteByTableId(tableId)
        }
    }

    func testExplicitOriginalStartIsNoOpAndPreservesRedo() throws {
        _ = try useFractionalTimeGrid()
        let original = try seed(ownTime: true, start: "08:35", end: "08:40")
        XCTAssertTrue(try move(original, from: 3, to: 12, node: 1))
        XCTAssertTrue(try repo.restoreLastSnapshot())
        notifications = 0
        XCTAssertFalse(try repo.moveCourseOccurrence(courseId: original.id, sourceWeek: 3,
            targetWeek: 3, targetDay: original.day, targetNode: 1, targetStartTime: "08:35:00"))
        XCTAssertEqual(try encoded(repo.getAllCourses()), try encoded([original]))
        XCTAssertFalse(repo.canUndo)
        XCTAssertTrue(repo.canRedo)
        XCTAssertEqual(notifications, 0)
    }

    func testExplicitDifferentStartWithinSameNodeIsAnActualMove() throws {
        _ = try useFractionalTimeGrid()
        let original = try seed(ownTime: true, start: "08:35", end: "08:40")
        XCTAssertTrue(try repo.moveCourseOccurrence(courseId: original.id, sourceWeek: 3,
            targetWeek: 3, targetDay: original.day, targetNode: 1, targetStartTime: "08:30"))
        let moved = try XCTUnwrap(repo.getCourses(tableId).first { $0.inWeek(3) })
        XCTAssertEqual(moved.startTime, "08:30")
        XCTAssertEqual(moved.endTime, "08:35")
    }

    func testExplicitInvalidStartOrMismatchedNodeRejectsWithoutWriting() throws {
        let table = try useFractionalTimeGrid()
        let original = try seed(ownTime: true, start: "08:35", end: "08:40")
        for (node, start) in [(1, "bad"), (1, "8:35"), (1, "24:00"), (1, "07:59"),
                              (1, "09:00"), (2, "08:35"), (2, "09:41"), (2, "23:58")] {
            XCTAssertThrowsError(try CourseOccurrenceDestination.resolve(source: original, targetNode: node,
                table: table, targetStartTime: start))
            XCTAssertThrowsError(try repo.moveCourseOccurrence(courseId: original.id, sourceWeek: 3,
                targetWeek: 3, targetDay: original.day, targetNode: node, targetStartTime: start))
        }
        XCTAssertEqual(try encoded(repo.getAllCourses()), try encoded([original]))
        XCTAssertFalse(repo.canUndo)
        XCTAssertEqual(notifications, 0)
    }

    func testStandardCourseRejectsExplicitStartAndNilStillSnapsCustomTime() throws {
        let table = try useFractionalTimeGrid()
        let standard = try seed()
        XCTAssertThrowsError(try CourseOccurrenceDestination.resolve(source: standard, targetNode: 1,
            table: table, targetStartTime: "08:35"))
        XCTAssertThrowsError(try repo.moveCourseOccurrence(courseId: standard.id, sourceWeek: 3,
            targetWeek: 3, targetDay: 4, targetNode: 1, targetStartTime: "08:35"))
        let custom = try seed(ownTime: true, start: "08:35", end: "08:40")
        let snapped = try CourseOccurrenceDestination.resolve(source: custom, targetNode: 1, table: table)
        XCTAssertEqual(snapped.startTime, "08:00")
        XCTAssertEqual(snapped.endTime, "08:05")
    }

    func testMoveIsPersistedAcrossFileDatabaseReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("move.sqlite").path
        func writeMove() throws -> Data {
            let disk = try AppDatabase(queue: DatabaseQueue(path: path))
            let tid = try disk.timeTableDao.insert(TimeTableEntity(name: "持久化", startDate: "2026-09-07"))
            let original = CourseEntity(groupId: "disk", tableId: tid, courseName: "持久化课程", day: 1,
                                        startNode: 1, step: 2, startWeek: 1, endWeek: 9, type: 1, color: "#FF123456")
            let id = try disk.courseDao.insert(original)
            let repository = ScheduleRepository(disk)
            XCTAssertTrue(try repository.moveCourseOccurrence(courseId: id, sourceWeek: 5, targetWeek: 12,
                                                               targetDay: 7, targetNode: 11))
            return try encoded(repository.getAllCourses())
        }
        let expected = try writeMove()
        let reopened = try AppDatabase(queue: DatabaseQueue(path: path))
        XCTAssertEqual(try encoded(reopened.courseDao.getAllCourses()), expected)
    }
}
