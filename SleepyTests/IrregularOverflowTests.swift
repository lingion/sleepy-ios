// IrregularOverflowTests.swift — ← Android IrregularOverflowTest.kt (14 用例全量移植)
// 用户反馈 2026-09-09(需求真源): 非常规时间课跨午间空隙吸附 bug。
// 场景: 10:30~12:30 与 14:00~16:00 两门非常规课; 作息 11:40~14:00 无节次。
// 旧 timeToNode 把 12:30 向上吸附进节 5 → 假冲突。本文件锁死修复语义。

import XCTest
@testable import Sleepy

final class IrregularOverflowTests: XCTestCase {

    private let base = TimeTableUtils.DEFAULT_TIME_JSON

    /// 用户场景课 1: 10:30~12:30, 存储坐标 (1,1) — 真实位置由时间决定
    private func morningOverflow(_ id: Int64, day: Int = 1) -> CourseEntity {
        CourseEntity(groupId: "g\(id)", tableId: 1, courseName: "上午溢出课",
                     day: day, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                     color: "", ownTime: true, startTime: "10:30", endTime: "12:30", id: id)
    }

    /// 用户场景课 2: 14:00~16:00 = 节 5-6
    private func afternoon(_ id: Int64, day: Int = 1) -> CourseEntity {
        CourseEntity(groupId: "g\(id)", tableId: 1, courseName: "下午课",
                     day: day, startNode: 5, step: 2, startWeek: 1, endWeek: 16,
                     color: "", ownTime: true, startTime: "14:00", endTime: "16:00", id: id)
    }

    private func lite(_ c: CourseEntity) -> CourseEntityLite {
        CourseEntityLite(courseName: c.courseName, day: c.day, startNode: c.startNode,
                         step: c.step, startWeek: c.startWeek, endWeek: c.endWeek,
                         type: c.type, ownTime: c.ownTime,
                         startTime: c.startTime, endTime: c.endTime,
                         isIrregularTime: c.isIrregularTime,
                         isIrregularNode: c.isIrregularNode)
    }

    // MARK: 加载链反算

    func testNormalizeNode_gapOverflow_notAbsorbedIntoAfternoon() {
        let n = morningOverflow(1).normalizeNode(timeJson: base)
        XCTAssertLessThanOrEqual(n.startNode + n.step - 1, 4,
            "反算节点范围不得跨过午间空隙(end 节点必须 <= 4), 实际=\(n.startNode)..\(n.startNode + n.step - 1)")
        XCTAssertGreaterThanOrEqual(n.step, 1, "step 不得为非正")
    }

    func testNormalizeNode_continuousOverlap_unchanged() {
        let c = CourseEntity(groupId: "g1", tableId: 1, courseName: "课",
                             day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                             color: "", ownTime: true, startTime: "10:00", endTime: "11:40")
        let n = c.normalizeNode(timeJson: base)
        XCTAssertEqual(3, n.startNode)
        XCTAssertEqual(2, n.step)
    }

    func testEndToEnd_userScenario_noFalseConflict() {
        let loaded = [morningOverflow(1), afternoon(2)].map { $0.normalizeNode(timeJson: base) }
        let clusters = ConflictLayoutEngine.findClusters(loaded)
        XCTAssertTrue(clusters.isEmpty, "用户场景: 10:30~12:30 与 14:00~16:00 真实时间不重叠, 绝不冲突")
        XCTAssertFalse(loaded.isEmpty)
    }

    // MARK: B 渲染期占位节次(贪心拓宽)

    func testPlaceholder_gapOverflow_synthSlotCreated() {
        let plan = TimeTableUtils.buildRenderSlotPlan(courses: [morningOverflow(1)], timeJson: base)
        let ph = plan.slots.filter { $0.isPlaceholder }
        XCTAssertEqual(1, ph.count, "应合成 1 个占位节次")
        XCTAssertEqual("11:40", ph[0].displayStart)
        XCTAssertEqual("12:30", ph[0].displayEnd)
        XCTAssertEqual(13, plan.slots.count, "原 12 节一个不少")
        XCTAssertEqual("11:40", plan.slots[3].displayEnd, "节 4 结束不变")
        XCTAssertEqual("14:00", plan.slots[5].displayStart, "节 5 开始不变(占位行插入后顺移)")
        XCTAssertEqual(4, plan.slots.firstIndex(where: { $0.isPlaceholder }), "占位节次排在节 4 之后")
    }

