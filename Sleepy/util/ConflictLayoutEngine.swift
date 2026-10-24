// ConflictLayoutEngine.swift — ← util/ConflictLayoutEngine.kt (终态 v1.0.61 / v7.10.16u+, 逐行翻译, GPL-3.0)
// Sleepy iOS — 100% port of sleepy Android
// 网格/周视图冲突布局引擎 — 纯函数,零 SwiftUI 依赖。

import Foundation

/// 同一天的冲突簇 — 簇内课程节点区间两两经传递闭包相连(直接或间接共享节次)。
struct ConflictCluster {
    let day: Int
    let courses: [CourseEntity]
}

/// 变体标记类型 — NONE=无标记(真卡自然露出),STACK/FOLD/RAIL 见设计文档 §3。
enum ConflictVariant {
    case noMark
    case stack
    case fold
    case rail
}

/**
 * 单课布局结果 — zRank=0 即该课所在图层为顶层;hidden=零露出;variant 仅 hidden 课非 NONE。
 * chainFront(v7.4 保留语义, v7.8 重定义为): 该课属于链式多课层且该层当前为顶层
 * (层内每门成员都拿顶层视觉与编辑交互)。
 */
struct LaidOutCourse {
    let course: CourseEntity
    let zRank: Int
    let hidden: Bool
    let variant: ConflictVariant
    var chainFront: Bool = false
}

/**
 * 图层间排序键 — 与 primaryComparator(step desc, startNode asc, id asc)对齐。
 * a = -step(反转使 desc 变 asc), b = startNode, c = id。
 */
private struct LayerSortKey: Comparable {
    let a: Int, b: Int, c: Int64
    static func < (l: LayerSortKey, r: LayerSortKey) -> Bool {
        if l.a != r.a { return l.a < r.a }
        if l.b != r.b { return l.b < r.b }
        return l.c < r.c
    }
}

enum ConflictLayoutEngine {

    /**
     * 找出全部冲突簇。输出簇间按 day 升序,簇内课程已按主课判定序排好。
     *
     * timeJson 非空(推荐,渲染主链路): ownTime 课的真实时间区间(分钟级)参与聚簇 —
     * 跨节次空隙反算出的节点范围不再制造假冲突(用户 2026-09-09: 12:30 结束跨午间
     * 空隙被吸进 14:00 节 = 报障本体)。比较基准:
     *   - ownTime 课 = startTime~endTime 本身
     *   - 常规课     = 其节次的真实起止时间(effectiveCourseTime 同一契约)
     * 节点区间只用于排序/簇内几何, 重叠判定一律按分钟区间。真实时间不重叠的课绝不入簇。
     *
     * timeJson 为空(旧调用方兼容): 行为与历史版本完全一致 — 节点区间 [startNode,
     * startNode+step-1] 相交即聚簇。
     */
    static func findClusters(_ courses: [CourseEntity], timeJson: String? = nil) -> [ConflictCluster] {
        // 按 day 分组 → 簇内按 startNode 升序,线性扫相邻区间合并 → 仅保留 size≥2 的簇
        let byDay = Dictionary(grouping: courses, by: { $0.day }).sorted { $0.key < $1.key }
        return byDay.flatMap { (day, dayCourses) in
            let sorted = dayCourses.sorted {
                if $0.startNode != $1.startNode { return $0.startNode < $1.startNode }
                if $0.step != $1.step { return $0.step < $1.step }
                return $0.id < $1.id
            }
            let regions = timeJson != nil
                ? mergeOverlappingByTime(sorted, timeJson!)
                : mergeOverlapping(sorted)
            return regions
                .filter { $0.count >= 2 }
                .map { ConflictCluster(day: day, courses: $0.sorted(by: primaryComparator)) }
        }
    }

    /// 主课判定序: step 降 > startNode 升 > id 升。
    static func primaryOrder(_ courses: [CourseEntity]) -> [CourseEntity] {
        courses.sorted(by: primaryComparator)
    }

    static func primaryComparator(_ a: CourseEntity, _ b: CourseEntity) -> Bool {
        if a.step != b.step { return a.step > b.step }          // step 降
        if a.startNode != b.startNode { return a.startNode < b.startNode } // startNode 升
        return a.id < b.id                                       // id 升
    }

