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

    // ← DateUtilsTest.kt:19-21 semesterStartDayIsInRange
    func testSemesterStartDayIsInRange() {
        XCTAssertEqual(.inRange, DateUtils.semesterStatus(startDate: "2026-09-07", maxWeek: 20, today: d("2026-09-07")))
    }

    // ← DateUtilsTest.kt:23-26 lastDayOfMaxWeekIsStillInRange
    func testLastDayOfMaxWeekIsStillInRange() {
        // 第 20 周最后一天: start + 20*7 - 1 = 2026-09-07 + 139 = 2027-01-24
        XCTAssertEqual(.inRange, DateUtils.semesterStatus(startDate: "2026-09-07", maxWeek: 20, today: d("2027-01-24")))
    }

    // ← DateUtilsTest.kt:28-30 dayAfterMaxWeekIsAfterEnd
    func testDayAfterMaxWeekIsAfterEnd() {
        XCTAssertEqual(.afterEnd, DateUtils.semesterStatus(startDate: "2026-09-07", maxWeek: 20, today: d("2027-01-25")))
    }

    // ← DateUtilsTest.kt:32-34 invalidStartDateFallsBackToInRange
    func testInvalidStartDateFallsBackToInRange() {
        XCTAssertEqual(.inRange, DateUtils.semesterStatus(startDate: "garbage", maxWeek: 20, today: d("2026-08-24")))
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

    // ==== ← DateUtilsTest.kt:51-59 onlyTheConcreteDateIsTodayAcrossWeeks ====

    func testOnlyTheConcreteDateIsTodayAcrossWeeks() {
        let today = d("2026-09-19")  // Saturday
        let currentSaturday = DateUtils.dateOfWeek(startDate: "2026-09-14", week: 1, dayOfWeek: 6)!
        let nextSaturday = DateUtils.dateOfWeek(startDate: "2026-09-14", week: 2, dayOfWeek: 6)!

        XCTAssertEqual(true, DateUtils.isDateToday(currentSaturday, today))
        XCTAssertEqual(false, DateUtils.isDateToday(nextSaturday, today))
        XCTAssertEqual(false, DateUtils.isDateToday(
            DateUtils.dateOfWeek(startDate: "2026-09-14", week: 1, dayOfWeek: 5)!, today))
    }
}

// ==== 非周一 startDate 归一回归 (issue #5: 2026-09-01 是周二, 显示成周一) ====
// ← DateUtilsMondayNormalizeTest (DateUtilsTest.kt:64-175), 2026-08-31 周一 / 2026-09-01 周二
final class DateUtilsMondayNormalizeTests: XCTestCase {

    private func d(_ s: String) -> Date { DateUtils.parseDate(s)! }

    func testNormalizeTuesdayToItsMonday() {
        XCTAssertEqual(d("2026-08-31"), DateUtils.mondayOf(d("2026-09-01")))
    }

    func testNormalizeIsIdentityForMonday() {
        XCTAssertEqual(d("2026-08-31"), DateUtils.mondayOf(d("2026-08-31")))
    }

    func testNormalizeSundayToSameWeekMonday() {
        XCTAssertEqual(d("2026-08-31"), DateUtils.mondayOf(d("2026-09-06")))
    }

    func testDateOfWeekNormalizesNonMondayStart() {
        // 用户填 09-01 当第一周起点 → 第1周周一应是 08-31 而非 09-01 本身
        XCTAssertEqual(d("2026-08-31"), DateUtils.dateOfWeek(startDate: "2026-09-01", week: 1, dayOfWeek: 1))
    }

    func testDateOfWeekTuesdayFromNonMondayStart() {
        // 第1周周二 = 09-01 真实周二
        XCTAssertEqual(d("2026-09-01"), DateUtils.dateOfWeek(startDate: "2026-09-01", week: 1, dayOfWeek: 2))
    }

    func testDateOfWeekSundayFromNonMondayStart() {
        XCTAssertEqual(d("2026-09-06"), DateUtils.dateOfWeek(startDate: "2026-09-01", week: 1, dayOfWeek: 7))
    }