    func testPlaceholder_greedy_takesLongestOverflow() {
        let a = CourseEntity(groupId: "g1", tableId: 1, courseName: "A",
                             day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                             color: "", ownTime: true, startTime: "10:30", endTime: "12:30")
        let b = CourseEntity(groupId: "g2", tableId: 1, courseName: "B",
                             day: 2, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                             color: "", ownTime: true, startTime: "11:00", endTime: "13:30")
        let plan = TimeTableUtils.buildRenderSlotPlan(courses: [a, b], timeJson: base)
        let ph = plan.slots.filter { $0.isPlaceholder }
        XCTAssertEqual(1, ph.count, "两门课跨同一空隙 → 只合 1 个占位节次")
        XCTAssertEqual("11:40", ph[0].displayStart)
        XCTAssertEqual("13:30", ph[0].displayEnd, "贪心取最长溢出")
    }

    func testPlaceholder_multipleGaps_separateSlots() {
        let noon = CourseEntity(groupId: "g1", tableId: 1, courseName: "午间",
                                day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                                color: "", ownTime: true, startTime: "10:30", endTime: "12:30")
        let evening = CourseEntity(groupId: "g2", tableId: 1, courseName: "傍晚",
                                   day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                                   color: "", ownTime: true, startTime: "17:00", endTime: "18:30")
        let plan = TimeTableUtils.buildRenderSlotPlan(courses: [noon, evening], timeJson: base)
        let ph = plan.slots.filter { $0.isPlaceholder }
        XCTAssertEqual(2, ph.count, "午休 + 傍晚两个空隙各合 1 个占位")
        XCTAssertTrue(ph.contains { $0.displayStart == "11:40" && $0.displayEnd == "12:30" })
        XCTAssertTrue(ph.contains { $0.displayStart == "17:40" && $0.displayEnd == "18:30" })
    }

    func testPlaceholder_noOverflow_zeroPlaceholder_identity() {
        let planRegular = TimeTableUtils.buildRenderSlotPlan(
            courses: [CourseEntity(groupId: "g1", tableId: 1, courseName: "常规课",
                                   day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, color: "")],
            timeJson: base)
        XCTAssertEqual(12, planRegular.slots.count)
        XCTAssertTrue(planRegular.slots.allSatisfy { !$0.isPlaceholder })

        let inNode = CourseEntity(groupId: "g9", tableId: 1, courseName: "节内",
                                  day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                                  color: "", ownTime: true, startTime: "08:10", endTime: "08:30")
        let plan2 = TimeTableUtils.buildRenderSlotPlan(courses: [inNode], timeJson: base)
        XCTAssertEqual(12, plan2.slots.count)
        XCTAssertTrue(plan2.slots.allSatisfy { !$0.isPlaceholder })
    }

    func testPlaceholder_neverTouchesTimeJson() {
        let before = base
        _ = TimeTableUtils.buildRenderSlotPlan(courses: [morningOverflow(1), afternoon(2)], timeJson: base)
        XCTAssertEqual(before, base, "timeJson 必须原样(渲染期合成物)")
    }

    // MARK: A 比例渲染基于扩展后槽位表

