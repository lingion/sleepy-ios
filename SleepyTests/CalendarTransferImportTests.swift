// CalendarTransferImportTests.swift — v1.0.62 B6 日历导入调休口径最小单测
// (SystemCalendarManager.kt v1.0.62; 原版本 侧无对应单测, 按 Kotlin 实现语义锁定)
//
// 锁两条口径:
//   1. selectedDateRange: 导入日期范围纳入调休目标日 — 源日在学期内的 targetDate
//      可把 SEMESTER 区间撑出学期末 / 把 start 提前到学期初之前; 源日出学期则不参与扩展。
//   2. buildEventSpecs: 事件内容按源日(courseDateForDate/coursesForDate — 放假日无课、
//      补班日上源日的课), 显示落位按目标日; 周次标签跟源日走。

import XCTest
@testable import Sleepy

final class CalendarTransferImportTests: XCTestCase {

    // 学期: 2026-09-07(周一) 起 18 周 → 学期末 2027-01-11
    private func table() -> TimeTableEntity {
        var t = TimeTableEntity(name: "T", startDate: "2026-09-07", maxWeek: 18, nodesPerDay: 12)
        t.id = 1
        return t
    }

    /// 周日的课 (调休补班常落在周六/周日)
    private func sundayCourse() -> CourseEntity {
        var c = CourseEntity(groupId: "g", tableId: 1, courseName: "高数", day: 7,
                             startNode: 1, step: 2, startWeek: 1, endWeek: 16, color: "#FF6750A4")
        c.id = 7
        return c
    }

    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = day; c.hour = 0
        c.timeZone = TimeZone(secondsFromGMT: 0)  // UTC for consistent CI behavior
        return Calendar(identifier: .gregorian).date(from: c)!
    }
    
    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)
        cal.firstWeekday = 2
        return cal
    }

    // ---- selectedDateRange: 目标日扩展 ----

    func testSemesterRange_extendsPastSemesterEndToLatestValidTarget() {
        let t = table()
        let today = d(2026, 10, 10)
        let cal = utcCalendar()
        // 基线: 学期末 2027-01-11
        let base = SystemCalendarManager.selectedDateRange(table: t, range: .SEMESTER, today: today, calendar: cal)
        XCTAssertEqual(DateUtils.dayStart(d(2026, 10, 10)), base.start)
        XCTAssertEqual(DateUtils.dayStart(d(2027, 1, 11)), base.end)
        // 源日 2026-10-08(周四, 第5周) 在学期内 → 目标日 2027-01-15 把 end 撑到 +1 天
        let transfers = [HolidayTransferEntry(sourceDate: d(2026, 10, 8), targetDate: d(2027, 1, 15), segmentId: "s")]
        let ext = SystemCalendarManager.selectedDateRange(table: t, range: .SEMESTER, today: today, transfers: transfers, calendar: cal)
        XCTAssertEqual(DateUtils.dayStart(d(2026, 10, 10)), ext.start)
        XCTAssertEqual(DateUtils.dayStart(d(2027, 1, 16)), ext.end)
    }

    func testSemesterRange_earlyTargetPullsStartBeforeSemesterStart() {
        let t = table()
        let today = d(2026, 8, 25)  // 开学前
        let cal = utcCalendar()
        // 基线: start 钳到学期初 2026-09-07
        let base = SystemCalendarManager.selectedDateRange(table: t, range: .SEMESTER, today: today, calendar: cal)
        XCTAssertEqual(DateUtils.dayStart(d(2026, 9, 7)), base.start)
        // 源日 2026-09-10(第1周) 在学期内 → 目标日 2026-08-30 把 start 提前
        let transfers = [HolidayTransferEntry(sourceDate: d(2026, 9, 10), targetDate: d(2026, 8, 30), segmentId: "s")]
        let ext = SystemCalendarManager.selectedDateRange(table: t, range: .SEMESTER, today: today, transfers: transfers, calendar: cal)
        XCTAssertEqual(DateUtils.dayStart(d(2026, 8, 30)), ext.start)
        XCTAssertEqual(DateUtils.dayStart(d(2027, 1, 11)), ext.end)
    }

    func testSemesterRange_outOfSemesterSourceDoesNotExtend() {
        let t = table()
        let today = d(2026, 10, 10)
        let cal = utcCalendar()
        // 源日 2027-03-01 已出学期(第26周 > maxWeek 18) → 该映射不参与区间扩展
        let transfers = [HolidayTransferEntry(sourceDate: d(2027, 3, 1), targetDate: d(2027, 1, 15), segmentId: "s")]
        let r = SystemCalendarManager.selectedDateRange(table: t, range: .SEMESTER, today: today, transfers: transfers, calendar: cal)
        XCTAssertEqual(DateUtils.dayStart(d(2026, 10, 10)), r.start)
        XCTAssertEqual(DateUtils.dayStart(d(2027, 1, 11)), r.end)
    }

    // ---- buildEventSpecs: 源日内容 / 目标日落位 ----

    /// 调休映射写入 AppPrefs(buildEventSpecs 从 prefs 读), 用完恢复
    private func withTransfers(_ tableId: Int64, _ transfers: [HolidayTransferEntry],
                               _ body: () throws -> Void) rethrows {
        let original = AppPrefs.shared.getHolidayTransfers(tableId)
        AppPrefs.shared.setHolidayTransfers(tableId, transfers)
        defer { AppPrefs.shared.setHolidayTransfers(tableId, original) }
        try body()
    }

    func testBuildEventSpecs_makeupDayCarriesSourceDayContentAndWeek() throws {
        let t = table()
        let cal = utcCalendar()
        // 放假日 2026-10-11(周日, 第5周) 的课调到 2026-10-17(周六, 第6周) 补
        let transfers = [HolidayTransferEntry(sourceDate: d(2026, 10, 11), targetDate: d(2026, 10, 17), segmentId: "s")]
        let options = CalendarImportOptions(calendarId: "test", applyHolidayTransfers: true)
        try withTransfers(t.id, transfers) {
            let (specs, invalid) = SystemCalendarManager.shared.buildEventSpecs(
                table: t, courses: [sundayCourse()], options: options,
                from: d(2026, 10, 17), until: d(2026, 10, 18), calendar: cal)
            XCTAssertEqual(0, invalid)
            XCTAssertEqual(1, specs.count)
            let spec = try XCTUnwrap(specs.first)
            // 落位在目标日
            XCTAssertEqual(DateUtils.dayStart(d(2026, 10, 17)), DateUtils.dayStart(spec.date))
            // 内容/周次跟源日: 第5周(源日 10-11 所在周), 而非目标日所在第6周
            XCTAssertEqual(5, spec.week)
            XCTAssertEqual("高数", spec.course.courseName)
            XCTAssertEqual("08:00", spec.startHHmm)
            XCTAssertEqual("09:40", spec.endHHmm)
            // 调课提示按源日星期(周日), marker 落目标日
            XCTAssertTrue(spec.description.contains("调课安排：按周日课程"), spec.description)
            XCTAssertTrue(spec.description.contains("2026-10-17"), spec.description)
            XCTAssertEqual("1:7:2026-10-17", spec.key)
        }
    }

    func testBuildEventSpecs_holidayDayItselfHasNoEvents() throws {
        let t = table()
        let cal = utcCalendar()
        let transfers = [HolidayTransferEntry(sourceDate: d(2026, 10, 11), targetDate: d(2026, 10, 17), segmentId: "s")]
        let options = CalendarImportOptions(calendarId: "test", applyHolidayTransfers: true)
        try withTransfers(t.id, transfers) {
            // 放假日当天(10-11)无课 — 课已被挪走
            let (specs, _) = SystemCalendarManager.shared.buildEventSpecs(
                table: t, courses: [sundayCourse()], options: options,
                from: d(2026, 10, 11), until: d(2026, 10, 12), calendar: cal)
            XCTAssertEqual(0, specs.count)
        }
    }

    func testBuildEventSpecs_withoutTransfersSaturdayStaysEmpty() {
        let t = table()
        let cal = utcCalendar()
        // 不启用调休: 周六(10-17)按自然星期取课, 无周日课 → 空
        let options = CalendarImportOptions(calendarId: "test", applyHolidayTransfers: false)
        let (specs, invalid) = SystemCalendarManager.shared.buildEventSpecs(
            table: t, courses: [sundayCourse()], options: options,
            from: d(2026, 10, 17), until: d(2026, 10, 18), calendar: cal)
        XCTAssertEqual(0, invalid)
        XCTAssertEqual(0, specs.count)
    }
}
