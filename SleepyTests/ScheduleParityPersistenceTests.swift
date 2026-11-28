import XCTest
@testable import Sleepy

final class ScheduleParityPersistenceTests: XCTestCase {
    func testNonpositiveCreateAndEditFailBeforeSaving() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        var invalid = TimeTableEntity(name: "Invalid", startDate: "2026-08-31", maxWeek: 0)

        assertInvalidWeekCount { _ = try repo.insertTable(invalid) }
        assertInvalidWeekCount {
            _ = try repo.importNewTable(table: invalid, courses: [], periodTable: nil)
        }
        XCTAssertTrue(try repo.getAllTables().isEmpty)

        let id = try db.timeTableDao.insert(TimeTableEntity(name: "Valid", startDate: "2026-08-31", maxWeek: 21))
        invalid.id = id
        invalid.maxWeek = -1
        assertInvalidWeekCount { try repo.updateTable(invalid) }
        assertInvalidWeekCount { try repo.updateTableMetadata(invalid) }
        assertInvalidWeekCount { try repo.updateTableMetadataAndBind(table: invalid, periodTableId: nil) }
        assertInvalidWeekCount { try repo.updateTableRemappingCourses(invalid) }
        XCTAssertEqual(try repo.getTable(id)?.maxWeek, 21)
        XCTAssertEqual(try repo.getTable(id)?.name, "Valid")
    }

    func testExportSnapshotMatchesRequestedTimetableAndRejectsDeletedTarget() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let period = PeriodTableEntity(name: "Later", timeJson: """
          [{"node":1,"start":"09:30","end":"10:15"}]
          """)
        let periodId = try db.periodTableDao.insert(period)
        let current = try db.timeTableDao.insert(TimeTableEntity(name: "Current", startDate: "2026-08-31", isDefault: true))
        let target = try db.timeTableDao.insert(TimeTableEntity(name: "Selected", startDate: "2026-08-31", periodTableId: periodId))
        _ = try db.courseDao.insert(CourseEntity(groupId: "a", tableId: current, courseName: "Wrong course",
            day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 20, color: ""))
        _ = try db.courseDao.insert(CourseEntity(groupId: "b", tableId: target, courseName: "Selected course",
            day: 3, startNode: 1, step: 1, startWeek: 1, endWeek: 20, color: ""))

        let snapshot = try repo.loadExportSnapshot(tableId: target)
        XCTAssertEqual(snapshot.table.id, target)
        XCTAssertEqual(snapshot.courses.map(\.courseName), ["Selected course"])
        XCTAssertEqual(snapshot.effectiveTable.timeJson, period.timeJson)
        try db.timeTableDao.deleteById(target)
        XCTAssertThrowsError(try repo.loadExportSnapshot(tableId: target))
        XCTAssertEqual(try repo.getDefaultTable()?.id, current)
    }

    private func assertInvalidWeekCount(_ operation: () throws -> Void,
                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            guard case ScheduleRepository.TableEditSaveError.invalidWeekCount = error else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
        }
    }
}
