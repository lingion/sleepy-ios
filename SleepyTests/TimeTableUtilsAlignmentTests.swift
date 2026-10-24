// TimeTableUtilsAlignmentTests.swift — ← Android util 测试套件移植(F122)
// 覆盖此前 iOS 零用例的: TimeTableUtilsMergeTest / TimeTableUtilsInferenceTest /
// TimeTableUtilsEdgeNodeTest / EdgeCandidatesTest / PeriodTablePreviewTest /
// PeriodTableBindConfirmRowsTest / Ics28CourseRemapTest。

import XCTest
@testable import Sleepy

/// ← Android 测试里的 Triple 构造便捷函数
private func jrows(_ triples: [(Int, String, String)]) -> String {
    TimeTableUtils.buildTimeJsonFromRows(
        triples.map { TimeTableUtils.TimeSlotRow(node: $0.0, start: $0.1, end: $0.2) })
}

private func row(_ node: Int, _ start: String, _ end: String,
                 edge: TimeTableUtils.EdgeClass? = nil) -> TimeTableUtils.TimeSlotRow {
    TimeTableUtils.TimeSlotRow(node: node, start: start, end: end, edgeClass: edge)
}

// MARK: - ← TimeTableUtilsMergeTest (v7.10.16k 无损合并语义)

final class TimeTableUtilsMergeTests: XCTestCase {

    private let current10 = jrows([
        (1, "08:00", "08:45"), (2, "08:50", "09:35"), (3, "10:00", "10:45"), (4, "10:50", "11:35"),
        (5, "14:00", "14:45"), (6, "14:50", "15:35"), (7, "16:00", "16:45"), (8, "16:50", "17:35"),
        (9, "19:00", "19:45"), (10, "19:50", "20:35")
    ])

    func testIncomingDeclares13RealTimesOverCurrent10ResultIs13() {
        let incoming = jrows([
            (1, "08:30", "09:10"), (2, "09:20", "10:00"), (3, "10:10", "10:50"), (4, "11:00", "11:40"),
            (5, "14:30", "15:10"), (6, "15:20", "16:00"), (7, "16:10", "16:50"), (8, "17:00", "17:40"),
            (9, "19:30", "20:10"), (10, "20:20", "21:00"), (11, "21:10", "21:50"), (12, "22:00", "22:40"),
            (13, "22:50", "23:30")
        ])
        let rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.mergeMostComplete(currentJson: current10, incomingJson: incoming))
        XCTAssertEqual(13, rows.count, "节次数必须 = max(双方) = 13, 导入源不得被原表压小")
        XCTAssertEqual("08:30", rows[0].start, "有真实时间时以导入源为准")
        XCTAssertEqual("22:50", rows[12].start, "第13节取导入源真实时间")
        XCTAssertEqual("23:30", rows[12].end)
    }

    func testIncomingBlankCurrent10CoursesReach13SmartDefaultsFillTail() {
        let rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.mergeMostComplete(currentJson: current10, incomingJson: "", requiredNodeCount: 13))
        XCTAssertEqual(13, rows.count, "13 节可达就必须是 13 节")
        XCTAssertEqual("08:00", rows[0].start, "1..10 保留原表真实时间")
        XCTAssertEqual("19:50", rows[9].start)
        XCTAssertEqual("20:50", rows[10].start, "11..13 用 smart 默认起始")
        XCTAssertEqual("22:30", rows[12].end)
    }

    func testIncomingShorterThanCurrentNeverShrinks() {
        let incoming = jrows([
            (1, "08:30", "09:10"), (2, "09:20", "10:00"), (3, "10:10", "10:50"), (4, "11:00", "11:40"),
            (5, "14:30", "15:10")
        ])
        let rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.mergeMostComplete(currentJson: current10, incomingJson: incoming))
        XCTAssertEqual(10, rows.count, "导入源短不得把原表压小")
        XCTAssertEqual("08:30", rows[0].start, "1..5 导入源优先")
        XCTAssertEqual("14:50", rows[5].start, "6..10 原表补位")
        XCTAssertEqual("20:35", rows[9].end)
    }

    func testBothBlankReturnsDefault() {
        XCTAssertEqual(TimeTableUtils.DEFAULT_TIME_JSON,
                       TimeTableUtils.mergeMostComplete(currentJson: "", incomingJson: ""))
    }

    func testRequiredNodeCountExtendsBeyondBothSources() {
        let current = jrows([(1, "08:00", "08:45")])
        let incoming = jrows([(1, "08:30", "09:10"), (2, "09:20", "10:00")])
        let rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.mergeMostComplete(currentJson: current, incomingJson: incoming, requiredNodeCount: 13))
        XCTAssertEqual(13, rows.count)
        XCTAssertEqual("08:30", rows[0].start, "导入源优先")
        XCTAssertEqual("20:50", rows[10].start, "超出双方声明的节次用 smart 默认")
    }

    // F122 issue: ← Android takeIf { isNotBlank } — 纯空白串 = 没声明,
    // 绝不能进 parseTimeSlotRows(catch 出 12 行 smart 伪声明把真实表盖掉)
    func testWhitespaceOnlyCurrentDoesNotEnterMerge() {
        let real = jrows([(1, "08:10", "08:50")])
        let rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.mergeMostComplete(currentJson: "   ", incomingJson: real))
        XCTAssertEqual(1, rows.count, "空白 current = 没声明, 不得铺出 12 行伪声明")
        XCTAssertEqual("08:10", rows[0].start)
    }

    func testWhitespaceOnlyTimeFallsThroughToOtherSide() {
        let current = jrows([(1, "08:00", "08:45")])
        let incoming = TimeTableUtils.buildTimeJsonFromRows([row(1, " ", " ")])
        let rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.mergeMostComplete(currentJson: current, incomingJson: incoming))
        XCTAssertEqual("08:00", rows[0].start, "纯空白时间 = 没声明, 回退原表")
    }
}

