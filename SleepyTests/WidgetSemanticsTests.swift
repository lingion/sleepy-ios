// WidgetSemanticsTests.swift — 小组件「行为语义」契约测试
//
// 移植自 原版本 纯逻辑测试 (只搬 iOS 真实实现的那部分约束, 源码扫描/RemoteViews 几何断言全部不搬):
//   · FixedWindowCoreTest.kt      → 窗口不变量 (空天 / ALL_DONE 公共闸 / 锚点 / 行原子 / 页脚 best-effort)
//   · FixedWindowWiringTest.kt    → S/M/L 容量口径表 (Today hDp−58 行30距4 · TwoDay hDp−44 行36距6)
//   · BottomBarFitTest.kt         → 填满档 (footerH=0 不二次预留) + 缺省 footerH 旧语义
//   · TodayOverflowGeometryTest.kt→ 行几何不丢课 + 冲突行高
//   · WidgetBoundarySchedulerTest → 边界分钟纯函数 + 行 end 口径
// Sleepy iOS — 100% port of 原版本

import XCTest
import WidgetKit
@testable import Sleepy

/// Swift 5.8 无 Array.single — 用带基数前置检查的等价物锁死「恰好一行/一门课」语义
private extension Array {
    var one: Element {
        precondition(!isEmpty, "expected 1 element, got 0")
        return self[0]
    }
}

final class WidgetSemanticsTests: XCTestCase {

    // MARK: - fixtures (测试同名构造器)

    /// ownTime 课: effectiveCourseTime 直读 startTime/endTime, 分钟完全受控
    private func course(
        _ id: Int64, day: Int = 1, startNode: Int = 1, step: Int = 1,
        start: String, end: String
    ) -> CourseEntity {
        var c = CourseEntity(
            groupId: "g\(id)", tableId: 1, courseName: "课\(id)",
            day: day, startNode: startNode, step: step,
            startWeek: 1, endWeek: 20, color: "blue")
        c.id = id
        c.isIrregularTime = true
        c.ownTime = true
        c.startTime = start
        c.endTime = end
        return c
    }

    /// 节次课 (无 ownTime), 用于纯节点域行几何
    private func nodeCourse(_ id: Int64, startNode: Int, step: Int = 1) -> CourseEntity {
        var c = CourseEntity(
            groupId: "g\(id)", tableId: 1, courseName: "课\(id)",
            day: 1, startNode: startNode, step: step,
            startWeek: 1, endWeek: 20, color: "")
        c.id = id
        return c
    }

    /// ← FixedWindowWiringTest.dayCourses: 首节 08:00, 每节起点 +100 分钟、时长 100 分钟
    private func dayCourses(_ n: Int) -> [CourseEntity] {
        (1...n).map { i in
            let s = 480 + (i - 1) * 100
            let e = s + 100
            return course(Int64(i), startNode: (i - 1) * 2 + 1, start: hm(s), end: hm(e))
        }
    }

