import XCTest
@testable import Sleepy

final class TableCopyGlobalNameParityTests: XCTestCase {
    func testDefaultCopyNameSkipsBothCourseAndPeriodTableNames() throws {
        let history = Sleepy.UndoManager.shared
        history.clear()
        defer { history.clear() }
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let source = try repo.insertTable(TimeTableEntity(name: "课表", startDate: "2026-09-07"))
        _ = try repo.insertTable(TimeTableEntity(name: "课表2", startDate: "2026-09-07"))
        _ = try repo.insertPeriodTable(PeriodTableEntity(name: "课表3"))
        let id = try repo.duplicateTable(source)
        XCTAssertEqual(try repo.getTable(id)?.name, "课表4")
    }

    func testExplicitCopyNameCannotCollideWithPeriodTableAndLeavesNoUndoOrPartialCopy() throws {
        let history = Sleepy.UndoManager.shared
        history.clear()
        defer { history.clear() }
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let source = try repo.insertTable(TimeTableEntity(name: "课表", startDate: "2026-09-07"))
        _ = try repo.insertPeriodTable(PeriodTableEntity(name: "占用名"))
        history.clear()
        XCTAssertThrowsError(try repo.duplicateTable(source, newName: " 占用名\n"))
        XCTAssertEqual(try repo.getAllTables().map(\.id), [source])
        XCTAssertFalse(history.hasSnapshot)
    }
}
