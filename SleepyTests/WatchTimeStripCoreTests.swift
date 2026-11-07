import XCTest
@testable import Sleepy

final class WatchTimeStripCoreTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ hour: Int, _ minute: Int = 0, day: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day,
                                           hour: hour, minute: minute))!
    }

    private func item(_ name: String, _ start: Int, _ end: Int,
                      day: Int = 7) -> WatchAgendaCore.ClassItem {
        WatchAgendaCore.ClassItem(courseName: name, room: "A101", startLabel: name,
                                  startMin: start, endMin: end,
                                  startDate: date(start / 60, start % 60, day: day),
                                  endDate: date(end / 60, end % 60, day: day))
    }

    private func snapshot(at now: Date, today: [WatchAgendaCore.ClassItem],
                          tomorrow: [WatchAgendaCore.ClassItem] = [],
                          showsTomorrow: Bool = false) -> WatchTimeStripCore.Snapshot {
        WatchTimeStripCore.snapshot(now: now, today: today, tomorrow: tomorrow,
                                    showsTomorrow: showsTomorrow, calendar: calendar)
    }

    func testNinetyMinuteClassInitiallyFillsWindow() throws {
        let result = snapshot(at: date(8), today: [item("A", 480, 570)])
        XCTAssertEqual(result.state, .today)
        XCTAssertEqual(result.windowStart, date(8))
        XCTAssertEqual(result.windowEnd, date(9, 30))
        XCTAssertEqual(result.segments.count, 1)
        let segment = try XCTUnwrap(result.segments.first)
        XCTAssertEqual(segment.courses.map(\.courseName), ["A"])
        XCTAssertEqual(segment.widthFraction, 1, accuracy: 0.000001)
    }

    func testThirtyMinuteBreakEntersAfterThirtyMinutes() {
        let result = snapshot(at: date(8, 30), today: [item("A", 480, 570), item("B", 600, 690)])
        XCTAssertEqual(result.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [60, 30])
        XCTAssertEqual(result.segments.map(\.isBreak), [false, true])
        XCTAssertEqual(result.segments[0].widthFraction, 2.0 / 3, accuracy: 0.000001)
        XCTAssertEqual(result.segments[1].offsetFraction(from: result.windowStart), 2.0 / 3,
                       accuracy: 0.000001)
    }

    func testTwentyTwoMinuteBreakAlsoRevealsNextEightMinutes() {
        let result = snapshot(at: date(8, 30), today: [item("A", 480, 570), item("B", 592, 682)])
        XCTAssertEqual(result.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [60, 22, 8])
        XCTAssertEqual(result.segments.map { $0.courses.map(\.courseName) }, [["A"], [], ["B"]])
        XCTAssertEqual(result.segments[1].widthFraction, 22.0 / 90, accuracy: 0.000001)
    }

    func testThreeEqualPartsAfterSixtyMinutes() {
        let result = snapshot(at: date(9), today: [item("A", 480, 570), item("B", 600, 690)])
        XCTAssertEqual(result.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [30, 30, 30])
        XCTAssertEqual(result.segments.map(\.isBreak), [false, true, false])
    }

    func testEndedClassLeavesAtExactEnd() {
        let result = snapshot(at: date(9, 30), today: [item("A", 480, 570), item("B", 600, 690)])
        XCTAssertEqual(result.segments.map { $0.courses.map(\.courseName) }, [[], ["B"]])
        XCTAssertEqual(result.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [30, 60])
    }

    func testLongLunchKeepsActualScale() throws {
        let result = snapshot(at: date(12), today: [item("A", 480, 570), item("B", 840, 930)])
        XCTAssertEqual(result.state, .today)
        XCTAssertEqual(result.segments.count, 1)
        let segment = try XCTUnwrap(result.segments.first)
        XCTAssertTrue(segment.isBreak)
        XCTAssertTrue(segment.courses.isEmpty)
        XCTAssertEqual(segment.widthFraction, 1)
    }

    func testPreClassWindowUsesRealTimeRatherThanJumpingAhead() {
        let result = snapshot(at: date(7), today: [item("A", 480, 570)])
        XCTAssertEqual(result.windowStart, date(7))
        XCTAssertEqual(result.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [60, 30])
        XCTAssertFalse(result.segments[0].isBreak)
    }

    func testOverlapsDoNotInventGapsOrDoubleCountWidth() {
        let result = snapshot(at: date(8, 30), today: [
            item("C", 585, 660), item("A", 480, 570), item("B", 510, 555)
        ])
        XCTAssertEqual(result.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [45, 15, 15, 15])
        XCTAssertEqual(result.segments.map { $0.courses.map(\.courseName) }, [["A", "B"], ["A"], [], ["C"]])
        XCTAssertEqual(result.segments.map(\.isBreak), [false, false, true, false])
        XCTAssertEqual(result.segments.reduce(0) { $0 + $1.widthFraction }, 1, accuracy: 0.000001)
    }

    func testInvalidIntervalsAreIgnored() {
        let result = snapshot(at: date(8), today: [item("Zero", 480, 480), item("Reverse", 500, 490)])
        XCTAssertEqual(result.state, .noClasses)
        XCTAssertTrue(result.segments.isEmpty)
    }

    func testTomorrowIsNotShownByDefaultAtLastEnd() {
        let result = snapshot(at: date(9, 30), today: [item("A", 480, 570)],
                              tomorrow: [item("B", 480, 570, day: 8)])
        XCTAssertEqual(result.state, .finished)
        XCTAssertTrue(result.segments.isEmpty)
    }

    func testTomorrowStartsAtFirstClassWhenTodayEndsAndAdvances() {
        let today = [item("A", 480, 570)]
        let tomorrow = [item("B", 540, 630, day: 8), item("C", 660, 750, day: 8)]
        let first = snapshot(at: date(9, 30), today: today, tomorrow: tomorrow, showsTomorrow: true)
        XCTAssertEqual(first.state, .tomorrowPreview)
        XCTAssertEqual(first.day, date(0, day: 8))
        XCTAssertEqual(first.windowStart, date(9, day: 8))
        let later = snapshot(at: date(10), today: today, tomorrow: tomorrow, showsTomorrow: true)
        XCTAssertEqual(later.windowStart, date(9, 30, day: 8))
        XCTAssertEqual(later.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [60, 30])
    }

    func testTomorrowPreviewRepeatsAfterLastEnd() {
        let result = snapshot(at: date(11), today: [item("A", 480, 570)],
                              tomorrow: [item("B", 540, 630, day: 8)], showsTomorrow: true)
        XCTAssertEqual(result.state, .tomorrowPreview)
        XCTAssertEqual(result.windowStart, date(9, day: 8))
    }

    func testEmptyTomorrowDoesNotSkipToAnotherDate() {
        let result = snapshot(at: date(20), today: [item("A", 480, 570)], showsTomorrow: true)
        XCTAssertEqual(result.state, .tomorrowEmpty)
        XCTAssertEqual(result.day, date(0, day: 8))
        XCTAssertTrue(result.segments.isEmpty)
    }

    func testEmptyTodayUsesOptInAndDeterministicPreviewAnchor() {
        XCTAssertEqual(snapshot(at: date(12), today: []).state, .noClasses)
        let result = snapshot(at: date(0, 30), today: [],
                              tomorrow: [item("B", 480, 570, day: 8)], showsTomorrow: true)
        XCTAssertEqual(result.state, .tomorrowPreview)
        XCTAssertEqual(result.windowStart, date(8, 30, day: 8))
    }

    func testLiveWindowIncludesTomorrowWhenItCrossesMidnight() {
        let today = [item("Late", 23 * 60, 23 * 60 + 45)]
        let tomorrow = [item("Early", 15, 60, day: 8)]
        for enabled in [false, true] {
            let result = snapshot(at: date(23, 15), today: today,
                                  tomorrow: tomorrow, showsTomorrow: enabled)
            XCTAssertEqual(result.state, .today)
            XCTAssertFalse(result.isTomorrow)
            XCTAssertEqual(result.windowStart, date(23, 15))
            XCTAssertEqual(result.windowEnd, date(0, 45, day: 8))
            XCTAssertEqual(result.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [30, 30, 30])
            XCTAssertEqual(result.segments.map { $0.courses.map(\.courseName) }, [["Late"], [], ["Early"]])
            XCTAssertEqual(result.segments.map(\.isBreak), [false, true, false])
        }
    }

    func testTomorrowOutsideLiveWindowDoesNotTurnTrailingFreeTimeIntoBreak() {
        let result = snapshot(at: date(8, 30), today: [item("A", 480, 570)],
                              tomorrow: [item("B", 480, 570, day: 8)])
        XCTAssertEqual(result.segments.map { $0.end.timeIntervalSince($0.start) / 60 }, [60, 30])
        XCTAssertEqual(result.segments.map(\.isBreak), [false, false])
        XCTAssertEqual(result.segments.map { $0.courses.map(\.courseName) }, [["A"], []])
    }

    func testLastClassEndStillRespectsPreviewOptionNearMidnight() {
        let today = [item("Late", 23 * 60, 23 * 60 + 45)]
        let tomorrow = [item("Early", 15, 60, day: 8)]
        let disabled = snapshot(at: date(23, 45), today: today, tomorrow: tomorrow)
        XCTAssertEqual(disabled.state, .finished)
        XCTAssertTrue(disabled.segments.isEmpty)
        let enabled = snapshot(at: date(23, 45), today: today,
                               tomorrow: tomorrow, showsTomorrow: true)
        XCTAssertEqual(enabled.state, .tomorrowPreview)
        XCTAssertEqual(enabled.windowStart, date(0, 15, day: 8))
    }

    func testNewCalendarDayReturnsToLiveMode() {
        let result = snapshot(at: date(0, day: 8), today: [item("B", 480, 570, day: 8)],
                              showsTomorrow: true)
        XCTAssertEqual(result.state, .today)
        XCTAssertEqual(result.windowStart, date(0, day: 8))
    }

    func testTimelineIsSortedDeduplicatedAndIncludesBoundariesAndMidnight() throws {
        let now = date(23, 58)
        let boundary = date(0, 7, day: 8)
        let dates = WatchTimeStripCore.timelineDates(now: now,
            courseBoundaries: [now, boundary, boundary, date(0, day: 9)], calendar: calendar)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates.last, now.addingTimeInterval(24 * 60 * 60))
        XCTAssertTrue(dates.contains(boundary))
        XCTAssertTrue(dates.contains(date(0, day: 8)))
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
        XCTAssertLessThanOrEqual(dates.count, 292)
        for (previous, next) in zip(dates, dates.dropFirst()) {
            XCTAssertGreaterThan(next, previous)
            XCTAssertLessThanOrEqual(next.timeIntervalSince(previous), 5 * 60)
        }
    }

    func testShortDayTimelineIncludesBothMidnights() throws {
        var cal = calendar
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 23, minute: 58)))
        let first = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let second = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 3, day: 9)))
        let dates = WatchTimeStripCore.timelineDates(now: now, courseBoundaries: [], calendar: cal)
        XCTAssertTrue(dates.contains(first))
        XCTAssertTrue(dates.contains(second))
    }

    func testTimelineHandlesDaylightSavingMidnightAsCalendarDate() throws {
        var cal = calendar
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let now = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0)))
        let nextDay = try XCTUnwrap(cal.date(byAdding: .day, value: 1, to: now))
        XCTAssertEqual(nextDay.timeIntervalSince(now), 25 * 60 * 60)
        let dates = WatchTimeStripCore.timelineDates(now: now, courseBoundaries: [], calendar: cal)
        XCTAssertFalse(dates.contains(nextDay))
        XCTAssertEqual(dates.last, now.addingTimeInterval(24 * 60 * 60))
    }
}
