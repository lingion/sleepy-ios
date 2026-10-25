// ConflictDetailReporterTests.swift — ← Android ConflictDetailReporterTest.kt (10 用例全量移植)
// v7.10.16t 保存时冲突明细报告(issue#10 后续, 用户 2026-09-04):
// 加课保存不再拦截冲突(撤闸), 但要在表单顶部把「和谁、哪天、哪几节、哪几周」
// 撞车全部讲清楚, 用户自己决定。报告器 = 纯 Swift 可测, 只挑「新草稿参与的冲突」
// (存量互撞不报), 文案格式: 周五 第3-4节 第1-16周 与「高等数学」冲突。
// 另钉死两条 iOS 侧对齐闸(本次 drift 修复): 边缘槽位卡禁止按时间重映射、
// 同 startNode 平手时保持入库次序(Android sortBy 稳定语义)。

import XCTest
@testable import Sleepy

final class ConflictDetailReporterTests: XCTestCase {

    private let dayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private func lite(
        _ name: String, day: Int, startNode: Int, step: Int,
        startWeek: Int = 1, endWeek: Int = 16, type: Int = 0,
        ownTime: Bool = false, startTime: String = "", endTime: String = "",
        isIrregularNode: Bool = false
    ) -> CourseEntityLite {
        CourseEntityLite(courseName: name, day: day, startNode: startNode, step: step,
                         startWeek: startWeek, endWeek: endWeek, type: type,
                         ownTime: ownTime, startTime: startTime, endTime: endTime,
                         isIrregularNode: isIrregularNode)
    }

    // MARK: - Android 10 用例逐条移植

    func testReportsExistingCourseHitByNewDraftWithFullDetail() {
        let stored = [lite("高等数学", day: 5, startNode: 3, step: 2)]
        let draft = lite("大学英语", day: 5, startNode: 4, step: 2)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: stored, dayNames: dayNames)

