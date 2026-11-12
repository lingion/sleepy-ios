import XCTest
@testable import Sleepy

final class ScheduleToolbarGeometryTests: XCTestCase {
    func testToolbarKeepsCenterAndAllThreeGroupsSeparatedAcrossWindowSizes() {
        for width in stride(from: CGFloat(109), through: 1024, by: 3) {
            for textWidth: CGFloat in [40, 70, 140] {
                for history in [false, true] { for confirm in [false, true] {
                    let plan = ScheduleToolbarGeometry.resolve(width: width, fullCenterWidth: 140 + textWidth,
                        groupedCenterWidth: 98, history: history, confirm: confirm)
                    let leftEnd = plan.inset + plan.startWidth * plan.fitScale
                    let rightStart = width - plan.inset - plan.endWidth * plan.fitScale
                    let centerStart = (width - plan.centerWidth * plan.fitScale) / 2
                    let centerEnd = (width + plan.centerWidth * plan.fitScale) / 2
                    XCTAssertLessThanOrEqual(leftEnd, centerStart)
                    XCTAssertGreaterThanOrEqual(rightStart, centerEnd)
                    XCTAssertEqual((centerStart + centerEnd) / 2, width / 2, accuracy: 0.001)
                    XCTAssertGreaterThan(plan.height, 0)
                    XCTAssertGreaterThanOrEqual(plan.sideScale, 2 / 3)
                } }
            }
        }
    }
    func testFullWeekLabelHasPriorityOverSideSpacingAndScale() {
        let plan = ScheduleToolbarGeometry.resolve(width: 360, fullCenterWidth: 188, groupedCenterWidth: 98, history: true, confirm: false)
        XCTAssertFalse(plan.grouped)
        XCTAssertLessThan(plan.sideScale, 1)
        let narrow = ScheduleToolbarGeometry.resolve(width: 280, fullCenterWidth: 220, groupedCenterWidth: 98, history: true, confirm: true)
        XCTAssertTrue(narrow.grouped)
        XCTAssertLessThan(narrow.fitScale, 1)
    }

    func testOrdinaryPhoneUsesMarginsBeforeShorteningWeekLabel() {
        let plan = ScheduleToolbarGeometry.resolve(width: 390, fullCenterWidth: 188,
            groupedCenterWidth: 98, history: false, confirm: false)
        XCTAssertFalse(plan.grouped)
        XCTAssertEqual(plan.inset, 4)
        XCTAssertEqual(plan.gap, 0)
        XCTAssertEqual(plan.sideGap, 0)
        XCTAssertEqual(plan.sideScale, 1)
        XCTAssertEqual(plan.fitScale, 1)
    }

    func testHistoryShrinksOnlySideActionsWhileFullWeekStillFits() {
        let plan = ScheduleToolbarGeometry.resolve(width: 360, fullCenterWidth: 188,
            groupedCenterWidth: 98, history: true, confirm: false)
        XCTAssertFalse(plan.grouped)
        XCTAssertEqual(plan.sideScale, 0.75)
        XCTAssertEqual(plan.fitScale, 1)
        XCTAssertEqual(plan.height, 48)
    }

    func testNativeMeasurementsUseTheSameFallbackAndPreserveCenterHeight() {
        let plan = ScheduleToolbarGeometry.resolve(width: 430, fullCenterWidth: 216,
            groupedCenterWidth: 106, history: false, confirm: false,
            normalStartWidth: 56, tightStartWidth: 56,
            normalEndWidth: 120, tightEndWidth: 112,
            sideHeight: 48, fullCenterHeight: 58, groupedCenterHeight: 32)
        XCTAssertFalse(plan.grouped)
        XCTAssertEqual(plan.inset, 0)
        XCTAssertEqual(plan.sideGap, 0)
        XCTAssertEqual(plan.sideScale, 0.9)
        XCTAssertEqual(plan.fitScale, 1)
        XCTAssertEqual(plan.centerWidth, 216)
        XCTAssertEqual(plan.height, 58)
    }

    func testNativeBusyToolbarGroupsOnlyAfterMinimumSideScale() {
        let plan = ScheduleToolbarGeometry.resolve(width: 280, fullCenterWidth: 216,
            groupedCenterWidth: 106, history: true, confirm: true,
            normalStartWidth: 188, tightStartWidth: 172,
            normalEndWidth: 120, tightEndWidth: 112,
            sideHeight: 48, fullCenterHeight: 58, groupedCenterHeight: 32)
        XCTAssertTrue(plan.grouped)
        XCTAssertEqual(plan.inset, 0)
        XCTAssertEqual(plan.sideGap, 0)
        XCTAssertEqual(plan.sideScale, 2 / 3)
        XCTAssertLessThan(plan.fitScale, 1)
    }
}
