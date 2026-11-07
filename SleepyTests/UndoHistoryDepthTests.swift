import XCTest
@testable import Sleepy

final class UndoHistoryDepthTests: XCTestCase {
    private func snapshot(_ id: Int64) -> UndoSnapshot {
        UndoSnapshot(tables: [], courses: [], defaultTableId: id)
    }

    private func capture(_ id: Int64, in history: Sleepy.UndoManager) {
        history.capture(tables: [], courses: [], defaultTableId: id)
    }

    func testDefaultDepthRetainsNewestFiveSteps() {
        let history = Sleepy.UndoManager()
        XCTAssertEqual(history.maxDepth, 5)
        for id in 1...8 { capture(Int64(id), in: history) }
        for id in stride(from: 8, through: 4, by: -1) {
            XCTAssertEqual(history.poll()?.defaultTableId, Int64(id))
        }
        XCTAssertNil(history.poll())
        XCTAssertFalse(history.hasSnapshot)
    }

    func testUndoRedoRoundTripPreservesThreeIndependentSteps() throws {
        let history = Sleepy.UndoManager()
        for id in 0...2 { capture(Int64(id), in: history) }
        var current = snapshot(3)
        for expected in [2, 1, 0] {
            let target = try XCTUnwrap(history.poll())
            history.recordRedo(current)
            current = target
            XCTAssertEqual(current.defaultTableId, Int64(expected))
        }
        XCTAssertFalse(history.hasSnapshot)
        for expected in [1, 2, 3] {
            let target = try XCTUnwrap(history.pollRedo())
            history.reinsertForRedoSymmetry(current)
            current = target
            XCTAssertEqual(current.defaultTableId, Int64(expected))
        }
        XCTAssertFalse(history.hasRedoSnapshot)
        XCTAssertEqual(history.poll()?.defaultTableId, 2)
        XCTAssertEqual(history.poll()?.defaultTableId, 1)
        XCTAssertEqual(history.poll()?.defaultTableId, 0)
        XCTAssertNil(history.poll())
    }

    func testDepthShrinkImmediatelyTrimsBothStacksAndGrowthDoesNotResurrectHistory() {
        let history = Sleepy.UndoManager(maxDepth: -1)
        for id in 1...6 { capture(Int64(id), in: history) }
        for id in 10...15 { history.recordRedo(snapshot(Int64(id))) }
        history.applyMaxDepth(2)
        history.maxDepth = 20
        XCTAssertEqual(history.poll()?.defaultTableId, 6)
        XCTAssertEqual(history.poll()?.defaultTableId, 5)
        XCTAssertNil(history.poll())
        XCTAssertEqual(history.pollRedo()?.defaultTableId, 15)
        XCTAssertEqual(history.pollRedo()?.defaultTableId, 14)
        XCTAssertNil(history.pollRedo())
    }

    func testZeroClearsBothStacksAndRejectsEveryInsertionPath() {
        let history = Sleepy.UndoManager()
        capture(1, in: history)
        history.recordRedo(snapshot(2))
        history.applyMaxDepth(0)
        capture(3, in: history)
        history.recordRedo(snapshot(4))
        history.reinsertForRedoSymmetry(snapshot(5))
        XCTAssertFalse(history.hasSnapshot)
        XCTAssertFalse(history.hasRedoSnapshot)
        XCTAssertNil(history.poll())
        XCTAssertNil(history.pollRedo())
        history.applyMaxDepth(5)
        XCTAssertNil(history.poll(), "重新开启不能复活已清空的历史")
        capture(6, in: history)
        XCTAssertEqual(history.poll()?.defaultTableId, 6)
    }

    func testEveryNegativeDepthIsUnlimitedForBothStacks() {
        for depth in [-1, -17, Int.min] {
            let history = Sleepy.UndoManager(maxDepth: depth)
            for id in 1...30 { capture(Int64(id), in: history) }
            for id in 31...60 { history.recordRedo(snapshot(Int64(id))) }
            for id in stride(from: 30, through: 1, by: -1) {
                XCTAssertEqual(history.poll()?.defaultTableId, Int64(id))
            }
            for id in stride(from: 60, through: 31, by: -1) {
                XCTAssertEqual(history.pollRedo()?.defaultTableId, Int64(id))
            }
            XCTAssertNil(history.poll())
            XCTAssertNil(history.pollRedo())
        }
    }

