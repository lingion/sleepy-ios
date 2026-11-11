import XCTest
@testable import Sleepy

final class ManualTimeSlotLifecycleParityTests: XCTestCase {
    private typealias Row = TimeTableUtils.TimeSlotRow

    func testDeleteAndFirstCompletionPreserveAppendedBeforeIdentity() {
        let json = TimeTableUtils.insertEdgeNode(timeJson: TimeTableUtils.buildTimeJsonFromRows([
            Row(node: 1, start: "08:00", end: "08:45"), Row(node: 2, start: "10:00", end: "10:45")]),
            edgeClass: .before, start: "07:00", end: "07:45")
        let original = TimeTableUtils.parseTimeSlotRows(json)
        XCTAssertEqual(original.map(\.node), [1, 2, 0])
        var rows = TimeTableUtils.removeAndRenumber(original, node: 2)
        XCTAssertEqual(rows.first(where: { $0.edgeClass == .before })?.node, 0)
        rows = TimeTableUtils.appendEmptyRow(rows)
        XCTAssertEqual(Set(rows.map(\.node)).count, rows.count)
        rows = TimeTableUtils.updateManualRowTime(rows, node: 2, start: "09:00")
        XCTAssertTrue(rows.last!.pendingManualInsertion)
        rows = TimeTableUtils.updateManualRowTime(rows, node: 2, end: "09:45")
        XCTAssertEqual(rows.map(\.node), [0, 1, 2])
        XCTAssertEqual(rows.map(\.start), ["07:00", "08:00", "09:00"])
        XCTAssertFalse(rows.last!.pendingManualInsertion)
    }

    func testOnlyFirstValidCompletionInsertsChronologicallyAndTiesKeepEstablishedFirst() {
        var rows = TimeTableUtils.appendEmptyRow([
            Row(node: 0, start: "06:00", end: "06:45", edgeClass: .before),
            Row(node: 1, start: "08:00", end: "08:45"),
            Row(node: 2, start: "10:00", end: "10:45"),
            Row(node: 3, start: "12:00", end: "12:45", edgeClass: .after)])
        rows = TimeTableUtils.updateManualRowTime(rows, node: 3, start: "09:00", end: "09:45")
        XCTAssertEqual(rows.map(\.node), [0, 1, 2, 3, 4])
        XCTAssertEqual(rows.map(\.start), ["06:00", "08:00", "09:00", "10:00", "12:00"])
        rows = TimeTableUtils.updateManualRowTime(rows, node: 2, start: "11:00")
        rows = TimeTableUtils.updateManualRowTime(rows, node: 2, end: "11:45")
        XCTAssertEqual(rows.map(\.start), ["06:00", "08:00", "11:00", "10:00", "12:00"])
        rows = TimeTableUtils.appendEmptyRow(rows)
        rows = TimeTableUtils.updateManualRowTime(rows, node: 4, start: "08:00", end: "08:30")
        XCTAssertEqual(rows.filter { $0.edgeClass == nil }.prefix(2).map(\.end), ["08:45", "08:30"])
    }

    func testTwoUnfinishedCardsStayAtTailAndCompleteIndependently() {
        var rows = [Row(node: 1, start: "08:00", end: "08:45"),
                    Row(node: 2, start: "12:00", end: "12:45", edgeClass: .after)]
        rows = TimeTableUtils.appendEmptyRow(rows)
        rows = TimeTableUtils.appendEmptyRow(rows)
        XCTAssertEqual(rows.map(\.node), [1, 4, 2, 3])
        rows = TimeTableUtils.updateManualRowTime(rows, node: 3, start: "10:00", end: "10:45")
        XCTAssertEqual(rows.map(\.start), ["08:00", "10:00", "12:00", ""])
        XCTAssertEqual(rows.map(\.node), [1, 2, 4, 3])
        rows = TimeTableUtils.updateManualRowTime(rows, node: 3, start: "09:00", end: "09:45")
        XCTAssertEqual(rows.map(\.start), ["08:00", "09:00", "10:00", "12:00"])
        XCTAssertEqual(rows.map(\.node), [1, 2, 3, 4])
    }

    func testPendingMarkerSurvivesDraftCodingButNeverPersistsInScheduleJSON() throws {
        let pending = Row(node: 2, start: "bad", end: "09:00", pendingManualInsertion: true)
        let restored = try JSONDecoder().decode(Row.self, from: JSONEncoder().encode(pending))
        XCTAssertTrue(restored.pendingManualInsertion)
        let legacy = try JSONDecoder().decode(Row.self, from: Data("{\"node\":2,\"start\":\"\",\"end\":\"09:00\"}".utf8))
        XCTAssertTrue(legacy.pendingManualInsertion)
        let json = TimeTableUtils.buildTimeJsonFromRows([restored])
        XCTAssertFalse(json.contains("pendingManualInsertion"))
        let invalid = TimeTableUtils.updateManualRowTime([restored], node: 2, start: "10:00")
        XCTAssertTrue(invalid[0].pendingManualInsertion)
        XCTAssertEqual(invalid[0].node, 2)
        let completed = TimeTableUtils.updateManualRowTime(invalid, node: 2, end: "10:45")
        XCTAssertFalse(completed[0].pendingManualInsertion)
        XCTAssertEqual(completed[0].node, 1)
    }

    func testAutoGrowthOnlyShiftsCollidingAfterGroupAndRetainsGaps() {
        let existing = [Row(node: 0, start: "06:00", end: "06:45", edgeClass: .before),
                        Row(node: 1, start: "08:00", end: "08:45"),
                        Row(node: 3, start: "12:00", end: "12:45", edgeClass: .after),
                        Row(node: 2, start: "09:00", end: "09:45"),
                        Row(node: 5, start: "14:00", end: "14:45", edgeClass: .after)]
        let derived = SmartPeriodConfig(totalPeriods: 3).derive()
        let merged = mergeAutoRows(existingRows: existing, derivedStandardRows: derived)
        XCTAssertEqual(merged.map(\.node), [0, 1, 4, 2, 6, 3])
        XCTAssertEqual(merged.filter { $0.edgeClass != nil }.map(\.start), ["06:00", "12:00", "14:00"])
        let unchanged = mergeAutoRows(existingRows: existing, derivedStandardRows: Array(derived.prefix(2)))
        XCTAssertEqual(unchanged.filter { $0.edgeClass != nil }.map(\.node), [0, 3, 5])
    }
}