    func testDateOfWeekMondayStartUnchanged() {
        // 合法周一基准行为不变
        XCTAssertEqual(d("2026-09-07"), DateUtils.dateOfWeek(startDate: "2026-09-07", week: 1, dayOfWeek: 1))
        XCTAssertEqual(d("2026-09-08"), DateUtils.dateOfWeek(startDate: "2026-09-07", week: 1, dayOfWeek: 2))
        XCTAssertEqual(d("2026-09-14"), DateUtils.dateOfWeek(startDate: "2026-09-07", week: 2, dayOfWeek: 1))
    }

    func testCurrentWeekTreatsNonMondayStartAsItsMonday() {
        // 存的 09-01, 今天 09-01 → 第1周周二
        XCTAssertEqual(1, DateUtils.currentWeek(startDate: "2026-09-01", today: d("2026-09-01")))
        // 今天 08-31 (周一) 也在第1周
        XCTAssertEqual(1, DateUtils.currentWeek(startDate: "2026-09-01", today: d("2026-08-31")))
        // 09-07 周一 → 第2周 (08-31 起算已过7天)
        XCTAssertEqual(2, DateUtils.currentWeek(startDate: "2026-09-01", today: d("2026-09-07")))
    }

    func testNormalizeStartDateString() {
        XCTAssertEqual("2026-08-31", DateUtils.normalizeStartDate("2026-09-01"))
        XCTAssertEqual("2026-08-31", DateUtils.normalizeStartDate("2026-09-06"))
        XCTAssertEqual("2026-08-31", DateUtils.normalizeStartDate("2026-08-31"))
    }

    func testNormalizeStartDateInvalidPassthrough() {
        XCTAssertEqual("garbage", DateUtils.normalizeStartDate("garbage"))
        XCTAssertEqual("", DateUtils.normalizeStartDate(""))
    }

    // ---- semesterStatus 同一归一口径 (D1/issue#5 类: raw startDate vs mondayOf 劈叉) ----

    func testSemesterStatusTreatsNonMondayStartAsItsMonday() {
        // 存的 09-01(周二), 今天 08-31(周一): currentWeek 说第1周, semesterStatus
        // 不得再说「未开始」(raw 比较 08-31 isBefore 09-01 = true = 劈叉根因)
        XCTAssertEqual(.inRange, DateUtils.semesterStatus(startDate: "2026-09-01", maxWeek: 20, today: d("2026-08-31")))
    }

    func testSemesterStatusWeekOneSundayInRangeForNonMondayStart() {
        XCTAssertEqual(.inRange, DateUtils.semesterStatus(startDate: "2026-09-01", maxWeek: 20, today: d("2026-09-06")))
    }

    func testSemesterStatusAfterEndBoundaryUsesNormalizedStart() {
        // maxWeek=1: 归一后第 2 周起点 = 08-31+7 = 09-07 → AFTER_END
        // (raw 口径 between(09-01, 09-07)=6 → 第1周, 会误报 IN_RANGE)
        XCTAssertEqual(.afterEnd, DateUtils.semesterStatus(startDate: "2026-09-01", maxWeek: 1, today: d("2026-09-07")))
    }

    func testSemesterStatusMondayStartBehaviorUnchanged() {
        // 合法周一基准: 归一是恒等变换, 三态边界逐位不变 (回归守卫)
        XCTAssertEqual(.beforeStart, DateUtils.semesterStatus(startDate: "2026-09-07", maxWeek: 20, today: d("2026-09-06")))
        XCTAssertEqual(.inRange, DateUtils.semesterStatus(startDate: "2026-09-07", maxWeek: 20, today: d("2026-09-07")))
        XCTAssertEqual(.afterEnd, DateUtils.semesterStatus(startDate: "2026-09-07", maxWeek: 1, today: d("2026-09-14")))
    }

    func testSemesterStatusAgreesWithCurrentWeekOnNormalization() {
        // 契约: 两函数必须同一归一口径 — currentWeek=1 (≤maxWeek) 时 semesterStatus 恒 IN_RANGE
        for day in ["2026-08-31", "2026-09-01", "2026-09-06"] {
            let today = d(day)
            XCTAssertEqual(1, DateUtils.currentWeek(startDate: "2026-09-01", today: today))
            XCTAssertEqual(.inRange, DateUtils.semesterStatus(startDate: "2026-09-01", maxWeek: 20, today: today),
                           "currentWeek(2026-09-01, \(day))=1 但 semesterStatus 不在学期内 (D1 劈叉)")
        }
    }
}