    /**
     * 布局一簇: 返回全簇课,输出顺序 = zRank 升序(主课判定序;topOverrideId 命中时该课
     * 所在图层整体提到 zRank 0,其余保持图层间相对顺序,层内按 startNode 升序拼接)。
     *
     * style ∈ "stack"/"fold"/"rail",按样式直配(v7.10.16u;旧版 stack 在 N≥3
     * 合流为 FOLD,层身份职责已移交轮换 + N 徽标后撤销)。
     *
     * maxNode(可空,final fix wave Important): UI 渲染把每课区间 clamp 进 [1, maxNode]
     * (startNode > maxNode 的课整课不画,step 截到不越界)。hidden 必须在同一裁剪空间算,
     * 否则「界外尾部节次独占」的课会被判非 hidden 拿不到标记,UI 裁剪后却零视觉零 tap。
     * 非 null 时先 clamp 再算露出(全被 clamp 出区间 → 露出集空 → hidden);null 同不裁剪。
     *
     * v7.8 图层语义: layers = chainGroups(courses) — 反复提取最大互不重叠集合。
     *   默认态: 全局主序最高课所在图层置顶,其余层按【层首课主序】垫后。
     *   override: 被点课所在图层整体置顶。
     *   v7.10.16r 交叉验证修订: layerOrderOverride(完整层序,轮换通道)优先 —
     *     按 rep id(层内 maxWith(primaryComparator),与 defaultLayerIdOrder/
     *     memberToLayerRep 三处同键)逐层映射,未知 id 跳过、重复 id 去重(评审 cycle2 #6:
     *     override 重复会让同一层被收集两次双绘)、缺失层按默认序补尾(层集合完备);
     *     无该参数时原 topOverrideId 语义不变(两通道互斥)。
     * v7.10.16m/n: fold 样式一切非置顶图层 hidden=true(虚线语言);STACK/RAIL 沉底真卡。
     */
    static func layoutCluster(
        _ cluster: ConflictCluster,
        style: String,
        topOverrideId: Int64? = nil,
        maxNode: Int? = nil,
        layerOrderOverride: [Int64]? = nil
    ) -> [LaidOutCourse] {
        let ordered = primaryOrder(cluster.courses)
        _ = ordered // (Kotlin 原文同样只用于文档语义;z 序实际来自图层构建)

        // === v7.8 图层构建 ===
        let layers = chainGroups(cluster.courses)
        var layerOfId: [Int64: [CourseEntity]] = [:]
        for g in layers { for c in g { layerOfId[c.id] = g } }
        let hasChainLayer = layers.contains { $0.count >= 2 }

        // 层间默认序: LayerSortKey = (-step, startNode, id) 升序 — step 反转 ≡ primaryComparator
        // 层代表 = 层内 maxWith(primaryComparator)(v7.10.16r 交叉验证修订: 链层 first()
        // 未必是代表,三处必须同键 — 见 defaultLayerIdOrder/memberToLayerRep)。
        let defaultLayerOrder: [[CourseEntity]] = layers.sorted { ga, gb in
            let ta = ga.max(by: primaryComparator)!
            let tb = gb.max(by: primaryComparator)!
            return LayerSortKey(a: -ta.step, b: ta.startNode, c: ta.id)
                < LayerSortKey(a: -tb.step, b: tb.startNode, c: tb.id)
        }
        // 层代表 id(去重/判同一性用): Swift 数组是值类型,用 maxWith 代表 id 判
        // 「同一层」 — Kotlin `it !== front` 语义等价(每课恰属一层,层代表 id 层间唯一)。
        func repId(_ g: [CourseEntity]) -> Int64 { g.max(by: primaryComparator)!.id }
        // z 序构造(v7.10.16r 交叉验证修订): layerOrderOverride(完整层序,轮换通道)
        // 优先 — 按 rep id 逐层映射,未知 id 跳过、缺失层按默认序补尾(层集合完备);
        // 无 override 时原 topOverrideId 语义不变(该层整体前移,其余默认序垫后)。
        var orderedLayers: [[CourseEntity]]
        if let override = layerOrderOverride {
            var byRep: [Int64: [CourseEntity]] = [:]
            for g in defaultLayerOrder { byRep[repId(g)] = g }
            // 去重防御(评审 cycle2 #6): override 序重复 id 会让同一层被收集两次双绘;
            // 按 rep id 去重保留首个命中,缺失层仍按默认序补尾(层集合完备)。
            var seen = Set<Int64>()
            var front: [[CourseEntity]] = []
            for rid in override {
                if let g = byRep[rid], seen.insert(rid).inserted { front.append(g) }
            }
            for g in defaultLayerOrder where !seen.contains(repId(g)) { front.append(g) }
            orderedLayers = front
        } else if let ov = topOverrideId, let front = layerOfId[ov] {
            let frontRep = repId(front)
            orderedLayers = [front] + defaultLayerOrder.filter { repId($0) != frontRep }
        } else {
            orderedLayers = defaultLayerOrder
        }
        let zOrdered: [CourseEntity] = orderedLayers.flatMap { g in g.sorted { $0.startNode < $1.startNode } }

        // === 露出区间工具 ===
        // 露出计算区间: maxNode 非 null 时先 clamp 进 [1, maxNode](与 UI 裁剪空间一致);
        // clamp 后为空(整课出界)→ 空区间,露出集恒空 → hidden(UI 本就不渲染该课)。
        func nodesOf(_ course: CourseEntity) -> ClosedRange<Int>? {
            let start: Int
            let endIncl: Int
            if let mn = maxNode {
                start = max(course.startNode, 1)
                endIncl = min(course.startNode + course.step - 1, mn)
                if start > endIncl { return nil }
            } else {
                start = course.startNode
                endIncl = course.startNode + course.step - 1
            }
            return start...endIncl
        }

        return zOrdered.enumerated().map { rank, course in
            let ownNodes = nodesOf(course)
            // chainFront(v7.8 重定义): 该课所在层是多课层且该层当前为顶层 → 全员置顶形态
            let ownLayer = layerOfId[course.id]
            let isFrontLayer: Bool
            if let own = ownLayer, let first = orderedLayers.first {
                // 值类型数组: 用成员 id 集合判「同一层」
                isFrontLayer = Set(own.map { $0.id }) == Set(first.map { $0.id })
            } else {
                isFrontLayer = false
            }
            // v7.10.16m: FOLD 沉底一律 hidden=true(回到经典 FOLD 虚线语言)。
            // v7.10.16n: fold 样式不看链组与否 — 一切非置顶图层 hidden=true。
            let foldSinkToDash = style == "fold" && ownLayer != nil && !isFrontLayer
            let hidden: Bool
            if foldSinkToDash {
                hidden = true
            } else if hasChainLayer {
                // 裁剪出界(整课不可见)仍标 hidden(UI 不渲染它)
                hidden = ownNodes == nil
            } else if ownNodes == nil {
                hidden = true
            } else if rank == 0 {
                hidden = false // 顶层课永不为 hidden
            } else {
                // 本课区间减去所有更高层(zRank 更小)课的覆盖并集 → 露出集
                var covered = Set<Int>()
                for i in 0..<rank {
                    if let ns = nodesOf(zOrdered[i]) { covered.formUnion(ns) }
                }
                hidden = ownNodes!.allSatisfy { covered.contains($0) }
            }
            let chainFront = hasChainLayer && ownLayer != nil && ownLayer!.count >= 2 && isFrontLayer

            // v7.6 图层语义: N≥3 合流的「N」按图层数——层算 1 层,不是裸课数。
            let layerCount = layers.count
            let variant: ConflictVariant = !hidden
                ? .noMark
                : variantFor(style, layerCount,
                             chainMode: hasChainLayer && ownLayer!.count >= 2)
            return LaidOutCourse(course: course, zRank: rank, hidden: hidden,
                                 variant: variant, chainFront: chainFront)
        }
    }

