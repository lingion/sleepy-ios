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
}
