import XCTest
@testable import Sleepy

final class HolidayCivilDayAuditTests: XCTestCase {
    func testWeekendGateUsesSameCivilDayAsCourseOccurrences() throws {
        // Sunday UTC, but Monday morning in the timetable's civil-day zone.
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T23:55:00Z"))
        let result = HolidayReminderPolicy.decide(date: date, publicHolidays: [], transferWorkdays: [],
            transfers: [], rulesEnabled: true, publicHolidayReminder: false,
            transferHolidayReminder: false, makeupWorkdayReminder: true,
            ordinaryWeekendReminder: false, dataAvailable: true)
        XCTAssertEqual(CourseOccurrences.day(date), 1)
        XCTAssertEqual(result.category, .normalWeekday)
        XCTAssertTrue(result.allowReminder)
    }

    func testHolidayYearUsesCivilDayAcrossNewYear() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-12-31T23:55:00Z"))
        XCTAssertEqual(HolidayReminderPolicyAdapter.year(for: date), 2027)
    }
}