    /**
     * hidden 课的 variant 映射(v7.10.16u, 用户 2026-09-04 报「叠层偏移怎么没了」):
     * 三种 style 全部直配。v7.10.16f 的「stack N≥3 合流 FOLD」撤销 —
     * 当初合流的理由是 4dp 偏移边承载不了三层语义,但 v7.10.16r 轮换上线后
     * 层身份已由轮换点击 + N 徽标承载,偏移边不再背负该职责,
     * 用户选叠层就该看到叠层(哪怕三层)。
     * rail 直配;**fold 永远 FOLD** — 删除 v3 的同起点回落
     * (「折角样式下肯定是永远折角的」;起点不齐的错位缺口是折角固有形态)。
     * 链式模式(chainMode=true): hidden 课是被链组全遮的重叠者,按样式直配。
     *
     * v7.6 图层语义(历史): clusterSize 形参曾以「图层数」驱动 N≥3 合流判定
     * (链组整组算 1 层);合流撤销后该形参不再参与分派,仅为调用兼容保留。
     */
    private static func variantFor(
        _ style: String,
        _ clusterSize: Int,
        chainMode: Bool = false
    ) -> ConflictVariant {
        _ = clusterSize // v7.10.16u 起不参与分派
        if style == "rail" { return .rail }
        // 链式模式: hidden 课=被链组全遮的重叠者,直接按样式走
        if chainMode { return style == "fold" ? .fold : .stack }
        // v7.10.16f(用户 2026-09-03): 折角样式永远折角 — 删除同起点回落
        if style == "fold" { return .fold }
        return .stack
    }

    /**
     * 图层划分(v7.8 定版) — 反复从剩余课中提取最大互不重叠集合:
     * 每轮按 startNode 升序,区间图最大独立集按右端点贪心。
     * 兜底: 极端情况取第一门课作单课图层,防死循环。
     */
    static func chainGroups(_ courses: [CourseEntity]) -> [[CourseEntity]] {
        if courses.isEmpty { return [] }
        var remaining = courses
        var layers: [[CourseEntity]] = []

        while !remaining.isEmpty {
            let sorted = remaining.sorted {
                if $0.startNode != $1.startNode { return $0.startNode < $1.startNode }
                if $0.step != $1.step { return $0.step < $1.step }
                return $0.id < $1.id
            }
            var layer: [CourseEntity] = []
            var currentEnd = -1
            for c in sorted {
                let start = c.startNode
                let inclEnd = c.startNode + c.step - 1
                if start > currentEnd {
                    layer.append(c)
                    currentEnd = inclEnd
                }
            }
            if layer.isEmpty {
                layer.append(sorted[0])
            }
            layers.append(layer.sorted { $0.startNode < $1.startNode })
            let layerIds = Set(layer.map { $0.id })
            remaining.removeAll { layerIds.contains($0.id) }
        }
        return layers
    }

    /// 线性扫已按 startNode 排序的区间,相邻相交则合并为一簇(传递闭包)。
    static func mergeOverlapping(_ sorted: [CourseEntity]) -> [[CourseEntity]] {
        if sorted.isEmpty { return [] }
        var clusters: [[CourseEntity]] = [[sorted[0]]]
        var currentEnd = sorted[0].startNode + sorted[0].step - 1
        for c in sorted.dropFirst() {
            if c.startNode <= currentEnd {
                clusters[clusters.count - 1].append(c)
                currentEnd = max(currentEnd, c.startNode + c.step - 1)
            } else {
                clusters.append([c])
                currentEnd = c.startNode + c.step - 1
            }
        }
        return clusters
    }

    // =====================================================================================
    // v7.10 Feature 2 — 周视图局部栏位分割
    // =====================================================================================

    /// 周视图栏位布局结果 — 每课一段;无冲突课 laneCount=1(全宽)。
    struct WeekLaneSegment {
        let course: CourseEntity
        let lane: Int        // 0 起的栏位序号
        let laneCount: Int   // 所在连通冲突区域的总栏数;无冲突 = 1
    }