// MARK: - ← TimeTableUtilsInferenceTest (issue#23 智慧节次推断)

final class TimeTableUtilsInferenceTests: XCTestCase {

    func testInfersMajorityDurationAsPrimaryAndAssignsMinorityPeriods() throws {
        let rows = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "09:50", "10:20"), row(4, "10:30", "11:15")]
        let config = try XCTUnwrap(TimeTableUtils.inferSmartPeriodConfig(rows))
        XCTAssertEqual(45, config.periodMinutes)
        XCTAssertEqual([45, 45, 30, 45], config.effectivePeriodMinutes())
        XCTAssertEqual(
            [("08:00", "08:45"), ("08:55", "09:40"), ("09:50", "10:20"), ("10:30", "11:15")].map { "\($0)-\($1)" },
            config.derive().map { "\($0.start)-\($0.end)" })
    }

    func testInfersAllDurationAndBreakGroupsInFirstSeenDeterministicOrder() throws {
        let rows = [row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(3, "09:50", "10:20"),
                    row(4, "10:30", "11:15"), row(5, "12:15", "13:00"), row(6, "13:10", "14:00")]
        let config = try XCTUnwrap(TimeTableUtils.inferSmartPeriodConfig(rows))
        XCTAssertEqual(45, config.periodMinutes)
        XCTAssertEqual([DurationOption(minutes: 30, isLong: false), DurationOption(minutes: 50, isLong: true)],
                       config.durations)
        XCTAssertEqual([nil, nil, 0, nil, nil, 1] as [Int?], config.periodAssignments)
        XCTAssertEqual([BreakOption(minutes: 10, isLong: false), BreakOption(minutes: 60, isLong: true)],
                       config.breaks)
        XCTAssertEqual([0, 0, 0, 1, 0] as [Int?], config.transitionAssignments)
        XCTAssertEqual(rows.map { "\($0.start)-\($0.end)" }, config.derive().map { "\($0.start)-\($0.end)" })
    }

    func testTieBetweenDurationsChoosesEarliestStandardNode() throws {
        let rows = [row(1, "08:00", "08:30"), row(2, "08:40", "09:25"), row(3, "09:35", "10:20"), row(4, "10:30", "11:00")]
        let config = try XCTUnwrap(TimeTableUtils.inferSmartPeriodConfig(rows))
        XCTAssertEqual(30, config.periodMinutes)
        XCTAssertEqual([DurationOption(minutes: 45, isLong: true)], config.durations)
        XCTAssertEqual([nil, 0, 0, nil] as [Int?], config.periodAssignments)
        XCTAssertEqual([BreakOption(minutes: 10)], config.breaks)
        XCTAssertEqual([0, 0, 0] as [Int?], config.transitionAssignments)
    }

    func testEdgeRowsAreExcludedFromInferenceAndDerivation() throws {
        let rows = [row(0, "07:00", "07:59", edge: .before), row(1, "08:00", "08:45"),
                    row(2, "08:55", "09:40"), row(3, "09:50", "10:35"), row(4, "22:00", "23:00", edge: .after)]
        let config = try XCTUnwrap(TimeTableUtils.inferSmartPeriodConfig(rows))
        XCTAssertEqual(3, config.totalPeriods)
        XCTAssertEqual(["08:00-08:45", "08:55-09:40", "09:50-10:35"], config.derive().map { "\($0.start)-\($0.end)" })
    }

    func testPreviousLabelsAndClassificationsArePreservedByMinutes() throws {
        let previous = SmartPeriodConfig(
            periodMinutes: 45, totalPeriods: 4,
            breaks: [BreakOption(minutes: 10, isLong: false, label: "课间"), BreakOption(minutes: 60, isLong: true, label: "午休")],
            durations: [DurationOption(minutes: 30, isLong: true, label: "短课"), DurationOption(minutes: 45, isLong: false, label: "标准课")])
        let rows = [row(1, "08:00", "08:45"), row(2, "08:55", "09:25"), row(3, "10:25", "11:10"), row(4, "11:20", "12:05")]
        let config = try XCTUnwrap(TimeTableUtils.inferSmartPeriodConfig(rows, previous: previous))
        XCTAssertEqual([DurationOption(minutes: 30, isLong: true, label: "短课")], config.durations)
        XCTAssertEqual(BreakOption(minutes: 10, isLong: false, label: "课间"), config.breaks.first)
        XCTAssertEqual(BreakOption(minutes: 60, isLong: true, label: "午休"), config.breaks.last)
    }

    func testMalformedReversedOverlappingOrNoncontiguousStandardRowsReturnNil() {
        XCTAssertNil(TimeTableUtils.inferSmartPeriodConfig([row(1, "bad", "08:45")]))
        XCTAssertNil(TimeTableUtils.inferSmartPeriodConfig([row(1, "09:00", "08:45")]))
        XCTAssertNil(TimeTableUtils.inferSmartPeriodConfig([row(1, "08:00", "08:45"), row(2, "08:40", "09:20")]))
        XCTAssertNil(TimeTableUtils.inferSmartPeriodConfig([row(1, "08:00", "08:45"), row(3, "08:55", "09:40")]))
        XCTAssertNil(TimeTableUtils.inferSmartPeriodConfig([row(0, "07:00", "07:30", edge: .before)]))
    }

    func testBlankStandardTimesAreRejectedInsteadOfInferred() {
        XCTAssertNil(TimeTableUtils.inferSmartPeriodConfig([row(1, "", "")]))
        XCTAssertNil(TimeTableUtils.inferSmartPeriodConfig([row(1, "08:00", "")]))
        XCTAssertNil(TimeTableUtils.inferSmartPeriodConfig([row(1, "08:00", "08:45"), row(2, "", "09:40")]))
    }

    func testRoundTripPreservesStandardRowsExactlyAndInNodeOrder() throws {
        let rows = [row(3, "10:00", "10:30"), row(1, "08:00", "08:45"), row(2, "08:55", "09:40"), row(4, "10:40", "11:25")]
        let config = try XCTUnwrap(TimeTableUtils.inferSmartPeriodConfig(rows))
        XCTAssertEqual([1, 2, 3, 4], config.derive().map { $0.node })
        XCTAssertEqual(["08:00-08:45", "08:55-09:40", "10:00-10:30", "10:40-11:25"],
                       config.derive().map { "\($0.start)-\($0.end)" })
    }
}

