import XCTest
@testable import Sleepy

final class JwImportLifecycleTests: XCTestCase {
    private let snapshot = JwImportDraftSnapshot(
        school: JwSchoolInfo(sortKey: "T", name: "Test school"),
        courses: [JwCourse(name: "Math", day: 1, startNode: 1, endNode: 2, startWeek: 1, endWeek: 16)],
        periods: [], tableName: "Parsed snapshot")

    func testNewParseAndFlowExitRejectEarlierAsyncReplies() {
        var lifecycle = JwImportParseLifecycle()
        let old = lifecycle.beginParse()
        let current = lifecycle.beginParse()
        XCTAssertFalse(lifecycle.accepts(old, didFinishFlow: false))
        XCTAssertTrue(lifecycle.accepts(current, didFinishFlow: false))
        XCTAssertFalse(lifecycle.accepts(current, didFinishFlow: true))
        lifecycle.invalidate()
        XCTAssertFalse(lifecycle.accepts(current, didFinishFlow: false))
    }

    func testDeleteDraftRemovesAnAutosaveThatCompletesAfterExit() throws {
        let repository = ImportDraftRepository(try AppDatabase.inMemory())
        var lifecycle = JwImportParseLifecycle()
        let epoch = lifecycle.beginParse()
        lifecycle.invalidate(keepingDraft: false)
        let lateId = try repository.save(snapshot)
        XCTAssertFalse(lifecycle.accepts(epoch, didFinishFlow: true))
        XCTAssertTrue(lifecycle.shouldDeleteLateSave(lateId, retainedDraftId: nil))
        if lifecycle.shouldDeleteLateSave(lateId, retainedDraftId: nil) {
            try repository.delete(lateId)
        }
        XCTAssertTrue(try repository.getAll().isEmpty)
    }

    func testKeepDraftRetainsLatestSnapshotAndRemovesOnlyTheDiscardedAutosave() throws {
        let repository = ImportDraftRepository(try AppDatabase.inMemory())
        var lifecycle = JwImportParseLifecycle()
        _ = lifecycle.beginParse()
        var latest = snapshot
        latest.tableName = "Kept user changes"
        let keptId = try repository.save(latest)
        lifecycle.invalidate(keepingDraft: true)
        let lateId = try repository.save(snapshot)
        XCTAssertFalse(lifecycle.shouldDeleteLateSave(keptId, retainedDraftId: keptId))
        XCTAssertTrue(lifecycle.shouldDeleteLateSave(lateId, retainedDraftId: keptId))
        if lifecycle.shouldDeleteLateSave(lateId, retainedDraftId: keptId) {
            try repository.delete(lateId)
        }
        XCTAssertEqual(try repository.getAll().map(\.id), [keptId])
        XCTAssertEqual(try repository.get(keptId), latest)
    }

    func testKeepDraftFallsBackToPendingAutosaveIfItsExplicitSaveFailed() {
        var lifecycle = JwImportParseLifecycle()
        _ = lifecycle.beginParse()
        lifecycle.invalidate(keepingDraft: true)
        XCTAssertFalse(lifecycle.shouldDeleteLateSave("pending-save", retainedDraftId: nil))
    }

    func testSupersededParseDiscardsItsUnadoptedAutosave() {
        var lifecycle = JwImportParseLifecycle()
        let old = lifecycle.beginParse()
        _ = lifecycle.beginParse()
        XCTAssertFalse(lifecycle.accepts(old, didFinishFlow: false))
        XCTAssertTrue(lifecycle.shouldDeleteLateSave("old-save", retainedDraftId: "current-save"))
    }
}