    private func hm(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func h(_ text: String) -> Int {
        let p = text.split(separator: ":").map { Int($0)! }
        return p[0] * 60 + p[1]
    }

    private func entries(_ rows: [[CourseEntity]], height: CGFloat = 38) -> [WidgetWindowCore.WindowEntry] {
        let spans = rows.flatMap { ConflictLayoutEngine.weekLaneRows($0) }
        return WidgetWindowCore.entriesOf(rows: spans, timeJson: nil) { _ in height }
    }

    private func day(_ date: Date, _ dow: Int, _ courses: [CourseEntity]) -> DayData {
        DayData(date: date, dayOfWeek: dow, courses: courses, timeJson: "")
    }

    // MARK: - 窗口不变量 (← FixedWindowCoreTest)

    func testEmptyRowsYieldsEmptyResultAndNoStatus() {
        let r = WidgetWindowCore.window(entries: [], availH: 198, mode: .timeWindow, nowMin: h("10:00"))
        XCTAssertTrue(r.visible.isEmpty)
        XCTAssertEqual(r.status, .none)
        XCTAssertFalse(r.footer)
    }

    func testAllDoneFiresEvenWhenEverythingFits() {
        // 2 节课全下课, availH 富余 → 结束态仍必须成立 (ab27230c: 长状态行整体退场)
        let e = entries([
            [course(1, start: "08:00", end: "09:40")],
            [course(2, startNode: 3, start: "10:00", end: "11:40")],
        ])
        let r = WidgetWindowCore.window(entries: e, availH: 198, mode: .timeWindow, nowMin: h("21:00"))
        XCTAssertEqual(r.status, .allDone)
        XCTAssertTrue(r.visible.isEmpty)
    }

    func testUnparseableEndTimeBlocksAllDoneAndFallsBackToHead() {
        // ownTime 但时间空串 → 分钟不可解析 → 不得谎报已结束
        let broken = course(9, start: "", end: "")
        let rows = ConflictLayoutEngine.weekLaneRows([broken])
        let e = WidgetWindowCore.entriesOf(rows: rows, timeJson: nil) { _ in 38 }
        let r = WidgetWindowCore.window(entries: e, availH: 198, mode: .timeWindow, nowMin: h("23:00"))
        XCTAssertEqual(r.status, .none)
        XCTAssertEqual(r.visible.count, 1, "不可解析 → HEAD 兜底, 首行可见")
    }

    func testAnchorIsFirstRowStillRunningAtNow() {
        let e = entries([
            [course(1, start: "08:00", end: "09:40")],
            [course(2, startNode: 3, start: "10:00", end: "11:40")],
            [course(3, startNode: 5, start: "14:00", end: "15:40")],
            [course(4, startNode: 7, start: "16:00", end: "17:40")],
        ])
        let r = WidgetWindowCore.window(entries: e, availH: 198, mode: .timeWindow, nowMin: h("10:30"))
        XCTAssertEqual(r.visible.first?.row.courses.one.id, 2, "锚点 = 进行中行")
    }

    func testRowEndingExactlyAtNowIsConsideredEnded() {
        let e = entries([
            [course(1, start: "08:00", end: "10:00")],
            [course(2, startNode: 3, start: "10:01", end: "11:40")],
        ])
        let r = WidgetWindowCore.window(entries: e, availH: 198, mode: .timeWindow, nowMin: h("10:00"))
        XCTAssertEqual(r.visible.first?.row.courses.one.id, 2, "endMin == now → 已结束")
    }

    func testInProgressRowAlwaysLandsInVisibleSegmentEvenIfWindowIsOneRow() {
        let e = entries([
            [course(1, start: "08:00", end: "09:40")],
            [course(2, startNode: 3, start: "10:00", end: "11:40")],
            [course(3, startNode: 5, start: "14:00", end: "15:40")],
        ])
        let r = WidgetWindowCore.window(entries: e, availH: 38, mode: .timeWindow, nowMin: h("10:30"))
        XCTAssertEqual(r.visible.count, 1)
        XCTAssertEqual(r.visible.one.row.courses.one.id, 2)
        XCTAssertFalse(r.footer, "1 行预算放不下页脚")
    }

    func testAnchorRowTallerThanAvailHIsKeptNotDropped() {
        let tall = entries([
            [course(1, start: "08:00", end: "09:40")],
            [course(2, startNode: 3, start: "10:00", end: "11:40")],
        ], height: 100)
        let r = WidgetWindowCore.window(entries: tall, availH: 38, mode: .timeWindow, nowMin: h("10:30"))
        XCTAssertEqual(r.visible.count, 1, "锚行超高 → 保留(渲染侧底裁)")
        XCTAssertEqual(r.visible.one.row.courses.one.id, 2)
    }

    func testConflictRowIsAtomicUnit() {
        let conflict = [
            course(1, startNode: 1, step: 2, start: "10:00", end: "11:40"),
            course(2, startNode: 2, step: 2, start: "10:00", end: "11:40"),
        ]
        let spans = ConflictLayoutEngine.weekLaneRows(conflict)
            + ConflictLayoutEngine.weekLaneRows([course(3, startNode: 5, start: "14:00", end: "15:40")])
        let e = WidgetWindowCore.entriesOf(rows: spans, timeJson: nil) { _ in 38 }
        XCTAssertEqual(e.count, 2, "两门重叠课并一行")
        let r = WidgetWindowCore.window(entries: e, availH: 38, mode: .timeWindow, nowMin: h("10:30"))
        XCTAssertEqual(r.visible.first?.row.courses.count, 2, "冲突行整行保留")
        XCTAssertEqual(r.visible.count, 1, "第 2 行整行出局(不出现半行)")
        XCTAssertEqual(r.hiddenAheadCourses, 1, "hiddenAhead 按课程数计")
    }

    func testHeadModeStartsFromFirstRow() {
        let e = entries([
            [course(1, start: "08:00", end: "09:40")],
            [course(2, startNode: 3, start: "10:00", end: "11:40")],
        ])
        let r = WidgetWindowCore.window(entries: e, availH: 38, mode: .head, nowMin: nil)
        XCTAssertEqual(r.visible.count, 1)
        XCTAssertEqual(r.visible.one.row.courses.one.id, 1)
    }

    func testFooterAppearsWhenRowsAreHidden() {
        let e = entries([
            [course(1, start: "08:00", end: "09:40")],
            [course(2, startNode: 3, start: "10:00", end: "11:40")],
            [course(3, startNode: 5, start: "14:00", end: "15:40")],
        ])
        let r = WidgetWindowCore.window(
            entries: e, availH: 38 + 10 + 38 + 20, mode: .head, nowMin: nil, gapDp: 10)
        XCTAssertEqual(r.visible.count, 2)
        XCTAssertTrue(r.footer)
        XCTAssertEqual(r.hiddenAheadCourses, 1)
    }

    func testFooterDroppedRatherThanReducingToZeroRows() {
        let e = entries([
            [course(1, start: "08:00", end: "09:40")],
            [course(2, startNode: 3, start: "10:00", end: "11:40")],
        ])
        // availH 恰好 1 行: 预留 20 页脚后 0 行 → 必须丢页脚保 1 行 (S 档真实场景)
        let r = WidgetWindowCore.window(entries: e, availH: 38, mode: .head, nowMin: nil)
        XCTAssertEqual(r.visible.count, 1, "永不出现纯页脚 0 行")
        XCTAssertFalse(r.footer)
    }

    func testNoFooterWhenEverythingFits() {
        let e = entries([
            [course(1, start: "08:00", end: "09:40")],
            [course(2, startNode: 3, start: "10:00", end: "11:40")],
        ])
        let r = WidgetWindowCore.window(entries: e, availH: 198, mode: .head, nowMin: nil, gapDp: 10)
        XCTAssertEqual(r.visible.count, 2)
        XCTAssertFalse(r.footer)
        XCTAssertEqual(r.hiddenAheadCourses, 0)
    }

    func testGapCountedInBudget() {
        let e = entries([
            [course(1, start: "08:00", end: "09:40")],
            [course(2, startNode: 3, start: "10:00", end: "11:40")],
        ])
        XCTAssertEqual(WidgetWindowCore.window(entries: e, availH: 72, mode: .head, nowMin: nil).visible.count, 1)
        XCTAssertEqual(WidgetWindowCore.window(entries: e, availH: 76, mode: .head, nowMin: nil).visible.count, 2)
    }

    func testAnchorUsesRealMinutesNotNodeOrder() {
        // 调休: 节次 1 挪到 14:00, 节次 3 照常 08:00 — 锚点按真实分钟
        let moved = course(1, startNode: 1, start: "14:00", end: "15:40")
        let normal = course(2, startNode: 3, start: "08:00", end: "09:40")
        let spans = ConflictLayoutEngine.weekLaneRows([moved, normal])
        let e = WidgetWindowCore.entriesOf(rows: spans, timeJson: nil) { _ in 38 }
        XCTAssertEqual(e.first?.row.courses.one.id, 1, "行序按节次: 挪课在前")
        let r = WidgetWindowCore.window(entries: e, availH: 198, mode: .timeWindow, nowMin: h("08:30"))
        XCTAssertEqual(r.visible.first?.row.courses.one.id, 2, "锚点按真实分钟")
    }

    func testNoInProgressPicksNearestUpcomingByRealMinutes() {
        let moved = course(1, startNode: 1, start: "14:00", end: "15:40")
        let soon = course(2, startNode: 3, start: "09:00", end: "09:40")
        let spans = ConflictLayoutEngine.weekLaneRows([moved, soon])
        let e = WidgetWindowCore.entriesOf(rows: spans, timeJson: nil) { _ in 38 }
        let r = WidgetWindowCore.window(entries: e, availH: 198, mode: .timeWindow, nowMin: h("08:30"))
        XCTAssertEqual(r.visible.first?.row.courses.one.id, 2, "无进行中 → 最近将来")
    }

    func testRowMinutesAreMinStartAndMaxEndOverCourses() {
        let rowEntries = entries([[
            course(1, startNode: 1, step: 2, start: "10:00", end: "11:40"),
            course(2, startNode: 2, step: 2, start: "10:00", end: "12:30"),
        ]])
        XCTAssertEqual(rowEntries.count, 1)
        let pair = rowEntries.one
        XCTAssertEqual(pair.startMin, h("10:00"))
        XCTAssertEqual(pair.endMin, h("12:30"))
    }

    // MARK: - 填满档 (← BottomBarFitTest)

    private func fillRows(_ n: Int) -> [WidgetWindowCore.WindowEntry] {
        let courses = (1...n).map { i -> CourseEntity in
            let s = 480 + (i - 1) * 100
            return course(Int64(i), startNode: (i - 1) * 2 + 1, start: hm(s), end: hm(s + 100))
        }
        let spans = courses.flatMap { ConflictLayoutEngine.weekLaneRows([$0]) }
        return WidgetWindowCore.entriesOf(rows: spans, timeJson: nil) { _ in 38 }
    }

    func testFillToMaxShowsTwoRowsWhenTwoFitNoDoubleDeduction() {
        // 用户翻车原话: 「本来有 4 节课, 能显示两节却只显示一节」— 填满档必须画满
        let r = WidgetWindowCore.window(
            entries: fillRows(4), availH: 86, mode: .head, nowMin: nil, gapDp: 10, footerH: 0)
        XCTAssertEqual(r.visible.count, 2, "装得下 2 行必须画 2 行")
        XCTAssertTrue(r.footer, "有隐藏课 → 点亮胶囊")
        XCTAssertEqual(r.hiddenAheadCourses, 2)
    }

    func testFillToMaxNoCapsuleWhenEverythingFits() {
        let r = WidgetWindowCore.window(
            entries: fillRows(2), availH: 86, mode: .head, nowMin: nil, gapDp: 10, footerH: 0)
        XCTAssertEqual(r.visible.count, 2)
        XCTAssertFalse(r.footer)
        XCTAssertEqual(r.hiddenAheadCourses, 0)
    }

    func testFillToMaxKeepsAnchorRowAndCapsuleWhenEvenOneRowOverflows() {
        let r = WidgetWindowCore.window(
            entries: fillRows(3), availH: 30, mode: .head, nowMin: nil, gapDp: 10, footerH: 0)
        XCTAssertEqual(r.visible.count, 1, "forceFirst 锚行保底")
        XCTAssertTrue(r.footer)
        XCTAssertEqual(r.hiddenAheadCourses, 2)
    }

    func testTwoDayDefaultFooterHUnchanged() {
        // 缺省 footerH=20: TwoDay/WeekList 旧「预留页脚重算」语义逐字节不变
        let r = WidgetWindowCore.window(
            entries: fillRows(4), availH: 86, mode: .head, nowMin: nil, gapDp: 10)
        XCTAssertEqual(r.visible.count, 1, "预留 20 页脚后只容 1 行 (旧语义)")
        XCTAssertTrue(r.footer)
    }

    /// 8c0fcbea + ab27230c: 胶囊恒画, 结束/无隐藏课 = 「+0」
    func testCapsuleTextAlwaysHasPlusForm() {
        XCTAssertEqual(WidgetWindowCore.capsuleText(hidden: 3), "+3")
        XCTAssertEqual(WidgetWindowCore.capsuleText(hidden: 0), "+0")
    }

    // MARK: - 行几何 (← TodayOverflowGeometryTest 可移植部分)

    func testRowSpansDropsNoCourseRows() {
        let courses = (0..<8).map { nodeCourse(Int64($0 + 1), startNode: $0 * 2 + 1) }
        let spans = WidgetRowGeometry.rowSpans(courses: courses, headerSpace: true, timeJson: nil)
        XCTAssertEqual(spans.count, 8)
        let contentH = WidgetRowGeometry.contentHeightDp(courses: courses, headerSpace: true, timeJson: nil)
        for span in spans {
            XCTAssertLessThanOrEqual(span.bottomDp, contentH)
        }
        XCTAssertEqual(contentH, spans.last!.bottomDp + WidgetRowGeometry.padBottom, accuracy: 0.01)
        XCTAssertEqual(spans[0].topDp, WidgetRowGeometry.contentTopDp(headerSpace: true), accuracy: 0.01)
    }

    func testConflictLaneRowSpansTallerThanSingleRow() {
        // 链式冲突 {1-2, 2-4, 4-5} → 一行, 同栏最多 2 张 → 2×30 + 3 = 63
        let chain = [
            nodeCourse(1, startNode: 1, step: 2),
            nodeCourse(2, startNode: 2, step: 3),
            nodeCourse(3, startNode: 4, step: 2),
        ]
        let spans = WidgetRowGeometry.rowSpans(courses: chain, headerSpace: false, timeJson: nil)
        XCTAssertEqual(spans.count, 1)
        XCTAssertEqual(spans[0].bottomDp - spans[0].topDp, 63, accuracy: 0.01)
        XCTAssertEqual(
            WidgetRowGeometry.contentHeightDp(courses: chain, headerSpace: false, timeJson: nil),
            30 + 63 + 14, accuracy: 0.01)
        XCTAssertEqual(
            WidgetRowGeometry.contentHeightDp(courses: chain, headerSpace: true, timeJson: nil),
            10 + 63 + 14, accuracy: 0.01)
    }

    func testEmptyDayContentHeightIsHeaderPlusPadding() {
        XCTAssertEqual(
            WidgetRowGeometry.contentHeightDp(courses: [], headerSpace: false, timeJson: nil),
            WidgetRowGeometry.contentTopDp(headerSpace: false) + WidgetRowGeometry.padBottom, accuracy: 0.01)
    }

    // MARK: - 档位容量口径 (← FixedWindowWiringTest + 74140535 重定档)

    func testTodayTierCapacityTable() {
        // S=110 → availH 52 → 1 行 · M=160 → 102 → 3 行 · L=250 → 192 → 5 行
        let courses = dayCourses(6)
        let s = WidgetWindows.today(courses: courses, timeJson: "", heightDp: 110, tier: .small, nowMin: h("07:00"))
        XCTAssertEqual(s.visible.count, 1)
        XCTAssertTrue(s.footer)
        XCTAssertEqual(s.hiddenAheadCourses, 5)
        XCTAssertEqual(s.status, .none)

        let m = WidgetWindows.today(courses: courses, timeJson: "", heightDp: 160, tier: .medium, nowMin: h("07:00"))
        XCTAssertEqual(m.visible.count, 3)
        XCTAssertTrue(m.footer)
        XCTAssertEqual(m.hiddenAheadCourses, 3)

        let l = WidgetWindows.today(courses: courses, timeJson: "", heightDp: 250, tier: .large, nowMin: h("07:00"))
        XCTAssertEqual(l.visible.count, 5)
        XCTAssertTrue(l.footer)
        XCTAssertEqual(l.hiddenAheadCourses, 1)
    }

    func testTodayNoFooterWhenEverythingFits() {
        let w = WidgetWindows.today(courses: dayCourses(2), timeJson: "", heightDp: 160, tier: .medium, nowMin: h("07:00"))
        XCTAssertEqual(w.visible.count, 2)
        XCTAssertFalse(w.footer)
        XCTAssertEqual(w.hiddenAheadCourses, 0)
    }

    func testTodayAllDoneGateFiresViaComputeEvenWhenFits() {
        let w = WidgetWindows.today(courses: dayCourses(2), timeJson: "", heightDp: 160, tier: .medium, nowMin: h("23:00"))
        XCTAssertEqual(w.status, .allDone)
        XCTAssertTrue(w.visible.isEmpty)
    }

    func testTodayPastDayUsesHeadModeWithoutNow() {
        let w = WidgetWindows.today(courses: dayCourses(5), timeJson: "", heightDp: 110, tier: .small, nowMin: nil)
        XCTAssertEqual(w.visible.count, 1)
        XCTAssertEqual(w.visible.first?.row.courses.first?.id, 1)
        XCTAssertTrue(w.footer)
    }

    func testTodayAnchorsOnInProgressClass() {
        // 5 节, 第 3 节进行中 → 窗口从第 3 节起
        let w = WidgetWindows.today(courses: dayCourses(5), timeJson: "", heightDp: 160, tier: .medium, nowMin: h("11:50"))
        XCTAssertEqual(w.visible.first?.row.courses.first?.id, 3)
    }

    func testMeasuredHeightFallsBackToTierBase() {
        XCTAssertEqual(WidgetWindows.resolveHeightDp(0, .medium), 160)
        XCTAssertEqual(WidgetWindows.resolveHeightDp(-5, .small), 110)
        XCTAssertEqual(WidgetWindows.resolveHeightDp(123, .small), 123)
    }

    func testFamilyMapsToTier() {
        XCTAssertEqual(WidgetLayoutTier(family: .systemSmall), .small)
        XCTAssertEqual(WidgetLayoutTier(family: .systemMedium), .medium)
        XCTAssertEqual(WidgetLayoutTier(family: .systemLarge), .large)
        XCTAssertEqual(WidgetLayoutTier(family: .systemExtraLarge), .large)
    }

    // MARK: - TwoDay 每列独立窗口 (← 8c0fcbea 每列独立计数)

    func testTwoDayPerColumnWindowsWithMergedFooterBudget() {
        // hDp=160 → availH 116: 两行 78 装得下, 三行 120 装不下 → 每列 2 行 + 页脚
        let cal = Calendar.current
        let days = [
            day(cal.date(byAdding: .day, value: 0, to: Date())!, 1, dayCourses(4)),
            day(cal.date(byAdding: .day, value: 1, to: Date())!, 2, dayCourses(3)),
        ]
        let wins = WidgetWindows.twoDay(days: days, heightDp: 160, tier: .medium, nowMin: h("07:00"))
        XCTAssertEqual(wins.count, 2)
        XCTAssertEqual(wins[0].visible.count, 2)
        XCTAssertTrue(wins[0].footer)
        XCTAssertEqual(wins[0].hiddenAheadCourses, 2)
        XCTAssertEqual(wins[1].hiddenAheadCourses, 1, "每列独立计数, 禁合并求和")
    }

    func testTwoDayTomorrowColumnStaysHeadWhenTodayIsAllDone() {
        let cal = Calendar.current
        let days = [
            day(cal.date(byAdding: .day, value: 0, to: Date())!, 1, dayCourses(2)),
            day(cal.date(byAdding: .day, value: 1, to: Date())!, 2, dayCourses(5)),
        ]
        let wins = WidgetWindows.twoDay(days: days, heightDp: 160, tier: .medium, nowMin: h("23:00"))
        XCTAssertEqual(wins[0].status, .allDone)
        XCTAssertEqual(wins[1].status, .none, "ALL_DONE 不得传染明天列")
        XCTAssertEqual(wins[1].visible.first?.row.courses.first?.id, 1)
    }

    func testTwoDayEmptyColumnYieldsEmptyWindowNotAllDone() {
        let cal = Calendar.current
        let days = [
            day(cal.date(byAdding: .day, value: 0, to: Date())!, 1, dayCourses(2)),
            day(cal.date(byAdding: .day, value: 1, to: Date())!, 2, []),
        ]
        let wins = WidgetWindows.twoDay(days: days, heightDp: 160, tier: .medium, nowMin: h("23:00"))
        XCTAssertTrue(wins[1].visible.isEmpty)
        XCTAssertEqual(wins[1].status, .none, "空列不得谎报已结束")
        XCTAssertFalse(wins[1].footer)
    }

    // MARK: - WeekList 列容量 (← 2c937b11 / 895fe72f)

    func testWeekListCapacityAndFooter() {
        let today = Calendar.current.startOfDay(for: Date())
        let days = [day(today, 1, dayCourses(10))]
        // availH = 250 − 58 = 192: 10 行 (190) 装得下 → 全装下无页脚
        let fits = WidgetWindows.weekList(days: days, heightDp: 250, tier: .large).one
        XCTAssertEqual(fits.visible.count, 10)
        XCTAssertFalse(fits.footer)
        XCTAssertEqual(WidgetWindows.weekListVisibleCounts(days: days, heightDp: 250, tier: .large), [10])
        // 11 门 → 溢出: 预留页脚 19 后 9 行
        let more = [day(today, 1, dayCourses(11))]
        let w = WidgetWindows.weekList(days: more, heightDp: 250, tier: .large).one
        XCTAssertEqual(w.visible.count, 9)
        XCTAssertTrue(w.footer)
        XCTAssertEqual(w.hiddenAheadCourses, 2)
    }

    func testWeekListSmallTierAndStatusRowDeduction() {
        let today = Calendar.current.startOfDay(for: Date())
        let days = [day(today, 1, dayCourses(5))]
        // S 档 110 − 58 = 52 → 2 行; 预留页脚 19 后 1 行
        let w = WidgetWindows.weekList(days: days, heightDp: 110, tier: .small).one
        XCTAssertEqual(w.visible.count, 1)
        XCTAssertTrue(w.footer)
        XCTAssertEqual(w.hiddenAheadCourses, 4)
        // 学期外状态行 16 → 再扣 16
        XCTAssertEqual(WidgetWindows.weekListAvailH(heightDp: 110, tier: .small, statusH: 16), 36, accuracy: 0.01)
    }

    // MARK: - 课程边界刷新 (← f7e80c84)

    func testNextBoundaryMinOffsetsByOneMinute() {
        XCTAssertNil(WidgetWindows.nextBoundaryMin([], nowMin: 540))
        XCTAssertEqual(WidgetWindows.nextBoundaryMin([700, 600], nowMin: 550), 601)
        XCTAssertEqual(WidgetWindows.nextBoundaryMin([599, 700], nowMin: 600), 701, "严格未来")
        XCTAssertNil(WidgetWindows.nextBoundaryMin([480, 600], nowMin: 1300))
    }

    func testRowEndMinsSequentialConflictAndUnparseable() {
        XCTAssertEqual(
            WidgetWindows.rowEndMins(courses: [
                course(1, startNode: 1, step: 2, start: "08:00", end: "09:40"),
                course(2, startNode: 3, step: 2, start: "10:00", end: "11:40"),
            ], timeJson: nil).sorted(), [580, 700])
        XCTAssertEqual(
            WidgetWindows.rowEndMins(courses: [
                course(1, startNode: 1, step: 2, start: "08:00", end: "09:40"),
                course(2, startNode: 2, step: 2, start: "08:45", end: "10:25"),
            ], timeJson: nil), [625], "冲突行取 max")
        XCTAssertEqual(
            WidgetWindows.rowEndMins(courses: [
                course(1, startNode: 1, step: 1, start: "", end: ""),
                course(2, startNode: 3, step: 1, start: "10:00", end: "10:50"),
            ], timeJson: nil), [650], "不可解析课剔除")
    }

    func testBoundaryDatesAreStrictlyFutureAndAscending() {
        let cal = DateUtils.isoCalendar
        let dayStart = cal.startOfDay(for: Date())
        let courses = [
            course(1, startNode: 1, step: 2, start: "08:00", end: "09:40"),
            course(2, startNode: 3, step: 2, start: "10:00", end: "11:40"),
            course(3, startNode: 5, step: 2, start: "14:00", end: "15:40"),
        ]
        let from = cal.date(bySettingHour: 9, minute: 10, second: 0, of: dayStart)!
        let dates = WidgetWindows.boundaryDates(courses: courses, timeJson: nil, from: from)
        let mins = dates.map {
            let c = cal.dateComponents([.hour, .minute], from: $0)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }
        XCTAssertEqual(mins, [581, 701, 941], "边界 = 行 end + 1, 严格未来且升序")
    }

    func testWeekWidgetRefreshStopsAtTheNextLocalMidnightAcrossAWeekBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let formatter = ISO8601DateFormatter()
        let sunday = try XCTUnwrap(formatter.date(from: "2026-11-08T23:00:00+08:00"))
        let monday = try XCTUnwrap(formatter.date(from: "2026-11-09T00:00:00+08:00"))
        XCTAssertEqual(WidgetBoundaryScheduler.nextRefresh(after: sunday, calendar: calendar), monday)
    }

