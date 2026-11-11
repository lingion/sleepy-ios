import XCTest
@testable import Sleepy

final class SmartPeriodBoundaryParityTests: XCTestCase {
    func testLastMinuteIsValidButMidnightIsRejectedWithoutPartialRows() {
        let lastMinute = SmartPeriodConfig(startTime: "23:58", periodMinutes: 1, totalPeriods: 1)
        XCTAssertNil(lastMinute.validationError())
        XCTAssertEqual(lastMinute.derive().map(\.end), ["23:59"])
        let midnight = SmartPeriodConfig(startTime: "23:58", periodMinutes: 2, totalPeriods: 1)
        XCTAssertEqual(midnight.validationError(), .exceedsDay)
        XCTAssertTrue(midnight.derive().isEmpty)
        let lateBreak = SmartPeriodConfig(startTime: "23:55", periodMinutes: 1, totalPeriods: 2,
                                         breaks: [BreakOption(minutes: 3)], transitionAssignments: [0])
        XCTAssertEqual(lateBreak.validationError(), .exceedsDay)
        XCTAssertTrue(lateBreak.derive().isEmpty)
    }

    func testStrictStartAndInvalidDurationsDoNotGenerateFallbackSchedules() {
        for start in ["8:00", "24:00", "08:60", " 08:00", "", "bad"] {
            let config = SmartPeriodConfig(startTime: start, totalPeriods: 1)
            XCTAssertEqual(config.validationError(), .startTime, start)
            XCTAssertTrue(config.derive().isEmpty, start)
        }
        for config in [SmartPeriodConfig(periodMinutes: 0), SmartPeriodConfig(periodMinutes: -1),
                       SmartPeriodConfig(breaks: [BreakOption(minutes: -1)]),
                       SmartPeriodConfig(durations: [DurationOption(minutes: 0)])] {
            XCTAssertEqual(config.validationError(), .duration)
            XCTAssertTrue(config.derive().isEmpty)
        }
    }

    func testCorruptImportedCountsAndDurationsAreBoundedBeforeAllocationOrArithmetic() {
        for count in [Int.min, -1, 0, 1440, Int.max] {
            let config = SmartPeriodConfig(totalPeriods: count)
            XCTAssertEqual(config.validationError(), .periodCount)
            XCTAssertTrue(config.derive().isEmpty)
            XCTAssertLessThanOrEqual(config.effectivePeriodAssignments().count, 1439)
            XCTAssertLessThanOrEqual(config.effectiveAssignments().count, 1438)
        }
        for config in [SmartPeriodConfig(periodMinutes: Int.max, totalPeriods: 1),
                       SmartPeriodConfig(totalPeriods: 2, breaks: [BreakOption(minutes: Int.max)],
                                         transitionAssignments: [0]),
                       SmartPeriodConfig(totalPeriods: 1, durations: [DurationOption(minutes: Int.max)],
                                         periodAssignments: [0])] {
            XCTAssertEqual(config.validationError(), .exceedsDay)
            XCTAssertTrue(config.derive().isEmpty)
        }
    }

    func testMixedDurationsAndBreaksShareOneDayBudget() {
        let config = SmartPeriodConfig(startTime: "22:00", periodMinutes: 30, totalPeriods: 3,
            breaks: [BreakOption(minutes: 14)], transitionAssignments: [nil, 0],
            durations: [DurationOption(minutes: 45)], periodAssignments: [nil, 0, nil])
        XCTAssertNil(config.validationError())
        XCTAssertEqual(config.derive().map(\.end), ["22:30", "23:15", "23:59"])
        var overflow = config
        overflow.breaks[0].minutes = 15
        XCTAssertEqual(overflow.validationError(), .exceedsDay)
        XCTAssertTrue(overflow.derive().isEmpty)
    }

    func testSavedSmartConfigMustMatchCurrentStandardRows() throws {
        let config = SmartPeriodConfig(startTime: "08:00", periodMinutes: 45, totalPeriods: 2)
        let matching = encodeMatchingSmartPeriodConfig(rows: config.derive(), stored: config)
        XCTAssertEqual(decodeSmartPeriodConfig(matching), config)
        let changed = [TimeTableUtils.TimeSlotRow(node: 1, start: "10:00", end: "10:30")]
        let encoded = encodeMatchingSmartPeriodConfig(rows: changed, stored: config)
        XCTAssertEqual(decodeSmartPeriodConfig(encoded)?.derive(), changed)
        XCTAssertEqual(encodeMatchingSmartPeriodConfig(rows: [TimeTableUtils.TimeSlotRow(node: 1,
            start: "24:00", end: "24:30")], stored: config), "")
    }
}
