import XCTest
@testable import Sleepy

final class PinchAnchor1064Tests: XCTestCase {
    func testSemesterPagerKeepsOnlyNeighborsAndTheActiveDragHost() {
        let semester = Array(1...366)
        for selected in semester {
            let ready = semester.filter {
                TimetableViewportPolicy.shouldRenderWeek($0, selectedWeek: selected, dragHostWeek: nil)
            }
            XCTAssertTrue(ready.contains(selected))
            XCTAssertLessThanOrEqual(ready.count, 3)
            for host in [1, 183, 366] {
                let pinned = semester.filter {
                    TimetableViewportPolicy.shouldRenderWeek($0, selectedWeek: selected, dragHostWeek: host)
                }
                XCTAssertEqual(Set(pinned), Set(ready + [host]))
                XCTAssertLessThanOrEqual(pinned.count, 4)
            }
        }
        XCTAssertFalse(TimetableViewportPolicy.shouldRenderWeek(0, selectedWeek: 1, dragHostWeek: 0))
        XCTAssertFalse(TimetableViewportPolicy.shouldRenderWeek(1, selectedWeek: 0, dragHostWeek: nil))
    }

    private let weights: [CGFloat] = [1, 0.36, 1, 1, 1.5, 1, 1, 1, 1, 1, 1, 1]
    private let breaks = [3, 7]

    func testWeightedRowsAndMealBandsKeepIndependentGeometry() {
        XCTAssertEqual(TimetableViewportPolicy.weightedRowsAbove(2.5, weights: weights), 1.86, accuracy: 0.00001)
        XCTAssertEqual(TimetableViewportPolicy.crossedMealBreaks(3.99, breakRows: breaks), 0)
        XCTAssertEqual(TimetableViewportPolicy.crossedMealBreaks(4, breakRows: breaks), 1)
        XCTAssertEqual(TimetableViewportPolicy.crossedMealBreaks(8.5, breakRows: breaks), 2)
        XCTAssertEqual(TimetableViewportPolicy.weightedRowsAbove(30, weights: weights), weights.reduce(0, +))
    }

    func testInverseMatchesRealWeightedGridAcrossHeightsAndBandPositions() {
        for height: CGFloat in [25.2, 36, 52, 72, 124.8] {
            for gap: CGFloat in [0, 24, 48] {
                for index in weights.indices {
                    for fraction: CGFloat in [0.1, 0.5, 0.99] {
                        let row = CGFloat(index) + fraction
                        let bodyY = height * TimetableViewportPolicy.weightedRowsAbove(row, weights: weights)
                            + gap * CGFloat(TimetableViewportPolicy.crossedMealBreaks(row, breakRows: breaks))
                        XCTAssertEqual(TimetableViewportPolicy.rowCoordinateFromBodyY(bodyY, rowPx: height,
                            mealGapExtraPx: gap, breakRows: breaks, weights: weights), row, accuracy: 0.00001)
                    }
                }
            }
        }
    }

    func testPointsInsideMealBandsResolveToSharedBoundary() {
        let before = TimetableViewportPolicy.weightedRowsAbove(4, weights: weights) * 52
        for offset: CGFloat in [1, 12, 23] {
            XCTAssertEqual(TimetableViewportPolicy.rowCoordinateFromBodyY(before + offset, rowPx: 52,
                mealGapExtraPx: 24, breakRows: breaks, weights: weights), 4, accuracy: 0.00001)
        }
    }

    func testCenterContentStaysAtSameViewportYThroughGrowingAndShrinking() {
        let startScroll: CGFloat = 210, center: CGFloat = 360, header: CGFloat = 68
        let anchor = TimetableViewportPolicy.capturePinchAnchor(scrollPx: startScroll, centerYPx: center,
            headerPx: header, rowPx: 52, mealGapExtraPx: 24, breakRows: breaks, weights: weights)
        for newHeight: CGFloat in [36, 60, 80, 96] {
            let target = TimetableViewportPolicy.pinchTargetScrollPx(anchor, rowPx0: 52, rowPx1: newHeight)
            let newContentY = startScroll + center + anchor.weightedRowsAbove * (newHeight - 52)
            XCTAssertEqual(newContentY - target, center, accuracy: 0.00001)
        }
    }

    func testAbsoluteTargetRecoversAfterOldScrollLimitClipsAnEarlierFrame() {
        let anchor = TimetableViewportPolicy.PinchAnchor(startScrollPx: 200, weightedRowsAbove: 7.5)
        let target = TimetableViewportPolicy.pinchTargetScrollPx(anchor, rowPx0: 52, rowPx1: 80)
        XCTAssertEqual(target, 410)
        let oldMaximum: CGFloat = 250
        XCTAssertEqual(min(target, oldMaximum), 250)
        XCTAssertEqual(TimetableViewportPolicy.pinchTargetScrollPx(anchor, rowPx0: 52, rowPx1: 80), 410)
    }

    func testHeaderAndMalformedEmptyGeometryUseTopAnchor() {
        for weights: [CGFloat] in [[], self.weights] {
            let anchor = TimetableViewportPolicy.capturePinchAnchor(scrollPx: 0, centerYPx: 30,
                headerPx: 68, rowPx: 52, mealGapExtraPx: 24, breakRows: breaks, weights: weights)
            XCTAssertEqual(anchor.weightedRowsAbove, 0)
            XCTAssertEqual(TimetableViewportPolicy.pinchTargetScrollPx(anchor, rowPx0: 52, rowPx1: 96), 0)
        }
        XCTAssertEqual(TimetableViewportPolicy.rowCoordinateFromBodyY(500, rowPx: 0,
            mealGapExtraPx: 24, breakRows: breaks, weights: weights), 0)
        XCTAssertEqual(TimetableViewportPolicy.rowCoordinateFromBodyY(100_000, rowPx: 52,
            mealGapExtraPx: 24, breakRows: breaks, weights: weights), CGFloat(weights.count))
        XCTAssertEqual(TimetableViewportPolicy.pinchTargetScrollPx(.init(startScrollPx: 0, weightedRowsAbove: 4),
            rowPx0: 52, rowPx1: 36), 0)
    }
}
