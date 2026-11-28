import XCTest
@testable import Sleepy

final class ImportedPeriodGapTests: XCTestCase {
    typealias Slot = TimeTableUtils.TimeSlotRow

    func testUnavailableMiddleSlotStaysBlankInsteadOfOverlappingSource() {
        let source = [
            Slot(node: 1, start: "08:00", end: "09:00"),
            Slot(node: 3, start: "09:30", end: "10:15")
        ]
        let rows = merged(source)
        XCTAssertEqual(rows, [source[0], Slot(node: 2, start: "", end: ""), source[1]])
    }

    func testUsesDefaultOrFitsRealGapWithoutChangingFixedTimes() {
        let source = [
            Slot(node: 1, start: "09:00", end: "09:45"),
            Slot(node: 3, start: "10:40", end: "11:25")
        ]
        let rows = merged(source)
        XCTAssertEqual(rows, [source[0], Slot(node: 2, start: "09:55", end: "10:40"), source[1]])
        XCTAssertEqual(CourseImportPolicy.validateConfirmationRows(rows), .valid)
    }

    func testConfirmationRejectsExplicitOverlapsWithoutRewritingTheSource() {
        let source = [
            Slot(node: 1, start: "08:00", end: "09:00"),
            Slot(node: 2, start: "08:30", end: "09:30")
        ]
        let rows = merged(source)
        XCTAssertEqual(rows, source)
        XCTAssertEqual(CourseImportPolicy.validateConfirmationRows(rows),
                       .overlap(prevNode: 1, prevEnd: "09:00", nextNode: 2, nextStart: "08:30"))
    }

    func testLastPeriodDoesNotWrapPastMidnight() {
        let last = Slot(node: 1, start: "22:30", end: "23:30")
        let rows = merged([last], required: 2)
        XCTAssertEqual(rows, [last, Slot(node: 2, start: "", end: "")])
    }

    private func merged(_ rows: [Slot], required: Int = 0) -> [Slot] {
        let incoming = TimeTableUtils.buildTimeJsonFromRows(rows)
        let json = TimeTableUtils.mergeMostComplete(currentJson: "", incomingJson: incoming, requiredNodeCount: required)
        return TimeTableUtils.parseTimeSlotRows(json)
    }
}