// MARK: - ← TimeTableUtilsEdgeNodeTest (issue#23 课表外节次 + 回收)

final class TimeTableUtilsEdgeNodeTests: XCTestCase {

    private let baseStandard = TimeTableUtils.DEFAULT_TIME_JSON

    private func rows(_ json: String) -> [TimeTableUtils.TimeSlotRow] {
        TimeTableUtils.parseTimeSlotRows(json)
    }

    func testInsertEdgeNodeBeforeFirstCallInsertsNodeZero() {
        let rs = rows(TimeTableUtils.insertEdgeNode(timeJson: baseStandard, edgeClass: .before, start: "07:30", end: "08:00"))
        XCTAssertEqual(13, rs.count, "标准 1..12 + 前置 0 = 13 行")
        let zero = rs.first { $0.node == 0 }
        XCTAssertNotNil(zero, "节点 0 必须存在")
        XCTAssertEqual("07:30", zero?.start)
        XCTAssertEqual("08:00", zero?.end)
    }

    func testInsertEdgeNodeBeforeWhenZeroExistsInsertsMinusOne() {
        let once = TimeTableUtils.insertEdgeNode(timeJson: baseStandard, edgeClass: .before, start: "07:30", end: "08:00")
        let twice = TimeTableUtils.insertEdgeNode(timeJson: once, edgeClass: .before, start: "07:00", end: "07:30")
        let rs = rows(twice)
        XCTAssertEqual(14, rs.count)
        let minus1 = rs.first { $0.node == -1 }
        XCTAssertNotNil(minus1, "节点 -1 必须存在")
        XCTAssertEqual("07:00", minus1?.start)
        XCTAssertNotNil(rs.first { $0.node == 0 }, "节点 0 仍存在")
    }

    func testInsertEdgeNodeBeforeKeepsStandardNodesUnchanged() {
        let rs = rows(TimeTableUtils.insertEdgeNode(timeJson: baseStandard, edgeClass: .before, start: "07:30", end: "08:00"))
        for n in 1...12 {
            XCTAssertNotNil(rs.first { $0.node == n }, "标准节次 \(n) 必须保留")
        }
    }

    func testInsertEdgeNodeAfterFirstCallInsertsMaxPlusOne() {
        let rs = rows(TimeTableUtils.insertEdgeNode(timeJson: baseStandard, edgeClass: .after, start: "22:30", end: "23:15"))
        XCTAssertEqual(13, rs.count)
        let n13 = rs.first { $0.node == 13 }
        XCTAssertNotNil(n13)
        XCTAssertEqual("22:30", n13?.start)
        XCTAssertEqual("23:15", n13?.end)
    }

    func testInsertEdgeNodeAfterWhenThirteenExistsInsertsFourteen() {
        let once = TimeTableUtils.insertEdgeNode(timeJson: baseStandard, edgeClass: .after, start: "22:30", end: "23:15")
        let twice = TimeTableUtils.insertEdgeNode(timeJson: once, edgeClass: .after, start: "23:15", end: "24:00")
        let rs = rows(twice)
        XCTAssertEqual(14, rs.count)
        XCTAssertEqual("23:15", rs.first { $0.node == 14 }?.start)
    }

    func testInsertEdgeNodeAfterWithFourteenStandardInsertsFifteen() {
        let fourteenStandard = TimeTableUtils.buildTimeJsonFromRows((1...14).map { row($0, "08:00", "08:45") })
        let rs = rows(TimeTableUtils.insertEdgeNode(timeJson: fourteenStandard, edgeClass: .after, start: "23:00", end: "23:45"))
        XCTAssertEqual(15, rs.count)
        XCTAssertNotNil(rs.first { $0.node == 15 })
    }

    func testRemoveEdgeNodeIfUnusedReturnsUnchangedWhenStillReferenced() {
        let json = TimeTableUtils.insertEdgeNode(timeJson: baseStandard, edgeClass: .before, start: "07:30", end: "08:00")
        XCTAssertEqual(json, TimeTableUtils.removeEdgeNodeIfUnused(timeJson: json, edgeNode: 0, usedNodes: [0]))
    }

