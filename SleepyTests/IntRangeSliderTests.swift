import XCTest
import UIKit
@testable import Sleepy

final class IntRangeSliderTests: XCTestCase {
    func testMovingEitherEndpointCannotCrossOrEscapeDomain() {
        let range = IntSliderRange(start: 3, end: 6, minimum: 1, maximum: 12)
        XCTAssertEqual(range.movingStart(to: 10, minimum: 1), IntSliderRange(start: 6, end: 6, minimum: 1, maximum: 12))
        XCTAssertEqual(range.movingStart(to: -2, minimum: 1).start, 1)
        XCTAssertEqual(range.movingEnd(to: 1, maximum: 12), IntSliderRange(start: 3, end: 3, minimum: 1, maximum: 12))
        XCTAssertEqual(range.movingEnd(to: 20, maximum: 12).end, 12)
    }

    func testGhostRequiresBothOpeningValuesAndDisappearsWhenRestored() {
        let range = IntSliderRange(start: 4, end: 8, minimum: 1, maximum: 16)
        XCTAssertNil(IntSliderRange.ghost(current: range, initialStart: nil, initialEnd: 8, minimum: 1, maximum: 16))
        XCTAssertNil(IntSliderRange.ghost(current: range, initialStart: 4, initialEnd: nil, minimum: 1, maximum: 16))
        XCTAssertNil(IntSliderRange.ghost(current: range, initialStart: 4, initialEnd: 8, minimum: 1, maximum: 16))
        XCTAssertEqual(IntSliderRange.ghost(current: range, initialStart: 2, initialEnd: 6, minimum: 1, maximum: 16),
                       IntSliderRange(start: 2, end: 6, minimum: 1, maximum: 16))
    }

    func testDisplayAndGhostShareClampingForDirtyImportedValues() {
        let shown = IntSliderRange(start: -3, end: 28, minimum: 1, maximum: 12)
        XCTAssertEqual(shown.start, 1)
        XCTAssertEqual(shown.end, 12)
        XCTAssertNil(IntSliderRange.ghost(current: shown, initialStart: -3, initialEnd: 28, minimum: 1, maximum: 12))
        let inverted = IntSliderRange(start: 8, end: 2, minimum: 1, maximum: 12)
        XCTAssertEqual(inverted.start, 8)
        XCTAssertEqual(inverted.end, 8)
    }

    func testOneStopDomainAlwaysShowsItsOnlyValue() {
        let range = IntSliderRange(start: 8, end: 20, minimum: 1, maximum: 1)
        XCTAssertEqual(range.start, 1)
        XCTAssertEqual(range.end, 1)
        XCTAssertNil(IntSliderRange.ghost(current: range, initialStart: 2, initialEnd: 4, minimum: 1, maximum: 1))
    }

