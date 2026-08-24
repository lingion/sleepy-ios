// SmartPeriodConfigTests.swift — ← data/entity/SmartPeriodConfigTest.kt 逐用例移植 (GPL-3.0)

import XCTest
@testable import Sleepy

final class SmartPeriodConfigTests: XCTestCase {

    func testDeriveDefault0MinuteBreaksConsecutive() {
        // 100 节 × 1 分钟, 默认全 0 分钟
        let cfg = SmartPeriodConfig(
            startTime: "08:00",
            periodMinutes: 1,
            totalPeriods: 5,
            breaks: [],
            transitionAssignments: []
        )
        let rows = cfg.derive()
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual("08:00", rows[0].start)
        XCTAssertEqual("08:01", rows[0].end)
        XCTAssertEqual("08:01", rows[1].start) // 连续
        XCTAssertEqual("08:05", rows[4].end)   // 5节 × 1分钟 = 08:05
    }

    func testDeriveOneSmallBreakPerTransition() {
        // 5 节 × 1 分钟, 每个 transition 用 1分钟小课间
        let cfg = SmartPeriodConfig(
            startTime: "08:00",
            periodMinutes: 1,
            totalPeriods: 5,
            breaks: [BreakOption(minutes: 1, isLong: false)],
            transitionAssignments: [0, 0, 0, 0]
        )
        let rows = cfg.derive()
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual("08:00", rows[0].start)
        XCTAssertEqual("08:01", rows[0].end)
        XCTAssertEqual("08:02", rows[1].start) // +1min break
        XCTAssertEqual("08:03", rows[1].end)
        XCTAssertEqual("08:04", rows[2].start) // +1min break
        XCTAssertEqual("08:09", rows[4].end)   // 5节 × 1分钟 + 4 × 1分钟 = 09
    }

    func testDeriveHEURealExample5Breaks() {
        // HEU: 5 个 break, 索引 0=10分钟小课间, 1=15分钟大课间, 2=65分钟大课间(午休)
        let cfg = SmartPeriodConfig(
            startTime: "08:00",
            periodMinutes: 45,
            totalPeriods: 5,
            breaks: [
                BreakOption(minutes: 10, isLong: false), // 0
                BreakOption(minutes: 15, isLong: true),  // 1
                BreakOption(minutes: 65, isLong: true),  // 2 (午休)
            ],
            // transition 0: 1→2, small (10min)
            // transition 1: 2→3, big (15min)
            // transition 2: 3→4, small (10min)
            // transition 3: 4→5, big (15min)
            // transition 4 omitted (5→6 lunch, but we only have 5 periods)
            transitionAssignments: [0, 1, 0, 1, nil]
        )
        let rows = cfg.derive()
        XCTAssertEqual(rows.count, 5)
        // 第1节 08:00 - 08:45
        XCTAssertEqual("08:00", rows[0].start)
        XCTAssertEqual("08:45", rows[0].end)
        // 第2节 08:55 (08:45 + 10min) - 09:40
        XCTAssertEqual("08:55", rows[1].start)
        XCTAssertEqual("09:40", rows[1].end)
        // 第3节 09:55 (09:40 + 15min) - 10:40
        XCTAssertEqual("09:55", rows[2].start)
        XCTAssertEqual("10:40", rows[2].end)
        // 第4节 10:50 (10:40 + 10min) - 11:35
        XCTAssertEqual("10:50", rows[3].start)
        XCTAssertEqual("11:35", rows[3].end)
        // 第5节 11:50 (11:35 + 15min) - 12:35
        XCTAssertEqual("11:50", rows[4].start)
        XCTAssertEqual("12:35", rows[4].end)
    }

    func testEffectiveAssignmentsNullPositionsDefaultTo0Minute() {
        let cfg = SmartPeriodConfig(
            startTime: "08:00",
            periodMinutes: 45,
            totalPeriods: 5,
            breaks: [BreakOption(minutes: 10)],
            transitionAssignments: [nil, 0, nil, nil]
        )
        let assigns = cfg.effectiveAssignments()
        XCTAssertEqual(4, assigns.count)
        XCTAssertEqual(nil, assigns[0])
        XCTAssertEqual(0, assigns[1])
        XCTAssertEqual(nil, assigns[2])
        XCTAssertEqual(nil, assigns[3])
    }

    func testEffectiveAssignmentsInvalidIndexFallsBackToNull() {
        // 索引越界 -> 视为 null (0 分钟)
        let cfg = SmartPeriodConfig(
            startTime: "08:00",
            periodMinutes: 45,
            totalPeriods: 5,
            breaks: [BreakOption(minutes: 10)],
            transitionAssignments: [5, 0, -1, 99] // 越界
        )
        let assigns = cfg.effectiveAssignments()
        // 越界 -> null
        XCTAssertEqual(nil, assigns[0])
        XCTAssertEqual(0, assigns[1])
        XCTAssertEqual(nil, assigns[2])
        XCTAssertEqual(nil, assigns[3])
    }

    func testEffectiveTransitionMinutesMixedBreaks() {
        let cfg = SmartPeriodConfig(
            startTime: "08:00",
            periodMinutes: 45,
            totalPeriods: 5,
            breaks: [
                BreakOption(minutes: 10, isLong: false), // 0
                BreakOption(minutes: 15, isLong: true)   // 1
            ],
            transitionAssignments: [0, 1, nil, 0]
        )
        let mins = cfg.effectiveTransitionMinutes()
        XCTAssertEqual([10, 15, 0, 10], mins)
    }

    func testTotalPeriodsMinimum1() {
        let cfg = SmartPeriodConfig(totalPeriods: 1)
        let rows = cfg.derive()
        XCTAssertEqual(1, rows.count)
    }
}
