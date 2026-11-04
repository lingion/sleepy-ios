import XCTest
@testable import Sleepy

final class QuickAddCourseTests: XCTestCase {
    private let rows: [QuickAddRow] = [
        .init(node: 0, top: 0, bottom: 24),
        .init(node: 1, top: 30, bottom: 78),
        .init(node: 2, top: 82, bottom: 130),
        // 占位及长课间已体现在实测行边界，不能用固定行高除法。
        .init(node: 3, top: 190, bottom: 270),
        .init(node: 4, top: 274, bottom: 322),
        .init(node: 5, top: 330, bottom: 350)
    ]

    func testBottomSnapsToMeasuredBoundaryAndKeepsTop() {
        let range = QuickAddRange(day: 4, startNode: 2, endNode: 2)
        let result = QuickAddCoursePolicy.resized(range, top: false, position: 269, rows: rows, maxStandard: 4)
        XCTAssertEqual(result, QuickAddRange(day: 4, startNode: 2, endNode: 3))
        XCTAssertEqual(result.step, 2)
    }

    func testTopSnapsIndependentlyAndCannotCrossBottom() {
        let range = QuickAddRange(day: 2, startNode: 2, endNode: 3)
        XCTAssertEqual(QuickAddCoursePolicy.resized(range, top: true, position: 31, rows: rows, maxStandard: 4),
                       QuickAddRange(day: 2, startNode: 1, endNode: 3))
        XCTAssertEqual(QuickAddCoursePolicy.resized(range, top: true, position: 999, rows: rows, maxStandard: 4),
                       QuickAddRange(day: 2, startNode: 3, endNode: 3))
        XCTAssertEqual(QuickAddCoursePolicy.resized(range, top: false, position: -999, rows: rows, maxStandard: 4),
                       QuickAddRange(day: 2, startNode: 2, endNode: 2))
    }

    func testStandardRangeCannotExpandIntoEdgePeriods() {
        let range = QuickAddRange(day: 7, startNode: 2, endNode: 3)
        XCTAssertEqual(QuickAddCoursePolicy.resized(range, top: true, position: -100, rows: rows, maxStandard: 4).startNode, 1)
        XCTAssertEqual(QuickAddCoursePolicy.resized(range, top: false, position: 999, rows: rows, maxStandard: 4).endNode, 4)
    }

    func testEdgePeriodsStaySingleSlot() {
        for node in [0, 5] {
            let range = QuickAddRange(day: 3, startNode: node, endNode: node)
            for top in [true, false] {
                for position: CGFloat in [-999, 999] {
                    XCTAssertEqual(QuickAddCoursePolicy.resized(range, top: top, position: position,
                        rows: rows, maxStandard: 4), range)
                }
            }
        }
    }

    func testMissingStandardNodeStopsExpansion() {
        let range = QuickAddRange(day: 5, startNode: 1, endNode: 1)
        XCTAssertEqual(QuickAddCoursePolicy.resized(range, top: false, position: 322,
            rows: rows.filter { $0.node != 2 }, maxStandard: 4), range)
    }

    @MainActor
    func testConfirmConsumesSelectionExactlyOnce() {
        let state = QuickAddCourseState()
        state.select(day: 6, node: 4)
        state.capsuleBounds = CGRect(x: 10, y: 20, width: 30, height: 40)
        var received: [QuickAddRange] = []
        state.confirm {
            XCTAssertNil(state.selection)
            XCTAssertNil(state.capsuleBounds)
            received.append($0)
        }
        state.confirm { received.append($0) }
        XCTAssertEqual(received, [QuickAddRange(day: 6, startNode: 4, endNode: 4)])
    }

    @MainActor
    func testOutsideShieldPassesCapsuleAndOwnsOutsideHit() {
        let state = QuickAddCourseState()
        let view = QuickAddOutsidePressView(frame: CGRect(x: 0, y: 0, width: 300, height: 600))
        view.state = state
        state.select(day: 2, node: 3)
        state.capsuleBounds = CGRect(x: 100, y: 100, width: 50, height: 80)
        XCTAssertNil(view.hitTest(CGPoint(x: 120, y: 120), with: nil))
        XCTAssertTrue(view.hitTest(CGPoint(x: 20, y: 120), with: nil) === view)
        XCTAssertNil(view.hitTest(CGPoint(x: -1, y: 120), with: nil))
        state.dismiss()
        XCTAssertNil(view.hitTest(CGPoint(x: 20, y: 120), with: nil))
        XCTAssertNil(state.capsuleBounds)
    }
}
