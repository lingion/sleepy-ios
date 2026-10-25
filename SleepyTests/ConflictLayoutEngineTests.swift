// ConflictLayoutEngineTests.swift — ← ConflictLayoutEngineTest.kt + ConflictCardGeometryTest.kt
// (忠实对齐安卓 107 用例的引擎子集, GPL-3.0) Sleepy iOS — 100% port of sleepy Android

import XCTest
@testable import Sleepy

final class ConflictLayoutEngineTests: XCTestCase {

    /// fixture 与安卓同款: 判定仅消费 day/startNode/step/id,其余字段填默认值。
    private func course(
        _ id: Int64, _ day: Int, _ startNode: Int, _ step: Int,
        name: String = "课程"
    ) -> CourseEntity {
        var c = CourseEntity(
            groupId: "grp-\(id)", tableId: 1, courseName: name,
            day: day, startNode: startNode, step: step,
            startWeek: 1, endWeek: 16, color: "")
        c.id = id
        return c
    }

    /// ownTime 课 fixture — startTime/endTime 参与时间域聚簇。
    private func ownCourse(
        _ id: Int64, _ day: Int, _ startNode: Int, _ step: Int,
        start: String, end: String
    ) -> CourseEntity {
        var c = course(id, day, startNode, step)
        c.ownTime = true
        c.startTime = start
        c.endTime = end
        return c
    }

    /// 标准 12 节时间表(08:00 起, 午间 11:40→14:00 空隙)。
    private let defaultTimeJson = TimeTableUtils.DEFAULT_TIME_JSON

    private func layoutById(
        _ courses: [CourseEntity], _ style: String,
        topOverrideId: Int64? = nil, maxNode: Int? = nil
    ) -> [Int64: LaidOutCourse] {
        precondition(!courses.isEmpty)
        let cluster = ConflictCluster(day: courses[0].day, courses: courses)
        return Dictionary(uniqueKeysWithValues: ConflictLayoutEngine.layoutCluster(
            cluster, style: style, topOverrideId: topOverrideId, maxNode: maxNode
        ).map { ($0.course.id, $0) })
    }

    private func eq(_ a: LaidOutCourse, _ b: LaidOutCourse) -> Bool {
        a.course.id == b.course.id && a.zRank == b.zRank && a.hidden == b.hidden
            && a.variant == b.variant && a.chainFront == b.chainFront
    }