    func testRemoveEdgeNodeIfUnusedRemovesWhenNoCourseReferences() {
        let json = TimeTableUtils.insertEdgeNode(timeJson: baseStandard, edgeClass: .before, start: "07:30", end: "08:00")
        let rs = rows(TimeTableUtils.removeEdgeNodeIfUnused(timeJson: json, edgeNode: 0, usedNodes: []))
        XCTAssertEqual(12, rs.count, "回到 12 行")
        XCTAssertNil(rs.first { $0.node == 0 }, "节点 0 必须被移除")
    }

    func testRemoveEdgeNodeIfUnusedDoesNotRemoveStandardNode() {
        XCTAssertEqual(baseStandard, TimeTableUtils.removeEdgeNodeIfUnused(timeJson: baseStandard, edgeNode: 5, usedNodes: []))
    }

    func testEdgeNodesOfBeforeReturnsDescendingList() {
        var json = baseStandard
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .before, start: "07:30", end: "08:00")
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .before, start: "07:00", end: "07:30")
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .before, start: "06:30", end: "07:00")
        XCTAssertEqual([0, -1, -2], TimeTableUtils.edgeNodesOf(timeJson: json, edgeClass: .before))
    }

    func testEdgeNodesOfAfterReturnsAscendingList() {
        var json = baseStandard
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .after, start: "22:30", end: "23:15")
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .after, start: "23:15", end: "24:00")
        XCTAssertEqual([13, 14], TimeTableUtils.edgeNodesOf(timeJson: json, edgeClass: .after))
    }

    func testEdgeNodesOfEmptyWhenNoEdge() {
        XCTAssertEqual([], TimeTableUtils.edgeNodesOf(timeJson: baseStandard, edgeClass: .before))
        XCTAssertEqual([], TimeTableUtils.edgeNodesOf(timeJson: baseStandard, edgeClass: .after))
    }

    // ===== reclaimUnusedEdgeNodes (F122: 此前 iOS 无实现) =====

    func testReclaimUnusedEdgeNodesRemovesAllUnusedBeforeEdges() {
        var json = baseStandard
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .before, start: "07:30", end: "08:00")
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .before, start: "07:00", end: "07:30")
        let rs = rows(TimeTableUtils.reclaimUnusedEdgeNodes(timeJson: json, usedNodes: []))
        XCTAssertEqual(12, rs.count)
        XCTAssertNil(rs.first { $0.node == 0 })
        XCTAssertNil(rs.first { $0.node == -1 })
    }

    func testReclaimUnusedEdgeNodesRemovesAllUnusedAfterEdges() {
        var json = baseStandard
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .after, start: "22:30", end: "23:15")
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .after, start: "23:15", end: "24:00")
        let rs = rows(TimeTableUtils.reclaimUnusedEdgeNodes(timeJson: json, usedNodes: []))
        XCTAssertEqual(12, rs.count)
        XCTAssertNil(rs.first { $0.node == 13 })
        XCTAssertNil(rs.first { $0.node == 14 })
    }

    func testReclaimUnusedEdgeNodesKeepsReferencedEdges() {
        var json = baseStandard
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .before, start: "07:30", end: "08:00")
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .before, start: "07:00", end: "07:30")
        let rs = rows(TimeTableUtils.reclaimUnusedEdgeNodes(timeJson: json, usedNodes: [0]))
        XCTAssertEqual(13, rs.count)
        XCTAssertNotNil(rs.first { $0.node == 0 }, "被引用的 0 保留")
        XCTAssertNil(rs.first { $0.node == -1 }, "无引用的 -1 回收")
    }

    func testReclaimUnusedEdgeNodesHandlesMixedBeforeAndAfter() {
        var json = baseStandard
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .before, start: "07:30", end: "08:00")
        json = TimeTableUtils.insertEdgeNode(timeJson: json, edgeClass: .after, start: "22:30", end: "23:15")
        let rs = rows(TimeTableUtils.reclaimUnusedEdgeNodes(timeJson: json, usedNodes: [13]))
        XCTAssertEqual(13, rs.count)
        XCTAssertNil(rs.first { $0.node == 0 }, "无引用前置回收")
        XCTAssertNotNil(rs.first { $0.node == 13 }, "有引用后置保留")
    }

    func testReclaimUnusedEdgeNodesNoopAndNeverStandard() {
        XCTAssertEqual(baseStandard, TimeTableUtils.reclaimUnusedEdgeNodes(timeJson: baseStandard, usedNodes: []))
    }
}

// MARK: - ← EdgeCandidatesTest (issue#23 §2.2)

final class EdgeCandidatesTests: XCTestCase {

    private func std(_ n: Int) -> TimeTableUtils.TimeSlotRow { row(n, "08:00", "08:45") }

    private func json(_ rows: [TimeTableUtils.TimeSlotRow]) -> String {
        TimeTableUtils.buildTimeJsonFromRows(rows)
    }

    func test纯标准节次_候选为新建0和新13() {
        let candidates = TimeTableUtils.edgeCandidates(json((1...12).map { std($0) }))
        XCTAssertEqual(2, candidates.count)
        XCTAssertEqual(0, candidates[0].node)
        XCTAssertFalse(candidates[0].exists)
        XCTAssertEqual("", candidates[0].start)
        XCTAssertEqual(13, candidates[1].node)
        XCTAssertFalse(candidates[1].exists)
    }

