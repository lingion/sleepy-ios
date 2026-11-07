import XCTest
import GRDB
@testable import Sleepy

final class ImportAtomicityAuditTests: XCTestCase {
    override func setUp() { super.setUp(); Sleepy.UndoManager.shared.clear() }
    override func tearDown() { Sleepy.UndoManager.shared.clear(); super.tearDown() }

    private func course(_ tableId: Int64, name: String) -> CourseEntity {
        CourseEntity(groupId: "g", tableId: tableId, courseName: name, day: 1,
                     startNode: 1, step: 1, startWeek: 1, endWeek: 24, color: "#123456")
    }

    func testReplacementFailureRollsBackMetadataTimesCoursesAndHistory() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let id = try repo.insertTable(TimeTableEntity(name: "old", startDate: "2026-09-07", maxWeek: 16))
        _ = try repo.insertCourses([course(id, name: "old course")])
        let before = try XCTUnwrap(repo.getTable(id))
        let oldCourses = try repo.getCourses(id)
        Sleepy.UndoManager.shared.clear()
        Sleepy.UndoManager.shared.recordRedo(UndoSnapshot(tables: [before], courses: oldCourses, defaultTableId: id))
        try db.dbQueue.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_import BEFORE INSERT ON courses BEGIN SELECT RAISE(ABORT, 'injected failure'); END;")
        }
        XCTAssertThrowsError(try repo.replaceImportedTable(id, name: "new", startDate: "2027-02-01",
            maxWeek: 24, nodesPerDay: 1, timeJson: "[]", courses: [course(id, name: "new course")], keepGroups: true))
        let after = try XCTUnwrap(repo.getTable(id))
        XCTAssertEqual(after.name, before.name)
        XCTAssertEqual(after.startDate, before.startDate)
        XCTAssertEqual(after.maxWeek, before.maxWeek)
        XCTAssertEqual(after.timeJson, before.timeJson)
        XCTAssertEqual(try repo.getCourses(id), oldCourses)
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
        XCTAssertTrue(Sleepy.UndoManager.shared.hasRedoSnapshot)
    }

    func testReplacementPersistsIncomingSemesterLengthAndResetsForeignIds() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let id = try repo.insertTable(TimeTableEntity(name: "old", startDate: "2026-09-07", maxWeek: 16))
        var imported = course(999, name: "new course")
        imported.id = 789
        try repo.replaceImportedTable(id, name: "new", startDate: "2026-09-07", maxWeek: 24,
            nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON, courses: [imported], keepGroups: true)
        XCTAssertEqual(try repo.getTable(id)?.maxWeek, 24)
        XCTAssertEqual(try repo.getCourses(id).first?.tableId, id)
        XCTAssertNotEqual(try repo.getCourses(id).first?.id, 789)
    }

    func testNewImportFailureLeavesRedoAvailable() throws {
        let db = try AppDatabase.inMemory()
        Sleepy.UndoManager.shared.recordRedo(UndoSnapshot(tables: [], courses: [], defaultTableId: nil))
        try db.dbQueue.write { db in
            try db.execute(sql: "CREATE TRIGGER fail_new_import BEFORE INSERT ON courses BEGIN SELECT RAISE(ABORT, 'injected failure'); END;")
        }
        XCTAssertThrowsError(try importNewTableAtomically(store: GRDBNewTableImportStore(db: db),
            table: TimeTableEntity(name: "new", startDate: "2026-09-07"), courses: [course(0, name: "new")],
            period: nil, bindingId: nil, keepGroups: true))
        XCTAssertFalse(Sleepy.UndoManager.shared.hasSnapshot)
        XCTAssertTrue(Sleepy.UndoManager.shared.hasRedoSnapshot)
        XCTAssertTrue(try ScheduleRepository(db).getAllTables().isEmpty)
    }
}
