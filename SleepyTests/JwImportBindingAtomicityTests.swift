import XCTest
import GRDB
@testable import Sleepy

final class JwImportBindingAtomicityTests: XCTestCase {
    override func setUp() { super.setUp(); Sleepy.UndoManager.shared.clear() }
    override func tearDown() { Sleepy.UndoManager.shared.clear(); super.tearDown() }
    private var courses: [JwCourse] { [.init(name: "Math", room: "A", teacher: "Ada", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 16)] }

    func testCombinedScheduleKeepsRawRulesAndDoesNotOverwriteSharedRows() throws {
        let db = try AppDatabase.inMemory()
        let base = #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"}]"#
        let combo = #"{ "name":"秋冬🍂","publicSchedules":[{"name":"Oct","startDate":"2026-10-01","endDate":"2026-10-31","timeSlots":[{"number":2,"startTime":"10:00","endTime":"10:45"}]}] }"#
        let existing = try db.periodTableDao.insert(.init(name: "Shared", timeJson: base))
        XCTAssertThrowsError(try importedDatedPeriodTable(name: "New", bindingId: existing, baseJson: base, comboScheduleJson: combo))
        let period = try importedDatedPeriodTable(name: "New", bindingId: -1, baseJson: base, comboScheduleJson: combo)
        XCTAssertThrowsError(try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "New",
            timeJson: base, periodTable: period, bindPeriodTableId: existing))
        var sameID = period
        sameID.id = existing
        XCTAssertThrowsError(try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "New",
            timeJson: base, periodTable: sameID))
        XCTAssertEqual(try db.timeTableDao.count(), 0)
        XCTAssertEqual(try db.periodTableDao.count(), 1)
        let id = try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "New",
            startDate: "2026-09-07", timeJson: base, nodesPerDay: 2, periodTable: period)
        let table = try XCTUnwrap(db.timeTableDao.getById(id))
        let newPeriodId = try XCTUnwrap(table.periodTableId)
        let saved = try XCTUnwrap(db.periodTableDao.getById(newPeriodId))
        XCTAssertNotEqual(newPeriodId, existing)
        XCTAssertEqual(table.startDate, "2026-09-07")
        XCTAssertEqual(try db.periodTableDao.getById(existing)?.comboScheduleJson, "")
        XCTAssertEqual(saved.comboScheduleJson, combo)
        XCTAssertEqual(try db.courseDao.getByTable(id).map(\.courseName), ["Math"])
        XCTAssertEqual(TimeTableUtils.parseTimeSlotRows(saved.timeJson(forDateKey: "2026-10-01"))[1].start, "10:00")
    }

    func testCombinedImportRejectsOutOfBasePeriodsBeforeWriting() throws {
        let db = try AppDatabase.inMemory()
        let base = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
        let valid = try importedDatedPeriodTable(name: "Invalid", bindingId: -1, baseJson: base,
                                               comboScheduleJson: #"{"publicSchedules":[]}"#)
        XCTAssertThrowsError(try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "Invalid",
            timeJson: base, nodesPerDay: 1, periodTable: valid))
        XCTAssertEqual(try db.timeTableDao.count(), 0)
        XCTAssertEqual(try db.periodTableDao.count(), 0)
        XCTAssertTrue(try db.courseDao.getAllCourses().isEmpty)
        let invalid = #"{"publicSchedules":[{"name":"Bad","startDate":"2050-05-01","endDate":"2050-09-30","timeSlots":[{"number":2,"startTime":"10:00","endTime":"10:45"}]}]}"#
        XCTAssertThrowsError(try importedDatedPeriodTable(name: "Invalid", bindingId: -1, baseJson: base, comboScheduleJson: invalid))
    }

    func testCombinedPeriodAndNewTimetableRollBackWithARejectedCourse() throws {
        let db = try AppDatabase.inMemory()
        let base = #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"}]"#
        let period = try importedDatedPeriodTable(name: "New", bindingId: -1, baseJson: base,
                                                comboScheduleJson: #"{"publicSchedules":[]}"#)
        try db.dbQueue.write {
            try $0.execute(sql: "CREATE TRIGGER reject_combo_fixture BEFORE INSERT ON courses BEGIN SELECT RAISE(ABORT, 'fixture rejected course'); END;")
        }
        XCTAssertThrowsError(try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "New",
            timeJson: base, periodTable: period))
        XCTAssertEqual(try db.timeTableDao.count(), 0)
        XCTAssertEqual(try db.periodTableDao.count(), 0)
        XCTAssertTrue(try db.courseDao.getAllCourses().isEmpty)
    }

    func testOnlyConfirmedLiveCaptureSetsTheSQLiteGrant() throws {
        let db = try AppDatabase.inMemory()
        let school = JwSchoolInfo(sortKey: "", name: "Fixture", url: "https://jw.example.edu", type: "qz")
        let source = JwImportDraftCodec.toSchoolSourceJson(school)
        let live = try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "Live",
            jwSchoolSourceJson: source, confirmedLocalCapture: true)
        let portable = try JwImportViewModel.importAsNewTable(db, courses: courses, tableName: "Portable",
            jwSchoolSourceJson: source)
        XCTAssertEqual(try db.timeTableDao.getById(live)?.jwSchoolSourceVerified, true)
        XCTAssertEqual(try db.timeTableDao.getById(portable)?.jwSchoolSourceVerified, false)
        XCTAssertEqual(try db.timeTableDao.getById(portable)?.jwSchoolSourceJson, source)
    }

    func testReviewedUpdateRechecksAuthorizationInsideTheWrite() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let identity = #"{"sourceType":"jw","schemaVersion":1,"school":{"name":"Fixture"}}"#
        let tableId = try db.timeTableDao.insert(.init(name: "Target", startDate: "2026-09-07",
            jwSchoolSourceJson: identity, jwSchoolSourceVerified: true))
        _ = try db.courseDao.insert(.init(groupId: "math", tableId: tableId, courseName: "Math",
            room: "Before", day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 1, color: "#FF6750A4"))
        let original = try db.courseDao.getByTable(tableId)
        var replacement = try XCTUnwrap(original.first)
        replacement.room = "After"
        // The ID and all course rows remain unchanged, but the authorization is revoked.
        var revoked = try XCTUnwrap(db.timeTableDao.getById(tableId))
        revoked.jwSchoolSourceVerified = false
        try db.timeTableDao.update(revoked)
        XCTAssertThrowsError(try repo.updateImportedCourses(tableId: tableId, courses: [replacement],
            expectedCourses: original, authorizedSource: identity))
        XCTAssertEqual(try db.courseDao.getByTable(tableId).map(\.room), ["Before"])
        revoked.jwSchoolSourceVerified = true
        try db.timeTableDao.update(revoked)
        try repo.updateImportedCourses(tableId: tableId, courses: [replacement],
            expectedCourses: original, authorizedSource: identity)
        XCTAssertEqual(try db.courseDao.getByTable(tableId).map(\.room), ["After"])
    }

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