    func test已有0号槽位_候选为负1复用0和新13() {
        let candidates = TimeTableUtils.edgeCandidates(
            json((1...12).map { std($0) } + [row(0, "08:00", "08:30", edge: .before)]))
        XCTAssertEqual(3, candidates.count)
        XCTAssertEqual(-1, candidates[0].node)
        XCTAssertFalse(candidates[0].exists)
        XCTAssertEqual(0, candidates[1].node)
        XCTAssertTrue(candidates[1].exists)
        XCTAssertEqual("08:00", candidates[1].start)
        XCTAssertEqual("08:30", candidates[1].end)
        XCTAssertEqual(13, candidates[2].node)
        XCTAssertFalse(candidates[2].exists)
    }

    func test已有负1到14_候选按升序含全部槽位加两个新建() {
        let candidates = TimeTableUtils.edgeCandidates(
            json((1...12).map { std($0) } +
                [row(-1, "07:30", "07:55", edge: .before), row(0, "08:00", "08:30", edge: .before),
                 row(13, "18:00", "18:40", edge: .after), row(14, "19:00", "19:40", edge: .after)]))
        XCTAssertEqual([-2, -1, 0, 13, 14, 15], candidates.map { $0.node })
        XCTAssertEqual([false, true, true, true, true, false], candidates.map { $0.exists })
        XCTAssertEqual("07:30", candidates[1].start)
        XCTAssertEqual("18:00", candidates[3].start)
    }

    func testUpdateEdgeNodeTimes_改边缘行生效() {
        let base = json((1...12).map { std($0) } + [row(0, "08:00", "08:30", edge: .before)])
        let updated = TimeTableUtils.updateEdgeNodeTimes(timeJson: base, node: 0, start: "07:50", end: "08:20")
        let parsed = TimeTableUtils.parseTimeSlotRows(updated)
        XCTAssertEqual("07:50", parsed.first { $0.node == 0 }?.start)
        XCTAssertEqual("08:20", parsed.first { $0.node == 0 }?.end)
        XCTAssertEqual("08:00", parsed.first { $0.node == 5 }?.start, "标准行不受影响")
    }

    func testUpdateEdgeNodeTimes_标准行原样返回() {
        let base = json((1...5).map { std($0) })
        XCTAssertEqual(base, TimeTableUtils.updateEdgeNodeTimes(timeJson: base, node: 5, start: "00:00", end: "01:00"))
    }

    func test损坏timeJson返回原样() {
        XCTAssertEqual("not json", TimeTableUtils.updateEdgeNodeTimes(timeJson: "not json", node: 0, start: "07:50", end: "08:20"))
    }
}

// MARK: - ← PeriodTablePreviewTest (issue#40 §5.2/§5.3 保存前预览)

private func previewCourse(_ name: String, startNode: Int = 1, step: Int = 2,
                           ownTime: Bool = false, type: Int = 0) -> CourseEntity {
    CourseEntity(groupId: "g-\(name)", tableId: 1, courseName: name, day: 1,
                 startNode: startNode, step: step, startWeek: 1, endWeek: 16,
                 type: type, color: "#FF6750A4",
                 ownTime: ownTime,
                 startTime: ownTime ? "07:30" : "", endTime: ownTime ? "09:00" : "")
}

final class PeriodTablePreviewTests: XCTestCase {

    private let oldJson = """
        [{"node":1,"start":"08:00","end":"08:45"},
         {"node":2,"start":"08:55","end":"09:40"},
         {"node":3,"start":"10:00","end":"10:45"},
         {"node":4,"start":"10:55","end":"11:40"}]
        """

    /** 第一节后移 20 分钟, 其余不变 */
    private let newJson = """
        [{"node":1,"start":"08:20","end":"09:05"},
         {"node":2,"start":"08:55","end":"09:40"},
         {"node":3,"start":"10:00","end":"10:45"},
         {"node":4,"start":"10:55","end":"11:40"}]
        """

