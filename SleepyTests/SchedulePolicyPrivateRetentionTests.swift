import XCTest
@testable import Sleepy

final class SchedulePolicyPrivateRetentionTests: XCTestCase {
    private let privateJSON = #"[{"node":1,"start":"08:00","end":"08:45"},{"node":2,"start":"09:00","end":"09:45"},{"node":3,"start":"10:00","end":"10:45"}]"#
    private let sharedJSON = #"[{"node":1,"start":"09:00","end":"09:45"},{"node":2,"start":"10:00","end":"10:45"}]"#
    private let replacementJSON = #"[{"node":1,"start":"07:00","end":"07:45"},{"node":2,"start":"08:00","end":"08:45"},{"node":3,"start":"09:00","end":"09:45"},{"node":4,"start":"10:00","end":"10:45"}]"#
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

    private func fixture(_ repo: ScheduleRepository, bound: Bool = true) throws -> (Int64, Int64) {
        let periodID = try repo.insertPeriodTable(PeriodTableEntity(
            name: "共享", nodesPerDay: 2, timeJson: sharedJSON, smartConfigJson: "shared-config"))
        let tableID = try repo.insertTable(TimeTableEntity(
            name: "私人", startDate: "2026-09-07", nodesPerDay: 3,
            timeJson: privateJSON, smartConfigJson: "private-config"))
        if bound { try repo.bindPeriodTable(timeTableId: tableID, periodTableId: periodID) }
        try repo.insertCourse(CourseEntity(groupId: "math", tableId: tableID,
                                           courseName: "数学", day: 1, startNode: 1,
                                           step: 1, startWeek: 1, endWeek: 16, color: ""))
        history.clear()
        return (tableID, periodID)
    }

    private func assertPrivateFields(_ table: TimeTableEntity, match original: TimeTableEntity,
                                     file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(table.timeJson, original.timeJson, file: file, line: line)
        XCTAssertEqual(table.nodesPerDay, original.nodesPerDay, file: file, line: line)
        XCTAssertEqual(table.smartConfigJson, original.smartConfigJson, file: file, line: line)
        XCTAssertEqual(table.preBindSnapshotJson, original.preBindSnapshotJson, file: file, line: line)
    }

    func testSyncPreservesPrivateTimesAndEditorStyleUnbindRestoresThem() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let (tableID, periodID) = try fixture(repo)
        let original = try XCTUnwrap(repo.getTable(tableID))
        var draft = try XCTUnwrap(repo.getPeriodTable(periodID))
        draft.timeJson = replacementJSON
        draft.nodesPerDay = 4
        draft.smartConfigJson = "new-shared-config"
        var edited = original.hydratedWith(draft)
        edited.name = "同步后的元数据"
        try repo.executeScheduleEditPolicy(editedTable: edited, draft: draft, policy: .sync)
        let saved = try XCTUnwrap(repo.getTable(tableID))
        assertPrivateFields(saved, match: original)
        XCTAssertEqual(saved.name, edited.name)
        XCTAssertEqual(try repo.getPeriodTable(periodID)?.timeJson, replacementJSON)
        XCTAssertEqual(try repo.getCourses(tableID).map(\.startNode), [1], "Sync keeps bindings to shared node numbers")

        // EditTableScreen's 'use this table's schedule' path submits the raw private fields.
        var own = saved
        own.name = "已恢复私人作息"
        try repo.updateTableMetadataAndBind(table: own, periodTableId: nil)
        let detached = try XCTUnwrap(repo.getTable(tableID))
        XCTAssertNil(detached.periodTableId)
        XCTAssertEqual(detached.timeJson, privateJSON)
        XCTAssertEqual(detached.nodesPerDay, 3)
        XCTAssertEqual(detached.smartConfigJson, "private-config")
        XCTAssertEqual(detached.preBindSnapshotJson, "")
    }

    func testCreateNewPreservesPrivateFieldsButRemapsToNewSharedTimesThenExplicitDetach() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let (tableID, periodID) = try fixture(repo)
        let original = try XCTUnwrap(repo.getTable(tableID))
        var draft = try XCTUnwrap(repo.getPeriodTable(periodID))
        draft.timeJson = replacementJSON
        draft.nodesPerDay = 4
        draft.smartConfigJson = "new-shared-config"
        var edited = original.hydratedWith(draft)
        edited.name = "新共享作息"
        try repo.executeScheduleEditPolicy(editedTable: edited, draft: draft, policy: .createNew)
        let saved = try XCTUnwrap(repo.getTable(tableID))
        assertPrivateFields(saved, match: original)
        XCTAssertNotEqual(saved.periodTableId, periodID)
        XCTAssertEqual(try repo.getPeriodTable(try XCTUnwrap(saved.periodTableId))?.timeJson, replacementJSON)
        XCTAssertEqual(try repo.getPeriodTable(periodID)?.timeJson, sharedJSON)
        XCTAssertEqual(try repo.getCourses(tableID).map(\.startNode), [3], "09:00 must map from old shared node 1 to new shared node 3")

        let privateDraft = PeriodTableEntity(name: "私人", nodesPerDay: saved.nodesPerDay,
                                              timeJson: saved.timeJson, smartConfigJson: saved.smartConfigJson)
        try repo.executeScheduleEditPolicy(editedTable: saved, draft: privateDraft, policy: .detachCopy)
        let detached = try XCTUnwrap(repo.getTable(tableID))
        XCTAssertNil(detached.periodTableId)
        XCTAssertEqual(detached.timeJson, privateJSON)
        XCTAssertEqual(detached.smartConfigJson, "private-config")
        XCTAssertEqual(detached.preBindSnapshotJson, "")
        XCTAssertEqual(try repo.getCourses(tableID).map(\.startNode), [2], "Detaching must read the actual new shared source, not the inactive private column")
    }

    func testCreatingFirstBindingSnapshotsPrivateTimesAndDirectUnbindRestoresThem() throws {
        let repo = ScheduleRepository(try AppDatabase.inMemory())
        let (tableID, _) = try fixture(repo, bound: false)
        let original = try XCTUnwrap(repo.getTable(tableID))
        let draft = PeriodTableEntity(name: "新作息", nodesPerDay: 4,
                                      timeJson: replacementJSON, smartConfigJson: "new-shared-config")
        let edited = original.hydratedWith(draft)
        try repo.executeScheduleEditPolicy(editedTable: edited, draft: draft, policy: .createNew)
        let saved = try XCTUnwrap(repo.getTable(tableID))
        XCTAssertEqual(saved.timeJson, privateJSON)
        XCTAssertEqual(saved.nodesPerDay, 3)
        XCTAssertEqual(saved.smartConfigJson, "private-config")
        XCTAssertFalse(saved.preBindSnapshotJson.isEmpty)
        XCTAssertEqual(try repo.getCourses(tableID).map(\.startNode), [2], "Unbound old node 1 is 08:00, which becomes shared node 2")
        try repo.bindPeriodTable(timeTableId: tableID, periodTableId: nil)
        let detached = try XCTUnwrap(repo.getTable(tableID))
        XCTAssertNil(detached.periodTableId)
        XCTAssertEqual(detached.timeJson, privateJSON)
        XCTAssertEqual(detached.nodesPerDay, 3)
        XCTAssertEqual(detached.smartConfigJson, "private-config")
        XCTAssertEqual(detached.preBindSnapshotJson, "")
    }
}