    @MainActor
    func testNativeEndpointStopsAtItsPeerWithoutRescalingItsTrack() {
        let slider = BaselineInputSlider(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        slider.minimumValue = 1
        slider.maximumValue = 12
        slider.allowedRange = 1...6
        slider.step = 1
        XCTAssertEqual(slider.constrainedValue(5.6), 6)
        XCTAssertEqual(slider.constrainedValue(9), 6)
        XCTAssertEqual(slider.constrainedValue(-5), 1)
        slider.value = 6
        slider.accessibilityIncrement()
        XCTAssertEqual(slider.value, 6)
        XCTAssertEqual(slider.minimumValue, 1)
        XCTAssertEqual(slider.maximumValue, 12)
        XCTAssertNil(slider.thumbImage(for: .normal))
        XCTAssertNil(slider.thumbImage(for: .highlighted))

        slider.allowedRange = 6...12
        slider.accessibilityDecrement()
        XCTAssertEqual(slider.value, 6)
        XCTAssertEqual(slider.constrainedValue(1), 6)
        XCTAssertEqual(slider.constrainedValue(11.6), 12)
        XCTAssertEqual(slider.minimumValue, 1)
        XCTAssertEqual(slider.maximumValue, 12)
    }

    @MainActor
    func testNativeEndpointAccessibilityUsesSingleInclusiveStepsAndHonorsDisabledState() {
        let slider = BaselineInputSlider()
        slider.minimumValue = 1
        slider.maximumValue = 30
        slider.allowedRange = 4...8
        slider.step = 1
        slider.value = 4
        slider.accessibilityIncrement()
        XCTAssertEqual(slider.value, 5)
        slider.accessibilityDecrement()
        XCTAssertEqual(slider.value, 4)
        slider.accessibilityDecrement()
        XCTAssertEqual(slider.value, 4)
        for _ in 0..<10 { slider.accessibilityIncrement() }
        XCTAssertEqual(slider.value, 8)
        slider.isEnabled = false
        slider.accessibilityDecrement()
        XCTAssertEqual(slider.value, 8)
        XCTAssertEqual(slider.constrainedValue(.nan), 4)
    }

    func testCoincidentThumbsWaitForDirectionEvenWhenTouchStartsOffCenter() {
        XCTAssertNil(IntSliderRange.thumb(at: 105, startX: 100, endX: 100, translation: 0, rightToLeft: false))
        XCTAssertEqual(IntSliderRange.thumb(at: 105, startX: 100, endX: 100, translation: -20, rightToLeft: false), .start)
        XCTAssertEqual(IntSliderRange.thumb(at: 95, startX: 100, endX: 100, translation: 20, rightToLeft: false), .end)
        XCTAssertEqual(IntSliderRange.thumb(at: 105, startX: 100, endX: 100, translation: 20, rightToLeft: true), .start)
        XCTAssertEqual(IntSliderRange.thumb(at: 95, startX: 100, endX: 100, translation: -20, rightToLeft: true), .end)
    }

    func testExistingCourseOpeningRangesSurviveDraftChanges() {
        let course = CourseEntity(groupId: "edit", tableId: 1, courseName: "Math", day: 2,
            startNode: 3, step: 2, startWeek: 4, endWeek: 12, color: "#FF6750A4")
        var block = AddCourseScreen.initialMeetingBlock(course)
        block.startNode = 7
        block.step = 1
        block.startWeek = 6
        block.endWeek = 10
        XCTAssertEqual(block.initialStartNode, 3)
        XCTAssertEqual(block.initialStep, 2)
        XCTAssertEqual(block.initialStartWeek, 4)
        XCTAssertEqual(block.initialEndWeek, 12)
    }

    func testNewAndQuickAddBlocksDoNotInventGhostBaselines() throws {
        let plain = AddCourseScreen.initialMeetingBlock(nil)
        XCTAssertNil(plain.initialStartNode)
        XCTAssertNil(plain.initialStep)
        XCTAssertNil(plain.initialStartWeek)
        XCTAssertNil(plain.initialEndWeek)
        let table = TimeTableEntity(name: "Schedule", startDate: "2026-11-02", maxWeek: 16,
            nodesPerDay: 12, timeJson: TimeTableUtils.DEFAULT_TIME_JSON, id: 7)
        let slot = CourseAddSlot(tableId: 7, week: 3, day: 2, node: 4, step: 2)
        let quick = try XCTUnwrap(AddCourseScreen.quickAddMeetingBlock(slot, table: table))
        XCTAssertNil(quick.initialStartNode)
        XCTAssertNil(quick.initialStep)
        XCTAssertNil(quick.initialStartWeek)
        XCTAssertNil(quick.initialEndWeek)
    }
    func testContinuousSliderEndpointsAndFilledRangeUsePhysicalCoordinatesInRTL() {
        for rtl in [false, true] {
            let track = SliderTrackGeometry(range: 0...100, containerWidth: 200, inset: 14,
                                            rightToLeft: rtl)
            XCTAssertEqual(track.position(0), rtl ? 186 : 14)
            XCTAssertEqual(track.position(50), 100)
            XCTAssertEqual(track.position(100), rtl ? 14 : 186)
            let active = track.activeRange(to: 25)
            XCTAssertEqual(active.lowerBound, rtl ? 143 : 14)
            XCTAssertEqual(active.upperBound, rtl ? 186 : 57)
            XCTAssertEqual(active.upperBound - active.lowerBound, 43)
            XCTAssertEqual(track.value(at: track.position(25)), 25, accuracy: 0.0001)
        }
    }

    func testHueThumbAndBaselineKeepTheSamePhysicalValueMapping() {
        for rtl in [false, true] {
            let track = SliderTrackGeometry(range: 0...360, containerWidth: 200,
                                            rightToLeft: rtl)
            XCTAssertEqual(track.position(0), rtl ? 200 : 0)
            XCTAssertEqual(track.position(180), 100)
            XCTAssertEqual(track.position(360), rtl ? 0 : 200)
            XCTAssertEqual(track.value(at: track.position(120)), 120, accuracy: 0.0001)
            XCTAssertEqual(track.position(480), track.position(360))
            XCTAssertEqual(track.position(-120), track.position(0))
        }
    }

    func testContinuousSliderCoordinatesStayInsideNarrowAndNormalTracks() {
        for width: CGFloat in [0, 20, 28, 44, 110, 328] {
            for inset: CGFloat in [0, 14] {
                for rtl in [false, true] {
                    for range in [(-12.0)...12, 0.0...360, 0.5...2] {
                        let track = SliderTrackGeometry(range: range, containerWidth: width,
                                                        inset: inset, rightToLeft: rtl)
                        for value in [range.lowerBound, range.lowerBound +
                                      (range.upperBound - range.lowerBound) * 0.25,
                                      (range.lowerBound + range.upperBound) / 2, range.upperBound] {
                            let x = track.position(value)
                            XCTAssertGreaterThanOrEqual(x, 0)
                            XCTAssertLessThanOrEqual(x, width)
                            let fill = track.activeRange(to: value)
                            XCTAssertGreaterThanOrEqual(fill.lowerBound, track.lowerX)
                            XCTAssertLessThanOrEqual(fill.upperBound, track.upperX)
                            if track.width > 0 {
                                XCTAssertEqual(track.value(at: x), value, accuracy: 0.0001)
                            }
                        }
                    }
                }
            }
        }
    }

}
