// ScheduleRenderingB5Tests.swift — v1.0.62 B5b 渲染口径单测
// 覆盖: displayMaxWeek(调休目标周并入) / longBreakCardHeightDp(带厚不进卡高) /
//       反向取课(补班日=sourceDate、放假日=无课, 经 HolidayTransferOps/HolidayReminderPolicy 域) /
//       shortDateChinese(M月d日 无前导零)
// ← Android DateUtilsTest.kt / TimetableViewportPolicyTest.kt / ConflictCardGeometryTest.kt 同域

import XCTest
@testable import Sleepy

final class ScheduleRenderingB5Tests: XCTestCase {

    // MARK: - displayMaxWeek (ScheduleState 纯结构体)

    private let start = "2026-09-07"   // 学期起点(周一锚定由 mondayOf 保证, 任意星期输入同口径)

    private func makeState(maxWeek: Int, transfers: [HolidayTransferEntry]) -> ScheduleState {
        var st = ScheduleState()
        var table = TimeTableEntity(name: "T", startDate: start)
        table.maxWeek = maxWeek
        table.id = 1
        st.tables = [table]
        st.selectedTableId = 1
        st.transfers = transfers
        return st
    }

    /// 无调休映射 → displayMaxWeek = 表 maxWeek
    func testDisplayMaxWeek_baseTableOnly() {
        let st = makeState(maxWeek: 20, transfers: [])
        XCTAssertEqual(st.displayMaxWeek, 20)
    }

    /// 学期内 source + 越过学期末的 target → 上限并入 target 所在周
    func testDisplayMaxWeek_extendsToTransferTargetWeek() {
        let source = DateUtils.dateOfWeek(startDate: start, week: 10, dayOfWeek: 4)!
        let target = DateUtils.dateOfWeek(startDate: start, week: 21, dayOfWeek: 6)!
        let st = makeState(maxWeek: 20, transfers: [
            HolidayTransferEntry(sourceDate: source, targetDate: target, segmentId: "s1")
        ])
        XCTAssertEqual(st.displayMaxWeek, 21)
    }

    /// target 未越过学期末 → 上限保持表 maxWeek(max 取大者)
    func testDisplayMaxWeek_targetInsideSemesterKeepsMaxWeek() {
        let source = DateUtils.dateOfWeek(startDate: start, week: 10, dayOfWeek: 4)!
        let target = DateUtils.dateOfWeek(startDate: start, week: 18, dayOfWeek: 6)!
        let st = makeState(maxWeek: 20, transfers: [
            HolidayTransferEntry(sourceDate: source, targetDate: target, segmentId: "s1")
        ])
        XCTAssertEqual(st.displayMaxWeek, 20)
    }

    /// source 学期外(semesterStatus != IN_RANGE)的映射不参与上限并入 ← Android filter 口径
    func testDisplayMaxWeek_ignoresOutOfRangeSource() {
        let source = DateUtils.dateOfWeek(startDate: start, week: 25, dayOfWeek: 3)!
        let target = DateUtils.dateOfWeek(startDate: start, week: 26, dayOfWeek: 5)!
        let st = makeState(maxWeek: 20, transfers: [
            HolidayTransferEntry(sourceDate: source, targetDate: target, segmentId: "s1")
        ])
        XCTAssertEqual(st.displayMaxWeek, 20)
    }

    /// 无表 → 兜底 20(与 Android `?: 20` 同口径)
    func testDisplayMaxWeek_noTableFallsBackTo20() {
        let st = ScheduleState()
        XCTAssertEqual(st.displayMaxWeek, 20)
    }

    // MARK: - longBreakCardHeightDp (带厚不进卡高)

    /// 卡高 = natural 跨度 − 普通行隙; 签名无带参数 = 带厚双扣口径不可表达
    func testLongBreakCardHeightDp_bandNotFoldedIntoCardHeight() {
        // 2 标准行(56×2) − gap 4 = 108 — 无任何"带厚"参与
        XCTAssertEqual(TimetableViewportPolicy.longBreakCardHeightDp(naturalSpanDp: 112, gapDp: 4), 108)
        // 1.5 行(84) − 4 = 80
        XCTAssertEqual(TimetableViewportPolicy.longBreakCardHeightDp(naturalSpanDp: 84, gapDp: 4), 80)
    }

    /// minSpanDp 保底: ownTime 短课 max(natural, 0.3 标准行) − gap
    func testLongBreakCardHeightDp_minSpanFloor() {
        // natural 10dp < 保底 16.8 → max(10, 16.8) − 4 = 12.8
        XCTAssertEqual(
            TimetableViewportPolicy.longBreakCardHeightDp(naturalSpanDp: 10, gapDp: 4, minSpanDp: 16.8),
            12.8, accuracy: 0.0001)
        // natural 30dp > 保底 → 30 − 4 = 26
        XCTAssertEqual(
            TimetableViewportPolicy.longBreakCardHeightDp(naturalSpanDp: 30, gapDp: 4, minSpanDp: 16.8),
            26, accuracy: 0.0001)
        // 缺省 minSpanDp = 0 → 纯 natural − gap
        XCTAssertEqual(TimetableViewportPolicy.longBreakCardHeightDp(naturalSpanDp: 40, gapDp: 4), 36)
    }

