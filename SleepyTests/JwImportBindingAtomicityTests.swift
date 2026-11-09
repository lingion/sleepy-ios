import XCTest
import GRDB
@testable import Sleepy

final class JwImportBindingAtomicityTests: XCTestCase {
    override func setUp() { super.setUp(); Sleepy.UndoManager.shared.clear() }
    override func tearDown() { Sleepy.UndoManager.shared.clear(); super.tearDown() }
    private var courses: [JwCourse] { [.init(name: "Math", room: "A", teacher: "Ada", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 16)] }

    func testMissingSelectedPeriodDoesNotCreateTableOrConsumeRedo() throws {
        let db = try AppDatabase.inMemory()
        Sleepy.UndoManager.shared.recordRedo(.init(tables: [], courses: [], defaultTableId: nil))
        XCTAssertThrowsError(try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "New", bindPeriodTableId: 999))
        XCTAssertTrue(try ScheduleRepository(db).getAllTables().isEmpty)
        XCTAssertTrue(try ScheduleRepository(db).getAllCourses().isEmpty)
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
        XCTAssertTrue(Sleepy.UndoManager.shared.hasRedoSnapshot)
    }

    func testBindingAndCoursesCommitAsOneUndoUnit() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let period = try repo.insertPeriodTable(.init(name: "Shared", nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON))
        Sleepy.UndoManager.shared.clear()
        let id = try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "New", startDate: "2026-11-03",
                                                       smartConfigJson: "smart", bindPeriodTableId: period)
        XCTAssertEqual(try repo.getTable(id)?.periodTableId, period)
        XCTAssertEqual(try repo.getTable(id)?.smartConfigJson, "smart")
        XCTAssertEqual(try repo.getTable(id)?.startDate, "2026-11-02")
        XCTAssertEqual(try repo.getCourses(id).count, 1)
        XCTAssertEqual(try repo.getAllPeriodTables().count, 1)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertTrue(try repo.getAllTables().isEmpty)
        XCTAssertNotNil(try repo.getPeriodTable(period))
    }

    func testCourseInsertFailureRollsBackTableAndBindingTogether() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let period = try repo.insertPeriodTable(.init(name: "Shared", nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON))
        Sleepy.UndoManager.shared.clear()
        try db.dbQueue.write { try $0.execute(sql: "CREATE TRIGGER reject_jw_course BEFORE INSERT ON courses BEGIN SELECT RAISE(ABORT, 'injected failure'); END;") }
        XCTAssertThrowsError(try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "New", bindPeriodTableId: period))
        XCTAssertTrue(try repo.getAllTables().isEmpty)
        XCTAssertNotNil(try repo.getPeriodTable(period))
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
    }
}