    /**
     * 周视图局部栏位分割(纯函数) — 「分栏只适用于周视图 跟网格视图无关」。
     * 三步: 按 day 分桶 → mergeOverlapping 分区域 → 区域内 chainGroups 分栏。
     */
    static func weekLaneSegments(_ courses: [CourseEntity]) -> [WeekLaneSegment] {
        if courses.isEmpty { return [] }
        var out: [WeekLaneSegment] = []
        // 分组保序 (Kotlin groupBy = LinkedHashMap 语义, 按输入遇到 day 的顺序),
        // 跨天输入时 segment 顺序才确定 — 与 weekLaneRows 同一 dayOrder 模式。
        var dayOrder: [Int] = []
        var byDay: [Int: [CourseEntity]] = [:]
        for c in courses {
            if byDay[c.day] == nil { dayOrder.append(c.day) }
            byDay[c.day, default: []].append(c)
        }
        for day in dayOrder {
            let dayCourses = byDay[day] ?? []
            let sorted = dayCourses.sorted {
                if $0.startNode != $1.startNode { return $0.startNode < $1.startNode }
                if $0.step != $1.step { return $0.step < $1.step }
                return $0.id < $1.id
            }
            for region in mergeOverlapping(sorted) {
                if region.count < 2 {
                    for c in region { out.append(WeekLaneSegment(course: c, lane: 0, laneCount: 1)) }
                    continue
                }
                let lanes = chainGroups(region)
                for (laneIdx, lane) in lanes.enumerated() {
                    for c in lane {
                        out.append(WeekLaneSegment(course: c, lane: laneIdx, laneCount: lanes.count))
                    }
                }
            }
        }
        return out
    }

    /// 周视图行分组结果 — 一行 = 一个渲染行。冲突区域整区域一行;无冲突课一行一门(全宽)。
    struct WeekLaneRow {
        let courses: [CourseEntity]      // 行内全部课,按 startNode 升序
        let laneOf: [Int64: Int]         // courseId → 栏位序号(仅冲突行非空)
        let laneCount: Int               // 冲突行 = 栏数;无冲突行 = 1
    }

    /**
     * 周视图渲染行分组(v7.10.6 / ← Android 25c943f0 issue #37) — 修复丢课/重复渲染:
     * 区域划分是划分(每课恰属一个区域),行成员 = 区域全体,每课恰渲染一次。
     * timeJson 非空时: ownTime 课先按真实时间归一化节点, 区域划分改走分钟域
     * (mergeOverlappingByTime, 混合域不成簇); 时间零交集的 ownTime 课对不再因
     * 落库占位节点相同被并成冲突行。行序: 各行按行首课 startNode 升序穿插。
     */
    static func weekLaneRows(_ courses: [CourseEntity], timeJson: String? = nil) -> [WeekLaneRow] {
        if courses.isEmpty { return [] }
        let prepared = timeJson == nil ? courses : courses.map { $0.normalizeNode(timeJson: timeJson!) }
        var rows: [WeekLaneRow] = []
        // 分组保序 (Kotlin groupBy = LinkedHashMap 语义), 避免跨天同节点行的顺序抖动
        var dayOrder: [Int] = []
        var byDay: [Int: [CourseEntity]] = [:]
        for c in prepared {
            if byDay[c.day] == nil { dayOrder.append(c.day) }
            byDay[c.day, default: []].append(c)
        }
        for day in dayOrder {
            let dayCourses = byDay[day] ?? []
            let sorted = dayCourses.sorted {
                if $0.startNode != $1.startNode { return $0.startNode < $1.startNode }
                if $0.step != $1.step { return $0.step < $1.step }
                return $0.id < $1.id
            }
            let regions = timeJson == nil
                ? mergeOverlapping(sorted)
                : mergeOverlappingByTime(sorted, timeJson!)
            for region in regions {
                if region.count < 2 {
                    for c in region { rows.append(WeekLaneRow(courses: [c], laneOf: [:], laneCount: 1)) }
                    continue
                }
                let lanes = chainGroups(region)
                var laneOf: [Int64: Int] = [:]
                for (laneIdx, lane) in lanes.enumerated() {
                    for c in lane { laneOf[c.id] = laneIdx }
                }
                rows.append(WeekLaneRow(courses: region.sorted { $0.startNode < $1.startNode },
                                        laneOf: laneOf, laneCount: lanes.count))
            }
        }
        return rows.sorted { $0.courses.first!.startNode < $1.courses.first!.startNode }
    }

    /// 真实时间区间(分钟级)聚簇 ← mergeOverlappingByTime: 相邻课真实时间区间相交才并簇。
    /// 混合域(一方时间不可解析)判不相交 — 节点数(1..12)永远小于分钟数, 直接比会把脏
    /// ownTime 课粘进时间簇; 宁可漏报不可误报。
    static func mergeOverlappingByTime(_ sorted: [CourseEntity], _ timeJson: String) -> [[CourseEntity]] {
        if sorted.isEmpty { return [] }
        let intervals = sorted.map { realIntervalOf($0, timeJson) }
        var clusters: [[CourseEntity]] = [[sorted[0]]]
        var currentEnd = intervals[0]?.1 ?? (sorted[0].startNode + sorted[0].step - 1)
        var currentEndIsTime = intervals[0] != nil
        for i in 1..<sorted.count {
            let c = sorted[i]
            let iv = intervals[i]
            let start: Int
            let end: Int
            let isTime: Bool
            if let iv = iv {
                start = iv.0; end = iv.1; isTime = true
            } else {
                start = c.startNode; end = c.startNode + c.step - 1; isTime = false
            }
            let overlaps: Bool
            if currentEndIsTime, iv != nil {
                overlaps = start < currentEnd
            } else if !currentEndIsTime, iv == nil {
                overlaps = start <= currentEnd
            } else {
                overlaps = false
            }
            if overlaps {
                clusters[clusters.count - 1].append(c)
                if end > currentEnd {
                    currentEnd = end
                    currentEndIsTime = isTime
                }
            } else {
                clusters.append([c])
                currentEnd = end
                currentEndIsTime = isTime
            }
        }
        return clusters
    }