    func testChangedNodeShowsOldToNewTimeForBoundCourses() {
        let preview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: oldJson, newTimeJson: newJson, courses: [previewCourse("高数", step: 2)])
        XCTAssertEqual(1, preview.changedCourses.count)
        let change = preview.changedCourses[0]
        XCTAssertEqual("高数", change.courseName)
        XCTAssertEqual("08:00-09:40", change.oldTime)
        XCTAssertEqual("08:20-09:40", change.newTime)
        XCTAssertEqual(0, preview.unchangedCount)
    }

    func testCourseOnUntouchedNodesCountsAsUnchanged() {
        let preview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: oldJson, newTimeJson: newJson,
            courses: [previewCourse("高数", step: 2), previewCourse("英语", startNode: 3, step: 2)])
        XCTAssertEqual(1, preview.changedCourses.count)
        XCTAssertEqual("高数", preview.changedCourses.first?.courseName)
        XCTAssertEqual(1, preview.unchangedCount)
    }

    func testOwnTimeCoursesAreExcludedFromInterpretation() {
        let preview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: oldJson, newTimeJson: newJson,
            courses: [previewCourse("自定义课", step: 2, ownTime: true), previewCourse("高数", step: 1)])
        XCTAssertEqual(1, preview.changedCourses.count)
        XCTAssertTrue(preview.changedCourses.allSatisfy { $0.courseName != "自定义课" })
        XCTAssertEqual(0, preview.unchangedCount, "自定义课不计入无变化 — 根本不参与解释")
    }

    func testIdenticalTimeJsonYieldsNoChanges() {
        let preview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: oldJson, newTimeJson: oldJson,
            courses: [previewCourse("高数"), previewCourse("英语", startNode: 3, step: 1)])
        XCTAssertTrue(preview.changedCourses.isEmpty)
        XCTAssertEqual(2, preview.unchangedCount)
    }

    func testMissingNodeInOldTableReportsNilOldTime() {
        let sparseOld = "[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\"}]"
        let preview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: sparseOld, newTimeJson: newJson, courses: [previewCourse("大四专选", startNode: 3, step: 1)])
        XCTAssertEqual(1, preview.changedCourses.count)
        XCTAssertNil(preview.changedCourses.first?.oldTime)
        XCTAssertEqual("10:00-10:45", preview.changedCourses.first?.newTime)
    }

    func testNodeNumbersAreNeverRewrittenByPreview() {
        let preview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: oldJson, newTimeJson: newJson, courses: [previewCourse("高数", step: 3)])
        let change = preview.changedCourses.first
        XCTAssertNotNil(change, "跨变化节次的课必须出现在预览里")
        XCTAssertEqual(1, change?.startNode)
        XCTAssertEqual(3, change?.step)
    }

    func testEmptyCoursesGiveEmptyPreview() {
        let preview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: oldJson, newTimeJson: newJson, courses: [])
        XCTAssertTrue(preview.changedCourses.isEmpty)
        XCTAssertEqual(0, preview.unchangedCount)
    }

    /** 2026-09-16 用户实测: 改第1节结束时间(拉长早八), 第一节的课必须全部列出旧→新 */
    func testUserScenarioEditingFirstPeriodListsAllFirstPeriodCourses() {
        let edited = """
            [{"node":1,"start":"08:00","end":"09:20"},
             {"node":2,"start":"08:55","end":"09:40"},
             {"node":3,"start":"10:00","end":"10:45"},
             {"node":4,"start":"10:55","end":"11:40"}]
            """
        let preview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: oldJson, newTimeJson: edited,
            courses: [previewCourse("高数", step: 1), previewCourse("英语", step: 2), previewCourse("体育", startNode: 3, step: 2)])
        XCTAssertEqual(2, preview.changedCourses.count, "第一节相关课必须全部报变化")
        XCTAssertEqual(["英语", "高数"], preview.changedCourses.map { $0.courseName }.sorted())
        let gaoshu = preview.changedCourses.first { $0.courseName == "高数" }
        XCTAssertEqual("08:00-08:45", gaoshu?.oldTime)
        XCTAssertEqual("08:00-09:20", gaoshu?.newTime)
        XCTAssertEqual(1, preview.unchangedCount)
    }

    /** 41 门课全量 — 真实规模下第一节变化必须全检出 */
    func testLargeBatchFirstPeriodChangeNotSwallowed() {
        let edited = oldJson.replacingOccurrences(of: "08:45", with: "09:20")
        let courses = (1...40).map { previewCourse("课\($0)", step: 2) } + [previewCourse("体育", startNode: 3, step: 2)]
        let preview = TimeTableUtils.previewPeriodTableChange(oldTimeJson: oldJson, newTimeJson: edited, courses: courses)
        XCTAssertEqual(40, preview.changedCourses.count, "40 门早八连堂课必须全部报变化")
        XCTAssertEqual(1, preview.unchangedCount)
    }

    /** 周次类型(0/1/2/3)不影响时间解释 */
    func testWeekTypeDoesNotBlockTimeInterpretation() {
        let edited = oldJson.replacingOccurrences(of: "08:45", with: "09:20")
        let variants = [0, 1, 2, 3].map { previewCourse("大物", step: 2, type: $0) }
        let preview = TimeTableUtils.previewPeriodTableChange(oldTimeJson: oldJson, newTimeJson: edited, courses: variants)
        XCTAssertEqual(4, preview.changedCourses.count)
    }

    /** buildTimeJsonFromRows 往返后预览必须仍能检出, 且 changedNodes 精确指向第 1 节 */
    func testRoundTripThroughBuildTimeJsonFromRowsPreservesChangeDetection() {
        let editedRows = TimeTableUtils.parseTimeSlotRows(oldJson).map {
            $0.node == 1 ? TimeTableUtils.TimeSlotRow(node: $0.node, start: $0.start, end: "09:20", edgeClass: $0.edgeClass) : $0
        }
        let editedJson = TimeTableUtils.buildTimeJsonFromRows(editedRows)
        let preview = TimeTableUtils.previewPeriodTableChange(
            oldTimeJson: oldJson, newTimeJson: editedJson, courses: [previewCourse("高数", step: 2)])
        XCTAssertEqual(1, preview.changedCourses.count)
        XCTAssertEqual("08:00-09:40", preview.changedCourses.first?.newTime)
        XCTAssertEqual([1], preview.changedCourses.first?.changedNodes)
    }
}

// MARK: - ← PeriodTableBindConfirmRowsTest (v1.0.56 T6 绑表真源, 用户反馈 2026-09-20)

final class PeriodTableBindConfirmRowsTests: XCTestCase {

