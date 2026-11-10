import XCTest
import Combine
@testable import Sleepy

final class ScheduleEditSessionTargetTests: XCTestCase {
    @MainActor
    func testNonselectedBoundTableStartsAndCancelsWithItsOwnActualSchedule() async throws {
        let history = Sleepy.UndoManager.shared
        let previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(0)
        defer { history.clear(); history.applyMaxDepth(previousDepth) }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let selectedTime = #"[{"node":1,"start":"08:00","end":"08:45"}]"#
        let editedTime = #"[{"node":1,"start":"10:00","end":"10:45"},{"node":2,"start":"11:00","end":"11:45"}]"#
        let selectedPeriod = try repo.insertPeriodTable(PeriodTableEntity(name: "主界面作息", nodesPerDay: 1, timeJson: selectedTime))
        let editedPeriod = try repo.insertPeriodTable(PeriodTableEntity(name: "编辑目标作息", nodesPerDay: 2, timeJson: editedTime))
        let selected = try repo.insertTable(TimeTableEntity(name: "主界面", startDate: "2026-09-07", isDefault: true))
        let edited = try repo.insertTable(TimeTableEntity(name: "编辑目标", startDate: "2026-09-07"))
        try repo.bindPeriodTable(timeTableId: selected, periodTableId: selectedPeriod)
        try repo.bindPeriodTable(timeTableId: edited, periodTableId: editedPeriod)
        let selectedOriginal = try XCTUnwrap(repo.getPeriodTable(selectedPeriod))
        let editedOriginal = try XCTUnwrap(repo.getPeriodTable(editedPeriod))
        let viewModel = ScheduleViewModel(repo: repo)
        let ready = expectation(description: "The selected table and its different bound schedule have loaded")
        let observation = viewModel.$state.filter {
            $0.selectedTableId == selected && $0.effectivePeriodTable?.id == selectedPeriod
        }.prefix(1).sink { _ in ready.fulfill() }
        defer { observation.cancel() }
        await fulfillment(of: [ready], timeout: 3)

        // Exercise the exact production session entry, with a genuine selected
        // table snapshot present to catch accidentally borrowing that snapshot.
        let session = try viewModel.startEditSessionForEditing(tableId: edited)
        XCTAssertEqual(session.tableId, edited)
        XCTAssertEqual(session.draftEffectiveSchedule, editedOriginal)
        XCTAssertFalse(session.hasScheduleChanged())
        var draft = editedOriginal
        draft.timeJson = #"[{"node":1,"start":"12:00","end":"12:45"}]"#
        session.updateDraft(draft)
        session.selectPolicy(.detachCopy)
        XCTAssertTrue(session.hasScheduleChanged())
        XCTAssertTrue(viewModel.hasPendingPolicy(tableId: edited))
        session.cancelPolicy()
        XCTAssertEqual(session.draftEffectiveSchedule, editedOriginal)
        XCTAssertFalse(session.hasScheduleChanged())
        XCTAssertFalse(viewModel.hasPendingPolicy(tableId: edited))

        XCTAssertEqual(viewModel.state.selectedTableId, selected)
        XCTAssertEqual(viewModel.state.effectivePeriodTable, selectedOriginal)
        XCTAssertEqual(try repo.getPeriodTable(selectedPeriod), selectedOriginal)
        XCTAssertEqual(try repo.getPeriodTable(editedPeriod), editedOriginal)
        XCTAssertEqual(try repo.getTable(selected)?.periodTableId, selectedPeriod)
        XCTAssertEqual(try repo.getTable(edited)?.periodTableId, editedPeriod)
        XCTAssertFalse(history.hasSnapshot)
    }

    @MainActor
    func testUnboundAndMissingExplicitTargetsCannotInheritAnotherSession() throws {
        let history = Sleepy.UndoManager.shared
        let previousDepth = history.maxDepth
        history.clear()
        history.applyMaxDepth(0)
        defer { history.clear(); history.applyMaxDepth(previousDepth) }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let table = try repo.insertTable(TimeTableEntity(name: "未绑定", startDate: "2026-09-07"))
        let viewModel = ScheduleViewModel(repo: repo)
        viewModel.startEditSession(tableId: table, originalEffectiveSchedule: PeriodTableEntity(name: "旧会话"))
        let session = try viewModel.startEditSessionForEditing(tableId: table)
        XCTAssertNil(session.draftEffectiveSchedule)
        XCTAssertFalse(session.hasScheduleChanged())
        XCTAssertThrowsError(try viewModel.startEditSessionForEditing(tableId: Int64.max))
    }
}
