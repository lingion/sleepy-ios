import XCTest
@testable import Sleepy

final class WidgetCompactWindowParityTests: XCTestCase {
    // 2426 has the same weekdays as 2026. A private fixture year keeps the real
    // holiday loader offline without replacing the cache used by other tests.
    private let startDate = "2426-09-07"
    private let tableId: Int64 = 2_426_106_301
    private var previousTransfers: [HolidayTransferEntry] = []
    private var previousHolidayCache: [String: Any] = [:]
    private let holidayCacheKeys = ["holiday_entries_2426", "holiday_entries_2426_loaded"]

    override func setUpWithError() throws {
        try super.setUpWithError()
        previousTransfers = AppPrefs.shared.getHolidayTransfers(tableId)
        AppPrefs.shared.setHolidayTransfers(tableId, [])
        let store = AppPrefs.shared.sharedBackedStore
        for key in holidayCacheKeys {
            if let value = store.object(forKey: key) { previousHolidayCache[key] = value }
        }
        store.set("[]", forKey: holidayCacheKeys[0])
        store.set(true, forKey: holidayCacheKeys[1])
    }

    override func tearDownWithError() throws {
        AppPrefs.shared.setHolidayTransfers(tableId, previousTransfers)
        let store = AppPrefs.shared.sharedBackedStore
        for key in holidayCacheKeys {
            if let previous = previousHolidayCache[key] { store.set(previous, forKey: key) }
            else { store.removeObject(forKey: key) }
        }
        previousHolidayCache.removeAll()
        try super.tearDownWithError()
    }

    private func date(_ key: String) -> Date { DateUtils.parseDate(key)! }

    private func row(_ id: Int64, day: Int, first: Int = 1, last: Int = 3,
                     type: Int = 0, node: Int = 1, fixed: String? = nil) -> CourseEntity {
        CourseEntity(groupId: "compact-\(id)", tableId: tableId, courseName: "Course \(id)",
                     day: day, startNode: node, step: 1, startWeek: first, endWeek: last,
                     type: type, color: "#FF6750A4", id: id, fixedDate: fixed)
    }

    private func transfer(_ source: String, _ target: String) {
        AppPrefs.shared.setHolidayTransfers(tableId, [
            HolidayTransferEntry(sourceDate: date(source), targetDate: date(target), segmentId: "compact")
        ])
    }

    private func build(_ rows: [CourseEntity], today: String, todayFirst: Bool = true,
                       displayDate: String? = nil, maxWeek: Int = 3,
                       todayTimeOffset: TimeInterval = 0) async throws -> [DayData] {
        let database = try AppDatabase.inMemory()
        let table = TimeTableEntity(name: "Compact window", startDate: startDate,
                                   maxWeek: maxWeek, timeJson: "[]", id: tableId)
        // Seed the real database without repository write hooks/undo snapshots;
        // the production builder reads it through the real ScheduleRepository.
        try database.timeTableDao.insert(table)
        for course in rows { try database.courseDao.insert(course) }
        return await WidgetCompactWindow.build(
            repo: ScheduleRepository(database), tableId: tableId, timeJson: table.timeJson,
            startDate: startDate, maxWeek: maxWeek,
            today: date(today).addingTimeInterval(todayTimeOffset), todayFirst: todayFirst,
            displayDate: displayDate.map { date($0) }
        )
    }

    private func day(_ days: [DayData], _ key: String,
                     file: StaticString = #filePath, line: UInt = #line) throws -> DayData {
        try XCTUnwrap(days.first { HolidayTransferOps.dayKey($0.date) == key }, file: file, line: line)
    }

    func testWindowPreservesCalendarOrderAndEachDatesTeachingWeekAcrossSunday() async throws {
        let rows = [row(1, day: 7, first: 1, last: 1),
                    row(2, day: 1, first: 2, last: 2),
                    row(3, day: 2, first: 2, last: 2),
                    row(4, day: 1, first: 1, last: 1)]
        for todayFirst in [true, false] {
            let days = try await build(rows, today: todayFirst ? "2426-09-13" : "2426-09-14",
                                       todayFirst: todayFirst)
            XCTAssertEqual(days.map { HolidayTransferOps.dayKey($0.date) },
                           ["2426-09-13", "2426-09-14", "2426-09-15"])
            XCTAssertEqual(days.map(\.dayOfWeek), [7, 1, 2])
            XCTAssertEqual(days.map { $0.courses.map(\.id) }, [[1], [2], [3]])
        }
    }

    func testMovedHolidayIsEmptyAndKeepsItsNaturalWeekday() async throws {
        transfer("2426-09-07", "2426-09-20")
        let days = try await build([row(1, day: 1), row(2, day: 7)], today: "2426-09-07")
        let holiday = try day(days, "2426-09-07")
        XCTAssertEqual(holiday.dayOfWeek, 1, "Column labels and visible-day filtering follow the displayed date")
        XCTAssertTrue(holiday.courses.isEmpty, "The moved-out day must not show the target weekday's courses")
    }

