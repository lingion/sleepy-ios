import Foundation

/**
 * v7.10.16t 保存时冲突明细报告(issue#10 轮换落地后的配套, 用户 2026-09-04):
 * 加课保存不再拦截冲突(v7.10.16t 撤除三层闸), 但把撞车细节完整讲给用户 —
 * 和哪门存量课、星期几、第几节到第几节、哪几周。只报「新草稿参与的冲突」,
 * 存量课之间的互撞不报(那是既有状态, 与本次保存无关)。
 *
 * 纯 JVM/Swift 可测: 输入草稿 + 存量 + 星期名, 输出结构化明细;文案模板由调用方
 * (AddCourseScreen 里 L10n.format)传入, 本文件不碰 iOS 资源。
 *
 * Android ConflictDetailReporter.kt 1:1 移植。
 */

/// 一条冲突明细。nodeRangeText/weekText 已是可直接嵌句子的短文本
public struct ConflictDetail {
    public let existingName: String
    public let draftName: String
    public let day: Int
    public let dayText: String
    public let nodeRangeText: String
    public let weekText: String
}

/// WeekType: 0=每周 1=单周 2=双周 3=按周次列实际指定的周
public enum CourseWeekType: Int {
    case everyWeek = 0
    case oddWeek = 1
    case evenWeek = 2
    case custom = 3
}

public enum ConflictDetailReporter {

    /**
     * 找出草稿与存量课的全部冲突(同 day + 节次区间相交 + 公共上课周)。
     * 每对(草稿, 存量)至多一条明细;多条草稿多条存量的组合逐对展开, 按存量课
     * 真实节点位置升序(表单从上往下读的顺序)。
     *
     * issue#23 Fix 3: 接受 timeJson 以便 ownTime 课程在比对前归一化到真实节点号。
     * 用户反馈 2026-09-09: 重叠判定升级为**真实时间区间(分钟级)**相交 —
     * ownTime 课用自身起止, 常规课用节次真实起止(effectiveCourseTime 同一契约)。
     * 跨节次空隙反算出的节点范围不再制造假冲突(12:30 结束跨午间空隙被吸进
     * 14:00 节 = 报障本体)。时间无法解析的课对回落节点区间判定(数据脏时保守)。
     */
    public static func draftConflictDetails(
        drafts: [CourseEntityLite],
        stored: [CourseEntityLite],
        dayNames: [String],
        timeJson: String = ""
    ) -> [ConflictDetail] {
        let timeJson = timeJson.isEmpty ? TimeTableUtils.DEFAULT_TIME_JSON : timeJson
        guard !drafts.isEmpty, !stored.isEmpty else { return [] }
        let normalizedDrafts = drafts.map { $0.normalizedForCompare(timeJson) }
        let normalizedStored = stored.map { $0.normalizedForCompare(timeJson) }
        let byDay = Dictionary(grouping: normalizedStored, by: { $0.day })
        var out: [ConflictDetail] = []
        for (idx, draft) in drafts.enumerated() {
            let nDraft = normalizedDrafts[idx]
            guard let candidates = byDay[nDraft.day] else { continue }
            // (existing course, (node range, parity?))
            var hits: [(CourseEntityLite, (ClosedRange<Int>, Int?))] = []
            for s in candidates {
                guard let commonWeeks = commonWeeks(nDraft, s) else { continue }
                if coursesOverlap(nDraft, s, timeJson) {
                    hits.append((s, commonWeeks))
                }
            }
            // Android sortBy 稳定(同 startNode 保持入库次序); iOS sort 不保证稳定 —
            // 用原始下标钉死平手次序, 与 Android 逐字节同序。
            let orderedHits = hits.enumerated()
                .sorted { ($0.element.0.startNode, $0.offset) < ($1.element.0.startNode, $1.offset) }
                .map(\.element)
            for (s, weeks) in orderedHits {
                let dayText = dayIndices(draft.day, names: dayNames)
                out.append(ConflictDetail(
                    existingName: s.courseName,
                    draftName: draft.courseName,
                    day: draft.day,
                    dayText: dayText,
                    nodeRangeText: nodeRangeText(nDraft, s),
                    weekText: weekText(weeks)
                ))
            }
        }
        return out
    }

