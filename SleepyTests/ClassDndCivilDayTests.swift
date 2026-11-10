import XCTest
@testable import Sleepy

final class ClassDndCivilDayTests: XCTestCase {
    private let table = TimeTableEntity(name: "课程", startDate: "2026-11-02", maxWeek: 2, id: 1)
    private func date(_ value: String) -> Date { CourseOccurrences.parseDate(value)! }
    private func course(day: Int = 1, week: Int = 1, fixed: String? = nil) -> CourseEntity {
        CourseEntity(groupId: "g", tableId: 1, courseName: "数学", day: day,
                     startNode: 1, step: 1, startWeek: week, endWeek: week,
                     color: "#FF6750A4", ownTime: true, startTime: "08:00", endTime: "09:00", fixedDate: fixed)
    }
    private func intervals(on day: String, courses: [CourseEntity], transfers: [HolidayTransferEntry] = []) -> [(Date, Date)] {
        ClassDndScheduler.intervalsForDate(date(day), table: table, courses: courses, transfers: transfers)
    }
    private func time(on day: String, hour: Int, minute: Int = 0) -> Date {
        CourseOccurrences.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date(day))!
    }

    func testCrossWeekMakeupUsesSourceWeekAndTargetCivilDate() throws {
        let transfer = HolidayTransferEntry(sourceDate: date("2026-11-02"), targetDate: date("2026-11-15"), segmentId: "holiday")
        let result = intervals(on: "2026-11-15", courses: [course()], transfers: [transfer])
        XCTAssertEqual(result.count, 1)
        let interval = try XCTUnwrap(result.first)
        XCTAssertEqual(interval.0, time(on: "2026-11-15", hour: 8))
        XCTAssertEqual(interval.1, time(on: "2026-11-15", hour: 9))
        XCTAssertTrue(intervals(on: "2026-11-02", courses: [course()], transfers: [transfer]).isEmpty)
    }

    func testMakeupAfterSemesterStillUsesValidSourceWeek() {
        let transfer = HolidayTransferEntry(sourceDate: date("2026-11-02"), targetDate: date("2026-11-22"), segmentId: "holiday")
        XCTAssertEqual(intervals(on: "2026-11-22", courses: [course()], transfers: [transfer]).count, 1)
    }

    func testFixedCourseStaysOnDateDespiteStaleWeekdayAndWeek() {
        let fixed = course(day: 4, week: 1, fixed: "2026-11-15")
        XCTAssertEqual(intervals(on: "2026-11-15", courses: [fixed]).count, 1)
        XCTAssertTrue(intervals(on: "2026-11-05", courses: [fixed]).isEmpty)
    }

    func testFixedCourseDoesNotFollowHolidayTransfer() {
        let transfer = HolidayTransferEntry(sourceDate: date("2026-11-02"), targetDate: date("2026-11-15"), segmentId: "holiday")
        let fixed = course(fixed: "2026-11-02")
        XCTAssertEqual(intervals(on: "2026-11-02", courses: [fixed], transfers: [transfer]).count, 1)
        XCTAssertTrue(intervals(on: "2026-11-15", courses: [fixed], transfers: [transfer]).isEmpty)
    }

    func testIntervalsUseTimetableCivilDayAcrossUTCDateBoundary() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T23:55:00Z"))
        let result = ClassDndScheduler.intervalsForDate(date, table: table, courses: [course()], transfers: [])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.0, ISO8601DateFormatter().date(from: "2026-11-02T00:00:00Z"))
        XCTAssertTrue(ClassDndScheduler.isCurrentlyInClass(result, now: time(on: "2026-11-02", hour: 8)))
        XCTAssertFalse(ClassDndScheduler.isCurrentlyInClass(result, now: time(on: "2026-11-02", hour: 9)))
    }

    func testIrregularTimeUsesItsExplicitTimeInsteadOfNodeTimes() throws {
        var row = course()
        row.ownTime = false
        row.isIrregularTime = true
        row.startTime = "07:10"
        row.endTime = "07:35"
        let interval = try XCTUnwrap(intervals(on: "2026-11-02", courses: [row]).first)
        XCTAssertEqual(interval.0, time(on: "2026-11-02", hour: 7, minute: 10))
        XCTAssertEqual(interval.1, time(on: "2026-11-02", hour: 7, minute: 35))
    }
}
