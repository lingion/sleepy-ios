import XCTest
import GRDB
@testable import Sleepy

final class RepositoryMutationFailureTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: ScheduleRepository!
    private let history = Sleepy.UndoManager.shared
    private var previousDepth = 5
    private var notifications = 0
    private var table: TimeTableEntity!
    private var period: PeriodTableEntity!
    private var course: CourseEntity!

    override func setUpWithError() throws {
        previousDepth = history.maxDepth
        history.clear()
        history.restoring = false
        history.applyMaxDepth(5)
        db = try AppDatabase.inMemory()
        repo = ScheduleRepository(db)
        repo.onDataChangedHook = { [weak self] in self?.notifications += 1 }
        let pid = try repo.insertPeriodTable(PeriodTableEntity(name: "作息"))
        period = try XCTUnwrap(repo.getPeriodTable(pid))
        let tid = try repo.insertTable(TimeTableEntity(name: "原表", startDate: "2026-09-07"))
        table = try XCTUnwrap(repo.getTable(tid))
        let cid = try repo.insertCourse(CourseEntity(groupId: "group", tableId: tid, courseName: "原课",
            day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, color: "", colorMode: CourseColorMode.GROUP))
        course = try XCTUnwrap(repo.getCourse(cid))
        history.clear()
        for name in ["A", "B", "C", "D", "E"] {
            try repo.insertTable(TimeTableEntity(name: name, startDate: "2026-09-07"))
        }
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertTrue(try repo.restoreLastSnapshot())
    }

    override func tearDown() {
        history.clear()
        history.restoring = false
        history.applyMaxDepth(previousDepth)
        repo = nil
        db = nil
        super.tearDown()
    }

    private func names() throws -> [String] { try repo.getAllTables().map(\.name).filter { $0 != "原表" }.sorted() }

    private func databaseState() throws -> [Data] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try [encoder.encode(repo.getAllTables().sorted { $0.id < $1.id }),
                    encoder.encode(repo.getAllCourses().sorted { $0.id < $1.id }),
                    encoder.encode(repo.getAllPeriodTables().sorted { $0.id < $1.id })]
    }

    private func block(_ event: String, on table: String, when condition: String = "1") throws {
        try db.dbQueue.write {
            try $0.execute(sql: """
                CREATE TRIGGER mutation_failure BEFORE \(event) ON \(table) WHEN \(condition)
                BEGIN SELECT RAISE(ABORT, 'injected mutation failure'); END;
                """)
        }
    }

    private func assertFailurePreservesHistory(_ mutation: () throws -> Void,
                                              file: StaticString = #filePath, line: UInt = #line) throws {
        let before = try databaseState()
        let beforeNotifications = notifications
        XCTAssertThrowsError(try mutation(), file: file, line: line)
        XCTAssertEqual(try databaseState(), before, file: file, line: line)
        XCTAssertEqual(notifications, beforeNotifications, file: file, line: line)
        XCTAssertTrue(repo.canUndo, file: file, line: line)
        XCTAssertTrue(repo.canRedo, file: file, line: line)
        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER mutation_failure") }
        for expected in [["A", "B"], ["A"], []] {
            XCTAssertTrue(try repo.restoreLastSnapshot(), file: file, line: line)
            XCTAssertEqual(try names(), expected, file: file, line: line)
        }
        XCTAssertFalse(try repo.restoreLastSnapshot(), file: file, line: line)
        for expected in [["A"], ["A", "B"], ["A", "B", "C"], ["A", "B", "C", "D"], ["A", "B", "C", "D", "E"]] {
            XCTAssertTrue(try repo.redoLastUndo(), file: file, line: line)
            XCTAssertEqual(try names(), expected, file: file, line: line)
        }
        XCTAssertFalse(try repo.redoLastUndo(), file: file, line: line)
    }

    func testFailedTableInsertPreservesBothCompleteStacks() throws {
        try block("INSERT", on: "time_tables")
        try assertFailurePreservesHistory { _ = try repo.insertTable(TimeTableEntity(name: "失败", startDate: "2026-09-07")) }
    }

    func testDefaultUpdateFailureRollsBackInsertedTableAndHistory() throws {
        try block("UPDATE", on: "time_tables")
        var next = TimeTableEntity(name: "失败", startDate: "2026-09-07")
        next.isDefault = true
        try assertFailurePreservesHistory { _ = try repo.insertTable(next) }
    }

    func testFailedCourseInsertPreservesBothCompleteStacks() throws {
        try block("INSERT", on: "courses")
        try assertFailurePreservesHistory { _ = try repo.insertCourse(course) }
    }

    func testFailedTableUpdatePreservesBothCompleteStacks() throws {
        try block("UPDATE", on: "time_tables")
        var next = table!
        next.name = "改名"
        try assertFailurePreservesHistory { try repo.updateTable(next) }
    }

    func testFailedCourseUpdatePreservesBothCompleteStacks() throws {
        try block("UPDATE", on: "courses")
        var next = course!
        next.courseName = "改名"
        try assertFailurePreservesHistory { try repo.updateCourse(next) }
    }

    func testFailedReminderUpdatePreservesBothCompleteStacks() throws {
        try block("UPDATE", on: "time_tables")
        try assertFailurePreservesHistory { try repo.setTableReminderEnabled(id: table.id, enabled: !table.reminderEnabled) }
    }

    func testFailedMetadataUpdatePreservesBothCompleteStacks() throws {
        try block("UPDATE", on: "time_tables")
        var next = table!
        next.name = "改名"
        try assertFailurePreservesHistory { try repo.updateTableMetadata(next) }
    }

    func testSecondMetadataWriteFailureRollsBackFirstWriteAndHistory() throws {
        try block("UPDATE", on: "period_tables")
        var next = table!
        next.name = "改名"
        try assertFailurePreservesHistory { try repo.updateTableMetadataWithPeriodTable(table: next, periodTable: period) }
    }

    func testBindContentFailureRollsBackBindingAndHistory() throws {
        try block("UPDATE", on: "period_tables")
        try assertFailurePreservesHistory {
            try repo.updateTableMetadataAndBind(table: table, periodTableId: period.id, periodContent: period)
        }
    }

    func testFailedBindingPreservesBothCompleteStacks() throws {
        try block("UPDATE", on: "time_tables")
        try assertFailurePreservesHistory { try repo.bindPeriodTable(timeTableId: table.id, periodTableId: period.id) }
    }

    func testRemapFailureRollsBackTableWriteAndHistory() throws {
        var original = table!
        original.timeJson = #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"08:50","end":"09:35"}]"#
        try db.timeTableDao.update(original)
        var next = original
        next.timeJson = #"[{"node":3,"start":"08:00","end":"08:45"},{"node":4,"start":"08:50","end":"09:35"}]"#
        try block("UPDATE", on: "courses")
        try assertFailurePreservesHistory { try repo.updateTableRemappingCourses(next) }
    }

    func testEdgeReclaimFailureRollsBackCourseDeletionAndHistory() throws {
        var original = table!
        original.timeJson = #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"08:50","end":"09:35"},{"node":3,"start":"10:00","end":"10:45","edge":"after"}]"#
        try db.timeTableDao.update(original)
        try block("UPDATE", on: "time_tables")
        try assertFailurePreservesHistory { try repo.deleteCourse(course.id) }
    }

    func testFailedPeriodInsertPreservesBothCompleteStacks() throws {
        try block("INSERT", on: "period_tables")
        try assertFailurePreservesHistory { _ = try repo.insertPeriodTable(PeriodTableEntity(name: "失败")) }
    }

    func testFailedPeriodCopyPreservesBothCompleteStacks() throws {
        try block("INSERT", on: "period_tables")
        try assertFailurePreservesHistory { _ = try repo.copyPeriodTable(sourceId: period.id) }
    }

    func testFailedNamedPeriodCopyPreservesBothCompleteStacks() throws {
        try block("INSERT", on: "period_tables")
        try assertFailurePreservesHistory { _ = try repo.copyPeriodTableAs(sourceId: period.id, newName: "失败") }
    }

    func testFailedPeriodUpdatePreservesBothCompleteStacks() throws {
        try block("UPDATE", on: "period_tables")
        try assertFailurePreservesHistory { try repo.updatePeriodTable(period) }
    }

    func testFailedPeriodSavePreservesBothCompleteStacks() throws {
        try block("UPDATE", on: "period_tables")
        try assertFailurePreservesHistory { _ = try repo.savePeriodTable(period) }
    }

    func testFailedCourseGroupReplacementRollsBackDeletionAndHistory() throws {
        try block("INSERT", on: "courses")
        try assertFailurePreservesHistory { try repo.updateCourseGroup(table.id, course.groupId, [course]) }
    }

    func testFailedDiffInsertionRollsBackEarlierDeletionAndHistory() throws {
        try block("INSERT", on: "courses")
        try assertFailurePreservesHistory {
            try repo.applyDiff(table.id, DiffResult(toInsert: [course], toUpdate: [], toDelete: [course.id]))
        }
    }

    func testFailedColorUpdatePreservesBothCompleteStacks() throws {
        try block("UPDATE", on: "courses")
        try assertFailurePreservesHistory { try repo.setGroupSourceColor(table.id, course.groupId, "#112233") }
    }

    func testFailedTableDeletionPreservesBothCompleteStacks() throws {
        try block("DELETE", on: "time_tables")
        try assertFailurePreservesHistory { try repo.deleteTable(table.id) }
    }

    func testFailedCourseDeletionPreservesBothCompleteStacks() throws {
        try block("DELETE", on: "courses")
        try assertFailurePreservesHistory { try repo.deleteCourse(course.id) }
    }

    func testFailedCourseGroupDeletionPreservesBothCompleteStacks() throws {
        try block("DELETE", on: "courses")
        try assertFailurePreservesHistory { try repo.deleteCourseGroup(table.id, course.groupId) }
    }

    func testFailedReplacementPreservesCoursesAndBothStacks() throws {
        try block("INSERT", on: "courses")
        try assertFailurePreservesHistory { try repo.replaceCourses(table.id, [course]) }
    }

    func testFailedKeepingGroupsReplacementPreservesCoursesAndBothStacks() throws {
        try block("INSERT", on: "courses")
        try assertFailurePreservesHistory { try repo.replaceCoursesKeepingGroups(table.id, [course]) }
    }

    func testLaterBulkInsertFailureRollsBackEarlierRowAndHistory() throws {
        try block("INSERT", on: "courses", when: "NEW.courseName = '失败'")
        var first = course!
        first.id = 0
        var second = first
        second.courseName = "失败"
        try assertFailurePreservesHistory { _ = try repo.insertCourses([first, second]) }
    }

    func testKeepingGroupsInsertFailurePreservesBothCompleteStacks() throws {
        try block("INSERT", on: "courses")
        try assertFailurePreservesHistory { _ = try repo.insertCoursesKeepingGroups([course]) }
    }

    func testFailedOnlyNestedBatchPreservesHistory() throws {
        try block("INSERT", on: "courses")
        try assertFailurePreservesHistory {
            history.beginBatch()
            defer { history.endBatch() }
            history.beginBatch()
            defer { history.endBatch() }
            _ = try repo.insertCourse(course)
        }
    }

    func testFailureThenSuccessfulNestedBatchCapturesExactlyItsFirstCommittedState() throws {
        try block("INSERT", on: "courses")
        history.beginBatch()
        do {
            defer { history.endBatch() }
            XCTAssertThrowsError(try repo.insertCourse(course))
            XCTAssertTrue(repo.canRedo)
            history.beginBatch()
            do {
                defer { history.endBatch() }
                try repo.insertTable(TimeTableEntity(name: "F", startDate: "2026-09-07"))
                try repo.insertTable(TimeTableEntity(name: "G", startDate: "2026-09-07"))
            }
        }
        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER mutation_failure") }
        XCTAssertFalse(repo.canRedo)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A", "B", "C"])
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A", "B"])
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B", "C", "F", "G"])
        XCTAssertFalse(try repo.redoLastUndo())
    }
}
