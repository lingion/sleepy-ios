import XCTest
@testable import Sleepy

@MainActor
final class HolidayViewportTests: XCTestCase {
    func testBatchMatchesPerDateDecisionsAndFreshPreferences() async throws {
        try await withFixture { dates, tableId, transfers in
            let prefs = AppPrefs.shared
            for holiday in [false, true] {
                for weekend in [false, true] {
                    for ignore in [false, true] {
                        prefs.setHolidayGreyHoliday(holiday)
                        prefs.setHolidayGreyWeekend(weekend)
                        prefs.setHolidayIgnoreWorkday(ignore)
                        var expected: Set<Date> = []
                        for date in dates {
                            if await HolidayManager.shouldGrey(date, tableId: tableId) { expected.insert(date) }
                        }
                        let actual = await HolidayManager.greyDates(dates, tableId: tableId, transfers: transfers)
                        XCTAssertEqual(actual, expected)
                    }
                }
            }
            prefs.setHolidayGreyHoliday(true)
            prefs.setHolidayGreyWeekend(false)
            let before = await HolidayManager.greyDates(dates, tableId: tableId, transfers: transfers)
            prefs.setHolidayRanges([])
            let after = await HolidayManager.greyDates(dates, tableId: tableId, transfers: transfers)
            XCTAssertNotEqual(before, after, "Editing overrides must take effect without restarting the cache")
            let empty = await HolidayManager.greyDates([], tableId: tableId)
            XCTAssertEqual(empty, [])
        }
    }

    func testBenchmarkViewportBatchAgainstPerCellWork() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1")
        try await withFixture { dates, tableId, transfers in
            var checksum = 0
            var individual: [Double] = []
            var batched: [Double] = []
            _ = await HolidayManager.greyDates(dates, tableId: tableId, transfers: transfers)
            for _ in 0..<7 {
                var start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<10 {
                    for date in dates {
                        if await HolidayManager.shouldGrey(date, tableId: tableId) { checksum &+= 1 }
                    }
                }
                individual.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 10 / 1_000_000)
                start = DispatchTime.now().uptimeNanoseconds
                for _ in 0..<10 {
                    let grey = await HolidayManager.greyDates(dates, tableId: tableId, transfers: transfers)
                    checksum &+= grey.count
                }
                batched.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 10 / 1_000_000)
            }
            print("GREY_BENCH per_cell_ms=\(individual) median=\(individual.sorted()[3]) batch_ms=\(batched) median=\(batched.sorted()[3]) checksum=\(checksum)")
        }
    }

    private func withFixture(_ operation: ([Date], Int64, [HolidayTransferEntry]) async throws -> Void) async throws {
        let prefs = AppPrefs.shared
        let store = prefs.sharedBackedStore
        let tableId: Int64 = 9_192_093
        let keys = [AppPrefs.KEY_HOLIDAY_GREY_HOLIDAY, AppPrefs.KEY_HOLIDAY_GREY_WEEKEND,
                    AppPrefs.KEY_HOLIDAY_IGNORE_WORKDAY, AppPrefs.KEY_HOLIDAY_OVERRIDES,
                    "holiday_transfer_\(tableId)", "holiday_entries_2093", "holiday_entries_2093_loaded"]
        let original = keys.map { ($0, store.object(forKey: $0)) }
        defer {
            for (key, value) in original {
                if let value { store.set(value, forKey: key) } else { store.removeObject(forKey: key) }
            }
        }
        store.set("[]", forKey: "holiday_entries_2093")
        store.set(true, forKey: "holiday_entries_2093_loaded")
        let start = try XCTUnwrap(DateUtils.parseDate("2093-09-07"))
        let dates = (0..<21).compactMap { CourseOccurrences.calendar.date(byAdding: .day, value: $0, to: start) }
        let transfer = HolidayTransferEntry(sourceDate: dates[0], targetDate: dates[6], segmentId: "probe")
        prefs.setHolidayTransfers(tableId, [transfer])
        prefs.setHolidayRanges([HolidayRange(id: "probe", name: "Holiday", startDate: dates[1],
            endDate: dates[3], type: HolidayManager.TYPE_PUBLIC_HOLIDAY, sourceKey: nil)])
        prefs.setHolidayGreyHoliday(true)
        prefs.setHolidayGreyWeekend(true)
        prefs.setHolidayIgnoreWorkday(true)
        try await operation(dates, tableId, [transfer])
    }
}