        XCTAssertEqual(1, details.count)
        let d = details[0]
        XCTAssertEqual("高等数学", d.existingName)
        XCTAssertEqual("大学英语", d.draftName)
        XCTAssertEqual(5, d.day)
        XCTAssertEqual("4", d.nodeRangeText)       // 交集: draft 4-5 ∩ stored 3-4 = 第4节
        XCTAssertEqual("第1-16周", d.weekText)
    }

    func testSingleNodeConflictShowsSingleNodeText() {
        let stored = [lite("体育", day: 1, startNode: 5, step: 1)]
        let draft = lite("选修", day: 1, startNode: 5, step: 1)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: stored, dayNames: dayNames)

        XCTAssertEqual("5", details[0].nodeRangeText)  // 单节不写 5-5
    }

    func testOddEvenWeekTypesDisjointNoReport() {
        // 单双周错开: 同天同节次但 1-16单周 vs 1-16双周 = 无公共周 → 不报
        let stored = [lite("物理", day: 2, startNode: 1, step: 2, type: 1)]
        let draft = lite("化学", day: 2, startNode: 1, step: 2, type: 2)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: stored, dayNames: dayNames)

        XCTAssertTrue(details.isEmpty)
    }

    func testPartialWeekOverlapReportsCommonWeekRange() {
        // 存量 1-8 周 vs 草稿 5-12 周 → 公共 5-8
        let stored = [lite("操作系统", day: 3, startNode: 6, step: 2, startWeek: 1, endWeek: 8)]
        let draft = lite("编译原理", day: 3, startNode: 7, step: 2, startWeek: 5, endWeek: 12)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: stored, dayNames: dayNames)

        XCTAssertEqual(1, details.count)
        XCTAssertEqual("第5-8周", details[0].weekText)
    }

    func testOddTypeCommonWeeksReportedAsOddWeeks() {
        // 存量 1-16 单周 vs 草稿 1-16 每周 → 公共周 = 1,3,5,…,15 → 显示「单周 第1-15周」
        let stored = [lite("毛概", day: 4, startNode: 1, step: 2, type: 1)]
        let draft = lite("法语", day: 4, startNode: 2, step: 2, type: 0)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: stored, dayNames: dayNames)

        XCTAssertEqual(1, details.count)
        XCTAssertEqual("单周 第1-15周", details[0].weekText)
    }

    func testStoredPairsConflictingWithEachOtherNotReported() {
        // 存量 a 与 b 互撞但都不碰草稿 → 不报(只报新草稿参与的冲突)
        let a = lite("甲", day: 1, startNode: 1, step: 2)
        let b = lite("乙", day: 1, startNode: 2, step: 2)
        let draft = lite("丙", day: 6, startNode: 1, step: 2)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: [a, b], dayNames: dayNames)

        XCTAssertTrue(details.isEmpty)
    }

    func testOneDraftHittingTwoCoursesReportsBoth() {
        let s1 = lite("高数", day: 1, startNode: 1, step: 4)
        let s2 = lite("线代", day: 1, startNode: 3, step: 4)
        let draft = lite("大物", day: 1, startNode: 2, step: 4)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: [s1, s2], dayNames: dayNames)

        XCTAssertEqual(2, details.count)
        // 按节次起点排序: 高数(1) 在线代(3) 前
        XCTAssertEqual("高数", details[0].existingName)
        XCTAssertEqual("线代", details[1].existingName)
    }

    func testSameGroupEditExcludedViaGroupIds() {
        // 编辑场景: 本组旧记录不算「存量他人」— 调用方已过滤, 这里钉死签名语义
        let s1 = lite("旧课", day: 1, startNode: 1, step: 2)
        let draft = lite("新课", day: 1, startNode: 2, step: 2)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: [s1], dayNames: dayNames)

        XCTAssertEqual(1, details.count)
    }

    func testFormatLineUsesDayNameNodeAndWeek() {
        // 模板必须与生产 Localizable.strings conflict_detail_line 一致(4 占位:
        // 星期/节次/周次/存量课名), 曾因测试自造 5 占位模板掩盖过传参错位
        let line = ConflictDetailReporter.formatDetail(
            ConflictDetail(existingName: "高等数学", draftName: "大学英语",
                           day: 5, dayText: "周五",
                           nodeRangeText: "3-4", weekText: "第1-16周"),
            template: "%1$@：第 %2$@ 节，%3$@，与「%4$@」冲突")
        XCTAssertEqual("周五：第 3-4 节，第1-16周，与「高等数学」冲突", line)
    }

    func testFormatLinePlacesEverySlotEvenWhenFieldsRepeatShape() {
        // 钉死槽位次序: 节次与周次文本可能形似("3-4"), 各占位必须各取所值
        let line = ConflictDetailReporter.formatDetail(
            ConflictDetail(existingName: "体育", draftName: "选修",
                           day: 1, dayText: "周一",
                           nodeRangeText: "3-4", weekText: "第3-4周"),
            template: "%1$@：第 %2$@ 节，%3$@，与「%4$@」冲突")
        XCTAssertEqual("周一：第 3-4 节，第3-4周，与「体育」冲突", line)
    }

    // MARK: - drift 修复钉死用例 1: 边缘槽位卡禁止按时间重映射 (← CourseEntity.kt:165 首闸)

    func testEdgeSlotCard_isNotRemappedByTime() {
        // 边缘槽位卡: startNode=13(槽位号本身), 同时 ownTime=true 带 10:00~10:45。
        // Android 铁律: isIrregularNode → normalizeNode 直接 return this, 禁止
        // timeToNode 重映射(否则 13 被吸进节 3, 与草稿的真实碰撞漏报)。
        let edge = lite("边缘实验", day: 1, startNode: 13, step: 1,
                        ownTime: true, startTime: "10:00", endTime: "10:45",
                        isIrregularNode: true)
        let draft = lite("草稿课", day: 1, startNode: 13, step: 1)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: [edge], dayNames: dayNames)

        XCTAssertEqual(1, details.count, "边缘卡网格位置 = 槽位编号本身, 第13节必须照常报冲突")
        XCTAssertEqual("13", details[0].nodeRangeText)
    }

    func testNonEdgeOwnTimeCard_isStillRemappedByTime() {
        // 对照组: 同字段但 isIrregularNode=false → 允许按时间反算(10:00~10:45 = 节 3),
        // 与第 13 节草稿无交集 → 不报。证明上面的报出来是因为闸, 不是因为判定本身。
        let own = lite("非常规时间课", day: 1, startNode: 13, step: 1,
                       ownTime: true, startTime: "10:00", endTime: "10:45",
                       isIrregularNode: false)
        let draft = lite("草稿课", day: 1, startNode: 13, step: 1)

        let details = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: [own], dayNames: dayNames)

        XCTAssertTrue(details.isEmpty)
    }

    // MARK: - drift 修复钉死用例 2: 平手保持入库次序 (← Android sortBy 稳定语义)

    func testEqualStartNodeTiesKeepStoredOrder() {
        // 两门存量课同天同 startNode(1) 同 step(2), 与草稿(2-2)都撞。
        // Android hits.sortBy(startNode) 稳定 → 保持入库次序; iOS 若用不稳定排序
        // 同节次平手可能对调。按 Android 语义钉死: 先入库先报, 反序入库则反序报告。
        let a = lite("甲", day: 2, startNode: 1, step: 2)
        let b = lite("乙", day: 2, startNode: 1, step: 2)
        let draft = lite("丙", day: 2, startNode: 2, step: 1)

        let forward = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: [a, b], dayNames: dayNames)
        XCTAssertEqual(2, forward.count)
        XCTAssertEqual(["甲", "乙"], forward.map(\.existingName))

        let reversed = ConflictDetailReporter.draftConflictDetails(
            drafts: [draft], stored: [b, a], dayNames: dayNames)
        XCTAssertEqual(["乙", "甲"], reversed.map(\.existingName))
    }
}