    func testMakeupDayUsesSourceWeekdayAndKeepsCoursesInNodeOrder() async throws {
        transfer("2426-09-07", "2426-09-20")
        let days = try await build([row(1, day: 1, first: 1, last: 1, node: 5),
                                    row(2, day: 1, first: 1, last: 1, node: 1),
                                    row(3, day: 7, first: 2, last: 2)], today: "2426-09-20")
        let makeup = try day(days, "2426-09-20")
        XCTAssertEqual(makeup.dayOfWeek, 7)
        XCTAssertEqual(makeup.courses.map(\.id), [2, 1], "Use source Monday, replacing destination Sunday's own courses")
    }

    func testSameWeekdayCrossWeekMakeupUsesSourceOddEvenWeek() async throws {
        transfer("2426-09-07", "2426-09-14")
        let days = try await build([row(1, day: 1, type: 1), row(2, day: 1, type: 2)],
                                   today: "2426-09-14")
        XCTAssertEqual(try day(days, "2426-09-14").courses.map(\.id), [1],
                       "Destination week 2 still teaches source week 1's odd-week course")
    }

    func testPostSemesterMakeupRetainsInSemesterSourceCourses() async throws {
        transfer("2426-09-07", "2426-10-04")
        let days = try await build([row(1, day: 1, first: 1, last: 1), row(2, day: 7)],
                                   today: "2426-10-04", maxWeek: 1)
        XCTAssertEqual(try day(days, "2426-10-04").courses.map(\.id), [1],
                       "Semester bounds apply to the original teaching date")
    }

    func testFixedDateStaysOnHolidayAndIsNotMovedToMakeupDay() async throws {
        transfer("2426-09-07", "2426-09-20")
        let rows = [row(1, day: 1), row(2, day: 1, fixed: "2426-09-07")]
        let source = try await build(rows, today: "2426-09-07")
        let target = try await build(rows, today: "2426-09-20")
        XCTAssertEqual(try day(source, "2426-09-07").courses.map(\.id), [2])
        XCTAssertEqual(try day(target, "2426-09-20").courses.map(\.id), [1])
    }

    func testFixedDateDoesNotRepeatOnItsMetadataWeekday() async throws {
        let days = try await build([row(1, day: 1, fixed: "2426-09-07")], today: "2426-09-14")
        XCTAssertTrue(try day(days, "2426-09-14").courses.isEmpty)
    }

    func testFixedDateAfterSemesterIgnoresStaleWeekAndWeekdayMetadata() async throws {
        let days = try await build([row(1, day: 4, first: 1, last: 1, fixed: "2426-10-04")],
                                   today: "2426-10-04")
        XCTAssertEqual(try day(days, "2426-10-04").courses.map(\.id), [1])
        XCTAssertTrue(try day(days, "2426-10-05").courses.isEmpty)
    }

    func testBeforeStartPreviewContainsOnlyRecurringWeekOneCourses() async throws {
        let days = try await build([row(1, day: 1, first: 1, last: 1),
                                    row(2, day: 1, first: 2, last: 2),
                                    row(3, day: 1, fixed: "2426-09-07")], today: "2426-08-31")
        XCTAssertEqual(try day(days, "2426-08-31").courses.map(\.id), [1],
                       "Pre-semester previews must not repeat a future fixed-date course")
    }

    func testBeforeStartMakeupUsesSourceWeekAndKeepsFixedDateOnActualTarget() async throws {
        transfer("2426-09-14", "2426-09-06")
        let days = try await build([row(1, day: 1, first: 2, last: 2),
                                    row(2, day: 7, first: 1, last: 1),
                                    row(3, day: 7, first: 1, last: 1, fixed: "2426-09-06")],
                                   today: "2426-09-06")
        XCTAssertEqual(try day(days, "2426-09-06").courses.map(\.id), [1, 3],
                       "An early makeup date uses actual source courses, bypassing the week-one preview")
    }

    func testDisplayDateAnchorsTodaySecondWindowToNearestBusyDate() async throws {
        let days = try await build([row(1, day: 1, first: 2, last: 2)], today: "2426-08-31",
                                   todayFirst: false, displayDate: "2426-09-14")
        XCTAssertEqual(days.map { HolidayTransferOps.dayKey($0.date) },
                       ["2426-09-13", "2426-09-14", "2426-09-15"])
        XCTAssertEqual(try day(days, "2426-09-14").courses.map(\.id), [1])
    }

    func testBeforeStartPreviewUsesCivilDateWhenTodayContainsTimeOfDay() async throws {
        let days = try await build([row(1, day: 1, first: 1, last: 1),
                                    row(2, day: 1, first: 2, last: 2),
                                    row(3, day: 1, fixed: "2426-09-07")],
                                   today: "2426-08-31", todayTimeOffset: 12 * 3600 + 34 * 60)
        XCTAssertEqual(days.map { HolidayTransferOps.dayKey($0.date) },
                       ["2426-08-31", "2426-09-01", "2426-09-02"])
        XCTAssertEqual(try day(days, "2426-08-31").courses.map(\.id), [1],
                       "A 12:34 timeline date must retain the original civil day's week-one preview")
    }
}
