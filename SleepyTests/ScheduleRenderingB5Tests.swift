// ScheduleRenderingB5Tests.swift — v1.0.62 B5b 渲染口径单测
// 覆盖: displayMaxWeek(调休目标周并入) / longBreakCardHeightDp(带厚不进卡高) /
//       反向取课(补班日=sourceDate、放假日=无课, 经 HolidayTransferOps/HolidayReminderPolicy 域) /
//       shortDateChinese(M月d日 无前导零)
// ← 原 DateUtilsTest.kt / TimetableViewportPolicyTest.kt / ConflictCardGeometryTest.kt 同域

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

    /// source 学期外(semesterStatus != IN_RANGE)的映射不参与上限并入 ← 原 filter 口径
    func testDisplayMaxWeek_ignoresOutOfRangeSource() {
        let source = DateUtils.dateOfWeek(startDate: start, week: 25, dayOfWeek: 3)!
        let target = DateUtils.dateOfWeek(startDate: start, week: 26, dayOfWeek: 5)!
        let st = makeState(maxWeek: 20, transfers: [
            HolidayTransferEntry(sourceDate: source, targetDate: target, segmentId: "s1")
        ])
        XCTAssertEqual(st.displayMaxWeek, 20)
    }

    /// 无表 → 兜底 20(与 原 `?: 20` 同口径)
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

    // MARK: - 今天页日期上下文

    func testTodayContextUsesSourceWeekForCrossWeekMakeup() {
        let source = DateUtils.dateOfWeek(startDate: start, week: 2, dayOfWeek: 4)!
        let today = DateUtils.dateOfWeek(startDate: start, week: 5, dayOfWeek: 7)!
        let state = makeState(maxWeek: 20, transfers: [
            HolidayTransferEntry(sourceDate: source, targetDate: today, segmentId: "today")
        ])

        let context = TodayDisplayContext(state: state, today: today)

        XCTAssertEqual(context.actualWeek, 2)
        XCTAssertEqual(context.semesterStatus, .inRange)
        XCTAssertEqual(context.date, today, "日期标题仍显示实际补课日")
    }

    func testTodayContextUsesInSemesterSourceBeforeSemesterStarts() {
        let source = DateUtils.parseDate("2026-09-07")!
        let today = DateUtils.parseDate("2026-09-06")!
        let state = makeState(maxWeek: 1, transfers: [
            HolidayTransferEntry(sourceDate: source, targetDate: today, segmentId: "early")
        ])

        let context = TodayDisplayContext(state: state, today: today)

        XCTAssertEqual(context.actualWeek, 1)
        XCTAssertEqual(context.semesterStatus, .inRange)
        XCTAssertEqual(context.date, today)
    }

    func testTodayContextUsesInSemesterSourceAfterSemesterEnds() {
        let source = DateUtils.parseDate("2026-09-07")!
        let today = DateUtils.parseDate("2026-09-20")!
        let state = makeState(maxWeek: 1, transfers: [
            HolidayTransferEntry(sourceDate: source, targetDate: today, segmentId: "late")
        ])

        let context = TodayDisplayContext(state: state, today: today)

        XCTAssertEqual(context.actualWeek, 1)
        XCTAssertEqual(context.semesterStatus, .inRange)
        XCTAssertEqual(context.date, today)
    }

    func testTodayContextUsesNaturalDateForHolidayAndUnmappedDays() {
        let source = DateUtils.parseDate("2026-09-07")!
        let target = DateUtils.parseDate("2026-09-20")!
        let state = makeState(maxWeek: 1, transfers: [
            HolidayTransferEntry(sourceDate: source, targetDate: target, segmentId: "holiday")
        ])
        XCTAssertNil(state.courseDateFor(source), "放假原日没有取课源日期")

        let holiday = TodayDisplayContext(state: state, today: source)
        XCTAssertEqual(holiday.actualWeek, 1)
        XCTAssertEqual(holiday.semesterStatus, .inRange)
        XCTAssertEqual(holiday.date, source)

        let unmappedDate = DateUtils.parseDate("2026-09-14")!
        let unmapped = TodayDisplayContext(state: state, today: unmappedDate)
        XCTAssertEqual(unmapped.actualWeek, 2)
        XCTAssertEqual(unmapped.semesterStatus, .afterEnd)
        XCTAssertEqual(unmapped.date, unmappedDate)
    }

    func testTodayContextWithoutCurrentTableKeepsStateFallback() {
        let today = DateUtils.parseDate("2026-09-20")!
        var state = ScheduleState()
        state.currentWeek = 7

        let context = TodayDisplayContext(state: state, today: today)

        XCTAssertEqual(context.actualWeek, 7)
        XCTAssertEqual(context.semesterStatus, .inRange)
        XCTAssertEqual(context.date, today)
    }

    // MARK: - shortDateChinese

    /// M月d日 无前导零 ← DateUtils.kt shortDateChinese
    func testShortDateChinese_noLeadingZeros() {
        XCTAssertEqual(DateUtils.shortDateChinese(DateUtils.parseDate("2026-10-05")!), "10月5日")
        XCTAssertEqual(DateUtils.shortDateChinese(DateUtils.parseDate("2026-01-06")!), "1月6日")
        XCTAssertEqual(DateUtils.shortDateChinese(DateUtils.parseDate("2026-12-31")!), "12月31日")
    }
}