    private lazy var feedbackJson: String = {
        let starts = ["08:10", "08:55", "09:40", "10:35", "11:20", "14:50", "15:35",
                      "16:20", "17:05", "19:00", "19:45", "20:30", "21:15"]
        return TimeTableUtils.buildTimeJsonFromRows(starts.enumerated().map { idx, s in
            let comps = s.split(separator: ":")
            let sh = Int(comps[0])!, sm = Int(comps[1])!
            let em = sm + 40, eh = sh + (em >= 60 ? 1 : 0)
            return row(idx + 1, s, String(format: "%02d:%02d", eh, em % 60))
        })
    }()

    private var tables: [(Int64, String)] { [(42, feedbackJson)] }

    /** 教务协议没回节次时间 → 手动 rows 全空 → 绑了表 → 校验必须用表 timeJson */
    func testBindExistingTableHydratesManualBlankRowsWithTableTimes() {
        let manualBlank = (1...13).map { row($0, "", "") }
        let effective = TimeTableUtils.effectiveRowsForConfirm(manualRows: manualBlank, bindId: 42, tables: tables)
        XCTAssertEqual(13, effective.count, "绑表时 rows 必须来自该表, 与手动 rows 全空无关")
        XCTAssertEqual("08:10", effective[0].start, "第1节必须是表的时间, 不能再是空串(否则又误报)")
        XCTAssertEqual("08:50", effective[0].end)
        XCTAssertEqual("21:15", effective[12].start, "第13节时间必须到位")
        XCTAssertEqual("21:55", effective[12].end)
    }

    /** nil (未绑) → 维持手动 rows 原值 */
    func testBindNilReturnsManualRowsUnchanged() {
        let manual = [row(1, "09:00", "09:45")]
        XCTAssertEqual(manual, TimeTableUtils.effectiveRowsForConfirm(manualRows: manual, bindId: nil, tables: tables))
    }

    /** -1 (本次导入自动建表) → 维持手动 rows */
    func testBindMinusOneSyntheticUsesManualRows() {
        let manual = [row(1, "09:00", "09:45")]
        XCTAssertEqual(manual, TimeTableUtils.effectiveRowsForConfirm(manualRows: manual, bindId: -1, tables: tables))
    }

    /** id>0 但表列表里找不到 → 兜底用手动 rows, 不抛异常 */
    func testBindExistingTableNotInListFallsBackToManual() {
        let manual = [row(1, "09:00", "09:45")]
        XCTAssertEqual(manual, TimeTableUtils.effectiveRowsForConfirm(manualRows: manual, bindId: 999, tables: tables))
    }
}

// MARK: - ← Ics28CourseRemapTest (issue#28 P3 绝对时间窗重排)

final class Ics28CourseRemapTests: XCTestCase {

    /** 正确的 NEU 12 节表: 五块 [08:00-09:40|10:00-11:40|14:00-15:40|16:00-17:40|18:30-22:00] */
    private lazy var neu12 = TimeTableUtils.buildTimeJsonFromRows([
        row(1, "08:00", "08:50"), row(2, "08:50", "09:40"),
        row(3, "10:00", "10:50"), row(4, "10:50", "11:40"),
        row(5, "14:00", "14:50"), row(6, "14:50", "15:40"),
        row(7, "16:00", "16:50"), row(8, "16:50", "17:40"),
        row(9, "18:30", "19:22"), row(10, "19:22", "20:15"),
        row(11, "20:15", "21:07"), row(12, "21:07", "22:00")])

    /** 报告者的错误 16 节表: 晚间块被锚在 13-16 节 */
    private lazy var wrong16 = TimeTableUtils.buildTimeJsonFromRows([
        row(1, "08:00", "08:45"), row(2, "08:45", "09:30"),
        row(3, "09:30", "10:15"), row(4, "10:15", "11:00"),
        row(5, "11:00", "11:45"), row(6, "12:30", "13:15"),
        row(7, "13:15", "14:00"), row(8, "14:00", "14:45"),
        row(9, "14:45", "15:30"), row(10, "15:30", "16:15"),
        row(11, "16:15", "17:00"), row(12, "17:00", "17:45"),
        row(13, "18:30", "19:22"), row(14, "19:22", "20:15"),
        row(15, "20:15", "21:07"), row(16, "21:07", "22:00")])

    func testEveningCourse16To12MovesToCorrectNodes() {
        let __r = TimeTableUtils.remapCourseNodes(startNode: 13, step: 4, oldTimeJson: wrong16, newTimeJson: neu12)
        XCTAssertEqual(__r.0, 9)
        XCTAssertEqual(__r.1, 4)
    }

    func testMorningCourseStaysPut() {
        let __r = TimeTableUtils.remapCourseNodes(startNode: 1, step: 2, oldTimeJson: wrong16, newTimeJson: neu12)
        XCTAssertEqual(__r.0, 1)
        XCTAssertEqual(__r.1, 2)
    }

    func testMiddayCourseShiftsToOverlapWindow() {
        let __r = TimeTableUtils.remapCourseNodes(startNode: 3, step: 2, oldTimeJson: wrong16, newTimeJson: neu12)
        XCTAssertEqual(__r.0, 2)
        XCTAssertEqual(__r.1, 3)
    }

    func testSameTableIdenticalJsonReturnsSameSpan() {
        let __r = TimeTableUtils.remapCourseNodes(startNode: 9, step: 4, oldTimeJson: neu12, newTimeJson: neu12)
        XCTAssertEqual(__r.0, 9)
        XCTAssertEqual(__r.1, 4)
    }

