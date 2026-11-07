import XCTest
@testable import Sleepy

final class WatchTimeStripAgendaTests: XCTestCase {
    private func date(_ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: day))!
    }

    private func table() -> TimeTableEntity {
        var table = TimeTableEntity(name: "Time strip", startDate: "2026-08-24", maxWeek: 20)
        table.id = 9997
        return table
    }

    func testSuppliedTransferMappingWorksWithoutProcessLocalPreferences() {
        let table = table()
        let saved = AppPrefs.shared.getHolidayTransfers(table.id)
        AppPrefs.shared.setHolidayTransfers(table.id, [])
        defer { AppPrefs.shared.setHolidayTransfers(table.id, saved) }
        let course = CourseEntity(groupId: "wednesday", tableId: table.id, courseName: "Wednesday",
                                  day: 3, startNode: 1, step: 1, startWeek: 1, endWeek: 20,
                                  color: "#FF6750A4")
        let transfers = [HolidayTransferEntry(sourceDate: date(6), targetDate: date(4), segmentId: "makeup")]
        let items = WatchAgendaCore.dayItems(table: table, courses: [course], date: date(6),
                                             displayMode: "time", transfers: transfers)
        XCTAssertEqual(items.map(\.courseName), ["Wednesday"])
        XCTAssertEqual(items.first?.startLabel, "08:00–08:45")
        XCTAssertEqual(Calendar(identifier: .gregorian).startOfDay(for: items[0].startDate), date(6))
        XCTAssertTrue(WatchAgendaCore.dayItems(table: table, courses: [course], date: date(6),
                                               displayMode: "time", transfers: []).isEmpty)
    }

    func testSuppliedTransferPreservesAfterSemesterMakeupRule() {
        var table = table()
        table.maxWeek = 9
        let course = CourseEntity(groupId: "makeup", tableId: table.id, courseName: "Makeup",
                                  day: 3, startNode: 1, step: 1, startWeek: 1, endWeek: 30,
                                  color: "#FF6750A4")
        let transfers = [HolidayTransferEntry(sourceDate: date(6), targetDate: date(4), segmentId: "makeup")]
        XCTAssertEqual(WatchAgendaCore.dayItems(table: table, courses: [course], date: date(6),
                                                displayMode: "time", transfers: transfers).count, 1)
        XCTAssertTrue(WatchAgendaCore.dayItems(table: table, courses: [course], date: date(6),
                                               displayMode: "time", transfers: []).isEmpty)
    }
}