    /// 课程真实时间区间(当日分钟) — 解析不出或 end<=start → nil (回落节点域)
    static func realIntervalOf(_ c: CourseEntity, _ timeJson: String) -> (Int, Int)? {
        guard let eff = TimeTableUtils.effectiveCourseTime(
            isIrregularTime: c.isIrregularTime || c.ownTime,
            startTime: c.startTime,
            endTime: c.endTime,
            startNode: c.startNode,
            step: c.step,
            timeJson: timeJson
        ) else { return nil }
        guard let s = TimeTableUtils.hmMinutes(eff.0),
              let e = TimeTableUtils.hmMinutes(eff.1), e > s else { return nil }
        return (s, e)
    }

    // =====================================================================================
    // v7.10.8 WeekGrid 网格小组件冲突分栏 — 与 App 周视图同一引擎,一份真相源
    // =====================================================================================

    /// 网格小组件单日冲突分栏结果: 横向起点比例与宽度比例。
    struct GridLaneRect {
        let course: CourseEntity
        let laneStartFraction: Double   // 横向起点占列宽比例 0..1
        let laneWidthFraction: Double   // 横向宽度占列宽比例 0..1
    }

    /// 网格小组件单日分栏(纯函数) — WeekGrid 渲染器对每天的课调一次。
    /// timeJson 非空 → ownTime 课按真实分钟聚簇(与 App 主视图同一时间域契约)。
    static func gridDayLanes(_ courses: [CourseEntity], timeJson: String? = nil) -> [GridLaneRect] {
        if courses.isEmpty { return [] }
        var out: [GridLaneRect] = []
        let prepared = timeJson == nil ? courses : courses.map { $0.normalizeNode(timeJson: timeJson!) }
        let sorted = prepared.sorted {
            if $0.startNode != $1.startNode { return $0.startNode < $1.startNode }
            if $0.step != $1.step { return $0.step < $1.step }
            return $0.id < $1.id
        }
        let regions = timeJson == nil
            ? mergeOverlapping(sorted)
            : mergeOverlappingByTime(sorted, timeJson!)
        for region in regions {
            if region.count < 2 {
                for c in region { out.append(GridLaneRect(course: c, laneStartFraction: 0, laneWidthFraction: 1)) }
                continue
            }
            let lanes = chainGroups(region)
            let w = 1.0 / Double(lanes.count)
            for (laneIdx, lane) in lanes.enumerated() {
                for c in lane {
                    out.append(GridLaneRect(course: c,
                                            laneStartFraction: Double(laneIdx) * w,
                                            laneWidthFraction: w))
                }
            }
        }
        return out.sorted { $0.course.startNode < $1.course.startNode }
    }

    /**
     * 冲突深度闸门(v7.10.9) — 同一天同一冲突区域最多 2 栏,第三层禁止存在。
     * 返回超出 2 栏的 day 集合(空集 = 合法)。
     */
    static func daysExceedingTwoLanes(_ courses: [CourseEntity]) -> Set<Int> {
        let byDay = Dictionary(grouping: courses, by: { $0.day })
        var out = Set<Int>()
        for (day, dayCourses) in byDay {
            let sorted = dayCourses.sorted {
                if $0.startNode != $1.startNode { return $0.startNode < $1.startNode }
                if $0.step != $1.step { return $0.step < $1.step }
                return $0.id < $1.id
            }
            let maxLanes = mergeOverlapping(sorted).map { chainGroups($0).count }.max() ?? 0
            if maxLanes > 2 { out.insert(day) }
        }
        return out
    }

    /// 簇键公式唯一真值(v7.10.16p) — "day:startNode:step"(锚课三元组)。
    static func conflictClusterKey(_ anchor: CourseEntity) -> String {
        "\(anchor.day):\(anchor.startNode):\(anchor.step)"
    }

    // =====================================================================================
    // v7.10.16r N≥3 轮换置顶 (issue#10)
    // =====================================================================================

    /// 簇的「默认图层序」— 每图层的代表 id,按 layoutCluster 同一真值排序:
    /// 图层按其代表课(maxWith(primaryComparator))的 (-step, startNode, id) 升序 —
    /// 与 layoutCluster.defaultLayerOrder 完全一致。
    /// 代表判定与 memberToLayerRep / layoutCluster.layerOrderOverride 三处同键:
    /// 均为层内 maxWith(primaryComparator) — 链层(成员 step 不等)的 first() 未必是
    /// 代表,两约定分裂会让气泡选课 indexOf=-1 静默无效(评审 cycle2 #1)。
    /// 注意 maxWith 语义 = 比较器下最大者: step 最小者最「大」;同 step 取 startNode 最大 —
    /// 与 primaryOrder「主序最前」(startNode 最小)是两端,层代表固定取 maxWith 端。
    static func defaultLayerIdOrder(_ courses: [CourseEntity]) -> [Int64] {
        orderedDefaultLayers(courses).map { $0.max(by: primaryComparator)!.id }
    }