    // MARK: - 反向取课 (经 HolidayTransferOps / ScheduleState)

    private func makeCourse(id: Int64, day: Int, startWeek: Int, endWeek: Int) -> CourseEntity {
        var c = CourseEntity(groupId: "g\(id)", tableId: 1, courseName: "课\(id)",
                             day: day, startNode: 1, step: 2,
                             startWeek: startWeek, endWeek: endWeek,
                             color: "#FF6750A4")
        c.id = id
        return c
    }

    /// 补班日 = sourceDate 星期的课; 放假日 = 无课; 未命中日 = 自然星期
    func testReverseCourseLookup_makeupDayCarriesSourceCourses() {
        // 第 10 周周四(放假日) → 第 10 周周日(补班日)
        let source = DateUtils.dateOfWeek(startDate: start, week: 10, dayOfWeek: 4)!
        let target = DateUtils.dateOfWeek(startDate: start, week: 10, dayOfWeek: 7)!
        let transfers = [HolidayTransferEntry(sourceDate: source, targetDate: target, segmentId: "s1")]
        let thursday = makeCourse(id: 1, day: 4, startWeek: 1, endWeek: 20)
        let sunday = makeCourse(id: 2, day: 7, startWeek: 1, endWeek: 20)
        let monday = makeCourse(id: 3, day: 1, startWeek: 1, endWeek: 20)
        let courses = [thursday, sunday, monday]

        // 补班日(周日)上的是周四的课 ← courseDateForDate(target) = sourceDate
        let targetCourses = HolidayTransferOps.coursesForDate(
            target, startDate: start, maxWeek: 20, courses: courses, transfers: transfers)
        XCTAssertEqual(targetCourses.map { $0.id }, [1], "补班日 = sourceDate 星期的课")
        XCTAssertEqual(HolidayTransferOps.courseDateForDate(target, transfers), source)

        // 放假日(周四)无课 ← courseDateForDate(source) = nil
        XCTAssertTrue(HolidayTransferOps.coursesForDate(
            source, startDate: start, maxWeek: 20, courses: courses, transfers: transfers).isEmpty,
            "放假日课被挪走 = 无课")
        XCTAssertNil(HolidayTransferOps.courseDateForDate(source, transfers))

        // 未命中日(周一) = 原日期自然取课
        let unmapped = DateUtils.dateOfWeek(startDate: start, week: 10, dayOfWeek: 1)!
        XCTAssertEqual(HolidayTransferOps.courseDateForDate(unmapped, transfers), unmapped)
        XCTAssertEqual(HolidayTransferOps.coursesForDate(
            unmapped, startDate: start, maxWeek: 20, courses: courses, transfers: transfers).map { $0.id },
            [3])
    }

    /// ScheduleState.courseDateFor/courseDayFor 反向口径(结构体级, 无 VM 依赖)
    func testScheduleState_courseDateForAndCourseDayFor() {
        let source = DateUtils.dateOfWeek(startDate: start, week: 10, dayOfWeek: 4)!
        let target = DateUtils.dateOfWeek(startDate: start, week: 10, dayOfWeek: 7)!
        var st = makeState(maxWeek: 20, transfers: [
            HolidayTransferEntry(sourceDate: source, targetDate: target, segmentId: "s1")
        ])
        // 补班日按 sourceDate 星期取课(周日 → 4)
        XCTAssertEqual(st.courseDayFor(target), 4)
        XCTAssertEqual(st.courseDateFor(target), source)
        // 放假日无课(nil)
        XCTAssertNil(st.courseDayFor(source))
        XCTAssertNil(st.courseDateFor(source))
        // 未映射日走自然星期
        let unmapped = DateUtils.dateOfWeek(startDate: start, week: 10, dayOfWeek: 3)!
        XCTAssertEqual(st.courseDayFor(unmapped), 3)

        // 空映射 → 恒自然星期(与旧 effectiveDayOfWeek 兜底一致)
        st.transfers = []
        XCTAssertEqual(st.courseDayFor(target), 7)
    }

    // MARK: - shortDateChinese

    /// M月d日 无前导零 ← DateUtils.kt shortDateChinese
    func testShortDateChinese_noLeadingZeros() {
        XCTAssertEqual(DateUtils.shortDateChinese(DateUtils.parseDate("2026-10-05")!), "10月5日")
        XCTAssertEqual(DateUtils.shortDateChinese(DateUtils.parseDate("2026-01-06")!), "1月6日")
        XCTAssertEqual(DateUtils.shortDateChinese(DateUtils.parseDate("2026-12-31")!), "12月31日")
    }
}