    private func assertLaid(_ a: LaidOutCourse, _ zRank: Int, _ hidden: Bool,
                            _ variant: ConflictVariant, chainFront: Bool = false,
                            _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.zRank, zRank, msg, file: file, line: line)
        XCTAssertEqual(a.hidden, hidden, msg, file: file, line: line)
        XCTAssertEqual(a.variant, variant, msg, file: file, line: line)
        XCTAssertEqual(a.chainFront, chainFront, msg, file: file, line: line)
    }

    // ============================ findClusters ============================

    func testClustersShareNodeMergeIntoOneCluster() {
        let a = course(1, 1, 1, 2), b = course(2, 1, 2, 2)
        let clusters = ConflictLayoutEngine.findClusters([a, b])
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].day, 1)
        XCTAssertEqual(clusters[0].courses.map { $0.id }, [a.id, b.id])
    }

    func testClustersTransitiveClosureThroughChain() {
        let a = course(1, 2, 1, 2), b = course(2, 2, 2, 2), c = course(3, 2, 3, 2)
        let clusters = ConflictLayoutEngine.findClusters([a, b, c])
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].day, 2)
        XCTAssertEqual(clusters[0].courses.map { $0.id }, [a.id, b.id, c.id])
    }

    func testClustersDisjointSameDayNotMerged() {
        let a = course(1, 1, 1, 2), b = course(2, 1, 3, 2)
        XCTAssertTrue(ConflictLayoutEngine.findClusters([a, b]).isEmpty)
    }

    func testClustersCrossDayNeverMerged() {
        let a = course(1, 1, 1, 2), b = course(2, 2, 1, 2)
        XCTAssertTrue(ConflictLayoutEngine.findClusters([a, b]).isEmpty)
    }

    func testClustersSingleCourseAndEmptyInputNotReturned() {
        XCTAssertTrue(ConflictLayoutEngine.findClusters([course(1, 1, 1, 2)]).isEmpty)
        XCTAssertTrue(ConflictLayoutEngine.findClusters([]).isEmpty)
    }

    func testClustersOutputDaysAscending() {
        let d3 = course(1, 3, 1, 2), d3b = course(2, 3, 2, 2)
        let d1 = course(3, 1, 1, 2), d1b = course(4, 1, 2, 2)
        let clusters = ConflictLayoutEngine.findClusters([d3, d3b, d1, d1b])
        XCTAssertEqual(clusters.map { $0.day }, [1, 3])
        XCTAssertEqual(clusters[0].courses.map { $0.id }, [d1.id, d1b.id])
        XCTAssertEqual(clusters[1].courses.map { $0.id }, [d3.id, d3b.id])
    }

    // ============================ findClusters 时间域 (v1.0.61 报障本体) ============================

    func testClustersTimeDomainLunchGapNotAbsorbedIntoAfternoonNode() {
        // 用户 2026-09-09 报障「12:30 跨午间空隙被吸进 14:00 节」= 报障本体。
        // X=ownTime 08:00–12:30 占位节点反算 1..5(覆盖节 5 落库占位),
        // Y=常规课节 5(14:00–14:45)。节点域假成簇;时间域 840 ≥ 750 不相交 → 绝不入簇。
        let x = ownCourse(1, 1, 1, 5, start: "08:00", end: "12:30")
        let y = course(2, 1, 5, 1)
        XCTAssertEqual(ConflictLayoutEngine.findClusters([x, y]).count, 1)  // 旧节点域: 假簇
        XCTAssertTrue(ConflictLayoutEngine.findClusters([x, y], timeJson: defaultTimeJson).isEmpty)
    }

    func testClustersTimeDomainRealOverlapStillClusters() {
        // 反向对照: 真实时间重叠的 ownTime 对仍成簇 — 时间域不漏报真冲突。
        // P=ownTime 08:00–09:00(占位节 1), Q=ownTime 08:30–09:30(占位节 3):
        // 节点区间 [1,1]/[3,3] 不相交(节点域不成簇), 分钟域 510<540 相交 → 成簇。
        let p = ownCourse(1, 1, 1, 1, start: "08:00", end: "09:00")
        let q = ownCourse(2, 1, 3, 1, start: "08:30", end: "09:30")
        XCTAssertTrue(ConflictLayoutEngine.findClusters([p, q]).isEmpty)
        let clusters = ConflictLayoutEngine.findClusters([p, q], timeJson: defaultTimeJson)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].courses.map { $0.id }, [p.id, q.id])
    }

    func testClustersTimeDomainMixedDomainDoesNotCluster() {
        // 混合域(一方时间不可解析)判不相交 — 节点数(1..12)永远小于分钟数,
        // 跨域直接比会把脏 ownTime 课粘进时间簇(探针实测早上 08:20 课 + 时间空课假成簇)。
        let p = ownCourse(1, 1, 1, 2, start: "08:00", end: "09:30")
        var q = course(2, 1, 2, 1)
        q.ownTime = true  // ownTime 但时间空 → realIntervalOf=nil → 脏数据
        XCTAssertEqual(ConflictLayoutEngine.findClusters([p, q]).count, 1)  // 节点域仍成簇
        XCTAssertTrue(ConflictLayoutEngine.findClusters([p, q], timeJson: defaultTimeJson).isEmpty)
    }

    // ============================ primaryOrder ============================

    func testPrimaryOrderStepDescendingIsFirstComponent() {
        let one = course(1, 1, 1, 1), two = course(2, 1, 2, 2), three = course(3, 1, 3, 3)
        XCTAssertEqual(ConflictLayoutEngine.primaryOrder([one, three, two]).map { $0.id },
                       [three.id, two.id, one.id])
    }

    func testPrimaryOrderSameStepStartNodeAscending() {
        let late = course(1, 1, 3, 2), early = course(2, 1, 1, 2)
        XCTAssertEqual(ConflictLayoutEngine.primaryOrder([late, early]).map { $0.id },
                       [early.id, late.id])
    }

    func testPrimaryOrderSameStepSameStartNodeIdAscending() {
        let bigId = course(9, 1, 1, 2), smallId = course(4, 1, 1, 2)
        XCTAssertEqual(ConflictLayoutEngine.primaryOrder([bigId, smallId]).map { $0.id },
                       [smallId.id, bigId.id])
    }

    func testPrimaryOrderFullTieBreakChain() {
        let startLate = course(5, 1, 4, 2), idSmall = course(2, 1, 1, 2), idBig = course(7, 1, 1, 2)
        XCTAssertEqual(ConflictLayoutEngine.primaryOrder([startLate, idBig, idSmall]).map { $0.id },
                       [idSmall.id, idBig.id, startLate.id])
    }

    // ============================ layoutCluster ============================

    func testLayoutFullyOverlappingPairHiddenTrueVariantsPerStyle() {
        let top = course(1, 1, 1, 3), under = course(2, 1, 1, 3)
        XCTAssertEqual(layoutById([top, under], "stack")[2]?.variant, .stack)
        XCTAssertEqual(layoutById([top, under], "fold")[2]?.variant, .fold)
        XCTAssertEqual(layoutById([top, under], "rail")[2]?.variant, .rail)
        for style in ["stack", "fold", "rail"] {
            let byId = layoutById([top, under], style)
            assertLaid(byId[1]!, 0, false, .noMark)
            assertLaid(byId[2]!, 1, true, style == "fold" ? .fold : style == "rail" ? .rail : .stack)
        }
    }

    func testLayoutSameStartDifferentEndShortCourseZeroExposureHidden() {
        let long14 = course(1, 1, 1, 4), short13 = course(2, 1, 1, 3)
        let byId = layoutById([long14, short13], "rail")
        XCTAssertEqual(byId[1]?.zRank, 0)
        XCTAssertEqual(byId[1]?.hidden, false)
        XCTAssertEqual(byId[2]?.zRank, 1)
        XCTAssertEqual(byId[2]?.hidden, true)
        XCTAssertEqual(byId[2]?.variant, .rail)
        XCTAssertEqual(byId[1]?.variant, .noMark)
    }

    func testLayoutFullyContainedInnerCourseHidden() {
        // v7.10.16f: fold 永远折角 — 起点不齐不再回落 STACK
        let outer = course(1, 2, 1, 5), inner = course(2, 2, 2, 2)
        let byId = layoutById([outer, inner], "fold")
        assertLaid(byId[1]!, 0, false, .noMark)
        assertLaid(byId[2]!, 1, true, .fold)
    }

    func testLayoutTrapezoidAllCoursesHaveExposure() {
        // v7.8: Layer1={2-4} 置顶(z0), Layer0={1-3,3-5} 垫底;链组态全员 hidden=false
        let a13 = course(1, 3, 1, 2), b24 = course(2, 3, 2, 2), c35 = course(3, 3, 3, 2)
        let laid = ConflictLayoutEngine.layoutCluster(ConflictCluster(day: 3, courses: [a13, b24, c35]), style: "stack")
        XCTAssertEqual(laid.count, 3)
        assertLaid(laid[0], 0, false, .noMark, chainFront: false, "2-4 顶层")
        assertLaid(laid[1], 1, false, .noMark, chainFront: false, "1-3")
        assertLaid(laid[2], 2, false, .noMark, chainFront: false, "3-5")
        XCTAssertEqual(laid[0].course.id, b24.id)
        XCTAssertEqual(laid[1].course.id, a13.id)
        XCTAssertEqual(laid[2].course.id, c35.id)
    }

    func testLayoutTopOverrideIdFlipsZOrderAndRecomputesHidden() {
        let a = course(1, 1, 1, 5), b = course(2, 1, 2, 5)
        let flipped = layoutById([a, b], "stack", topOverrideId: 2)
        XCTAssertEqual(flipped[2]?.zRank, 0)
        XCTAssertEqual(flipped[2]?.hidden, false)
        XCTAssertEqual(flipped[1]?.zRank, 1)
        XCTAssertEqual(flipped[1]?.hidden, false) // 独占节 1 仍露出

        let t = course(1, 2, 1, 3), u = course(2, 2, 1, 3)
        let sameRangeFlipped = layoutById([t, u], "stack", topOverrideId: 2)
        XCTAssertEqual(sameRangeFlipped[2]?.zRank, 0)
        XCTAssertEqual(sameRangeFlipped[1]?.zRank, 1)
        XCTAssertEqual(sameRangeFlipped[1]?.hidden, true)
        XCTAssertEqual(sameRangeFlipped[1]?.variant, .stack)
        XCTAssertEqual(sameRangeFlipped[2]?.variant, .noMark)
    }

    func testLayoutTopOverrideIdMissFallsBackToPrimaryOrder() {
        let top = course(1, 1, 1, 3), under = course(2, 1, 1, 3)
        let byId = layoutById([top, under], "rail", topOverrideId: 999)
        XCTAssertEqual(byId[1]?.zRank, 0)
        XCTAssertEqual(byId[2]?.hidden, true)
        XCTAssertEqual(byId[2]?.variant, .rail)
    }

    func testLayoutThreeCoursesStackKeepsStackVariant() {
        // v7.10.16u(用户 2026-09-04 报「叠层偏移怎么没了」): N≥3 合流撤销 —
        // 层身份已由轮换点击 + N 徽标承载,4dp 偏移边不再承载三层语义。
        // stack 样式按 style 直配,任何层数都是 STACK。
        let a = course(1, 1, 1, 3), b = course(2, 1, 1, 3), c = course(3, 1, 1, 3)
        let byId = layoutById([a, b, c], "stack")
        assertLaid(byId[1]!, 0, false, .noMark)
        assertLaid(byId[2]!, 1, true, .stack)
        assertLaid(byId[3]!, 2, true, .stack)
    }

    func testLayoutRailVariantIndependentOfClusterSize() {
        let two = [course(1, 1, 1, 3), course(2, 1, 1, 3)]
        XCTAssertEqual(layoutById(two, "rail")[2]?.variant, .rail)
        let three = two + [course(3, 1, 1, 3)]
        XCTAssertEqual(layoutById(three, "rail")[2]?.variant, .rail)
        XCTAssertEqual(layoutById(three, "rail")[3]?.variant, .rail)
    }

    // ============================ v7.9 默认置顶偏好集成 ============================

    func testV79DefaultTopLiftsChainLayerAtomically() {
        let a = course(1, 1, 1, 3, name: "A")
        let b = course(2, 1, 3, 4, name: "B")
        let c = course(3, 1, 1, 2, name: "C")
        let cluster = ConflictCluster(day: 1, courses: [a, b, c])
        let groups = ConflictLayoutEngine.chainGroups(cluster.courses)
        XCTAssertEqual(groups.count, 2)

        let defaultLaid = layoutById(cluster.courses, "rail")
        XCTAssertEqual(defaultLaid[1]?.zRank, 0) // A 默认顶层
        XCTAssertEqual(defaultLaid[3]?.zRank, 1) // C 次
        XCTAssertEqual(defaultLaid[2]?.zRank, 2) // B 末

        // 用户保存默认置顶 = C → {C, B} 整组置顶
        let pickedLaid = layoutById(cluster.courses, "rail", topOverrideId: 3)
        XCTAssertEqual(pickedLaid[3]?.zRank, 0)
        XCTAssertEqual(pickedLaid[2]?.zRank, 1)
        XCTAssertEqual(pickedLaid[1]?.zRank, 2)
    }

    func testV79DefaultTopLiftsSingletonLayer() {
        let outer = course(10, 1, 1, 3), inner = course(20, 1, 1, 2)
        let defaultLaid = layoutById([outer, inner], "rail")
        XCTAssertEqual(defaultLaid[10]?.zRank, 0)
        XCTAssertEqual(defaultLaid[20]?.zRank, 1)
        let pickedLaid = layoutById([outer, inner], "rail", topOverrideId: 20)
        XCTAssertEqual(pickedLaid[20]?.zRank, 0)
        XCTAssertEqual(pickedLaid[10]?.zRank, 1)
    }

    func testV79DefaultTopChainRepSameAsMemberLiftsWholeLayer() {
        let a = course(1, 1, 1, 3), b = course(2, 1, 3, 4), c = course(3, 1, 1, 2)
        let pickedLaid = layoutById([a, b, c], "rail", topOverrideId: 2) // 选 B → {C,B} 整组置顶
        XCTAssertEqual(pickedLaid[3]?.zRank, 0) // C 顶层(startNode 小)
        XCTAssertEqual(pickedLaid[2]?.zRank, 1)
        XCTAssertEqual(pickedLaid[1]?.zRank, 2)
    }

    // ============================ v7.6 图层语义 ============================

    func testChainGroupsLayerCountGroupCountsAsSingleLayer() {
        let courses = [course(1, 1, 1, 3), course(2, 1, 4, 3), course(3, 1, 1, 6)]
        let groups = ConflictLayoutEngine.chainGroups(courses)
        XCTAssertEqual(groups.map { $0.count }, [2, 1])
    }

    func testLayoutGroupedOverlapperHiddenVariantNotDrivenByRawCourseCount() {
        let courses = [course(1, 1, 1, 3), course(2, 1, 4, 3), course(3, 1, 1, 6)]
        let byId = layoutById(courses, "stack")
        XCTAssertEqual(byId[3]?.hidden, false)
        XCTAssertEqual(byId[3]?.variant, .noMark)
    }

    func testLayoutOutputPreservesPrimaryOrderWithOverrideLast() {
        let a = course(1, 1, 1, 3), b = course(2, 1, 1, 3), c = course(3, 1, 1, 3)
        let defaultOrder = ConflictLayoutEngine.layoutCluster(
            ConflictCluster(day: 1, courses: [c, a, b]), style: "rail").map { $0.course.id }
        XCTAssertEqual(defaultOrder, [a.id, b.id, c.id])
        let overrideOrder = ConflictLayoutEngine.layoutCluster(
            ConflictCluster(day: 1, courses: [c, a, b]), style: "rail", topOverrideId: 3).map { $0.course.id }
        XCTAssertEqual(overrideOrder, [c.id, a.id, b.id])
    }

    // ============================ maxNode 裁剪 ============================

    func testLayoutClusterMaxNodeClampsExposureSpaceOutOfGridTailHidden() {
        let y = course(1, 1, 10, 3), x = course(2, 1, 11, 3)
        let byId = layoutById([y, x], "rail", maxNode: 12)
        XCTAssertEqual(byId[1]?.zRank, 0)
        XCTAssertEqual(byId[1]?.hidden, false)
        XCTAssertEqual(byId[2]?.hidden, true)
        XCTAssertEqual(byId[2]?.variant, .rail)
    }

    func testLayoutClusterMaxNodeMixedGroupsInOneCluster() {
        let a1 = course(1, 1, 1, 2), a2 = course(2, 1, 1, 2)
        let b1 = course(3, 1, 3, 2), b2 = course(4, 1, 3, 2)
        let byId = layoutById([a1, a2, b1, b2], "stack")
        assertLaid(byId[1]!, 0, false, .noMark, chainFront: true)
        assertLaid(byId[3]!, 1, false, .noMark, chainFront: true)
        assertLaid(byId[2]!, 2, false, .noMark, chainFront: false)
        assertLaid(byId[4]!, 3, false, .noMark, chainFront: false)
    }

    func testLayoutClusterMaxNodeTailOutOfGridCourseProducesNoPhantomCoverage() {
        let z = course(1, 1, 13, 3), c = course(2, 1, 12, 2)
        let byId = layoutById([z, c], "rail", maxNode: 12)
        XCTAssertEqual(byId[1]?.hidden, true)
        XCTAssertEqual(byId[2]?.hidden, false)
    }

    // ============================ layoutFor ============================

    func testLayoutForMultiClusterInputFlattensAllClusterCourses() {
        let d1a = course(1, 1, 1, 2), d1b = course(2, 1, 2, 2)
        let d3a = course(3, 3, 1, 3), d3b = course(4, 3, 1, 3), d3c = course(5, 3, 1, 3)
        let solo = course(9, 2, 1, 2)
        let laid = ConflictLayoutEngine.layoutFor([d1a, d1b, d3a, d3b, d3c, solo], style: "stack")
        XCTAssertEqual(laid.map { $0.course.id }, [1, 2, 3, 4, 5])
    }

    func testLayoutForZRankRestartsFromZeroPerCluster() {
        let d1a = course(1, 1, 1, 2), d1b = course(2, 1, 2, 2)
        let d3a = course(3, 3, 1, 3), d3b = course(4, 3, 1, 3)
        let laid = ConflictLayoutEngine.layoutFor([d1a, d1b, d3a, d3b], style: "stack")
        XCTAssertEqual(laid.map { $0.zRank }, [0, 1, 0, 1])
    }

    func testLayoutForTopOverrideIdAppliesToTargetClusterOnly() {
        let d1a = course(1, 1, 1, 2), d1b = course(2, 1, 2, 2)
        let d3a = course(3, 3, 1, 3), d3b = course(4, 3, 1, 3)
        let laid = ConflictLayoutEngine.layoutFor([d1a, d1b, d3a, d3b], style: "stack", topOverrideId: 4)
        XCTAssertEqual(laid[0].course.id, d1a.id)
        XCTAssertEqual(laid[1].course.id, d1b.id)
        XCTAssertEqual(laid[2].course.id, d3b.id)
        XCTAssertEqual(laid[3].course.id, d3a.id)
        XCTAssertEqual(laid[3].hidden, true)
        XCTAssertEqual(laid[3].variant, .stack)
    }

    func testLayoutForNoConflictsReturnsEmpty() {
        let a = course(1, 1, 1, 2), b = course(2, 1, 3, 2)
        XCTAssertTrue(ConflictLayoutEngine.layoutFor([a, b], style: "rail").isEmpty)
        XCTAssertTrue(ConflictLayoutEngine.layoutFor([], style: "rail").isEmpty)
    }

    func testLayoutForStylePropagatesToHiddenVariants() {
        let a = course(1, 1, 1, 3), b = course(2, 1, 1, 3)
        XCTAssertEqual(ConflictLayoutEngine.layoutFor([a, b], style: "rail").first { $0.course.id == 2 }?.variant, .rail)
        XCTAssertEqual(ConflictLayoutEngine.layoutFor([a, b], style: "fold").first { $0.course.id == 2 }?.variant, .fold)
    }

    // ============================ overlayMarkOrder ============================

    private func drawOrderIds(_ items: [ConflictLayoutEngine.CourseDrawItem]) -> [String] {
        items.map {
            switch $0 {
            case .card(let l): return "Card:\(l.course.id)"
            case .mark(let id, _): return "Mark:\(id)"
            }
        }
    }

    func testOverlayMarkOrderMarksComeAfterTopCardInDrawOrder() {
        let a = course(1, 1, 1, 3), b = course(2, 1, 1, 3)
        let order = ConflictLayoutEngine.overlayMarkOrder(
            ConflictLayoutEngine.layoutFor([a, b], style: "stack"))
        XCTAssertEqual(drawOrderIds(order), ["Card:2", "Card:1", "Mark:2"])
    }

    func testOverlayMarkOrderAllHiddenMarksAppendedAndPickable() {
        let a = course(1, 1, 1, 3), b = course(2, 1, 1, 3), c = course(3, 1, 1, 3)
        let order = ConflictLayoutEngine.overlayMarkOrder(
            ConflictLayoutEngine.layoutFor([a, b, c], style: "rail"))
        XCTAssertEqual(drawOrderIds(order), ["Card:3", "Card:2", "Card:1", "Mark:2", "Mark:3"])
    }

    func testOverlayMarkOrderNoHiddenOnlyCardsAndTopLast() {
        let a13 = course(1, 3, 1, 2), b24 = course(2, 3, 2, 2), c35 = course(3, 3, 3, 2)
        let order = ConflictLayoutEngine.overlayMarkOrder(
            ConflictLayoutEngine.layoutFor([a13, b24, c35], style: "stack"))
        XCTAssertEqual(drawOrderIds(order), ["Card:3", "Card:1", "Card:2"])
    }

    func testOverlayMarkOrderOverrideMovesHiddenMarkWithCourse() {
        let a = course(1, 1, 1, 3), b = course(2, 1, 1, 3)
        let order = ConflictLayoutEngine.overlayMarkOrder(
            ConflictLayoutEngine.layoutFor([a, b], style: "fold", topOverrideId: 2))
        XCTAssertEqual(drawOrderIds(order), ["Card:1", "Card:2", "Mark:1"])
    }

    func testOverlayMarkOrderOutOfGridTopFallsBackToFirstVisible() {
        let visible = [
            LaidOutCourse(course: course(2, 1, 1, 2), zRank: 1, hidden: false, variant: .noMark),
            LaidOutCourse(course: course(3, 1, 2, 2), zRank: 2, hidden: false, variant: .noMark),
        ]
        let order = ConflictLayoutEngine.overlayMarkOrder(visible)
        XCTAssertEqual(drawOrderIds(order), ["Card:3", "Card:2"])
    }

    func testOverlayMarkOrderEmptyInputReturnsEmpty() {
        XCTAssertTrue(ConflictLayoutEngine.overlayMarkOrder([]).isEmpty)
    }

    // ============================ markHitArea / foldSwitchHitArea ============================

    func testMarkHitAreaStackIsBottomEdgeStripNotFullCard() {
        let (w, h) = ConflictLayoutEngine.markHitArea(.stack, cardWidth: 60, cardHeight: 120)
        XCTAssertEqual(w, 36, accuracy: 0.001)
        XCTAssertEqual(h, 36, accuracy: 0.001)
    }

    func testMarkHitAreaFoldIsTopCornerTriangleZoneNotFullCard() {
        let (w, h) = ConflictLayoutEngine.markHitArea(.fold, cardWidth: 60, cardHeight: 120)
        XCTAssertEqual(w, 36, accuracy: 0.001)
        XCTAssertEqual(h, 36, accuracy: 0.001)
    }

    func testMarkHitAreaRailIsSameAsStackNotRightStripe() {
        let (w, h) = ConflictLayoutEngine.markHitArea(.rail, cardWidth: 60, cardHeight: 120)
        XCTAssertEqual(w, 36, accuracy: 0.001)
        XCTAssertEqual(h, 36, accuracy: 0.001)
    }

    func testFoldSwitchHitAreaFoldCoversFlapAndCutout36dp() {
        let (w, h) = ConflictLayoutEngine.foldSwitchHitArea(.fold, cardWidth: 60, cardHeight: 120)
        XCTAssertEqual(w, 36, accuracy: 0.001)
        XCTAssertEqual(h, 36, accuracy: 0.001)
    }

    func testFoldSwitchHitAreaNonFoldVariantsAreNotTappable() {
        for v in [ConflictVariant.stack, .rail, .noMark] {
            let (w, h) = ConflictLayoutEngine.foldSwitchHitArea(v, cardWidth: 60, cardHeight: 120)
            XCTAssertEqual(w, 0, accuracy: 0.001)
            XCTAssertEqual(h, 0, accuracy: 0.001)
        }
    }

    func testFoldSwitchHitAreaScalesWithUserFoldSize() {
        let (w, h) = ConflictLayoutEngine.foldSwitchHitArea(.fold, cardWidth: 60, cardHeight: 120, foldSize: 24)
        XCTAssertEqual(w, 44, accuracy: 0.001)
        let (w8, h8) = ConflictLayoutEngine.foldSwitchHitArea(.fold, cardWidth: 60, cardHeight: 120, foldSize: 8)
        XCTAssertEqual(w8, 28, accuracy: 0.001)
        let (w16, h16) = ConflictLayoutEngine.foldSwitchHitArea(.fold, cardWidth: 60, cardHeight: 120)
        XCTAssertEqual(w16, 36, accuracy: 0.001)
    }

    // ============================ v7.10.16r 轮换 ============================

    func testRotationNextCyclesLeft() {
        XCTAssertEqual(ConflictLayoutEngine.rotationNext(123), 231)
        XCTAssertEqual(ConflictLayoutEngine.rotationNext(231), 312)
        XCTAssertEqual(ConflictLayoutEngine.rotationNext(12), 21)
        // 非法输入
        XCTAssertEqual(ConflictLayoutEngine.rotationNext(0), 0)
        XCTAssertEqual(ConflictLayoutEngine.rotationNext(-1), 0)
        XCTAssertEqual(ConflictLayoutEngine.rotationNext(10), 0)  // 含 0 位
        XCTAssertEqual(ConflictLayoutEngine.rotationNext(5), 5)   // 1 层无轮换
    }

    func testApplyLayerRotationModulo() {
        let order: [Int64] = [1, 2, 3]
        XCTAssertEqual(ConflictLayoutEngine.applyLayerRotation(order, 1), [2, 3, 1])
        XCTAssertEqual(ConflictLayoutEngine.applyLayerRotation(order, 3), order)
        XCTAssertEqual(ConflictLayoutEngine.applyLayerRotation(order, -1), [3, 1, 2])
        XCTAssertEqual(ConflictLayoutEngine.applyLayerRotation([1], 5), [1])
    }

    func testRotationLayerOrderMapsIdsByDefaultZOrder() {
        // 图层默认序 = layoutCluster 的 zRank 序(主课判定序);
        // 1-2(id1)/1-3(id2)/1-4(id3) 全重叠: 默认序 = step 降 → id3,id2,id1
        let a = course(1, 1, 1, 2), b = course(2, 1, 1, 3), c = course(3, 1, 1, 4)
        XCTAssertEqual(ConflictLayoutEngine.defaultLayerIdOrder([a, b, c]), [3, 2, 1])
    }

    func testRotationOverrideAwareBaselinePutsUserTopFirst() {
        // 置顶感知基准序: 用户置顶层永远排基准首位,其余层保持默认相对序(评审 #4)
        let a = course(1, 1, 1, 2), b = course(2, 1, 1, 3), c = course(3, 1, 1, 4)
        // 默认序 [3,2,1],用户置顶 id1 → 基准 [1,3,2](id1 提前,其余相对序不变)
        XCTAssertEqual(ConflictLayoutEngine.overrideAwareLayerOrder([a, b, c], topRepId: 1), [1, 3, 2])
        // 置顶层不在簇内(null/已删) → 基准退回默认序
        XCTAssertEqual(ConflictLayoutEngine.overrideAwareLayerOrder([a, b, c], topRepId: nil), [3, 2, 1])
        XCTAssertEqual(ConflictLayoutEngine.overrideAwareLayerOrder([a, b, c], topRepId: 999), [3, 2, 1])
    }

    func testRotationFullOrderOverrideDrivesCompleteZReorder() {
        // 评审 #2 核心: 轮换必须换「完整层序」而非只前置一层。
        // 3 层默认序 [3,2,1](可见对 {3,2}): 完整重排 [1,3,2] → id3 到第二可见位。
        let a = course(1, 1, 1, 2), b = course(2, 1, 1, 3), c = course(3, 1, 1, 4)
        let cluster = ConflictLayoutEngine.findClusters([a, b, c])[0]
        func zOrder(_ layerOrder: [Int64]) -> [(Int64, Int)] {
            ConflictLayoutEngine.layoutCluster(
                cluster, style: "stack", maxNode: 12, layerOrderOverride: layerOrder
            ).sorted { $0.zRank < $1.zRank }.map { ($0.course.id, $0.zRank) }
        }
        // 默认序 [3,2,1]: z0=3, z1=2, z2=1
        XCTAssert(zOrder([3, 2, 1]).elementsEqual([(3, 0), (2, 1), (1, 2)], by: { $0 == $1 }))
        // 完整重排 [2,1,3]: z0=2, z1=1, z2=3
        XCTAssert(zOrder([2, 1, 3]).elementsEqual([(2, 0), (1, 1), (3, 2)], by: { $0 == $1 }))
        // 完整重排 [1,3,2]: id3 到第二可见位(旧「只前置一层」语义下永不可达的位置)
        XCTAssert(zOrder([1, 3, 2]).elementsEqual([(1, 0), (3, 1), (2, 2)], by: { $0 == $1 }))
    }

    func testRotationFullOrderOverrideNullFallsBackToTopOverrideSemantics() {
        // layerOrderOverride=nil → 原 topOverrideId 语义不变(向前兼容,不回归)
        let a = course(1, 1, 1, 2), b = course(2, 1, 1, 3), c = course(3, 1, 1, 4)
        let cluster = ConflictLayoutEngine.findClusters([a, b, c])[0]
        let laid = ConflictLayoutEngine.layoutCluster(
            cluster, style: "stack", topOverrideId: 1, maxNode: 12)
        // override 语义: id1 所在层置顶,其余按默认序 [3,2,1] 垫后 → z 序 1,3,2
        XCTAssertEqual(laid.first { $0.zRank == 0 }?.course.id, 1)
        XCTAssertEqual(laid.first { $0.zRank == 1 }?.course.id, 3)
        XCTAssertEqual(laid.first { $0.zRank == 2 }?.course.id, 2)
    }

    func testRotationLayerOrderOverrideIgnoresUnknownIdsKeepsKnownTail() {
        // 防御: override 序含未知 id(课被删/漂移)→ 未知项跳过,缺失层按默认序补尾,
        // 层集合必须完备(每层恰一 zRank,不丢层)
        let a = course(1, 1, 1, 2), b = course(2, 1, 1, 3), c = course(3, 1, 1, 4)
        let cluster = ConflictLayoutEngine.findClusters([a, b, c])[0]
        let laid = ConflictLayoutEngine.layoutCluster(
            cluster, style: "stack", maxNode: 12, layerOrderOverride: [2, 999])
        // [2,999] → 999 未知跳过,缺失 [3,1] 按默认序补尾 → z 序 2,3,1
        XCTAssertEqual(laid.sorted { $0.zRank < $1.zRank }.map { $0.course.id }, [2, 3, 1])
    }

    func testRotationLayerOrderOverrideDuplicateIdsDoNotDuplicateLayers() {
        // 防御(评审 cycle2 #6): override 序含重复 id → 层集合仍完备,不双绘
        let a = course(1, 1, 1, 2), b = course(2, 1, 1, 3)
        let cluster = ConflictLayoutEngine.findClusters([a, b])[0]
        let laid = ConflictLayoutEngine.layoutCluster(
            cluster, style: "stack", maxNode: 12, layerOrderOverride: [2, 2])
        XCTAssertEqual(laid.count, 2)
    }

    func testRotationChainLayerRepUnifiedAsComparatorMax() {
        // 评审 cycle2 #1: 链层 [2-3(id2), 4-9(id4)] 的 first()(=2-3) ≠ maxWith。
        // 层代表必须三处同键(maxWith): defaultLayerIdOrder / memberToLayerRep /
        // layoutCluster.layerOrderOverride — 否则气泡选课 indexOf=-1 静默无效、轮换错层。
        let a = course(1, 1, 1, 2)   // 1-2
        let b = course(2, 1, 2, 2)   // 2-3
        let c = course(3, 1, 3, 2)   // 3-4
        let d = course(4, 1, 4, 6)   // 4-9
        let e = course(5, 1, 5, 2)   // 5-6
        let f = course(6, 1, 6, 2)   // 6-7
        let all = [a, b, c, d, e, f]

        // 图层: [a,c,e] / [b,d] / [f];层代表 = maxWith: e / b / f
        // ([a,c,e] 同 step → startNode 最大 e;[b,d] step 降 → step 最小的 b)
        let order = ConflictLayoutEngine.defaultLayerIdOrder(all)
        XCTAssertEqual(order, [2, 5, 6])

        let rep = ConflictLayoutEngine.memberToLayerRep(all)
        XCTAssertEqual(rep[2], 2)  // b = [b,d] 层代表(maxWith step 最小端)
        XCTAssertEqual(rep[4], 2)  // d → 同层代表 b(三处同键,反查归一)
        XCTAssertEqual(rep[1], 5)  // a → 层代表 e(同 step 层 startNode 最大)

        // picker 路径契约: 任一成员反查的代表必须在 defaultLayerIdOrder 里
        // (否则 indexOf=-1,弹窗点了没反应)
        for (member, r) in rep {
            XCTAssertTrue(order.contains(r), "member \(member) rep \(r) not in order")
        }

        // 轮换落地: layerOrderOverride 传完整序 → z 序完整重排
        // (层序 [b,d 层, a,c,e 层, f 层],层内按 startNode 拼: b,d,a,c,e,f)
        let cluster = ConflictLayoutEngine.findClusters(all)[0]
        let laid = ConflictLayoutEngine.layoutCluster(
            cluster, style: "stack", maxNode: 12, layerOrderOverride: order)
        XCTAssertEqual(laid.sorted { $0.zRank < $1.zRank }.map { $0.course.id }, [2, 4, 1, 3, 5, 6])
    }

    func testRotationOverrideAwareResolvesNonRepMemberToItsLayer() {
        // radio 可以传链层任一成员 → 调用方(ConflictCard)先经 memberToLayerRep
        // 归一到层代表再进 overrideAwareLayerOrder;本测试钉死该两段契约。
        let a = course(1, 1, 1, 3)   // 1-3
        let b = course(2, 1, 4, 3)   // 4-6(与 a 同链层)
        let x = course(3, 1, 2, 4)   // 2-5
        // 层: [a,b](代表 b: maxWith 同 step 取 startNode 最大) / [x](step4 单课层)
        // 默认序: x 层 key(-4,2,3) < b 层 key(-3,4,2) → [3,2]
        XCTAssertEqual(ConflictLayoutEngine.defaultLayerIdOrder([a, b, x]), [3, 2])
        let rep = ConflictLayoutEngine.memberToLayerRep([a, b, x])
        XCTAssertEqual(rep[1], 2)  // 非代表成员 a → 层代表 b
        XCTAssertEqual(rep[2], 2)
        // UI 同款两段: 任一层成员先归一到代表 b(id2),再前置其层 → [b 层, x 层]
        XCTAssertEqual(ConflictLayoutEngine.overrideAwareLayerOrder([a, b, x], topRepId: rep[1]), [2, 3])
    }

    func testRotationBadgeHiddenLayersFormula() {
        // 评审 #3: 气泡「+N」= 层数-2(按层计),与 hidden 课数无关、轮换中恒定
        XCTAssertEqual(ConflictLayoutEngine.hiddenLayerCount(3), 1)
        XCTAssertEqual(ConflictLayoutEngine.hiddenLayerCount(4), 2)
        XCTAssertEqual(ConflictLayoutEngine.hiddenLayerCount(7), 5)
        XCTAssertEqual(ConflictLayoutEngine.hiddenLayerCount(2), 0)
        XCTAssertEqual(ConflictLayoutEngine.hiddenLayerCount(1), 0)
        XCTAssertEqual(ConflictLayoutEngine.hiddenLayerCount(0), 0)
    }

    func testBadgeHiddenLayerCountCardinalityUsesFullClusterLayers() {
        // 基数裁定(评审 cycle2 #2): +N 用全量簇层数(含出界层),不按 maxNode 可渲染层裁剪 —
        // 徽标 +N 与气泡弹窗候选(全量层)必须一致,出界层照样可选中轮换到顶。
        // maxNode=12: id1/id2=11-13 叠放, id3=13-15(经节 13 与两课同簇, clamp 后整课出界)。
        // 三课两两相交 → chainGroups 每轮仅取一课 = 全量 3 层 → 「+1」;
        // 若按可渲染层裁(drawList 滤 startNode>maxNode 的 id3)只剩 2 层 → 「+0」与弹窗分叉 = 禁止。
        let a = course(1, 1, 11, 3), b = course(2, 1, 11, 3), tail = course(3, 1, 13, 3)
        let clusters = ConflictLayoutEngine.findClusters([a, b, tail])
        XCTAssertEqual(clusters.count, 1)  // 链式经节 13 相接
        let fullLayers = ConflictLayoutEngine.defaultLayerIdOrder(clusters[0].courses)
        XCTAssertEqual(fullLayers.count, 3)
        XCTAssertEqual(ConflictLayoutEngine.hiddenLayerCount(fullLayers.count), 1)
        // 出界层在布局里仍按 hidden=true 参与(整课不可见,记账不丢层)
        let laid = ConflictLayoutEngine.layoutCluster(clusters[0], style: "stack", maxNode: 12)
        XCTAssertEqual(laid.first { $0.course.id == 3 }?.hidden, true)
    }

    func testDefaultLayerIdOrderMatchesLayoutClusterDefault() {
        // 1-3/1-4/4-6: chainGroups → {1-3,4-6} 与 {1-4};层代表统一 maxWith(评审 cycle2 #1):
        //   {1-4} rep=3 key(-4,1,3) 先;{1-3,4-6} 同 step → 大 startNode 端 4-6(rep=4)
        //   key(-3,4,4) 垫后 → [3,4](旧 first() 约定会给 [3,1],已随引擎三处同键修订撤销)
        let a = course(1, 1, 1, 3), b = course(3, 1, 1, 4), c = course(4, 1, 4, 3)
        XCTAssertEqual(ConflictLayoutEngine.defaultLayerIdOrder([a, b, c]), [3, 4])
    }

    func testMemberToLayerRepMapsWholeGroup() {
        // {1-3,4-6} 组(层代表 = maxWith:同 step 取 startNode 最大 = 4-6, id=2)
        // + 1-6 自成层: 1↦2, 2↦2, 3↦3(三处同键 — defaultLayerIdOrder/memberToLayerRep/
        // layoutCluster.layerOrderOverride 全部按 maxWith,链层 first() 旧约定已撤销)
        let a = course(1, 1, 1, 3), b = course(2, 1, 4, 3), c = course(3, 1, 1, 6)
        let rep = ConflictLayoutEngine.memberToLayerRep([a, b, c])
        XCTAssertEqual(rep[1], 2)
        XCTAssertEqual(rep[2], 2) // b 与 a 同层,层代表 = 主序末端 maxWith = b(id=2)
        XCTAssertEqual(rep[3], 3)
    }

    // ============================ v7.10.16p 簇键 + 清理 ============================

    func testConflictClusterKeyFormat() {
        XCTAssertEqual(ConflictLayoutEngine.conflictClusterKey(course(7, 3, 5, 2)), "3:5:2")
    }

    func testPruneConflictDefaultTopDropsDeadKeysAndReps() {
        let live = [course(1, 1, 1, 2), course(2, 1, 2, 2)]
        let stored: [String: Int64] = [
            "1:1:2": 1,   // 键有效 rep 有效 → 保留
            "5:1:2": 1,   // 键不存在于现存簇 → 删
            "2:2:2": 99,  // rep 指向不存在课 → 删
        ]
        let pruned = ConflictLayoutEngine.pruneConflictDefaultTop(stored, live)
        XCTAssertEqual(pruned, ["1:1:2": 1])
    }

    func testPruneConflictDefaultTopEmptyInputs() {
        XCTAssertTrue(ConflictLayoutEngine.pruneConflictDefaultTop([:], [course(1, 1, 1, 2)]).isEmpty)
        XCTAssertTrue(ConflictLayoutEngine.pruneConflictDefaultTop(["1:1:2": 1], []).isEmpty)
    }

    func testPruneConflictDefaultTopTimeDomainKeysKeepOwnTimePref() {
        // 用户报障 2026-09-10: 旧节点域 liveKeys 与网格时间域簇键永不相等,
        // 用户的置顶偏好被 prune 静默误删。ownTime 对时间域成簇 → 键 "1:1:5";
        // 不带 timeJson 的节点域键不同 → 必须按同一时间域比对才保留。
        let p = ownCourse(1, 1, 1, 3, start: "08:00", end: "09:30")
        let q = ownCourse(2, 1, 3, 3, start: "09:00", end: "10:30")
        // 键域随时间域簇: 时间域簇锚课(主序最前 = step 降)推算的键必须与存储键一致才保留。
        let timeClusters = ConflictLayoutEngine.findClusters([p, q], timeJson: defaultTimeJson)
        XCTAssertEqual(timeClusters.count, 1)
        let timeKey = ConflictLayoutEngine.conflictClusterKey(timeClusters[0])
        let kept = ConflictLayoutEngine.pruneConflictDefaultTop(
            [timeKey: 1], [p, q], timeJson: defaultTimeJson)
        XCTAssertEqual(kept, [timeKey: 1])  // 时间域键比对 → 保留
        // 旧节点域键与时间域簇键分叉的病灶回归闸: 用同一 timeJson 重算,
        // 指向已删课的 repId 仍被删。
        let pruned = ConflictLayoutEngine.pruneConflictDefaultTop(
            [timeKey: 99], [p, q], timeJson: defaultTimeJson)
        XCTAssertTrue(pruned.isEmpty)  // repId=99 不在现存课 → 删
    }

    // ============================ 周视图分栏 ============================

    func testWeekLaneSegmentsDisjointRegionFullWidth() {
        let a = course(1, 1, 1, 2), b = course(2, 1, 5, 2)
        let segs = ConflictLayoutEngine.weekLaneSegments([a, b])
        XCTAssertEqual(segs.count, 2)
        XCTAssertTrue(segs.allSatisfy { $0.laneCount == 1 && $0.lane == 0 })
    }

    func testWeekLaneSegmentsConflictRegionTwoLanes() {
        // 1-3 与 2-4 完全重叠不可并排 → 2 栏
        let a = course(1, 1, 1, 3), b = course(2, 1, 2, 3)
        let segs = ConflictLayoutEngine.weekLaneSegments([a, b])
        XCTAssertEqual(segs.count, 2)
        XCTAssertTrue(segs.allSatisfy { $0.laneCount == 2 })
        XCTAssertEqual(segs.first { $0.course.id == 1 }?.lane, 0)
        XCTAssertEqual(segs.first { $0.course.id == 2 }?.lane, 1)
    }

    func testWeekLaneRowsPartitionAndOrder() {
        // 链式 1-2/2-3/3-4 一个区域一行;chainGroups 右端点贪心: 1-2 与 3-4 可并排同栏,
        // 2-3 独栏 → 2 栏(与安卓同 fixture 真值一致)
        let a = course(1, 1, 1, 2), b = course(2, 1, 2, 2), c = course(3, 1, 3, 2)
        let rows = ConflictLayoutEngine.weekLaneRows([a, b, c])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].courses.count, 3)
        XCTAssertEqual(rows[0].laneCount, 2)
        XCTAssertEqual(rows[0].laneOf[a.id], 0)
        XCTAssertEqual(rows[0].laneOf[b.id], 1)
        XCTAssertEqual(rows[0].laneOf[c.id], 0)
    }

    func testGridDayLanesHalvesForPair() {
        let a = course(1, 1, 1, 3), b = course(2, 1, 1, 3)
        let rects = ConflictLayoutEngine.gridDayLanes([a, b])
        XCTAssertEqual(rects.count, 2)
        let ra = rects.first { $0.course.id == 1 }!
        let rb = rects.first { $0.course.id == 2 }!
        XCTAssertEqual(ra.laneStartFraction, 0, accuracy: 0.001)
        XCTAssertEqual(ra.laneWidthFraction, 0.5, accuracy: 0.001)
        XCTAssertEqual(rb.laneStartFraction, 0.5, accuracy: 0.001)
    }

    func testDaysExceedingTwoLanesDetectsThirdLayer() {
        // 三课完全重叠 → 3 栏 → day 1 违规
        let a = course(1, 1, 1, 2), b = course(2, 1, 1, 2), c = course(3, 1, 1, 2)
        XCTAssertEqual(ConflictLayoutEngine.daysExceedingTwoLanes([a, b, c]), [1])
        // 两课重叠合法
        XCTAssertEqual(ConflictLayoutEngine.daysExceedingTwoLanes([a, b]), [])
    }

    func testWeekLaneSegmentsMultiDayInputOutputIsDeterministic() {
        // Kotlin groupBy = LinkedHashMap 语义: segment 顺序按输入遇到 day 的次序,
        // 与 weekLaneRows 的显式 dayOrder 同一契约(iOS Dictionary(grouping:) 无序迭代曾致非确定)。
        let d3 = [course(1, 3, 1, 2), course(2, 3, 2, 2)]
        let d1 = [course(3, 1, 1, 2), course(4, 1, 2, 2)]
        let input = d3 + d1
        let expectedDays = [3, 3, 1, 1]
        for _ in 0..<20 {  // 字典哈希序随进程 seed 抖动,多次采样钉死确定性
            let segs = ConflictLayoutEngine.weekLaneSegments(input)
            XCTAssertEqual(segs.map { $0.course.day }, expectedDays)
            XCTAssertEqual(segs.map { $0.course.id }, [1, 2, 3, 4])
        }
    }
}