    /// 模板拼行(模板含 4 占位: 星期/节次交集文案/周文案/存量课名)
    public static func formatDetail(_ d: ConflictDetail, template: String) -> String {
        return String(format: template, d.dayText, d.nodeRangeText, d.weekText, d.existingName)
    }

    // MARK: - 内部: 区间与周次判定

    private static func nodesOverlap(_ a: CourseEntityLite, _ b: CourseEntityLite) -> Bool {
        let aEnd = a.startNode + a.step - 1
        let bEnd = b.startNode + b.step - 1
        return a.startNode <= bEnd && b.startNode <= aEnd
    }

    /**
     * 重叠判定(分钟级优先): 两课都能解析出真实时间区间 → 分钟域半开区间相交;
     * 任一解析失败 → 回落节点区间(数据脏时保守, 不静默漏报)。
     */
    private static func coursesOverlap(_ a: CourseEntityLite, _ b: CourseEntityLite, _ timeJson: String) -> Bool {
        if let ivA = realIntervalOf(a, timeJson), let ivB = realIntervalOf(b, timeJson) {
            return ivA.0 < ivB.1 && ivB.0 < ivA.1
        }
        return nodesOverlap(a, b)
    }

    /// 课的真实时间区间(秒, 自午夜起) — ownTime 用自身起止, 常规课用节次起止。
    private static func realIntervalOf(_ c: CourseEntityLite, _ timeJson: String) -> (Int, Int)? {
        guard let eff = TimeTableUtils.effectiveCourseTime(
            isIrregularTime: c.isIrregularTime || c.ownTime,
            startTime: c.startTime, endTime: c.endTime,
            startNode: c.startNode, step: c.step, timeJson: timeJson) else { return nil }
        guard let s = TimeTableUtils.hmToSeconds(eff.0),
              let e = TimeTableUtils.hmToSeconds(eff.1), e > s else { return nil }
        return (s, e)
    }

    /// 节次交集(闭区间), 无交集返回 nil
    private static func nodeIntersection(_ a: CourseEntityLite, _ b: CourseEntityLite) -> ClosedRange<Int>? {
        let lo = max(a.startNode, b.startNode)
        let hi = min(a.startNode + a.step - 1, b.startNode + b.step - 1)
        return lo <= hi ? lo...hi : nil
    }

    /// 公共上课周: 返回(实际命中闭区间, 奇偶限定) 二元组;无公共周返回 nil
    private static func commonWeeks(_ a: CourseEntityLite, _ b: CourseEntityLite) -> (ClosedRange<Int>, Int?)? {
        let lo = max(a.startWeek, b.startWeek)
        let hi = min(a.endWeek, b.endWeek)
        guard lo <= hi else { return nil }
        let parity: Int? = {
            if a.type == 1 || b.type == 1 { return 1 }
            if a.type == 2 || b.type == 2 { return 2 }
            return nil
        }()
        func hits(_ week: Int, _ type: Int) -> Bool {
            switch type {
            case 1: return week % 2 == 1
            case 2: return week % 2 == 0
            default: return true
            }
        }
        var first = -1
        var last = -1
        for week in lo...hi {
            if hits(week, a.type) && hits(week, b.type) {
                if first < 0 { first = week }
                last = week
            }
        }
        guard first >= 0 else { return nil }
        return (first...last, parity)
    }

    private static func nodeRangeText(_ draft: CourseEntityLite, _ s: CourseEntityLite) -> String {
        guard let r = nodeIntersection(draft, s) else { return "" }
        return r.lowerBound == r.upperBound ? "\(r.lowerBound)" : "\(r.lowerBound)-\(r.upperBound)"
    }

