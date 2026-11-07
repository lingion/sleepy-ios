import XCTest
#if !OCCURRENCE_IDENTITY_STANDALONE
@testable import Sleepy
#endif

final class CourseOccurrenceIdentityTests: XCTestCase {
    private let startDate = "2026-09-07"

    // 输入日期也走生产日历，避免用另一时区的 DateFormatter 构造出前一天。
    private func transfer(fromWeek: Int, fromDay: Int, toWeek: Int, toDay: Int,
                          startDate: String = "2026-09-07") throws -> HolidayTransferEntry {
        HolidayTransferEntry(
            sourceDate: try XCTUnwrap(DateUtils.dateOfWeek(
                startDate: startDate, week: fromWeek, dayOfWeek: fromDay)),
            targetDate: try XCTUnwrap(DateUtils.dateOfWeek(
                startDate: startDate, week: toWeek, dayOfWeek: toDay)),
            segmentId: "occurrence-identity")
    }

    private func resolve(_ week: Int, _ day: Int, maxWeek: Int = 4,
                         transfers: [HolidayTransferEntry] = []) -> CourseOccurrenceIdentity? {
        CourseOccurrenceIdentity.resolve(startDate: startDate, maxWeek: maxWeek,
                                         displayWeek: week, displayDay: day, transfers: transfers)
    }

    func testUntransferredColumnsKeepTheirActualWeekAndDay() {
        XCTAssertEqual(resolve(1, 1), CourseOccurrenceIdentity(week: 1, day: 1))
        XCTAssertEqual(resolve(4, 7), CourseOccurrenceIdentity(week: 4, day: 7))
        XCTAssertNil(resolve(5, 1), "学期外普通展示列不能生成库内 occurrence")
    }

    func testCrossWeekMakeupResolvesSourceWeekAndDayRatherThanDisplayCoordinates() throws {
        let transfers = [try transfer(fromWeek: 1, fromDay: 2, toWeek: 2, toDay: 7)]
        XCTAssertEqual(resolve(2, 7, transfers: transfers), CourseOccurrenceIdentity(week: 1, day: 2))
        XCTAssertEqual(resolve(2, 2, transfers: transfers), CourseOccurrenceIdentity(week: 2, day: 2))
        XCTAssertNil(resolve(1, 2, transfers: transfers), "原放假日已无课")
    }

    func testExtendedDisplayWeekCanResolveBackInsideSemester() throws {
        let transfers = [try transfer(fromWeek: 4, fromDay: 5, toWeek: 6, toDay: 1)]
        XCTAssertEqual(resolve(6, 1, transfers: transfers), CourseOccurrenceIdentity(week: 4, day: 5))
        XCTAssertNil(resolve(6, 2, transfers: transfers))
        XCTAssertNil(resolve(4, 5, transfers: transfers))
    }

    func testInSemesterDisplayRejectsSourcesBeforeAndAfterRealSemester() throws {
        let transfers = [try transfer(fromWeek: 0, fromDay: 5, toWeek: 2, toDay: 6),
                         try transfer(fromWeek: 5, fromDay: 1, toWeek: 2, toDay: 7)]
        XCTAssertNil(resolve(2, 6, transfers: transfers), "不能把学期前源日钳制成第一周")
        XCTAssertNil(resolve(2, 7, transfers: transfers), "不能按展示周误接学期外源日")
    }

    func testHolidayColumnIsEmptyInBothIdentityAndRealRenderer() throws {
        let transfers = [try transfer(fromWeek: 1, fromDay: 2, toWeek: 2, toDay: 7)]
        let table = TimeTableEntity(name: "身份测试", startDate: startDate, maxWeek: 4)
        let course = makeCourse(id: 11, day: 2, type: 0)
        XCTAssertNil(resolve(1, 2, transfers: transfers))
        XCTAssertTrue(renderCoursesForWeek(table, week: 1, courses: [course],
                                           transfers: transfers, timeJson: nil).isEmpty)
        let makeup = renderCoursesForWeek(table, week: 2, courses: [course],
                                           transfers: transfers, timeJson: nil)
        XCTAssertEqual(makeup.filter { $0.day == 7 }.map(\.id), [11])
    }

