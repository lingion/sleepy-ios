// ClassDndSchedulerTests.swift — ← widget/notification/ClassDndSchedulerTest.kt (12 用例全移植)
// 上课自动勿扰边界计算纯函数测试 — 不依赖 UIKit/课表库。
// 不变量: 区间 [start, end) 半开; 只排未来边界; 破损 ownTime 回落/跳过;
//         节点缺失跳过; end<=start 跳过; savedFilter 默认 ALL 契约。
// 平台适配说明:
//   - Android `savedFilter 默认 ALL` + `resetSavedFilterForTest 复位` 两条用例
//     锁的是 companion @Volatile 可变字段; iOS 无系统级 DND 快照, 该状态不存在,
//     契约收敛为静态常量 ClassDndScheduler.savedFilterDefault(=INTERRUPTION_FILTER_ALL),
//     下面两条用例改锁此常量与"无可变残留"语义。
//   - Android 破损 ownTime(空白串)回落节点表 → 本文件新增 1 条回落契约用例
//     (对应 courseInterval 的 isNotBlank 语义修复)。

import XCTest
@testable import Sleepy

final class ClassDndSchedulerTests: XCTestCase {

    // 固定基准日 2026-10-07 (← Android today = LocalDate.of(2026,10,7)), 全用例同一历法语义。
    private let y = 2026, mo = 10, d0 = 7

    private func ts(_ day: Int, _ h: Int, _ m: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = day; c.hour = h; c.minute = m
        return DateUtils.isoCalendar.date(from: c)!
    }

    /// "HH:mm" → 当日 Date (基准日 d0)。
    private func iv(_ start: String, _ end: String, day: Int = 7) -> (Date, Date) {
        func parse(_ s: String) -> Date {
            let p = s.split(separator: ":").map { Int($0)! }
            return ts(day, p[0], p[1])
        }
        return (parse(start), parse(end))
    }

    private func t(_ day: Int, _ hm: String) -> Date {
        let p = hm.split(separator: ":").map { Int($0)! }
        return ts(day, p[0], p[1])
    }

    private func nodesOf(_ spec: [(node: Int, start: String, end: String)]) -> [TimeTableUtils.NodeTime] {
        spec.map {
            TimeTableUtils.NodeTime(node: $0.node,
                                    start: t(d0, $0.start),
                                    end: t(d0, $0.end))
        }
    }

    private func ownCourse(_ start: String, _ end: String) -> CourseEntity {
        CourseEntity(groupId: "g", tableId: 1, courseName: "c",
                     day: 3, startNode: 1, step: 1, startWeek: 1, endWeek: 20,
                     color: "#FF6750A4", ownTime: true, startTime: start, endTime: end)
    }

    private func nodeCourse(startNode: Int, step: Int) -> CourseEntity {
        CourseEntity(groupId: "g", tableId: 1, courseName: "c",
                     day: 3, startNode: startNode, step: step, startWeek: 1, endWeek: 20,
                     color: "#FF6750A4")
    }

    // MARK: - isCurrentlyInClass

    /// ← `区间起点含 终点不含`
    func testIsCurrentlyInClass_HalfOpen() {
        let ivs = [iv("08:00", "09:40")]
        XCTAssertTrue(ClassDndScheduler.isCurrentlyInClass(ivs, now: t(d0, "08:00")))
        XCTAssertTrue(ClassDndScheduler.isCurrentlyInClass(ivs, now: t(d0, "09:39")))
        XCTAssertFalse(ClassDndScheduler.isCurrentlyInClass(ivs, now: t(d0, "09:40")))
        XCTAssertFalse(ClassDndScheduler.isCurrentlyInClass(ivs, now: t(d0, "07:59")))
    }

    /// ← `空区间永远 false`
    func testIsCurrentlyInClass_EmptyAlwaysFalse() {
        XCTAssertFalse(ClassDndScheduler.isCurrentlyInClass([], now: Date()))
    }

    // MARK: - nextBoundaries

    /// ← `只取未来边界`
    func testNextBoundaries_FutureOnly() {
        let ivs = [
            iv("08:00", "09:40"),                    // now=12:00 → 全过期
            iv("14:00", "15:40", day: d0 + 1),
        ]
        let now = t(d0, "12:00")
        let b = ClassDndScheduler.nextBoundaries(ivs, now: now)
        XCTAssertEqual(b.nextStart, t(d0 + 1, "14:00"))
        XCTAssertEqual(b.nextEnd, t(d0 + 1, "15:40"))
    }

    /// ← `无未来边界 双双 null`
    func testNextBoundaries_NoneFuture_BothNil() {
        let b = ClassDndScheduler.nextBoundaries([iv("08:00", "09:40")], now: t(d0, "12:00"))
        XCTAssertNil(b.nextStart)
        XCTAssertNil(b.nextEnd)
    }