    /**
     * 周文案(用户要求「哪几周」讲清):
     *   「第1-16周」/「第5-8周」/「单周 第1-15周」/「双周 第2-14周」/单周点「第5周」。
     * 留 formatGap 钩子供 i18n; 当前实现保留 Kotlin 模板: 单周/双周 前缀 + 第X-Y周
     */
    private static func weekText(_ weeks: (ClosedRange<Int>, Int?)) -> String {
        let (r, parity) = weeks
        let range = r.lowerBound == r.upperBound ? "\(r.lowerBound)" : "\(r.lowerBound)-\(r.upperBound)"
        let prefix: String
        switch parity {
        case 1: prefix = "单周 "
        case 2: prefix = "双周 "
        default: prefix = ""
        }
        return "\(prefix)第\(range)周"
    }

    /// iOS 0-indexed -> 1-indexed day lookup
    private static func dayIndices(_ day: Int, names: [String]) -> String {
        let idx = day - 1
        return idx >= 0 && idx < names.count ? names[idx] : ""
    }
}

/// 极简 Course 实体: 仅冲突检测需要的字段, 避免与 Room/GRDB 实体耦合
public struct CourseEntityLite {
    public let courseName: String
    public let day: Int           // 1..7
    public let startNode: Int     // 第几节开始
    public let step: Int          // 连节数
    public let startWeek: Int
    public let endWeek: Int
    public let type: Int          // CourseWeekType.rawValue
    // issue#23 Fix 3: ownTime 课比对前须 normalizeNode + 分钟域重叠判定 — 需要真实起止
    public let ownTime: Bool
    public let startTime: String
    public let endTime: String
    public let isIrregularTime: Bool
    /// issue#23 §5: 边缘槽位卡 — 网格位置 = 槽位编号本身, 禁止按时间重映射
    /// (← Android CourseEntity.kt normalizeNode 首闸 `if (isIrregularNode) return this`)
    public let isIrregularNode: Bool

    public init(courseName: String, day: Int, startNode: Int, step: Int,
                startWeek: Int, endWeek: Int, type: Int,
                ownTime: Bool = false, startTime: String = "", endTime: String = "",
                isIrregularTime: Bool = false, isIrregularNode: Bool = false) {
        self.courseName = courseName
        self.day = day
        self.startNode = startNode
        self.step = step
        self.startWeek = startWeek
        self.endWeek = endWeek
        self.type = type
        self.ownTime = ownTime
        self.startTime = startTime
        self.endTime = endTime
        self.isIrregularTime = isIrregularTime
        self.isIrregularNode = isIrregularNode
    }

    /// issue#23 Fix 3: ownTime 课程/草稿的 startNode 只是 UI 占位, 真实网格位置
    /// 由 startTime/endTime 反算(normalizeNode)。比较前必须先 normalize, 否则
    /// ownTime 草稿按占位 startNode 比对会漏报/误报冲突。
    ///
    /// 逐字镜像 Android CourseEntity.normalizeNode(CourseEntity.kt:163-172):
    /// 边缘槽位卡首闸禁止重映射, 起止时间用 isBlank 语义(纯空白当空), 与同仓
    /// CourseEntity.swift:141-146 的 normalizeNode 保持同一契约。
    func normalizedForCompare(_ timeJson: String) -> CourseEntityLite {
        // issue#23: 边缘槽位卡的网格位置 = 槽位编号本身, 禁止按时间重映射
        // (← Android CourseEntity.kt:165 首闸; 草稿 ownTime=true 带起止时同样适用)
        guard !isIrregularNode else { return self }
        guard ownTime, Self.isNotBlank(startTime), Self.isNotBlank(endTime) else { return self }
        guard let mapped = TimeTableUtils.timeToNode(startTime, endTime, timeJson) else { return self }
        return CourseEntityLite(courseName: courseName, day: day, startNode: mapped.0, step: mapped.1,
                                startWeek: startWeek, endWeek: endWeek, type: type,
                                ownTime: ownTime, startTime: startTime, endTime: endTime,
                                isIrregularTime: isIrregularTime, isIrregularNode: isIrregularNode)
    }

    /// Kotlin `isNotBlank()` 等价(纯空白串视为空), 与 CourseEntity.swift:111 同实现
    private static func isNotBlank(_ s: String) -> Bool {
        return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