    func testOddAndEvenOccurrencesFollowRealSourceWeekInBothDirections() throws {
        let transfers = [try transfer(fromWeek: 1, fromDay: 2, toWeek: 2, toDay: 7),
                         try transfer(fromWeek: 2, fromDay: 2, toWeek: 3, toDay: 6)]
        let table = TimeTableEntity(name: "单双周", startDate: startDate, maxWeek: 4)
        let odd = makeCourse(id: 11, day: 2, type: 1)
        let even = makeCourse(id: 12, day: 2, type: 2)
        let naturalSunday = makeCourse(id: 13, day: 7, type: 0)
        let courses = [odd, even, naturalSunday]
        let weekTwo = renderCoursesForWeek(table, week: 2, courses: courses,
                                           transfers: transfers, timeJson: nil)
        XCTAssertEqual(weekTwo.filter { $0.day == 7 }.map(\.id), [11],
                       "偶数展示周补单数源周课，屏蔽补班日原课程")
        let first = try XCTUnwrap(resolve(2, 7, transfers: transfers))
        XCTAssertEqual(first, CourseOccurrenceIdentity(week: 1, day: 2))
        XCTAssertTrue(odd.inWeek(first.week))
        XCTAssertFalse(even.inWeek(first.week))

        let weekThree = renderCoursesForWeek(table, week: 3, courses: courses,
                                             transfers: transfers, timeJson: nil)
        XCTAssertEqual(weekThree.filter { $0.day == 6 }.map(\.id), [12])
        let second = try XCTUnwrap(resolve(3, 6, transfers: transfers))
        XCTAssertEqual(second, CourseOccurrenceIdentity(week: 2, day: 2))
        XCTAssertTrue(even.inWeek(second.week))
        XCTAssertFalse(odd.inWeek(second.week))
        XCTAssertNotEqual(first, second, "同一自然星期也不能丢掉真实源周")
    }

    func testExtendedWeekIdentityMatchesRealRendererAndKeepsOriginalRowID() throws {
        let transfers = [try transfer(fromWeek: 4, fromDay: 2, toWeek: 6, toDay: 1)]
        let table = TimeTableEntity(name: "学期后补课", startDate: startDate, maxWeek: 4)
        let course = makeCourse(id: 24, day: 2, type: 2)
        let rendered = renderCoursesForWeek(table, week: 6, courses: [course],
                                            transfers: transfers, timeJson: nil)
        XCTAssertEqual(rendered.map(\.id), [24])
        XCTAssertEqual(rendered.map(\.day), [1])
        let captured = try XCTUnwrap(resolve(6, 1, transfers: transfers))
        XCTAssertEqual(captured, CourseOccurrenceIdentity(week: 4, day: 2))
        XCTAssertEqual(course.day, 2, "身份与原行匹配，不从投影行 day=1 反推")
        XCTAssertTrue(course.inWeek(captured.week))
    }

    func testSourceAndDestinationColumnsShareTheSameResolutionRule() throws {
        let transfers = [try transfer(fromWeek: 1, fromDay: 2, toWeek: 2, toDay: 7),
                         try transfer(fromWeek: 4, fromDay: 5, toWeek: 6, toDay: 1)]
        let capturedSource = try XCTUnwrap(resolve(2, 7, transfers: transfers))
        let destination = try XCTUnwrap(resolve(6, 1, transfers: transfers))
        XCTAssertEqual(capturedSource, CourseOccurrenceIdentity(week: 1, day: 2))
        XCTAssertEqual(destination, CourseOccurrenceIdentity(week: 4, day: 5))
        // 起拖后偏好变化，已捕获的值仍指向原始 occurrence。
        XCTAssertEqual(resolve(2, 7), CourseOccurrenceIdentity(week: 2, day: 7))
        XCTAssertEqual(capturedSource, CourseOccurrenceIdentity(week: 1, day: 2))
    }

    func testTargetDatePrecedenceMatchesRendererWhenDateIsAlsoAHolidaySource() throws {
        let transfers = [try transfer(fromWeek: 1, fromDay: 2, toWeek: 2, toDay: 7),
                         try transfer(fromWeek: 2, fromDay: 7, toWeek: 3, toDay: 6)]
        XCTAssertEqual(resolve(2, 7, transfers: transfers), CourseOccurrenceIdentity(week: 1, day: 2),
                       "命中 target 优先，不能先按 sourceDate 拒绝，也不能递归追溯")
        XCTAssertEqual(resolve(3, 6, transfers: transfers), CourseOccurrenceIdentity(week: 2, day: 7))
    }

    func testCrossYearAndNonMondayStartUseDateUtilsCalendar() throws {
        let start = "2026-12-30"
        let transfers = [try transfer(fromWeek: 1, fromDay: 4, toWeek: 2, toDay: 7, startDate: start)]
        XCTAssertEqual(CourseOccurrenceIdentity.resolve(startDate: start, maxWeek: 2,
            displayWeek: 2, displayDay: 7, transfers: transfers), CourseOccurrenceIdentity(week: 1, day: 4))
    }

    func testInvalidDisplayCoordinatesAndTableBoundsReject() {
        for (week, day, maxWeek) in [(0, 1, 4), (-1, 1, 4), (1, 0, 4), (1, 8, 4),
                                      (1, 1, 0), (1, 1, -1), (Int.max, 7, 4)] {
            XCTAssertNil(resolve(week, day, maxWeek: maxWeek))
        }
        XCTAssertNil(CourseOccurrenceIdentity.resolve(startDate: "not-a-date", maxWeek: 4,
            displayWeek: 1, displayDay: 1, transfers: []))
    }

    private func makeCourse(id: Int64, day: Int, type: Int) -> CourseEntity {
        CourseEntity(groupId: "identity-\(id)", tableId: 1, courseName: "课程\(id)", day: day,
                     startNode: 1, step: 1, startWeek: 1, endWeek: 4, type: type,
                     color: "#FF123456", id: id)
    }
}
