import XCTest
@testable import Sleepy

final class PeriodValidation1064Tests: XCTestCase {
    private typealias Row = TimeTableUtils.TimeSlotRow

    private func row(_ node: Int = 1, _ start: String = "08:00", _ end: String = "08:45") -> Row {
        Row(node: node, start: start, end: end)
    }

    private func json(_ value: Any) throws -> String {
        String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)!
    }

    private func course(_ start: Int, _ step: Int) -> CourseEntity {
        CourseEntity(groupId: "period", tableId: 1, courseName: "课程", day: 1,
                     startNode: start, step: step, startWeek: 1, endWeek: 16, color: "")
    }

    func testMinuteClockAcceptsTrimmedClocksAndRejectsSecondsAndMalformedValues() {
        XCTAssertEqual(TimeTableUtils.parsePeriodClock(" \n23:59\t"), 1_439)
        XCTAssertEqual(TimeTableUtils.parsePeriodClock("00:00"), 0)
        for value in ["8:00", "08:00:00", "24:00", "08:60", "08:0", "０８:００", "08:00x", ""] {
            XCTAssertNil(TimeTableUtils.parsePeriodClock(value), value)
        }
    }

    func testStrictDecoderRetainsLegacyIdentityAndSortsDeclaredNodes() {
        let raw = "[{\"node\":\"3\",\"start\":\"09:00\",\"end\":\"09:45\"},{\"start\":\"08:00\",\"end\":\"08:45\"}]"
        XCTAssertEqual(TimeTableUtils.parseNodes(raw).map(\.node), [2, 3])
        XCTAssertEqual(TimeTableUtils.validateTimeJson(raw), .valid)
    }

    func testStrictDecoderRejectsSuppliedNonInt32IdentityWithoutEditorDefaults() throws {
        for identity: Any in [true, false, NSNull(), 1.5, "1.0", " 1", "2147483648", [1]] {
            let raw = try json([["node": identity, "start": "08:00", "end": "08:45"]])
            XCTAssertEqual(TimeTableUtils.validateTimeJson(raw), .invalidData)
            XCTAssertTrue(TimeTableUtils.parseNodes(raw).isEmpty)
        }
        for raw in ["{}", "[1]", "[{\"node\":1}]", "[{\"start\":800,\"end\":\"08:45\"}]"] {
            XCTAssertEqual(TimeTableUtils.validateTimeJson(raw), .invalidData)
            XCTAssertTrue(TimeTableUtils.parseNodes(raw).isEmpty)
        }
        for identity in ["1.0", "1e0"] {
            let raw = "[{\"node\":\(identity),\"start\":\"08:00\",\"end\":\"08:45\"}]"
            XCTAssertEqual(TimeTableUtils.validateTimeJson(raw), .invalidData)
            XCTAssertTrue(TimeTableUtils.parseNodes(raw).isEmpty)
        }
    }

    func testDuplicateIdentityFailsParsingAndKeepsSpecificDiagnostic() {
        let rows = [row(), row(1, "09:00", "09:45")]
        let raw = TimeTableUtils.buildTimeJsonFromRows(rows)
        XCTAssertTrue(TimeTableUtils.parseNodes(raw).isEmpty)
        XCTAssertEqual(TimeTableUtils.validateTimeJson(raw), .duplicateNode(node: 1))
    }

    func testValidationChecksClockRangeAndPositiveIntervals() {
        XCTAssertEqual(TimeTableUtils.validatePeriodRows([]), .empty)
        XCTAssertEqual(TimeTableUtils.validateTimeJson(" \n"), .empty)
        XCTAssertEqual(TimeTableUtils.validateTimeJson("[]"), .empty)
        XCTAssertEqual(TimeTableUtils.validatePeriodRows([row(4, "25:00", "26:00")]),
                       .invalidFormat(node: 4, rawStart: "25:00", rawEnd: "26:00"))
        XCTAssertEqual(TimeTableUtils.validatePeriodRows([row(4, "09:00", "09:00")]),
                       .endBeforeStart(node: 4, start: "09:00", end: "09:00"))
    }

    func testOverlapFollowsNodeOrderAndIncludesEdgeRowsWithTouchingEndpointsAllowed() {
        let before = Row(node: 0, start: "07:30", end: "08:10", edgeClass: .before)
        XCTAssertEqual(TimeTableUtils.validatePeriodRows([row(), before]),
                       .overlap(prevNode: 0, prevEnd: "08:10", nextNode: 1, nextStart: "08:00"))
        XCTAssertEqual(TimeTableUtils.validatePeriodRows([row(2, "08:45", "09:30"), row()]), .valid)
        XCTAssertTrue(TimeTableUtils.isPeriodTableValid(TimeTableUtils.DEFAULT_TIME_JSON))
    }

    func testReaderKeepsRealOverlappingClocksWhileValidatorDiagnosesThem() {
        let raw = TimeTableUtils.buildTimeJsonFromRows([row(), row(2, "08:30", "09:15")])
        XCTAssertEqual(TimeTableUtils.parseNodes(raw).count, 2)
        XCTAssertEqual(TimeTableUtils.sanitizeTimeJsonForDisplay(raw), raw)
        XCTAssertEqual(TimeTableUtils.validateTimeJson(raw),
                       .overlap(prevNode: 1, prevEnd: "08:45", nextNode: 2, nextStart: "08:30"))
    }

    func testDisplaySanitizerTrimsOnlyValidClocksAndPreservesMetadataAndInvalidValues() throws {
        let raw = "[{\"node\":0,\"start\":\" 07:00 \",\"end\":\"07:45\",\"edge\":\"before\",\"source\":{\"id\":3}}, {\"node\":1,\"start\":\"8:00 \",\"end\":\"08:45:00\"}, 2]"
        let result = TimeTableUtils.sanitizeTimeJsonForDisplay(raw)
        let data = try XCTUnwrap(result.data(using: .utf8))
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [Any])
        let first = try XCTUnwrap(array[0] as? [String: Any])
        let second = try XCTUnwrap(array[1] as? [String: Any])
        XCTAssertEqual(first["start"] as? String, "07:00")
        XCTAssertEqual(first["edge"] as? String, "before")
        XCTAssertEqual((first["source"] as? [String: Int])?["id"], 3)
        XCTAssertEqual(second["start"] as? String, "8:00 ")
        XCTAssertEqual(second["end"] as? String, "08:45:00")
        XCTAssertEqual(array[2] as? Int, 2)
        XCTAssertEqual(TimeTableUtils.sanitizeTimeJsonForDisplay(result), result)
    }

    func testDisplaySanitizerReturnsExactOriginalWhenNoClockCanBeTrimmed() {
        for raw in ["not json", "[ {\"start\":\"8:00 \"} ]", "[ {\"node\":1, \"start\":\"08:00\", \"end\":\"08:45\"} ]"] {
            XCTAssertEqual(TimeTableUtils.sanitizeTimeJsonForDisplay(raw), raw)
        }
    }

    func testSerializationTrimsClocksWithoutRenumberingOrDroppingEdgeIdentity() {
        let source = Row(node: -1, start: " 06:00 ", end: "\n06:45", edgeClass: .before)
        XCTAssertEqual(TimeTableUtils.buildTimeJsonFromRows([source]),
                       "[{\"node\":-1,\"start\":\"06:00\",\"end\":\"06:45\",\"edge\":\"before\"}]")
    }

    func testLiveConflictSkipsWholeBlankRowsAndUsesNearestFilledNeighbors() {
        XCTAssertNil(TimeTableUtils.findConflictForSlot([row(1, "", "")], targetNode: 1))
        XCTAssertNil(TimeTableUtils.findConflictForSlot([row()], targetNode: 2))
        XCTAssertEqual(TimeTableUtils.findConflictForSlot([row(1, "", "08:45")], targetNode: 1),
                       .invalidFormat(node: 1, rawStart: "", rawEnd: "08:45"))
        let rows = [row(), row(2, "", ""), row(3, "08:30", "09:15")]
        XCTAssertEqual(TimeTableUtils.findConflictForSlot(rows, targetNode: 3),
                       .overlap(prevNode: 1, prevEnd: "08:45", nextNode: 3, nextStart: "08:30"))
        XCTAssertEqual(TimeTableUtils.findConflictForSlot(rows, targetNode: 1),
                       .overlap(prevNode: 1, prevEnd: "08:45", nextNode: 3, nextStart: "08:30"))
    }

    func testReorderValidationChecksPreviousEndAllRowsAndDuplicateIdentity() {
        XCTAssertFalse(TimeTableUtils.isTimeSlotOrderValid([row(), row(2, "08:30", "09:00")]))
        XCTAssertTrue(TimeTableUtils.isTimeSlotOrderValid([row(), row(2, "", ""), row(3, "08:45", "09:30")]))
        XCTAssertFalse(TimeTableUtils.isTimeSlotOrderValid([row(), row(1, "", "")]))
        XCTAssertFalse(TimeTableUtils.isTimeSlotOrderValid([row(), Row(node: 0, start: "07:00", end: "07:45", edgeClass: .before)]))
    }

    func testFirstMissingCourseNodeChecksSparseCoverageAndExemptsActualTimeCourses() {
        var actual = course(90, 10); actual.isIrregularTime = true
        var owned = course(90, 10); owned.ownTime = true
        XCTAssertNil(TimeTableUtils.firstMissingCourseNode(courses: [actual, owned, course(1, 0)], rows: []))
        XCTAssertEqual(TimeTableUtils.firstMissingCourseNode(courses: [course(1, 3)], rows: [row(), row(3)]), 2)
        XCTAssertNil(TimeTableUtils.firstMissingCourseNode(courses: [course(1, 3)], rows: [row(3), row(), row(2), row(2)]))
        XCTAssertEqual(TimeTableUtils.firstMissingCourseNode(courses: [course(1, Int.max)], rows: [row(), row(2)]), 3)
        XCTAssertEqual(TimeTableUtils.firstMissingCourseNode(courses: [course(Int.max, Int.max)], rows: []), Int64.max)
        XCTAssertEqual(TimeTableUtils.firstMissingCourseNode(courses: [course(Int.max, 1), course(2, 1)], rows: [row(Int.max)]), 2)
    }

    func testEffectiveCourseTimeRejectsMissingDefaultsAndOverflowButKeepsActualSeconds() {
        XCTAssertNil(TimeTableUtils.effectiveCourseTime(isIrregularTime: false, startTime: "", endTime: "",
                                                      startNode: 1, step: 1, timeJson: "not json"))
        for (node, step) in [(1, 0), (Int.max, 2), (Int.min, Int.min), (2_147_483_647, 2)] {
            XCTAssertNil(TimeTableUtils.effectiveCourseTime(isIrregularTime: false, startTime: "", endTime: "",
                                                          startNode: node, step: step, timeJson: TimeTableUtils.DEFAULT_TIME_JSON))
        }
        let parts = TimeTableUtils.effectiveCourseTime(isIrregularTime: true, startTime: "08:00:30", endTime: "08:45:15",
                                                     startNode: 90, step: 0, timeJson: "invalid")
        XCTAssertEqual(parts?.0, "08:00:30")
        XCTAssertEqual(parts?.1, "08:45:15")
    }

    func testScheduleStateDiagnosesPersistedSourceAndSanitizesOnlyRenderCopy() {
        let raw = "[{\"node\":1,\"start\":\" 08:00 \",\"end\":\"08:45\"},{\"node\":2,\"start\":\"08:30\",\"end\":\"09:15\"}]"
        var state = ScheduleState()
        state.selectedTableId = 5
        state.tables = [TimeTableEntity(name: "课表", startDate: "2026-09-07", timeJson: raw, id: 5)]
        XCTAssertTrue(state.hasPeriodConflict)
        XCTAssertEqual(state.effectiveCurrentTable?.timeJson, raw)
        XCTAssertNotEqual(state.effectiveRenderTimeJson, raw)
        XCTAssertEqual(TimeTableUtils.parseNodes(state.effectiveRenderTimeJson!).count, 2)
        XCTAssertFalse(ScheduleState().hasPeriodConflict)
    }
}