    /// 簇的「默认图层序」完整形态: 排序后的图层本体(每层 = 成员课列表)。
    /// defaultLayerIdOrder / 轮换 UI 的成员→层代表反查共用,保证单一真值。
    /// 层代表 = maxWith(primaryComparator)(与 badge/详情 radio 的 rep 语义一致)。
    private static func orderedDefaultLayers(_ courses: [CourseEntity]) -> [[CourseEntity]] {
        chainGroups(courses).sorted { ga, gb in
            let ta = ga.max(by: primaryComparator)!
            let tb = gb.max(by: primaryComparator)!
            return LayerSortKey(a: -ta.step, b: ta.startNode, c: ta.id)
                < LayerSortKey(a: -tb.step, b: tb.startNode, c: tb.id)
        }
    }

    /// 置顶感知轮换基准序(评审 #4): 用户置顶层(topRepId)永远排基准首位,其余层保持
    /// 默认相对序。整周期轮换(步数 ≡ 0 mod N)时轮换序 === 基准序 → 用户置顶层自动
    /// 回到顶部,持久化偏好不被临时轮换遮蔽。topRepId 为 nil / 不在簇内 → 退回默认序。
    static func overrideAwareLayerOrder(_ courses: [CourseEntity], topRepId: Int64?) -> [Int64] {
        let defaultOrder = defaultLayerIdOrder(courses)
        guard let top = topRepId, defaultOrder.contains(top) else { return defaultOrder }
        return [top] + defaultOrder.filter { $0 != top }
    }

    /// 气泡徽标文案(评审 #3): 「+N」= 层数 - 2(默认两层已显示),按层计不按课数,
    /// 轮换中恒定;层数 <2 → 0(不显示)。
    /// 基数裁定(评审 cycle2 #2, trade-off 有意为之): layerCount 用**全量簇层数**,
    /// 不按网格内可渲染层裁剪 — 徽标 +N 与气泡弹窗候选(picker 全量层)必须一致,
    /// 出界层(整课 > maxNode)在弹窗里照样可选中并轮换到顶。
    static func hiddenLayerCount(_ layerCount: Int) -> Int { max(layerCount - 2, 0) }

    /// 成员课 id → 其所在图层的代表 id(maxWith(primaryComparator),与
    /// overrideAwareLayerOrder / defaultLayerIdOrder / layoutCluster.layerOrderOverride
    /// 三处同键 — 评审 cycle2 #1)。
    /// 气泡弹窗点选任意成员时反查该层在轮换序中的位置。
    static func memberToLayerRep(_ courses: [CourseEntity]) -> [Int64: Int64] {
        var out: [Int64: Int64] = [:]
        for layer in orderedDefaultLayers(courses) {
            let rep = layer.max(by: primaryComparator)!.id
            for c in layer { out[c.id] = rep }
        }
        return out
    }

    /// 轮换推进一位(纯函数)。层序编码为按位十进制(123 → 231),循环左移。
    /// 非法输入(≤0 / 含 0 位 / 超 9 层 / 1 层)不轮换。
    static func rotationNext(_ order: Int) -> Int {
        if order <= 0 { return 0 }
        var digits = 0
        var v = order
        while v > 0 {
            if v % 10 == 0 { return 0 } // 0 位非法(层号从 1 起)
            v /= 10
            digits += 1
        }
        if digits > 9 || digits < 2 { return order }
        let pw = Int(pow(10.0, Double(digits - 1)))
        let head = order / pw
        let tail = order % pw
        return tail * 10 + head
    }

    /// 把轮换推进 [steps] 位应用到默认序(循环左移)。steps 取模,负数同余处理。
    static func applyLayerRotation(_ defaultOrder: [Int64], _ steps: Int) -> [Int64] {
        if defaultOrder.count < 2 || steps % defaultOrder.count == 0 { return defaultOrder }
        let k = ((steps % defaultOrder.count) + defaultOrder.count) % defaultOrder.count
        return Array(defaultOrder[k...]) + Array(defaultOrder[..<k])
    }

    /// 解析当前应显示的图层序: 会话轮换步数非空则循环左移,否则默认序。
    static func resolveLayerOrder(_ courses: [CourseEntity], _ sessionRotation: Int?) -> [Int64] {
        let defaultOrder = defaultLayerIdOrder(courses)
        if let r = sessionRotation, r > 0 {
            return applyLayerRotation(defaultOrder, r)
        }
        return defaultOrder
    }

    static func conflictClusterKey(_ cluster: ConflictCluster) -> String {
        conflictClusterKey(cluster.courses.first!)
    }

    /**
     * 清理指向已失效课程的置顶偏好(v7.10.16p): 删课后 defaultTopMap repId 指向已删课
     * → 偏好静默失效。规则: repId 不在现存课 → 删;键不在现存簇键集合 → 删;其余保留。
     */
    static func pruneConflictDefaultTop(
        _ stored: [String: Int64],
        _ currentCourses: [CourseEntity],
        timeJson: String? = nil
    ) -> [String: Int64] {
        if stored.isEmpty || currentCourses.isEmpty { return [:] }
        let liveIds = Set(currentCourses.map { $0.id })
        var liveKeys = Set<String>()
        for c in findClusters(currentCourses, timeJson: timeJson) { liveKeys.insert(conflictClusterKey(c)) }
        return stored.filter { liveKeys.contains($0.key) && liveIds.contains($0.value) }
    }

    // =====================================================================================
    // ← ui/component/ConflictCard.kt 的纯函数部分(引擎封装 + 绘制序 + 命中区几何)
    // =====================================================================================