    func testWeekWidgetRefreshKeepsItsSixHourCeilingAndAdvancesFromMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let midnight = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-09T00:00:00+08:00"))
        XCTAssertEqual(WidgetBoundaryScheduler.nextRefresh(after: midnight, calendar: calendar),
                       midnight.addingTimeInterval(6 * 3600))
    }

    func testWeekWidgetRefreshUsesCivilMidnightOnDaylightSavingTransitionDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let formatter = ISO8601DateFormatter()
        for (evening, midnight) in [
            ("2026-03-08T18:30:00-04:00", "2026-03-09T00:00:00-04:00"),
            ("2026-11-01T18:30:00-05:00", "2026-11-02T00:00:00-05:00")
        ] {
            XCTAssertEqual(WidgetBoundaryScheduler.nextRefresh(
                after: try XCTUnwrap(formatter.date(from: evening)), calendar: calendar),
                try XCTUnwrap(formatter.date(from: midnight)))
        }
    }

    func testSmallWeekGridTimelineAdvancesTheCapturedTodayWindowAtCourseBoundaries() throws {
        let calendar = DateUtils.isoCalendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8)))
        let day = DayData(date: calendar.startOfDay(for: now), dayOfWeek: DateUtils.todayDayOfWeek(today: now),
                          courses: [course(1, start: "08:00", end: "08:45"),
                                    course(2, startNode: 3, start: "10:00", end: "10:45")], timeJson: "")
        let data = WeekData(days: [day], hasTable: true)
        let timeline = WeekGridWidgetProvider.timelineEntries(data: data, family: .systemSmall, from: now)
        XCTAssertEqual(timeline.map { $0.minimumTodayEntry.nowMin }, [480, 526, 646])
        XCTAssertEqual(timeline.map(\.date), [now, now.addingTimeInterval(46 * 60),
                                               now.addingTimeInterval(166 * 60)])
        let windows = timeline.map { entry -> WidgetWindowCore.WindowResult? in
            let today = entry.minimumTodayEntry
            XCTAssertEqual(today.date, entry.date)
            XCTAssertTrue(today.data.isToday)
            return TodayWidgetEntryView.window(data: today.data, heightDp: 158, tier: .small,
                                               nowMin: today.nowMin)
        }
        XCTAssertEqual(windows[0]?.visible.first?.row.courses.first?.id, 1)
        XCTAssertEqual(windows[1]?.visible.first?.row.courses.first?.id, 2)
        XCTAssertEqual(windows[2]?.status, .allDone)
    }

    func testWeekGridTimelineDoesNotApplyTodayBoundariesToRegularOrFutureFaces() throws {
        let calendar = DateUtils.isoCalendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 8)))
        let future = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        let day = DayData(date: calendar.startOfDay(for: future), dayOfWeek: DateUtils.todayDayOfWeek(today: future),
                          courses: [course(1, start: "08:00", end: "08:45")], timeJson: "")
        let data = WeekData(days: [day], hasTable: true, weekDisplayStatus: .nearestBusyDay,
                            nearestBusyTargetDate: day.date)
        XCTAssertEqual(WeekGridWidgetProvider.timelineEntries(data: data, family: .systemLarge, from: now).count, 1)
        let compact = WeekGridWidgetProvider.timelineEntries(data: data, family: .systemSmall, from: now)
        XCTAssertEqual(compact.count, 1)
        XCTAssertFalse(compact[0].minimumTodayEntry.data.isToday)
        XCTAssertEqual(compact[0].minimumTodayEntry.data.date, day.date)
    }

    func testSmallWeekGridDoesNotCarryYesterdayDataIntoAMidnightBoundaryEntry() throws {
        let calendar = DateUtils.isoCalendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 23)))
        let day = DayData(date: calendar.startOfDay(for: now), dayOfWeek: DateUtils.todayDayOfWeek(today: now),
                          courses: [course(1, start: "23:00", end: "23:59")], timeJson: "")
        let timeline = WeekGridWidgetProvider.timelineEntries(data: WeekData(days: [day], hasTable: true),
                                                              family: .systemSmall, from: now)
        XCTAssertEqual(timeline.map(\.date), [now], "午夜必须重新装载日期/周次，不能复用昨天的数据")
    }

    // MARK: - timeJson 分簇 (← 25c943f0 非标准时间被误判冲突)

    func testTimeJsonSplitsCoursesThatSharePlaceholderNodes() {
        // 两节 ownTime 课落库占位节点相同 (node1 step2), 真实时间零交集
        let a = course(1, startNode: 1, step: 2, start: "08:00", end: "08:45")
        let b = course(2, startNode: 1, step: 2, start: "10:00", end: "10:45")
        let timeJson = "[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\"},"
            + "{\"node\":2,\"start\":\"08:50\",\"end\":\"09:35\"},"
            + "{\"node\":3,\"start\":\"10:00\",\"end\":\"10:45\"},"
            + "{\"node\":4,\"start\":\"10:50\",\"end\":\"11:35\"}]"
        XCTAssertEqual(ConflictLayoutEngine.weekLaneRows([a, b]).count, 1, "节点域: 同占位节点被并成冲突行")
        XCTAssertEqual(
            ConflictLayoutEngine.weekLaneRows([a, b], timeJson: timeJson).count, 2,
            "时间域: 零交集不再误判冲突")
    }

    func testTimeJsonKeepsRealOverlapAsOneRow() {
        let a = course(1, startNode: 1, step: 2, start: "08:00", end: "09:30")
        let b = course(2, startNode: 3, step: 2, start: "09:00", end: "10:30")
        let timeJson = "[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\"},"
            + "{\"node\":2,\"start\":\"08:50\",\"end\":\"09:35\"},"
            + "{\"node\":3,\"start\":\"09:40\",\"end\":\"10:25\"},"
            + "{\"node\":4,\"start\":\"10:30\",\"end\":\"11:15\"}]"
        let rows = ConflictLayoutEngine.weekLaneRows([a, b], timeJson: timeJson)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].courses.count, 2)
    }

    /// 窗口锚点必须走 timeJson 真实时间 (非标准作息不被误判为已结束)
    func testTodayWindowUsesEffectiveTimeWithTimeJson() {
        let timeJson = "[{\"node\":1,\"start\":\"19:00\",\"end\":\"19:45\"},"
            + "{\"node\":2,\"start\":\"19:55\",\"end\":\"20:40\"}]"
        let c = nodeCourse(1, startNode: 1, step: 2)
        let w = WidgetWindows.today(courses: [c], timeJson: timeJson, heightDp: 250, tier: .large, nowMin: h("21:00"))
        XCTAssertEqual(w.status, .allDone, "19:00-20:40 在 21:00 已结束")
        let early = WidgetWindows.today(courses: [c], timeJson: timeJson, heightDp: 250, tier: .large, nowMin: h("18:00"))
        XCTAssertEqual(early.status, .none)
        XCTAssertEqual(early.visible.count, 1)
    }
}