    func testOldRowMissingKeepsCourseUnchanged() {
        let __r = TimeTableUtils.remapCourseNodes(startNode: 13, step: 4, oldTimeJson: neu12, newTimeJson: neu12)
        XCTAssertEqual(__r.0, 13)
        XCTAssertEqual(__r.1, 4)
    }

    func testCourseBeyondNewTableClampsToOverlappingTail() {
        let __r = TimeTableUtils.remapCourseNodes(startNode: 15, step: 2, oldTimeJson: wrong16, newTimeJson: neu12)
        XCTAssertEqual(__r.0, 11)
        XCTAssertEqual(__r.1, 2)
    }

    func testBlankOldJsonFallsBackToTwelveSmartRowsUnmappableCourseKept() {
        let __r = TimeTableUtils.remapCourseNodes(startNode: 16, step: 2, oldTimeJson: "", newTimeJson: neu12)
        XCTAssertEqual(__r.0, 16)
        XCTAssertEqual(__r.1, 2)
    }
}

// MARK: - F122 严格时间/兼容旧格式/键序 补充用例

final class TimeTableUtilsStrictParsingTests: XCTestCase {

    // ← Android parseNodes: o.optInt("node", i + 1) — issue#40 旧格式补号
    func testParseNodesLegacyEntriesWithoutNodeKeyGetIndexPlusOne() {
        let nodes = TimeTableUtils.parseNodes("[{\"start\":\"08:00\",\"end\":\"08:45\"},{\"start\":\"08:55\",\"end\":\"09:40\"}]")
        XCTAssertEqual(2, nodes.count)
        XCTAssertEqual([1, 2], nodes.map { $0.node })
        XCTAssertEqual("08:00", TimeTableUtils.formatTime(nodes[0].start))
    }

    // ← Android 整体 try/catch: 单行坏 → 全表空(不是丢单行)
    func testParseNodesAnyBadRowFailsEntireList() {
        XCTAssertTrue(TimeTableUtils.parseNodes("[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\"},{\"node\":2}]").isEmpty)
        XCTAssertTrue(TimeTableUtils.parseNodes("[{\"node\":1,\"start\":\"25:00\",\"end\":\"25:45\"}]").isEmpty)
    }

    // ← Android LocalTime.parse 严格语义
    func testHmToSecondsMatchesLocalTimeStrictness() {
        XCTAssertNil(TimeTableUtils.hmToSeconds("9:30"))    // Android 拒绝单位小时
        XCTAssertNil(TimeTableUtils.hmToSeconds("24:00"))   // Android 拒绝
        XCTAssertNil(TimeTableUtils.hmToSeconds("25:00"))   // 旧 iOS 会跨日滚动
        XCTAssertEqual(9 * 3600 + 30 * 60 + 15, TimeTableUtils.hmToSeconds("09:30:15")) // Android 接受秒
        XCTAssertNil(TimeTableUtils.hmToSeconds("09:60"))
    }

    func testTimeToNodeRejectsOutOfRangeTimes() {
        XCTAssertNil(TimeTableUtils.timeToNode("25:00", "26:00", TimeTableUtils.DEFAULT_TIME_JSON))
    }

    // courseTimeParts ownTime 守卫: ← isNotBlank (纯空白落到节点查询)
    func testCourseTimePartsWhitespaceOwnTimeFallsThroughToNodes() {
        let parts = TimeTableUtils.courseTimeParts(courseStartNode: 1, courseStep: 1,
                                                   timeJson: TimeTableUtils.DEFAULT_TIME_JSON,
                                                   ownTime: true, startTime: " ", endTime: " ")
        XCTAssertNotNil(parts)
        XCTAssertEqual("08:00", parts?.0)
        XCTAssertEqual("08:45", parts?.1)
    }

    // ← Android JSONObject.put 插入序: node,start,end,edge 逐字节稳定
    func testBuildTimeJsonKeyOrderIsAndroidByteIdentical() {
        let js = TimeTableUtils.buildTimeJsonFromRows([row(1, "08:00", "08:45", edge: .before)])
        XCTAssertEqual("[{\"node\":1,\"start\":\"08:00\",\"end\":\"08:45\",\"edge\":\"before\"}]", js)
        let plain = TimeTableUtils.buildTimeJsonFromRows((1...12).map { TimeTableUtils.parseTimeSlotRows(TimeTableUtils.DEFAULT_TIME_JSON)[$0 - 1] })
        XCTAssertEqual(TimeTableUtils.DEFAULT_TIME_JSON
                       .replacingOccurrences(of: "\n", with: "")
                       .replacingOccurrences(of: " ", with: ""), plain,
                       "默认表往返必须与 Android org.json 紧凑输出逐字节一致")
    }

    // ← Android extendTimeJsonWith: node > currentMax 复制进来并连续重编号
    func testExtendTimeJsonWithAppendsRenumberedTail() {
        let cur = jrows([(1, "08:00", "08:45")])
        let inc = jrows([(2, "10:00", "10:45"), (5, "14:00", "14:45")])
        let rows = TimeTableUtils.parseTimeSlotRows(TimeTableUtils.extendTimeJsonWith(currentJson: cur, incomingJson: inc))
        XCTAssertEqual([1, 2, 3], rows.map { $0.node })
        XCTAssertEqual("10:00", rows[1].start)
        XCTAssertEqual("14:00", rows[2].start)
        XCTAssertEqual(cur, TimeTableUtils.extendTimeJsonWith(currentJson: cur, incomingJson: cur), "无新节次原样返回")
    }
}
