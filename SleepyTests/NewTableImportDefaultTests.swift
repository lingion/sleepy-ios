import XCTest
@testable import Sleepy

final class NewTableImportDefaultTests: XCTestCase {
    private let times = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
    private var previousDepth = 5

    override func setUp() {
        super.setUp()
        previousDepth = Sleepy.UndoManager.shared.maxDepth
        Sleepy.UndoManager.shared.clear()
        Sleepy.UndoManager.shared.applyMaxDepth(5)
    }

    override func tearDown() {
        Sleepy.UndoManager.shared.clear()
        Sleepy.UndoManager.shared.applyMaxDepth(previousDepth)
        super.tearDown()
    }

    private func importedCourse() -> CourseEntity {
        .init(groupId: "import-default-test", tableId: 0, courseName: "Imported",
              day: 2, startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: "#FF6750A4")
    }

    func testFirstImportedTimetableBecomesDefault() throws {
        let repository = ScheduleRepository(try AppDatabase.inMemory())
        let id = try repository.importNewTable(table: .init(name: "First", startDate: "2026-11-02",
            nodesPerDay: 1, timeJson: times, isDefault: false), courses: [importedCourse()],
            periodTable: .init(name: "First bell", nodesPerDay: 1, timeJson: times))
        XCTAssertEqual(try repository.getDefaultTable()?.id, id)
        XCTAssertEqual(try repository.getReminderTables().filter(\.reminderEnabled).map(\.id), [id])
    }

    func testLaterImportPreservesDefaultAndAutomaticReminderScopeThroughUndoAndRedo() throws {
        let database = try AppDatabase.inMemory()
        let selected = try database.timeTableDao.insert(.init(name: "Selected", startDate: "2026-11-02",
            nodesPerDay: 1, timeJson: times, isDefault: true))
        let repository = ScheduleRepository(database)
        let imported = try repository.importNewTable(table: .init(name: "Imported", startDate: "2026-11-02",
            nodesPerDay: 1, timeJson: times, isDefault: true), courses: [importedCourse()],
            periodTable: .init(name: "Imported bell", nodesPerDay: 1, timeJson: times))

        XCTAssertEqual(try repository.getDefaultTable()?.id, selected)
        XCTAssertEqual(try repository.getAllTables().filter(\.isDefault).map(\.id), [selected])
        XCTAssertEqual(try repository.getReminderTables().filter(\.reminderEnabled).map(\.id), [selected])
        XCTAssertFalse(try XCTUnwrap(repository.getTable(imported)).isDefault)
        XCTAssertEqual(try repository.getCourses(imported).map(\.courseName), ["Imported"])

        XCTAssertTrue(try repository.restoreLastSnapshot())
        XCTAssertEqual(try repository.getAllTables().map(\.id), [selected])
        XCTAssertEqual(try repository.getDefaultTable()?.id, selected)
        XCTAssertTrue(try repository.redoLastUndo())
        XCTAssertEqual(try repository.getAllTables().count, 2)
        XCTAssertEqual(try repository.getDefaultTable()?.id, selected)
        XCTAssertEqual(try repository.getReminderTables().filter(\.reminderEnabled).map(\.id), [selected])
    }

    func testFirstAcademicImportBecomesDefault() throws {
        let database = try AppDatabase.inMemory()
        let id = try JwImportViewModel.importAsNewTable(database, courses: academicCourses,
            tableName: "First", startDate: "2026-11-02", timeJson: times)
        let repository = ScheduleRepository(database)
        XCTAssertEqual(try repository.getDefaultTable()?.id, id)
        XCTAssertEqual(try repository.getReminderTables().filter(\.reminderEnabled).map(\.id), [id])
    }

    func testLaterAcademicImportPreservesDefaultWithAndWithoutAnAutomaticPeriodTable() throws {
        for period: PeriodTableEntity? in [nil, .init(name: "Imported bell", nodesPerDay: 1, timeJson: times)] {
            let database = try AppDatabase.inMemory()
            let selected = try database.timeTableDao.insert(.init(name: "Selected", startDate: "2026-11-02",
                nodesPerDay: 1, timeJson: times, isDefault: true))
            let id = try JwImportViewModel.importAsNewTable(database, courses: academicCourses,
                tableName: "Imported", startDate: "2026-11-02", timeJson: times, periodTable: period)
            let repository = ScheduleRepository(database)
            XCTAssertEqual(try repository.getDefaultTable()?.id, selected)
            XCTAssertEqual(try repository.getAllTables().filter(\.isDefault).map(\.id), [selected])
            XCTAssertEqual(try repository.getReminderTables().filter(\.reminderEnabled).map(\.id), [selected])
            XCTAssertFalse(try XCTUnwrap(repository.getTable(id)).isDefault)
            XCTAssertEqual(try repository.getCourses(id).map(\.courseName), ["Imported"])
            XCTAssertEqual(try repository.getAllPeriodTables().count, period == nil ? 0 : 1)
        }
    }

    private var academicCourses: [JwCourse] {
        [.init(name: "Imported", room: "A", teacher: "Ada", day: 2,
               startNode: 1, endNode: 1, startWeek: 1, endWeek: 16)]
    }
}
