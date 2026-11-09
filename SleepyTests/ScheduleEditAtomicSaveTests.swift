import XCTest
import GRDB
@testable import Sleepy

final class ScheduleEditAtomicSaveTests: XCTestCase {
    private let oldJSON = #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"}]"#
    private let newJSON = #"[{"node":1,"start":"07:00","end":"07:45"},{"node":2,"start":"08:00","end":"08:45"},{"node":3,"start":"09:00","end":"09:45"}]"#

    private struct DatabaseContents: Encodable {
        let tables: [TimeTableEntity]
        let periods: [PeriodTableEntity]
        let courses: [CourseEntity]
    }

    private func contents(_ repo: ScheduleRepository) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(DatabaseContents(
            tables: repo.getAllTables().sorted { $0.id < $1.id },
            periods: repo.getAllPeriodTables().sorted { $0.id < $1.id },
            courses: repo.getAllCourses().sorted { $0.id < $1.id }))
    }

    private func block(_ db: AppDatabase, table: String) throws {
        try db.dbQueue.write {
            try $0.execute(sql: "CREATE TRIGGER reject_edit BEFORE UPDATE ON \(table) BEGIN SELECT RAISE(ABORT, 'injected save failure'); END;")
        }
    }

    @MainActor
    private func checkPolicyRollbackAndRetry(_ policy: SchedulePolicy, blockedTable: String) throws {
        let history = Sleepy.UndoManager.shared
        let previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(5)
        defer { history.clear(); history.applyMaxDepth(previousDepth) }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let periodID = try repo.insertPeriodTable(PeriodTableEntity(name: "共享作息", nodesPerDay: 2, timeJson: oldJSON))
        let tableID = try repo.insertTable(TimeTableEntity(name: "待编辑课表", startDate: "2026-11-02", nodesPerDay: 2, timeJson: oldJSON))
        try repo.bindPeriodTable(timeTableId: tableID, periodTableId: periodID)
        let otherID = try repo.insertTable(TimeTableEntity(name: "另一张课表", startDate: "2026-11-02", nodesPerDay: 2, timeJson: oldJSON))
        try repo.bindPeriodTable(timeTableId: otherID, periodTableId: periodID)
        try repo.insertCourse(CourseEntity(groupId: "math", tableId: tableID, courseName: "数学", day: 1,
                                           startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: ""))
        history.clear()
        // Keep a redo entry so failure must preserve both history stacks.
        try repo.insertTable(TimeTableEntity(name: "可重做", startDate: "2026-11-02"))
        XCTAssertTrue(try repo.restoreLastSnapshot())
        let before = try contents(repo)
        let original = try XCTUnwrap(repo.getPeriodTable(periodID))
        var draft = original
        draft.timeJson = newJSON
        draft.nodesPerDay = 3
        var edited = try XCTUnwrap(repo.getTable(tableID))
        edited.name = "保存后的名字"
        edited.timeJson = newJSON
        edited.nodesPerDay = 3
        let vm = ScheduleViewModel(repo: repo)
        let session = vm.startEditSession(tableId: tableID, originalEffectiveSchedule: original)
        session.updateDraft(draft)
        session.selectPolicy(policy)
        var finished = 0
        var failure: String?
        var changes = 0
        repo.onDataChangedHook = { changes += 1 }
        try block(db, table: blockedTable)

        XCTAssertFalse(vm.executePolicyAndSave(tableId: tableID, editedTable: edited,
                                               newTimeJson: newJSON, smartConfigJson: "", nodesPerDay: 3,
                                               onFinish: { finished += 1 }, onFailure: { failure = $0 }))
        XCTAssertEqual(try contents(repo), before, "Every earlier SQL statement must roll back")
        XCTAssertEqual(finished, 0, "The editor must keep its draft open on failure")
        XCTAssertEqual(failure, L10n.format("table_reminder_save_failed"))
        XCTAssertEqual(vm.state.error, failure)
        XCTAssertEqual(session.draftEffectiveSchedule, draft)
        XCTAssertEqual(session.pendingSchedulePolicy, policy)
        XCTAssertFalse(history.hasSnapshot)
        XCTAssertTrue(history.hasRedoSnapshot)
        XCTAssertEqual(changes, 0)

        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER reject_edit") }
        XCTAssertTrue(vm.executePolicyAndSave(tableId: tableID, editedTable: edited,
                                              newTimeJson: newJSON, smartConfigJson: "", nodesPerDay: 3,
                                              onFinish: { finished += 1 }))
        XCTAssertEqual(finished, 1)
        XCTAssertNil(vm.state.error)
        XCTAssertEqual(session.pendingSchedulePolicy, .none)
        XCTAssertEqual(changes, 1)
        XCTAssertFalse(history.hasRedoSnapshot)
        let saved = try XCTUnwrap(repo.getTable(tableID))
        XCTAssertEqual(saved.name, edited.name)
        XCTAssertEqual(try repo.getTable(otherID)?.periodTableId, periodID)
        switch policy {
        case .detachCopy:
            XCTAssertNil(saved.periodTableId)
            XCTAssertEqual(saved.preBindSnapshotJson, "")
            XCTAssertEqual(saved.timeJson, newJSON)
            XCTAssertEqual(try repo.getPeriodTable(periodID), original)
            XCTAssertEqual(try repo.getCourses(tableID).first?.startNode, 2)
        case .createNew:
            XCTAssertNotEqual(saved.periodTableId, periodID)
            XCTAssertEqual(try repo.getPeriodTable(try XCTUnwrap(saved.periodTableId))?.timeJson, newJSON)
            XCTAssertEqual(try repo.getAllPeriodTables().count, 2)
            XCTAssertEqual(try repo.getPeriodTable(periodID), original)
            XCTAssertEqual(try repo.getCourses(tableID).first?.startNode, 2)
        case .sync:
            XCTAssertEqual(saved.periodTableId, periodID)
            XCTAssertEqual(try repo.getPeriodTable(periodID)?.timeJson, newJSON)
            XCTAssertEqual(try repo.getCourses(tableID).first?.startNode, 1, "Shared edits preserve course node bindings")
        case .none:
            XCTFail("A real save policy is required")
        }
        XCTAssertTrue(try repo.restoreLastSnapshot())
        XCTAssertEqual(try contents(repo), before, "One undo must restore the entire policy save")
        XCTAssertFalse(history.hasSnapshot)
    }

    @MainActor
    func testDetachCourseFailureRollsBackAndKeepsDraftForRetry() throws {
        try checkPolicyRollbackAndRetry(.detachCopy, blockedTable: "courses")
    }

    @MainActor
    func testCreateNewBindingFailureRollsBackInsertedPeriodAndKeepsDraft() throws {
        try checkPolicyRollbackAndRetry(.createNew, blockedTable: "time_tables")
    }

    @MainActor
    func testSyncMetadataFailureRollsBackSharedPeriodForEveryOwner() throws {
        try checkPolicyRollbackAndRetry(.sync, blockedTable: "time_tables")
    }

    @MainActor
    func testUnboundSaveFailureDoesNotFinishEditorOrPublishHistory() throws {
        let history = Sleepy.UndoManager.shared
        let previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(5)
        defer { history.clear(); history.applyMaxDepth(previousDepth) }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let tableID = try repo.insertTable(TimeTableEntity(name: "原名", startDate: "2026-11-02", nodesPerDay: 2, timeJson: oldJSON))
        try repo.insertCourse(CourseEntity(groupId: "math", tableId: tableID, courseName: "数学", day: 1,
                                           startNode: 1, step: 1, startWeek: 1, endWeek: 16, color: ""))
        history.clear()
        let before = try contents(repo)
        var edited = try XCTUnwrap(repo.getTable(tableID))
        edited.name = "编辑草稿"
        edited.timeJson = newJSON
        edited.nodesPerDay = 3
        let vm = ScheduleViewModel(repo: repo)
        var finished = false
        var failure: String?
        try block(db, table: "courses")
        XCTAssertFalse(vm.updateTableRemappingCourses(edited, onFinish: { finished = true }, onFailure: { failure = $0 }))
        XCTAssertFalse(finished)
        XCTAssertNotNil(failure)
        XCTAssertEqual(try contents(repo), before)
        XCTAssertFalse(history.hasSnapshot)
        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER reject_edit") }
        XCTAssertTrue(vm.updateTableRemappingCourses(edited, onFinish: { finished = true }))
        XCTAssertTrue(finished)
        XCTAssertEqual(try repo.getCourses(tableID).first?.startNode, 2)
    }

    @MainActor
    func testRebindAndSharedMetadataFailuresDoNotFinishEditor() throws {
        let history = Sleepy.UndoManager.shared
        history.clear()
        defer { history.clear() }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let tableID = try repo.insertTable(TimeTableEntity(name: "原名", startDate: "2026-11-02"))
        let periodID = try repo.insertPeriodTable(PeriodTableEntity(name: "目标作息"))
        var edited = try XCTUnwrap(repo.getTable(tableID))
        edited.name = "草稿名"
        var period = try XCTUnwrap(repo.getPeriodTable(periodID))
        period.timeJson = newJSON
        let vm = ScheduleViewModel(repo: repo)
        let before = try contents(repo)
        var finished = 0
        try block(db, table: "period_tables")
        XCTAssertFalse(vm.updateTableMetadataAndBind(table: edited, periodTableId: periodID, periodContent: period,
                                                     onFinish: { finished += 1 }))
        XCTAssertEqual(try contents(repo), before)
        XCTAssertFalse(vm.updateTableMetadataWithPeriodTable(table: edited, periodTable: period,
                                                             onFinish: { finished += 1 }))
        XCTAssertEqual(try contents(repo), before)
        XCTAssertEqual(finished, 0)
    }
}