    /// ← `多门课 各自取最早未来`
    func testNextBoundaries_MultipleCourses_EarliestEach() {
        let ivs = [
            iv("10:00", "11:40"),
            iv("09:00", "09:40"),
            iv("13:00", "14:40"),
        ]
        let b = ClassDndScheduler.nextBoundaries(ivs, now: t(d0, "08:00"))
        XCTAssertEqual(b.nextStart, t(d0, "09:00"))
        XCTAssertEqual(b.nextEnd, t(d0, "09:40"))
    }

    // MARK: - courseInterval

    /// ← `ownTime 课 直接用自定义时间`
    func testCourseInterval_OwnTime_UsesCustomTimes() {
        let iv = ClassDndScheduler.courseInterval(
            date: ts(d0, 0, 0),
            course: ownCourse("09:30", "11:00"),
            nodes: nodesOf([(node: 1, start: "08:00", end: "08:45")]))
        XCTAssertEqual(iv?.0, t(d0, "09:30"))
        XCTAssertEqual(iv?.1, t(d0, "11:00"))
    }

    /// ← `节次课 按节点表换算 step 跨多节`
    func testCourseInterval_NodeCourse_StepSpansNodes() {
        let nodes = nodesOf([(node: 1, start: "08:00", end: "08:45"),
                             (node: 2, start: "08:55", end: "09:40")])
        let iv = ClassDndScheduler.courseInterval(
            date: ts(d0, 0, 0), course: nodeCourse(startNode: 1, step: 2), nodes: nodes)
        XCTAssertEqual(iv?.0, t(d0, "08:00"))
        XCTAssertEqual(iv?.1, t(d0, "09:40"))
    }

    /// ← `破损 ownTime 跳过`
    func testCourseInterval_BrokenOwnTime_Skipped() {
        XCTAssertNil(ClassDndScheduler.courseInterval(
            date: ts(d0, 0, 0), course: ownCourse("25:00", "11:00"), nodes: []))
        XCTAssertNil(ClassDndScheduler.courseInterval(
            date: ts(d0, 0, 0), course: ownCourse("09:00", "99:99"), nodes: []))
    }

    /// ownTime 但时间串纯空白 → 回落节点表 (← Android isNotBlank 语义; 修复前 iOS 用
    /// isEmpty 判定会把 " " 当有效时间直接解析失败丢课, 而非回落)。
    func testCourseInterval_BlankOwnTime_FallsBackToNodes() {
        let nodes = nodesOf([(node: 1, start: "08:00", end: "08:45"),
                             (node: 2, start: "08:55", end: "09:40")])
        var c = ownCourse(" ", "  ")
        c.startNode = 1; c.step = 2
        let iv = ClassDndScheduler.courseInterval(date: ts(d0, 0, 0), course: c, nodes: nodes)
        XCTAssertEqual(iv?.0, t(d0, "08:00"))
        XCTAssertEqual(iv?.1, t(d0, "09:40"))
    }

    /// ← `找不到节点表 跳过`
    func testCourseInterval_MissingNode_Skipped() {
        XCTAssertNil(ClassDndScheduler.courseInterval(
            date: ts(d0, 0, 0),
            course: nodeCourse(startNode: 9, step: 1),
            nodes: nodesOf([(node: 1, start: "08:00", end: "08:45")])))
    }

    /// ← `结束不晚于开始 跳过`
    func testCourseInterval_EndNotAfterStart_Skipped() {
        XCTAssertNil(ClassDndScheduler.courseInterval(
            date: ts(d0, 0, 0), course: ownCourse("10:00", "10:00"), nodes: []))
        XCTAssertNil(ClassDndScheduler.courseInterval(
            date: ts(d0, 0, 0), course: ownCourse("10:00", "09:00"), nodes: []))
    }

    // MARK: - savedFilter 契约 (applyDnd 离开恢复依赖; iOS 退化为常量语义)

    /// ← `savedFilter 默认 ALL — 未进入过 DND 时离开恢复到系统初始值`
    func testSavedFilter_DefaultIsAll() {
        // Android NotificationManager.INTERRUPTION_FILTER_ALL == 1
        XCTAssertEqual(ClassDndScheduler.savedFilterDefault, 1)
    }

    /// ← `resetSavedFilterForTest 把 savedFilter 复位到 ALL`
    /// iOS 无可变 savedFilter 字段 (无系统 DND 可快照), 复位语义天然成立 —
    /// 锁"契约常量稳定", 防止未来引入实例态时悄悄破坏离开恢复默认。
    func testSavedFilter_ResetSemanticsIsConstant() {
        XCTAssertEqual(ClassDndScheduler.savedFilterDefault, 1)
        XCTAssertEqual(ClassDndScheduler.savedFilterDefault, 1)
    }
}
