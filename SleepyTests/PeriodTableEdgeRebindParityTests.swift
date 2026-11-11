import XCTest
import GRDB
@testable import Sleepy

final class PeriodTableEdgeRebindParityTests: XCTestCase {
    private typealias Row = TimeTableUtils.TimeSlotRow
    private let history = Sleepy.UndoManager.shared
    private var previousDepth = 5

    override func setUp() {
        super.setUp()
        previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(5)
    }

    override func tearDown() {
        history.clear()
        history.applyMaxDepth(previousDepth)
        super.tearDown()
    }

    private func json(after: Int) -> String {
        TimeTableUtils.buildTimeJsonFromRows([
            Row(node: 1, start: "08:00", end: "08:45"),
            Row(node: after, start: "12:00", end: "12:45", edgeClass: .after)])
    }

    private func addEdgeCourse(_ repo: ScheduleRepository, tableId: Int64, node: Int) throws -> Int64 {
        try repo.insertCourse(CourseEntity(groupId: "edge", tableId: tableId, courseName: "边缘课",
            day: 1, startNode: node, step: 1, startWeek: 1, endWeek: 16, color: "", isIrregularNode: true))
    }

    func testRebindMigratesTargetExistingOwnersBeforeAddingNewBinding() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let periodId = try repo.insertPeriodTable(PeriodTableEntity(name: "目标作息", timeJson: json(after: 2)))
        let existing = try repo.insertTable(TimeTableEntity(name: "原绑定", startDate: "2026-09-07", periodTableId: periodId))
        let incoming = try repo.insertTable(TimeTableEntity(name: "新绑定", startDate: "2026-09-07", timeJson: json(after: 2)))
        let existingCourse = try addEdgeCourse(repo, tableId: existing, node: 2)
        let incomingCourse = try addEdgeCourse(repo, tableId: incoming, node: 2)
        var target = try XCTUnwrap(repo.getPeriodTable(periodId))
        target.timeJson = json(after: 3)
        let edited = try XCTUnwrap(repo.getTable(incoming))
        history.clear()
        try repo.updateTableMetadataAndBind(table: edited, periodTableId: periodId, periodContent: target)
        XCTAssertEqual(try repo.getCourse(existingCourse)?.startNode, 3)
        XCTAssertEqual(try repo.getCourse(incomingCourse)?.startNode, 2)
        XCTAssertEqual(try repo.getTable(incoming)?.periodTableId, periodId)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try repo.getCourse(existingCourse)?.startNode, 2)
        XCTAssertNil(try repo.getTable(incoming)?.periodTableId)
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try repo.getCourse(existingCourse)?.startNode, 3)
        XCTAssertEqual(try repo.getCourse(incomingCourse)?.startNode, 2)
    }

    func testExplicitUnbindRetainsOrdinalPolicyAndRestoresPrivateScheduleWithUndo() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let periodId = try repo.insertPeriodTable(PeriodTableEntity(name: "共享", timeJson: json(after: 3)))
        let tid = try repo.insertTable(TimeTableEntity(name: "私人", startDate: "2026-09-07", timeJson: json(after: 2)))
        let courseId = try addEdgeCourse(repo, tableId: tid, node: 3)
        try repo.bindPeriodTable(timeTableId: tid, periodTableId: periodId)
        let edited = try XCTUnwrap(repo.getTable(tid))
        history.clear()
        try repo.updateTableMetadataAndBind(table: edited, periodTableId: nil)
        XCTAssertNil(try repo.getTable(tid)?.periodTableId)
        XCTAssertEqual(try repo.getTable(tid)?.timeJson, json(after: 2))
        XCTAssertEqual(try repo.getCourse(courseId)?.startNode, 3)
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try repo.getTable(tid)?.periodTableId, periodId)
        XCTAssertEqual(try repo.getCourse(courseId)?.startNode, 3)
    }

    func testCourseWriteFailureRollsBackSharedScheduleAndEveryOwnerWithoutUndo() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let periodId = try repo.insertPeriodTable(PeriodTableEntity(name: "共享", timeJson: json(after: 2)))
        let first = try repo.insertTable(TimeTableEntity(name: "甲", startDate: "2026-09-07", periodTableId: periodId))
        let second = try repo.insertTable(TimeTableEntity(name: "乙", startDate: "2026-09-07", periodTableId: periodId))
        let firstCourse = try addEdgeCourse(repo, tableId: first, node: 2)
        let secondCourse = try addEdgeCourse(repo, tableId: second, node: 2)
        try db.dbQueue.write { db in
            try db.execute(sql: "CREATE TRIGGER reject_edge_migration BEFORE UPDATE ON courses WHEN OLD.id = \(secondCourse) BEGIN SELECT RAISE(ABORT, 'edge migration rejected'); END")
        }
        var period = try XCTUnwrap(repo.getPeriodTable(periodId))
        period.timeJson = json(after: 3)
        history.clear()
        XCTAssertThrowsError(try repo.savePeriodTable(period))
        XCTAssertEqual(try repo.getPeriodTable(periodId)?.timeJson, json(after: 2))
        XCTAssertEqual(try repo.getCourse(firstCourse)?.startNode, 2)
        XCTAssertEqual(try repo.getCourse(secondCourse)?.startNode, 2)
        XCTAssertFalse(history.hasSnapshot)
    }
}
