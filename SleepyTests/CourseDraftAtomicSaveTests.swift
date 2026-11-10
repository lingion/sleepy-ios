import XCTest
import GRDB
@testable import Sleepy

final class CourseDraftAtomicSaveTests: XCTestCase {
    private let baseJSON = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
    private let history = Sleepy.UndoManager.shared
    private var previousDepth = 5

    override func setUp() {
        super.setUp()
        previousDepth = history.maxDepth
        history.clear()
        history.restoring = false
        history.applyMaxDepth(5)
    }

    override func tearDown() {
        history.clear()
        history.restoring = false
        history.applyMaxDepth(previousDepth)
        super.tearDown()
    }

    private func course(tableID: Int64, node: Int, name: String = "早课", group: String = "early") -> CourseEntity {
        CourseEntity(groupId: group, tableId: tableID, courseName: name, day: 1,
                     startNode: node, step: 1, startWeek: 1, endWeek: 16, color: "")
    }

    private func edgeJSON(_ base: String) -> String {
        TimeTableUtils.insertEdgeNode(timeJson: base, edgeClass: .before, start: "07:00", end: "07:45")
    }

    private func block(_ db: AppDatabase, table: String) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "CREATE TRIGGER reject_slot_save BEFORE UPDATE ON \(table) BEGIN SELECT RAISE(ABORT, 'injected slot failure'); END;")
        }
    }

    private func checkInsertFailureAndRetry(shared: Bool) throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let tableID = try repo.insertTable(TimeTableEntity(name: "主课表", startDate: "2026-11-02", nodesPerDay: 1, timeJson: baseJSON))
        let periodID: Int64?
        if shared {
            periodID = try repo.insertPeriodTable(PeriodTableEntity(name: "共享作息", nodesPerDay: 1, timeJson: baseJSON))
            try repo.bindPeriodTable(timeTableId: tableID, periodTableId: periodID)
        } else {
            periodID = nil
        }
        history.clear()
        var changes = 0
        repo.onDataChangedHook = { changes += 1 }
        let updatedJSON = edgeJSON(baseJSON)
        let timeChange = ScheduleRepository.CourseTimeChange(expectedPeriodTableId: periodID,
                                                              originalTimeJson: baseJSON, updatedTimeJson: updatedJSON)
        try block(db, table: shared ? "period_tables" : "time_tables")
        XCTAssertThrowsError(try repo.saveCourseDrafts(tableId: tableID, editingGroupId: nil,
                                                       drafts: [course(tableID: tableID, node: 0)], timeChange: timeChange))
        XCTAssertTrue(try repo.getCourses(tableID).isEmpty, "A failed edge write must roll back the already inserted course")
        XCTAssertEqual(try repo.getTable(tableID)?.timeJson, baseJSON)
        if let periodID { XCTAssertEqual(try repo.getPeriodTable(periodID)?.timeJson, baseJSON) }
        XCTAssertFalse(history.hasSnapshot)
        XCTAssertEqual(changes, 0)

        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER reject_slot_save") }
        try repo.saveCourseDrafts(tableId: tableID, editingGroupId: nil,
                                  drafts: [course(tableID: tableID, node: 0)], timeChange: timeChange)
        XCTAssertEqual(try repo.getCourses(tableID).map(\.startNode), [0])
        let effective = try XCTUnwrap(repo.getTable(tableID)).hydratedWith(try repo.effectivePeriodTable(tableId: tableID))
        XCTAssertEqual(effective.timeJson, updatedJSON)
        XCTAssertEqual(changes, 1)
        if shared { XCTAssertEqual(try repo.getTable(tableID)?.timeJson, baseJSON, "Shared edits must leave compatibility columns intact") }
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertTrue(try repo.getCourses(tableID).isEmpty)
        XCTAssertEqual(try XCTUnwrap(repo.getTable(tableID)).hydratedWith(try repo.effectivePeriodTable(tableId: tableID)).timeJson, baseJSON)
        XCTAssertFalse(history.hasSnapshot, "Course and time change are exactly one undo step")
        XCTAssertTrue(try repo.redoLastUndo())
        XCTAssertEqual(try repo.getCourses(tableID).map(\.startNode), [0])
    }

    func testUnboundCourseAndBeforeSlotInsertRollBackTogether() throws {
        try checkInsertFailureAndRetry(shared: false)
    }

    func testSharedCourseAndBeforeSlotInsertRollBackTogether() throws {
        try checkInsertFailureAndRetry(shared: true)
    }

    func testGroupReplacementRollsBackDeletedRowsIfSharedSlotUpdateFails() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let periodID = try repo.insertPeriodTable(PeriodTableEntity(name: "共享", nodesPerDay: 1, timeJson: baseJSON))
        let tableID = try repo.insertTable(TimeTableEntity(name: "课表", startDate: "2026-11-02", nodesPerDay: 1, timeJson: baseJSON))
        try repo.bindPeriodTable(timeTableId: tableID, periodTableId: periodID)
        try repo.insertCourse(course(tableID: tableID, node: 1))
        let original = try repo.getCourses(tableID)
        history.clear()
        let change = ScheduleRepository.CourseTimeChange(expectedPeriodTableId: periodID,
                                                          originalTimeJson: baseJSON, updatedTimeJson: edgeJSON(baseJSON))
        try block(db, table: "period_tables")
        XCTAssertThrowsError(try repo.saveCourseDrafts(tableId: tableID, editingGroupId: "early",
                                                       drafts: [course(tableID: tableID, node: 0)], timeChange: change))
        XCTAssertEqual(try repo.getCourses(tableID), original)
        XCTAssertEqual(try repo.getPeriodTable(periodID)?.timeJson, baseJSON)
        XCTAssertFalse(history.hasSnapshot)
        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER reject_slot_save") }
        try repo.saveCourseDrafts(tableId: tableID, editingGroupId: "early",
                                  drafts: [course(tableID: tableID, node: 0)], timeChange: change)
        XCTAssertEqual(try repo.getCourses(tableID).map(\.startNode), [0])
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try repo.getCourses(tableID), original)
        XCTAssertEqual(try repo.getPeriodTable(periodID)?.timeJson, baseJSON)
    }

    func testReclaimKeepsSharedSlotReferencedByAnotherOwner() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let json = edgeJSON(baseJSON)
        let periodID = try repo.insertPeriodTable(PeriodTableEntity(name: "共享", nodesPerDay: 1, timeJson: json))
        let firstID = try repo.insertTable(TimeTableEntity(name: "甲", startDate: "2026-11-02", nodesPerDay: 1, timeJson: baseJSON))
        let secondID = try repo.insertTable(TimeTableEntity(name: "乙", startDate: "2026-11-02", nodesPerDay: 1, timeJson: baseJSON))
        for id in [firstID, secondID] {
            try repo.bindPeriodTable(timeTableId: id, periodTableId: periodID)
            try repo.insertCourse(course(tableID: id, node: 0))
        }
        try repo.saveCourseDrafts(tableId: firstID, editingGroupId: "early",
                                  drafts: [course(tableID: firstID, node: 1)])
        XCTAssertEqual(try repo.getPeriodTable(periodID)?.timeJson, json)
        try repo.saveCourseDrafts(tableId: secondID, editingGroupId: "early",
                                  drafts: [course(tableID: secondID, node: 1)])
        XCTAssertEqual(TimeTableUtils.edgeNodesOf(timeJson: try XCTUnwrap(repo.getPeriodTable(periodID)).timeJson,
                                                 edgeClass: .before), [])
        XCTAssertEqual(try repo.getTable(firstID)?.timeJson, baseJSON)
        XCTAssertEqual(try repo.getTable(secondID)?.timeJson, baseJSON)
    }

    func testStaleLoadedTimeCannotOverwriteNewScheduleOrInsertCourse() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let tableID = try repo.insertTable(TimeTableEntity(name: "课表", startDate: "2026-11-02", nodesPerDay: 1, timeJson: baseJSON))
        var current = try XCTUnwrap(repo.getTable(tableID))
        current.timeJson = #"[{"node":1,"start":"10:00","end":"10:45"}]"#
        try repo.updateTable(current)
        history.clear()
        let change = ScheduleRepository.CourseTimeChange(expectedPeriodTableId: nil,
                                                          originalTimeJson: baseJSON, updatedTimeJson: edgeJSON(baseJSON))
        XCTAssertThrowsError(try repo.saveCourseDrafts(tableId: tableID, editingGroupId: nil,
                                                       drafts: [course(tableID: tableID, node: 0)], timeChange: change))
        XCTAssertTrue(try repo.getCourses(tableID).isEmpty)
        XCTAssertEqual(try repo.getTable(tableID)?.timeJson, current.timeJson)
        XCTAssertFalse(history.hasSnapshot)
    }
}