    func testNestedBatchRecordsOnlyOuterFirstCaptureAndKeepsPreviousAction() {
        let history = Sleepy.UndoManager()
        capture(1, in: history)
        history.beginBatch()
        capture(2, in: history)
        history.beginBatch()
        capture(3, in: history)
        history.endBatch()
        capture(4, in: history)
        history.endBatch()
        history.beginBatch()
        capture(5, in: history)
        history.endBatch()
        XCTAssertEqual(history.poll()?.defaultTableId, 5)
        XCTAssertEqual(history.poll()?.defaultTableId, 2)
        XCTAssertEqual(history.poll()?.defaultTableId, 1)
        XCTAssertNil(history.poll())
    }

    func testEmptyBatchPreservesRedoAndFirstNewWriteClearsEntireRedoBranch() {
        let history = Sleepy.UndoManager()
        capture(1, in: history)
        history.recordRedo(snapshot(2))
        history.recordRedo(snapshot(3))
        history.beginBatch()
        history.endBatch()
        XCTAssertTrue(history.hasRedoSnapshot)
        history.beginBatch()
        capture(4, in: history)
        capture(5, in: history)
        history.endBatch()
        XCTAssertNil(history.pollRedo())
        XCTAssertEqual(history.poll()?.defaultTableId, 4)
        XCTAssertEqual(history.poll()?.defaultTableId, 1)
        XCTAssertNil(history.poll())
    }

    func testRestoringSuppressesCaptureWithoutClearingRedoOrConsumingBatchAnchor() {
        let history = Sleepy.UndoManager()
        capture(1, in: history)
        history.recordRedo(snapshot(2))
        history.beginBatch()
        history.restoring = true
        capture(3, in: history)
        XCTAssertEqual(history.pollRedo()?.defaultTableId, 2)
        history.restoring = false
        capture(4, in: history)
        history.endBatch()
        XCTAssertEqual(history.poll()?.defaultTableId, 4)
        XCTAssertEqual(history.poll()?.defaultTableId, 1)
        XCTAssertNil(history.poll())
    }

    func testFailedRestoreReinsertionPreservesOlderHistoryAndOppositeStack() throws {
        let history = Sleepy.UndoManager(maxDepth: 2)
        capture(1, in: history)
        capture(2, in: history)
        history.recordRedo(snapshot(3))
        history.recordRedo(snapshot(4))
        let undo = try XCTUnwrap(history.poll())
        history.reinsertForRedoSymmetry(undo)
        let redo = try XCTUnwrap(history.pollRedo())
        history.recordRedo(redo)
        XCTAssertEqual(history.poll()?.defaultTableId, 2)
        XCTAssertEqual(history.poll()?.defaultTableId, 1)
        XCTAssertNil(history.poll())
        XCTAssertEqual(history.pollRedo()?.defaultTableId, 4)
        XCTAssertEqual(history.pollRedo()?.defaultTableId, 3)
        XCTAssertNil(history.pollRedo())
    }

    func testRedoAndSymmetryInsertionRespectPositiveCap() {
        let history = Sleepy.UndoManager(maxDepth: 2)
        for id in 1...4 {
            history.reinsertForRedoSymmetry(snapshot(Int64(id)))
            history.recordRedo(snapshot(Int64(id + 10)))
        }
        XCTAssertEqual(history.poll()?.defaultTableId, 4)
        XCTAssertEqual(history.poll()?.defaultTableId, 3)
        XCTAssertNil(history.poll())
        XCTAssertEqual(history.pollRedo()?.defaultTableId, 14)
        XCTAssertEqual(history.pollRedo()?.defaultTableId, 13)
        XCTAssertNil(history.pollRedo())
    }
}