    /**
     * 引擎封装 — UI 渲染层的唯一入口(纯函数可测)。
     * findClusters(仅 size≥2 的簇)后逐簇 layoutCluster 展开,展平返回全部簇内课。
     * topOverrideId 只影响命中其 id 的那个簇,其余簇回落主课判定序。
     */
    static func layoutFor(
        _ courses: [CourseEntity],
        style: String,
        topOverrideId: Int64? = nil
    ) -> [LaidOutCourse] {
        findClusters(courses).flatMap { cluster in
            layoutCluster(cluster, style: style, topOverrideId: topOverrideId)
        }
    }

    /// 簇内绘制项 — Card(课卡)或 Mark(hidden 课的命中区)。
    enum CourseDrawItem {
        case card(LaidOutCourse)
        case mark(hiddenCourseId: Int64, variant: ConflictVariant)
    }

    /**
     * 簇内绘制序计算 — hidden 课的定义 = 被更高层课完全覆盖。故绘制序 =
     * 非顶层课卡(zRank 降序,先画被盖住的)→ 顶卡(zRank 0 最后画) → 全部 hidden 课的
     * Mark 命中区(按 zRank 升序,叠在一切卡之上)。
     * 顶层判定兜底: 无 zRank 0 时取列表首位当顶层;输入为空才返回空。
     */
    static func overlayMarkOrder(_ laid: [LaidOutCourse]) -> [CourseDrawItem] {
        if laid.isEmpty { return [] }
        let top = laid.first { $0.zRank == 0 } ?? laid[0]
        let others = laid.filter { $0.course.id != top.course.id || $0.zRank != top.zRank }
            .sorted { $0.zRank > $1.zRank }
        let marks = laid.filter { $0.hidden }.sorted { $0.zRank < $1.zRank }
            .map { CourseDrawItem.mark(hiddenCourseId: $0.course.id, variant: $0.variant) }
        return others.map { CourseDrawItem.card($0) }
            + [.card(top)]
            + marks
    }

    // ---- 视觉常量(视觉修订 v4, 单位 dp) ----
    /// STACK/FOLD 命中区视觉基准边(dp): 16 + 内延 20 = 36dp 见方。
    static let markSquareDp: Double = 16
    /// 命中区在视觉区基础上的总内延(dp,单边) — 手指命中容差。
    static let markHitPadDp: Double = 20
    /// STACK 叠卡收缩量 d(dp) — 几何测试基线(实际值跟设置滑杆走)。
    static let stackOffsetDp: Double = 8
    /// FOLD 折痕直角边长 f(dp) — 默认基线(实际值跟用户拖杆设置走,v7.10.16o)。
    static let foldSizeDp: Double = 16
    /// RAIL 顶卡右侧收窄量(dp) — 测试基线(与 STACK_OFFSET 共用同一设置值)。
    static let railInsetDp: Double = 10

    /**
     * 标记命中区尺寸计算(纯函数): 命中区 = 视觉区 + MARK_HIT_PAD 总内延,
     * 绝不铺满整卡。返回 (w, h)。NONE → (0, 0) 不可点。
     * v7.8.4: RAIL 命中区复用 STACK 风格 — 自身区间右下 36dp 见方。
     */
    static func markHitArea(
        _ variant: ConflictVariant,
        cardWidth: Double,
        cardHeight: Double,
        railWidth: Double = railInsetDp,
        railSegmentHeight: Double? = nil
    ) -> (Double, Double) {
        switch variant {
        case .stack, .fold, .rail:
            let side = min(markSquareDp + markHitPadDp, cardWidth, cardHeight)
            return (side, side)
        case .noMark:
            return (0, 0)
        }
    }

    /**
     * FOLD 折角切换命中区尺寸(纯函数,v7.10.16h): flap 与缺角空白合占顶卡右上
     * f 见方;叠加 MARK_HIT_PAD 指腹容差 → f+20dp 见方。NONE 无折角 → 不可点。
     */
    static func foldSwitchHitArea(
        _ variant: ConflictVariant,
        cardWidth: Double,
        cardHeight: Double,
        foldSize: Double = foldSizeDp
    ) -> (Double, Double) {
        switch variant {
        case .fold:
            let side = min(foldSize + markHitPadDp, cardWidth, cardHeight)
            return (side, side)
        default:
            return (0, 0)
        }
    }

    /**
     * 簇级形态(纯函数,v5) — hidden 课 variant 优先;交换置顶后可能无 hidden 课,
     * 形态不能塌缩成 NONE: rail 恒 RAIL;fold 回落看 foldEligible;其余回落 STACK。
     */
    static func clusterForm(
        style: String,
        firstHiddenVariant: ConflictVariant?,
        foldEligible: Bool = false
    ) -> ConflictVariant {
        if let v = firstHiddenVariant { return v }
        if style == "rail" { return .rail }
        if style == "fold" && foldEligible { return .fold }
        return .stack
    }

    /// 簇内单卡/命中区放置矩形(dp),渲染与单测共用同一份真值。
    struct ConflictRect {
        var x: Double, y: Double, width: Double, height: Double
    }

    /// N 徽标的「N」按图层数,不按裸课数。防御: 组切分与课数对不上 → 回落裸课数。
    static func conflictBadgeLayerCount(groupSizes: [Int], rawCount: Int) -> Int {
        groupSizes.reduce(0, +) == rawCount ? groupSizes.count : rawCount
    }

    /// N 徽标可见性 = 图层 N≥3 且存在 hidden 课(N≥3 的逃生门语义,单位是图层)。
    static func conflictShowBadge(_ layerCount: Int, _ hiddenCount: Int) -> Bool {
        layerCount >= 3 && hiddenCount > 0
    }