    func testFractional_afterPlanSchedule_realMinuteRatio() throws {
        let plan = TimeTableUtils.buildRenderSlotPlan(courses: [morningOverflow(1)], timeJson: base)
        let frac = try XCTUnwrap(TimeTableUtils.timeToFractionalRows("10:30", "12:30", slots: plan.slots))
        // 节 3 = 10:00~10:45, 10:30 = 行 2 + 30/45
        XCTAssertEqual(2.0 + 30.0 / 45.0, frac.0, accuracy: 0.0001)
        // 12:30 = 占位节次(行 4, 11:40~12:30)末端 → 行坐标 5.0
        XCTAssertEqual(5.0, frac.1, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(frac.1, 5.0 + 0.0001, "绝不越过占位节次进 14:00 行")
    }

    // MARK: C 冲突判定按真实时间区间(分钟级)

    func testClusters_ownTimeRealTimeOverlap_required() {
        let clusters = ConflictLayoutEngine.findClusters([morningOverflow(1), afternoon(2)], timeJson: base)
        XCTAssertTrue(clusters.isEmpty, "真实时间不重叠的课绝不成簇")
    }

    func testClusters_trueTimeOverlap_stillClusters() {
        let a = CourseEntity(groupId: "g1", tableId: 1, courseName: "A",
                             day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                             color: "", ownTime: true, startTime: "10:30", endTime: "12:30")
        let b = CourseEntity(groupId: "g2", tableId: 1, courseName: "B",
                             day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                             color: "", ownTime: true, startTime: "12:00", endTime: "13:00")
        let clusters = ConflictLayoutEngine.findClusters([a, b], timeJson: base)
        XCTAssertEqual(1, clusters.count, "12:00~13:00 与 10:30~12:30 真实重叠 → 成簇")
        XCTAssertEqual(2, clusters[0].courses.count)
    }

    func testClusters_ownTimeVsRegular_usesRealNodeTimes() {
        let reg34 = CourseEntity(groupId: "g2", tableId: 1, courseName: "常规课",
                                 day: 1, startNode: 3, step: 2, startWeek: 1, endWeek: 16, color: "")
        let reg56 = CourseEntity(groupId: "g2", tableId: 1, courseName: "常规课",
                                 day: 1, startNode: 5, step: 2, startWeek: 1, endWeek: 16, color: "")
        let clusters1 = ConflictLayoutEngine.findClusters([morningOverflow(1), reg34], timeJson: base)
        XCTAssertEqual(1, clusters1.count, "10:30~12:30 ∩ 10:00~11:40 = 重叠 → 成簇")
        let clusters2 = ConflictLayoutEngine.findClusters([morningOverflow(1), reg56], timeJson: base)
        XCTAssertTrue(clusters2.isEmpty,
            "10:30~12:30 与 14:00~15:40 节点反算假相交, 真实不重叠 → 绝不成簇")
    }

    func testConflictReporter_minuteOverlap_semantics() {
        let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        let r1 = ConflictDetailReporter.draftConflictDetails(
            drafts: [lite(morningOverflow(100))], stored: [lite(afternoon(1))],
            dayNames: dayNames, timeJson: base)
        XCTAssertTrue(r1.isEmpty, "真实时间不重叠绝不能报冲突")

        let reg = CourseEntity(groupId: "g1", tableId: 1, courseName: "常规课",
                               day: 1, startNode: 3, step: 2, startWeek: 1, endWeek: 16, color: "")
        let r2 = ConflictDetailReporter.draftConflictDetails(
            drafts: [lite(morningOverflow(100))], stored: [lite(reg)],
            dayNames: dayNames, timeJson: base)
        XCTAssertEqual(1, r2.count, "与节 3-4(10:00~11:40)真实交叠 → 报")
    }

    // MARK: A 簇内 ownTime 卡片比例定位

    func testClusterCard_ownTime_fractionalPlacement() throws {
        let a = CourseEntity(groupId: "g1", tableId: 1, courseName: "A",
                             day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                             color: "", ownTime: true, startTime: "10:30", endTime: "12:30")
        let b = CourseEntity(groupId: "g2", tableId: 1, courseName: "B",
                             day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                             color: "", ownTime: true, startTime: "12:00", endTime: "13:00")
        let plan = TimeTableUtils.buildRenderSlotPlan(courses: [a, b], timeJson: base)
        let fracA = try XCTUnwrap(TimeTableUtils.timeToFractionalRows("10:30", "12:30", slots: plan.slots))
        let fracB = try XCTUnwrap(TimeTableUtils.timeToFractionalRows("12:00", "13:00", slots: plan.slots))
        XCTAssertLessThan(fracB.0, fracA.1,
            "真实重叠在比例坐标上必须体现: B 起(\(fracB.0)) < A 止(\(fracA.1))")
        XCTAssertGreaterThan(fracB.0, 3.0, "12:00 必须落在 11:40 之后的占位行, 行坐标应 > 3")
    }
}
