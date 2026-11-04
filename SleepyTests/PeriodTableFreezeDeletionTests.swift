import XCTest
import GRDB
@testable import Sleepy

final class PeriodTableFreezeDeletionTests: XCTestCase {
    private var database: AppDatabase!
    private var repository: ScheduleRepository!
    private var previousDepth = 5
    private let history = Sleepy.UndoManager.shared

    override func setUpWithError() throws {
        previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(5)
        database = try AppDatabase.inMemory()
        repository = ScheduleRepository(database)
        try database.dbQueue.write { db in
            var period = PeriodTableEntity(name: "共享作息", nodesPerDay: 2,
                timeJson: "[{\"node\":1,\"startTime\":\"09:00\",\"endTime\":\"09:45\"}]",
                smartConfigJson: "shared-smart", id: 1)
            try period.insert(db)
            for id in [Int64(1), Int64(2)] {
                var table = TimeTableEntity(name: "课表\(id)", startDate: "2026-09-07",
                    nodesPerDay: 12, timeJson: "old-own-times", isDefault: id == 1,
                    periodTableId: 1, preBindSnapshotJson: "old-binding", id: id)
                try table.insert(db)
            }
            var course = CourseEntity(groupId: "math", tableId: 1, courseName: "数学",
                day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: "")
            try course.insert(db)
        }
    }

    override func tearDown() {
        history.clear()
        history.applyMaxDepth(previousDepth)
        repository = nil
        database = nil
        super.tearDown()
    }

    func testDeleteFreezesEveryOwnerAndSupportsUndoRedo() throws {
        let before = try repository.getAllTables()
        let courses = try database.courseDao.getAllCourses()
        let period = try XCTUnwrap(repository.getAllPeriodTables().first)
        XCTAssertTrue(try repository.deletePeriodTable(1, onlyIfUnbound: false))
        XCTAssertTrue(try repository.getAllPeriodTables().isEmpty)
        let frozen = try repository.getAllTables()
        XCTAssertEqual(frozen.count, 2)
        for table in frozen {
            XCTAssertNil(table.periodTableId)
            XCTAssertEqual(table.preBindSnapshotJson, "")
            XCTAssertEqual(table.timeJson, period.timeJson)
            XCTAssertEqual(table.nodesPerDay, period.nodesPerDay)
            XCTAssertEqual(table.smartConfigJson, period.smartConfigJson)
        }
        XCTAssertEqual(try database.courseDao.getAllCourses(), courses)
        XCTAssertTrue(try repository.restoreLastSnapshot())
        XCTAssertEqual(try repository.getAllTables().map(\.periodTableId), before.map(\.periodTableId))
        XCTAssertEqual(try repository.getAllTables().map(\.timeJson), before.map(\.timeJson))
        XCTAssertEqual(try repository.getAllPeriodTables().count, 1)
        XCTAssertTrue(try repository.redoLastUndo())
        XCTAssertTrue(try repository.getAllPeriodTables().isEmpty)
        XCTAssertTrue(try repository.getAllTables().allSatisfy { $0.periodTableId == nil })
    }

    func testAbandonedDraftCannotDeleteAnAdoptedPeriod() throws {
        XCTAssertFalse(try repository.deletePeriodTable(1, onlyIfUnbound: true))
        XCTAssertFalse(try repository.deletePeriodTable(999, onlyIfUnbound: false))
        XCTAssertFalse(history.hasSnapshot)
        XCTAssertEqual(try repository.getAllPeriodTables().count, 1)
        XCTAssertTrue(try repository.getAllTables().allSatisfy { $0.periodTableId == 1 })
    }

    func testDeleteFailureRollsBackFreezingAndDoesNotConsumeHistory() throws {
        try database.dbQueue.write { db in
            try db.execute(sql: """
                CREATE TRIGGER block_period_delete BEFORE DELETE ON period_tables
                BEGIN SELECT RAISE(ABORT, 'injected deletion failure'); END;
                """)
        }
        XCTAssertThrowsError(try repository.deletePeriodTable(1, onlyIfUnbound: false))
        XCTAssertEqual(try repository.getAllPeriodTables().count, 1)
        XCTAssertTrue(try repository.getAllTables().allSatisfy {
            $0.periodTableId == 1 && $0.timeJson == "old-own-times" && $0.preBindSnapshotJson == "old-binding"
        })
        XCTAssertFalse(history.hasSnapshot)
    }
}
