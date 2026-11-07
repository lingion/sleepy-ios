import XCTest
import GRDB
@testable import Sleepy

/// 真实 GRDB 事务验收; 失败恢复用例依赖 docs/undo-v1063-integration.md 的 Repository 补丁。
final class UndoRepositoryHistoryTests: XCTestCase {
    private var db: AppDatabase!
    private var repo: ScheduleRepository!
    private var previousDepth = 5
    private var notifications = 0
    private let history = Sleepy.UndoManager.shared

    override func setUpWithError() throws {
        previousDepth = history.maxDepth
        history.clear()
        history.restoring = false
        history.applyMaxDepth(5)
        db = try AppDatabase.inMemory()
        repo = ScheduleRepository(db)
        notifications = 0
        repo.onDataChangedHook = { [weak self] in self?.notifications += 1 }
    }

    override func tearDown() {
        history.clear()
        history.restoring = false
        history.applyMaxDepth(previousDepth)
        repo = nil
        db = nil
        super.tearDown()
    }

    private func seedThreeActions() throws {
        for name in ["A", "B", "C"] {
            try repo.insertTable(TimeTableEntity(name: name, startDate: "2026-09-07"))
        }
    }

    private func names() throws -> [String] {
        try repo.getAllTables().map(\.name).sorted()
    }

    private func blockSnapshotInsertion() throws {
        try db.dbQueue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER undo_test_restore_failure BEFORE INSERT ON time_tables
                BEGIN SELECT RAISE(ABORT, 'injected undo restore failure'); END;
                """)
        }
    }

    private func unblockSnapshotInsertion() throws {
        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER undo_test_restore_failure") }
    }

    func testThreeRepositoryActionsUndoRedoInOrderAndNewWriteDropsRedo() throws {
        try seedThreeActions()
        for expected in [["A", "B"], ["A"], []] {
            XCTAssertTrue(try repo.restoreLastSnapshot())
            XCTAssertEqual(try names(), expected)
        }
        XCTAssertFalse(try repo.restoreLastSnapshot())
        for expected in [["A"], ["A", "B"], ["A", "B", "C"]] {
            XCTAssertTrue(try repo.redoLastUndo())
            XCTAssertEqual(try names(), expected)
        }
        XCTAssertFalse(try repo.redoLastUndo())
        XCTAssertTrue(try repo.restoreLastSnapshot())
        try repo.insertTable(TimeTableEntity(name: "D", startDate: "2026-09-07"))
        XCTAssertEqual(try names(), ["A", "B", "D"])
        XCTAssertFalse(try repo.redoLastUndo())
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A", "B"])
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A"])
    }

    func testBatchWithTableAndCoursesConsumesExactlyOneHistoryStep() throws {
        try repo.insertTable(TimeTableEntity(name: "A", startDate: "2026-09-07"))
        history.beginBatch()
        do {
            defer { history.endBatch() }
            let id = try repo.insertTable(TimeTableEntity(name: "B", startDate: "2026-09-07"))
            for name in ["数学", "英语"] {
                try repo.insertCourse(CourseEntity(groupId: name, tableId: id, courseName: name,
                                                   day: 1, startNode: 1, step: 2,
                                                   startWeek: 1, endWeek: 16, color: ""))
            }
        }
        XCTAssertEqual(try db.courseDao.getAllCourses().count, 2)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A"])
        XCTAssertTrue(try db.courseDao.getAllCourses().isEmpty)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), [])
        XCTAssertFalse(try repo.restoreLastSnapshot())
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B"])
        XCTAssertEqual(try db.courseDao.getAllCourses().map(\.courseName).sorted(), ["数学", "英语"])
        XCTAssertFalse(try repo.redoLastUndo())
    }

    func testUndoApplyFailureRollsBackDatabaseAndKeepsBothHistoryStacks() throws {
        try seedThreeActions()
        XCTAssertTrue(try repo.restoreLastSnapshot())
        let before = notifications
        try blockSnapshotInsertion()
        XCTAssertThrowsError(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A", "B"], "恢复删除已经发生, 事务仍必须完整回滚")
        XCTAssertEqual(try repo.getDefaultTable()?.name, "A")
        XCTAssertEqual(notifications, before)
        XCTAssertFalse(history.restoring)
        try unblockSnapshotInsertion()
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A"], "失败那一步仍可重试, 不能跳到空库")
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B"])
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B", "C"])
        XCTAssertFalse(try repo.redoLastUndo())
    }

    func testRedoApplyFailureRollsBackDatabaseAndKeepsBothHistoryStacks() throws {
        try seedThreeActions()
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertTrue(try repo.restoreLastSnapshot())
        let before = notifications
        try blockSnapshotInsertion()
        XCTAssertThrowsError(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A"])
        XCTAssertEqual(notifications, before)
        XCTAssertFalse(history.restoring)
        try unblockSnapshotInsertion()
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B"], "重做失败不能丢掉 B 这一步")
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B", "C"])
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A", "B"])
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A"])
    }

    func testUndoSnapshotReadFailureDoesNotConsumeHistory() throws {
        try seedThreeActions()
        XCTAssertTrue(try repo.restoreLastSnapshot())
        try db.dbQueue.write {
            try $0.execute(sql: "ALTER TABLE period_tables RENAME TO unavailable_period_tables")
        }
        XCTAssertThrowsError(try repo.restoreLastSnapshot())
        XCTAssertFalse(history.restoring)
        try db.dbQueue.write {
            try $0.execute(sql: "ALTER TABLE unavailable_period_tables RENAME TO period_tables")
        }
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A"])
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B"])
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B", "C"])
    }

    func testRedoSnapshotReadFailureDoesNotConsumeHistory() throws {
        try seedThreeActions()
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertTrue(try repo.restoreLastSnapshot())
        try db.dbQueue.write {
            try $0.execute(sql: "ALTER TABLE period_tables RENAME TO unavailable_period_tables")
        }
        XCTAssertThrowsError(try repo.redoLastUndo())
        XCTAssertFalse(history.restoring)
        try db.dbQueue.write {
            try $0.execute(sql: "ALTER TABLE unavailable_period_tables RENAME TO period_tables")
        }
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B"])
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try names(), ["A", "B", "C"])
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try names(), ["A", "B"])
    }
}
