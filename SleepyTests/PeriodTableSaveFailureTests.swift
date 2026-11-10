import XCTest
import GRDB
@testable import Sleepy

final class PeriodTableSaveFailureTests: XCTestCase {
    @MainActor
    func testSharedPeriodFailureRetainsDraftAndOnlyFinishesAfterRetry() throws {
        let history = Sleepy.UndoManager.shared
        history.clear()
        defer { history.clear() }
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let id = try repo.insertPeriodTable(PeriodTableEntity(name: "原作息"))
        let original = try XCTUnwrap(repo.getPeriodTable(id))
        var draft = original
        draft.name = "未保存草稿"
        draft.timeJson = #"[{"node":1,"start":"09:00","end":"09:45"}]"#
        let vm = ScheduleViewModel(repo: repo)
        var finished = false
        var message: String?
        try db.dbQueue.write {
            try $0.execute(sql: "CREATE TRIGGER reject_period BEFORE UPDATE ON period_tables BEGIN SELECT RAISE(ABORT, 'injected'); END;")
        }
        XCTAssertFalse(vm.updatePeriodTableContent(draft, onFinish: { finished = true }, onFailure: { message = $0 }))
        XCTAssertFalse(finished)
        XCTAssertEqual(message, L10n.format("table_reminder_save_failed"))
        XCTAssertEqual(try repo.getPeriodTable(id), original)
        XCTAssertEqual(draft.name, "未保存草稿")
        try db.dbQueue.write { try $0.execute(sql: "DROP TRIGGER reject_period") }
        XCTAssertTrue(vm.updatePeriodTableContent(draft, onFinish: { finished = true }))
        XCTAssertTrue(finished)
        XCTAssertEqual(try repo.getPeriodTable(id)?.name, draft.name)
    }

    @MainActor
    func testDeletedSaveTargetsCannotReportSuccess() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let vm = ScheduleViewModel(repo: repo)
        var deletedPeriod = PeriodTableEntity(name: "已删除")
        deletedPeriod.id = 987
        var deletedTable = TimeTableEntity(name: "已删除", startDate: "2026-11-02")
        deletedTable.id = 654
        var finished = 0
        XCTAssertFalse(vm.updatePeriodTableContent(deletedPeriod, onFinish: { finished += 1 }))
        XCTAssertFalse(vm.updateTableMetadata(deletedTable, onFinish: { finished += 1 }))
        XCTAssertFalse(vm.bindPeriodTable(timeTableId: deletedTable.id, periodTableId: nil,
                                          onFinish: { finished += 1 }))
        XCTAssertEqual(finished, 0)
        XCTAssertNotNil(vm.state.error)
    }
}