    /**
     * 簇内单卡放置矩形(纯函数,v5)。锚点规则: 一切锚定都是相对该课自身区间的方位。
     *   STACK: 顶卡缩 d 锚自身左上;非顶卡缩 d 锚自身右下。切换只换层级,几何恒定。
     *   RAIL:  顶卡右缘收窄 topInset;非顶卡全宽。都按自身真实节位/节数铺。
     *   FOLD/NONE: 全尺寸,自身节位。
     * v6: topInset = 用户设置(A 偏移 d / C 右缘让宽共用),滑杆 4..20dp。
     */
    static func conflictCardRect(
        startNode: Int,
        ownRows: Int,
        isTop: Bool,
        form: ConflictVariant,
        colW: Double,
        rowH: Double,
        gapH: Double,
        minStart: Int,
        topInset: Double = 7
    ) -> ConflictRect {
        let ownH = rowH * Double(max(ownRows, 1)) - gapH
        let y = rowH * Double(startNode - minStart)
        if isTop && form == .stack {
            return ConflictRect(x: 0, y: y, width: colW - topInset, height: ownH - topInset)
        }
        if isTop && form == .rail {
            return ConflictRect(x: 0, y: y, width: colW - topInset, height: ownH)
        }
        if !isTop && form == .stack {
            // 锚自身区间右下: 右缘贴格位右边,下缘贴自己区间的底
            let h = ownH - topInset
            return ConflictRect(x: topInset, y: y + ownH - h, width: colW - topInset, height: h)
        }
        return ConflictRect(x: 0, y: y, width: colW, height: ownH)
    }

    /**
     * hidden 课命中区矩形(纯函数,v5) — 视觉区 + MARK_HIT_PAD 内延,锚自身区间。
     * v7.8.4: RAIL 复用 STACK 风格 — 自身区间右下 36dp 见方。
     */
    static func conflictMarkRect(
        startNode: Int,
        ownRows: Int,
        form: ConflictVariant,
        colW: Double,
        rowH: Double,
        gapH: Double,
        minStart: Int,
        clusterH: Double,
        topInset: Double = 7
    ) -> ConflictRect {
        let ownH = rowH * Double(max(ownRows, 1)) - gapH
        let y = rowH * Double(startNode - minStart)
        switch form {
        case .stack, .rail:
            let side = min(markSquareDp + markHitPadDp, colW, ownH)
            return ConflictRect(x: colW - side, y: y + ownH - side, width: side, height: side)
        default:
            return ConflictRect(x: 0, y: 0, width: 0, height: 0)
        }
    }

    // =====================================================================================
    // issue#23 §5 分数行几何 — ownTime 课按真实分钟比例落位(与整格版同规则,仅坐标换域)
    // =====================================================================================

    /**
     * 簇内单卡放置矩形(分数行坐标版,v6)。与 conflictCardRect 同规则, 差异:
     * - 行坐标是 Double(可含小数, ownTime 课按分钟比例);
     * - 行高经 spanDpOf 加权(占位节次行按分钟占比), nil = 等高回落 rowH*行数。
     */
    static func conflictCardRectFrac(
        startRowFrac: Double,
        ownRowsFrac: Double,
        isTop: Bool,
        form: ConflictVariant,
        colW: Double,
        rowH: Double,
        gapH: Double,
        minStartRow: Double,
        topInset: Double = 7,
        spanDpOf: ((Double, Double) -> Double)? = nil
    ) -> ConflictRect {
        let ownSpanDp = max(spanDpOf?(startRowFrac, startRowFrac + ownRowsFrac)
                            ?? rowH * ownRowsFrac, rowH * 0.3)
        let ownH = ownSpanDp - gapH
        let y = spanDpOf?(minStartRow, startRowFrac) ?? rowH * (startRowFrac - minStartRow)
        if isTop && form == .stack {
            return ConflictRect(x: 0, y: y, width: colW - topInset, height: ownH - topInset)
        }
        if isTop && form == .rail {
            return ConflictRect(x: 0, y: y, width: colW - topInset, height: ownH)
        }
        if !isTop && form == .stack {
            let h = ownH - topInset
            return ConflictRect(x: topInset, y: y + ownH - h, width: colW - topInset, height: h)
        }
        return ConflictRect(x: 0, y: y, width: colW, height: ownH)
    }

    /// hidden 课命中区矩形(分数行坐标版,v6) — 与 conflictMarkRect 同规则, 坐标换域。
    static func conflictMarkRectFrac(
        startRowFrac: Double,
        ownRowsFrac: Double,
        form: ConflictVariant,
        colW: Double,
        rowH: Double,
        gapH: Double,
        minStartRow: Double,
        spanDpOf: ((Double, Double) -> Double)? = nil
    ) -> ConflictRect {
        let ownH = max(spanDpOf?(startRowFrac, startRowFrac + ownRowsFrac)
                       ?? rowH * ownRowsFrac, rowH * 0.3) - gapH
        let y = spanDpOf?(minStartRow, startRowFrac) ?? rowH * (startRowFrac - minStartRow)
        switch form {
        case .stack, .rail:
            let side = min(markSquareDp + markHitPadDp, colW, ownH)
            return ConflictRect(x: colW - side, y: y + ownH - side, width: side, height: side)
        default:
            return ConflictRect(x: 0, y: 0, width: 0, height: 0)
        }
    }
}
