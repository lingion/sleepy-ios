// DateUtilsTests.swift — ← util/DateUtilsTest.kt 逐用例移植 + 语义钉桩 (GPL-3.0)

import XCTest
@testable import Sleepy

final class DateUtilsTests: XCTestCase {

    private func d(_ s: String) -> Date {
        DateUtils.parseDate(s)!
    }

    // ==== Android 原用例 ====

    func testBeforeSemesterNeverProducesNegativeWeek() {
        XCTAssertEqual(1, DateUtils.currentWeek(startDate: "2026-09-07", today: d("2026-08-24")))
        XCTAssertEqual(.beforeStart, DateUtils.semesterStatus(startDate: "2026-09-07", maxWeek: 20, today: d("2026-08-24")))
    }

    func testDetectsAfterSemester() {
        XCTAssertEqual(.afterEnd, DateUtils.semesterStatus(startDate: "2026-09-07", maxWeek: 20, today: d("2027-02-01")))
    }

    // ==== 语义钉桩(Kotlin 逐行为) ====

    func testCurrentWeekFirstDay() {
        // 开学当天 = 第 1 周
        XCTAssertEqual(1, DateUtils.currentWeek(startDate: "2026-03-02", today: d("2026-03-02")))
        // 第 7 天(周日) 仍是第 1 周
        XCTAssertEqual(1, DateUtils.currentWeek(startDate: "2026-03-02", today: d("2026-03-08")))
        // 第 8 天(下周一) = 第 2 周
        XCTAssertEqual(2, DateUtils.currentWeek(startDate: "2026-03-02", today: d("2026-03-09")))
        // 非法 startDate → 1
        XCTAssertEqual(1, DateUtils.currentWeek(startDate: "bad", today: d("2026-03-02")))
    }

    func testTodayDayOfWeek() {
        // 2026-08-24 是周一
        XCTAssertEqual(1, DateUtils.todayDayOfWeek(today: d("2026-08-24")))
        // 2026-08-30 周日
        XCTAssertEqual(7, DateUtils.todayDayOfWeek(today: d("2026-08-30")))
        // 2026-08-26 周三
        XCTAssertEqual(3, DateUtils.todayDayOfWeek(today: d("2026-08-26")))
    }

    func testDateOfWeek() {
        // 2026-03-02 周一开学 → 第2周周3 = 2026-03-11
        XCTAssertEqual(d("2026-03-11"), DateUtils.dateOfWeek(startDate: "2026-03-02", week: 2, dayOfWeek: 3))
        // 第1周周1 = 开学日
        XCTAssertEqual(d("2026-03-02"), DateUtils.dateOfWeek(startDate: "2026-03-02", week: 1, dayOfWeek: 1))
    }

    func testDateOfWeekDay() {
        // 2026-03-02(周一) 同周的周5 = 2026-03-06
        XCTAssertEqual(d("2026-03-06"), DateUtils.dateOfWeekDay(ref: d("2026-03-02"), dayOfWeek: 5))
        // 参照周三(03-04) 的上周一 = 2026-02-23 (offset = 1-3 = -2? 不, offset=dayOfWeek-ref dow=1-3=-2 → 03-02)
        XCTAssertEqual(d("2026-03-02"), DateUtils.dateOfWeekDay(ref: d("2026-03-04"), dayOfWeek: 1))
    }

    func testIsoWeekNumber() {
        // 2026-01-01 是周四,ISO 周为第 1 周
        XCTAssertEqual(1, DateUtils.isoWeekNumber(d("2026-01-01")))
        // 2026-08-24 落在 ISO 第 35 周
        XCTAssertEqual(35, DateUtils.isoWeekNumber(d("2026-08-24")))
    }

    func testFormatters() {
        XCTAssertEqual("03-02", DateUtils.shortDate(d("2026-03-02")))
        XCTAssertEqual("2026-03-02", DateUtils.fullDate(d("2026-03-02")))
        XCTAssertEqual("3/2", DateUtils.shortDateSlash(d("2026-03-02")))
        XCTAssertEqual("12/31", DateUtils.shortDateSlash(d("2026-12-31")))
    }

    func testChineseDay() {
        XCTAssertEqual("周一", DateUtils.chineseDay(1))
        XCTAssertEqual("周日", DateUtils.chineseDay(7))
        XCTAssertEqual("", DateUtils.chineseDay(0))
        XCTAssertEqual("", DateUtils.chineseDay(8))
    }
}
