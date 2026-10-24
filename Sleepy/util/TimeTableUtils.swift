// TimeTableUtils.swift — ← util/TimeTableUtils.kt (逐行翻译, GPL-3.0)

import Foundation

/// 时间表 (timeJson) 解析与查询工具。
///
/// TimeTableEntity.timeJson 格式:
///   [{"node":1,"start":"08:00","end":"08:45"}, {"node":2,...}, ...]
///
/// UI 渲染时用 timeSlotsFor 把 JSON 转为每节独立的 TimeSlot；
/// 与 WakeUp 默认 12 节制对应，若用户改 nodesPerDay，会按节点列表拆段。
enum TimeTableUtils {

    /// 默认节次时间表（12 节 / 45-50 分钟）。
    ///
    /// 这是 timeJson 的**唯一权威默认值**；
    /// TimeTableEntity 默认构造、TimeTableUtils 解析、UI 渲染都从这里走。
    static let DEFAULT_TIME_JSON = """
        [
            {"node":1,"start":"08:00","end":"08:45"},
            {"node":2,"start":"08:55","end":"09:40"},
            {"node":3,"start":"10:00","end":"10:45"},
            {"node":4,"start":"10:55","end":"11:40"},
            {"node":5,"start":"14:00","end":"14:45"},
            {"node":6,"start":"14:55","end":"15:40"},
            {"node":7,"start":"16:00","end":"16:45"},
            {"node":8,"start":"16:55","end":"17:40"},
            {"node":9,"start":"19:00","end":"19:45"},
            {"node":10,"start":"19:55","end":"20:40"},
            {"node":11,"start":"20:50","end":"21:35"},
            {"node":12,"start":"21:45","end":"22:30"}
        ]
        """

    struct NodeTime: Equatable {
        let node: Int
        let start: Date   // 当日时刻,仅时分秒有意义
        let end: Date
    }

    /// 解析 timeJson -> 按 node 排序的 list。
    /// 兼容无 "node" 键的旧格式([{start,end},...]) — 节点号按数组序号补(1 起)。
    /// issue#40 预览读旧格式 timeJson(如迁移生成的 period_tables 行)时不再整体解析失败。
    /// ← Android parseNodes `o.optInt("node", i + 1)` + 整体 try/catch:
    /// 任一行缺 start/end 或时间非法 → 整体返回空数组(不是丢弃单行)。
    static func parseNodes(_ timeJson: String) -> [NodeTime] {
        guard let data = timeJson.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        var out: [NodeTime] = []
        out.reserveCapacity(arr.count)
        for (i, o) in arr.enumerated() {
            let node = (o["node"] as? NSNumber)?.intValue ?? (i + 1)
            guard let startS = o["start"] as? String,
                  let endS = o["end"] as? String,
                  let start = parseTime(startS, base: today),
                  let end = parseTime(endS, base: today) else { return [] }
            out.append(NodeTime(node: node, start: start, end: end))
        }
        return out.sorted { $0.node < $1.node }
    }

    private static func parseTime(_ s: String, base: Date) -> Date? {
        // ← Android LocalTime.parse 严格语义(见 hmToSeconds): "9:30"/"24:00"/"25:00"
        // 旧实现(Int 无范围检查)会容忍甚至跨日滚动, 与 Android 分叉 → 现统一走严格解析。
        guard let secs = hmToSeconds(s) else { return nil }
        return base.addingTimeInterval(TimeInterval(secs))
    }

    static func formatTime(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// 把节点时间表转为每节独立的 TimeSlotRow 展示行(D5 TimeSlot 的数据来源)
    static func timeSlotsFor(timeJson: String) -> [TimeSlotRow] {
        parseNodes(timeJson).map { n in
            TimeSlotRow(node: n.node, start: formatTime(n.start), end: formatTime(n.end))
        }
    }

    /// 课程的开始节-结束节对应的"开始时间-结束时间"。
    /// 直接用节点的 start/end 拼接，不依赖外层 TimeSlot。
    /// 找不到节点则返回 nil。
    static func courseTimeString(courseStartNode: Int, courseStep: Int, timeJson: String,
                                 ownTime: Bool = false, startTime: String = "", endTime: String = "") -> String? {
        let parts = courseTimeParts(courseStartNode: courseStartNode, courseStep: courseStep,
                                    timeJson: timeJson, ownTime: ownTime,
                                    startTime: startTime, endTime: endTime)
        return parts.map { "\($0.0)-\($0.1)" }
    }

    /// 课程的 (开始时间, 结束时间)，用于需要分行渲染的场景。
    /// 逻辑同 courseTimeString，但返回拆分后的两部分，避免外层再 split。
    static func courseTimeParts(courseStartNode: Int, courseStep: Int, timeJson: String,
                                ownTime: Bool = false, startTime: String = "", endTime: String = "") -> (String, String)? {
        // ← Android startTime.isNotBlank() && endTime.isNotBlank(): 纯空白 ownTime
        // 不算自带时间, 必须落到节点查询(旧 !isEmpty 会把 " " 原样返回)。
        if ownTime && !startTime.isBlank && !endTime.isBlank {
            return (startTime, endTime)
        }
        let nodes = parseNodes(timeJson)
        if nodes.isEmpty { return nil }
        let endNode = courseStartNode + courseStep - 1
        guard let first = nodes.first(where: { $0.node == courseStartNode }),
              let last = nodes.first(where: { $0.node == endNode }) else { return nil }
        return (formatTime(first.start), formatTime(last.end))
    }

    /// 根据课程的 startTime/endTime 反算等效的 (startNode, step)。
    /// 用于把 ownTime=true 的课映射到节次网格上。
    ///
    /// 规则：
    /// - startNode = 时间表中 start ≤ courseStart 的最大节点（向下取）
    /// - endNode   = 从 startNode 起沿节点序连续延伸的最后一节 — 课程在节次空隙内
    ///   结束时停在空隙前的那一节, 绝不跨过空隙吸附到下一节 (用户 2026-09-09:
    ///   12:30 结束跨午间空隙被吸进 14:00 节 = 报障本体; 旧行为 "end ≥ courseEnd
    ///   的最小节点" 会跨空隙撑大 step, 已否决)
    /// - step      = endNode - startNode + 1
    /// - 若 StartTime 早于第一节，用第1节；endTime 晚于最后一节，用最后一节
    /// 返回 nil 表示无法映射（时间格式错误或时间表为空）。
    static func timeToNode(_ startTime: String, _ endTime: String, _ timeJson: String) -> (Int, Int)? {
        let nodes = parseNodes(timeJson)
        if nodes.isEmpty { return nil }
        let refDay = Calendar.current.startOfDay(for: nodes[0].start)
        guard let st = parseTime(startTime, base: refDay),
              let et = parseTime(endTime, base: refDay) else { return nil }

        let startIdx = nodes.lastIndex { $0.start <= st } ?? -1
        let sIdx = max(startIdx, 0)
        var endIdx = sIdx
        var i = sIdx + 1
        while i < nodes.count && nodes[i].start < et {
            endIdx = i
            i += 1
        }

        let startNode = nodes[sIdx].node
        let endNode = nodes[endIdx].node
        if endNode < startNode { return nil }
        return (startNode, endNode - startNode + 1)
    }

    // ------------------------------------------------------------------
    // issue#23 §5 渲染: 非常规时间胶囊按真实分钟在网格内按比例定位
    // ------------------------------------------------------------------

    /// "HH:mm"/"HH:mm:ss" → 自午夜起秒数; 非法 → nil
    /// ← Android LocalTime.parse 严格语义: 小时/分钟必须两位且 00-23 / 00-59,
    /// 可选两位秒 00-59。"9:30"(单位小时)、"24:00"、"25:00"、"10:20:99" 一律拒绝
    /// (旧实现 Int 宽容解析, 与 Android 双向分叉: "25:00" 曾跨日滚动改变比较结果)。
    static func hmToSeconds(_ s: String) -> Int? {
        localTimeParse(s)
    }

    /// LocalTime.parse 等价严格解析(数字位数+范围双闸)。
    private static func localTimeParse(_ s: String) -> Int? {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        var sec = 0
        if parts.count == 3 {
            guard parts[2].count == 2, let ss = Int(parts[2]), (0...59).contains(ss) else { return nil }
            sec = ss
        }
        return h * 3600 + m * 60 + sec
    }

    /// 便捷: 拿 TimeTableEntity 直接出 rows
    static func timeSlotsFor(table: TimeTableEntity?) -> [TimeSlotRow] {
        table.map { timeSlotsFor(timeJson: $0.timeJson) } ?? []
    }

    // ------------------------------------------------------------------
    // 编辑用的 row 数据模型 + JSON 互转
    // 共享给 EditTableScreen + ImportSheet
    // ------------------------------------------------------------------

    /// 节次编辑用的行模型：node=节次编号, start/end="HH:mm"。
    /// 节点编号在删除时会重新 1..N 连续编号。
    struct TimeSlotRow: Codable, Equatable {
        var node: Int
        var start: String
        var end: String
        /// Non-null only for nodes created by the manual-course edge controls.
        var edgeClass: EdgeClass? = nil
    }

    /**
     * issue#23: 从手动编辑的标准行推断自动模式配置(← Android inferSmartPeriodConfig:336)。
     * Edge 行被刻意忽略; 调用方在手动模式保留它们。previous 提供时按分钟数承接既有
     * 分组标签/长短分类(用户改行不丢已调好的「大课间/午休」等标签)。
     *
     * 失败返回 nil 的情形: 标准行为空 / 首节≠1 / 断号 / 时间畸形(严格 LocalTime 语义)/
     * end≤start / 相邻行重叠。
     */
    static func inferSmartPeriodConfig(_ rows: [TimeSlotRow],
                                       previous: SmartPeriodConfig? = nil) -> SmartPeriodConfig? {
        struct ParsedRow { let start: Int; let end: Int; let duration: Int }  // 自午夜分钟数
        let standard = rows.filter { $0.edgeClass == nil }.sorted { $0.node < $1.node }
        if standard.isEmpty || standard.first!.node != 1 ||
            (standard.map { $0.node } != Array(1...standard.count)) { return nil }

        var parsed: [ParsedRow] = []
        parsed.reserveCapacity(standard.count)
        for row in standard {
            guard let s = hmToSeconds(row.start.trimmingCharacters(in: .whitespaces)),
                  let e = hmToSeconds(row.end.trimmingCharacters(in: .whitespaces)) else { return nil }
            if e <= s { return nil }
            parsed.append(ParsedRow(start: s, end: e, duration: (e - s) / 60))
        }
        for i in 1..<parsed.count {
            if parsed[i].start < parsed[i - 1].end { return nil }
        }

        // 众数(并列取首次出现) — ← Android mode(): groupingBy + sortedBy count desc, firstIndex
        func mode<T: Hashable>(_ values: [T]) -> T {
            var counts: [T: Int] = [:]
            for v in values { counts[v, default: 0] += 1 }
            return counts.sorted { a, b in
                a.value != b.value ? a.value > b.value
                    : values.firstIndex(of: a.key)! < values.firstIndex(of: b.key)!
            }.first!.key
        }

        let primaryMinutes = mode(parsed.map { $0.duration })
        // distinct() 保首次出现序, 去掉主时长
        var seenDurations = Set<Int>()
        let durationMinutes = parsed.map { $0.duration }
            .filter { seenDurations.insert($0).inserted }
            .filter { $0 != primaryMinutes }
        let previousDurationByMinutes = Dictionary(
            (previous?.durations ?? []).map { ($0.minutes, $0) }, uniquingKeysWith: { a, _ in a })
        let durations = durationMinutes.map { minutes -> DurationOption in
            if let prev = previousDurationByMinutes[minutes] { return prev }
            return DurationOption(minutes: minutes, isLong: minutes > primaryMinutes)
        }
        var durationIndex: [Int: Int] = [:]
        for (i, d) in durations.enumerated() { durationIndex[d.minutes] = i }
        let periodAssignments: [Int?] = parsed.map { durationIndex[$0.duration] }  // 主时长 → nil

        let transitionMinutes = (1..<parsed.count).map { i in
            (parsed[i].start - parsed[i - 1].end) / 60
        }
        var seenBreaks = Set<Int>()
        let breakMinutes = transitionMinutes
            .filter { $0 > 0 }
            .filter { seenBreaks.insert($0).inserted }
        let previousBreakByMinutes = Dictionary(
            (previous?.breaks ?? []).map { ($0.minutes, $0) }, uniquingKeysWith: { a, _ in a })
        let minBreak = breakMinutes.min()
        let breaks = breakMinutes.map { minutes -> BreakOption in
            if let prev = previousBreakByMinutes[minutes] { return prev }
            // ← Android: minutes > (breakMinutes.minOrNull() ?: minutes)
            return BreakOption(minutes: minutes, isLong: minBreak.map { minutes > $0 } ?? false)
        }
        var breakIndex: [Int: Int] = [:]
        for (i, b) in breaks.enumerated() { breakIndex[b.minutes] = i }
        let transitionAssignments: [Int?] = transitionMinutes.map { breakIndex[$0] }  // 0 分钟连续 → nil

        // startTime = 首节开始 "HH:mm"(LocalTime.toString().substring(0,5) 语义)
        let st = parsed.first!.start
        let startTime = String(format: "%02d:%02d", st / 60 / 60 % 24, st / 60 % 60)
        return SmartPeriodConfig(
            startTime: startTime,
            periodMinutes: primaryMinutes,
            totalPeriods: parsed.count,
            breaks: breaks,
            transitionAssignments: transitionAssignments,
            durations: durations,
            periodAssignments: periodAssignments)
    }

    /// timeJson -> 编辑 rows (按数组顺序)
    static func parseTimeSlotRows(_ timeJson: String) -> [TimeSlotRow] {
        guard let data = timeJson.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return (1...12).map { node in TimeSlotRow(node: node, start: smartStartDefault(node), end: smartEndDefault(node)) }
        }
        return arr.enumerated().map { i, o in
            TimeSlotRow(
                node: (o["node"] as? NSNumber)?.intValue ?? (i + 1),
                start: (o["start"] as? String) ?? smartStartDefault(i + 1),
                end: (o["end"] as? String) ?? smartEndDefault(i + 1),
                edgeClass: (o["edge"] as? String).flatMap(TimeTableUtils.parseEdgeClass)
            )
        }
    }

    /// rows -> timeJson (edge 元数据只在边缘节点时写出 "edge" 键)
    /// 手写序列化 — 键序固定 node,start,end,edge(= Android JSONObject.put 插入序),
    /// 输出与 org.json JSONArray.toString 逐字节一致(紧凑、无空格、字符串转义同规则),
    /// 保证跨平台 timeJson 可直接做字节级对比。
    /// (旧 JSONSerialization [String: Any] 键序不保证, 实测输出 start,end,node — 分叉)
    static func buildTimeJsonFromRows(_ rows: [TimeSlotRow]) -> String {
        var out = "["
        for (idx, row) in rows.enumerated() {
            if idx > 0 { out.append(",") }
            out.append("{")
            out.append("\"node\":\(row.node),")
            out.append("\"start\":\(jsonString(row.start)),")
            out.append("\"end\":\(jsonString(row.end))")
            if let e = row.edgeClass {
                out.append(",\"edge\":\(jsonString(e.rawValue))")
            }
            out.append("}")
        }
        out.append("]")
        return out
    }

    /// org.json JSONObject.quote 等价转义: " \\ \n \r \t 与 <0x20 控制符 \u 形式。
    private static func jsonString(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{0C}": out += "\\f"
            case "\u{08}": out += "\\b"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        out += "\""
        return out
    }

    /// 删除某 node 后**重新编号**为 1..N (用户友好)，返回新 list。
    static func removeAndRenumber(_ rows: [TimeSlotRow], node: Int) -> [TimeSlotRow] {
        rows.filter { $0.node != node }.enumerated().map { idx, r in
            var copy = r; copy.node = idx + 1; return copy
        }
    }

    /// 追加一节 (node = max + 1)，时间留空让用户填。
    static func appendEmptyRow(_ rows: [TimeSlotRow]) -> [TimeSlotRow] {
        let nextNode = (rows.map { $0.node }.max() ?? 0) + 1
        return rows + [TimeSlotRow(node: nextNode, start: "", end: "")]
    }

    /**
     * 追加导入扩展 timeJson — 把 incomingJson 中 node > currentMaxNode 的节次复制进来,
     * 时间从 incoming 拿, node 重新连续编号避免冲突。
     * 用于"追加课程时, 课表自动延伸到新最大节次"场景。(← Android extendTimeJsonWith:450;
     * Android 侧现无调用方, 此移植为 API 面平价)
     */
    static func extendTimeJsonWith(currentJson: String, incomingJson: String) -> String {
        let currentRows = parseTimeSlotRows(currentJson)
        let incomingRows = parseTimeSlotRows(incomingJson)
        let currentMaxNode = currentRows.map { $0.node }.max() ?? 0
        let newRows = incomingRows.filter { $0.node > currentMaxNode }
        if newRows.isEmpty { return currentJson }
        // node 重新连续编号(避免原 incoming 跳号, 保持 1..N 连续)
        let merged = currentRows + newRows.enumerated().map { idx, r in
            var copy = r; copy.node = currentMaxNode + idx + 1; return copy
        }
        return buildTimeJsonFromRows(merged)
    }

    // ------------------------------------------------------------------
    // 课表外节次 (issue #23 / 手动课程"非常规"开关)
    // 标准节次 = 1..maxContiguousFromOne 的连续节点; 前置边缘 < 1, 后置边缘 > maxContiguous。
    // 这些节点是 timeJson 的真实结构: 删除边缘节点的最后一门课时必须回收该节点。
    // ------------------------------------------------------------------

    /// 边缘节次的方向: 前置 (< 1) / 后置 (> maxContiguous)
    enum EdgeClass: String, Codable, Equatable {
        case before = "before"
        case after = "after"
    }

    /// timeJson 中 1..N 的最大连续 N — 标准节次的上界。
    /// 标准节点的 edgeClass 必须为 null; 默认 12 节制返回 12, 全删/异常返回 0。
    private static func maxContiguousFromOne(_ rows: [TimeSlotRow]) -> Int {
        let std = rows.filter { $0.edgeClass == nil }.map { $0.node }
        let present = Set(std)
        guard present.contains(1) else { return 0 }
        var n = 1
        while present.contains(n + 1) { n += 1 }
        return n
    }

    /// "before"/"after" (大小写不敏感) -> EdgeClass, 其他 -> nil
    private static func parseEdgeClass(_ s: String) -> EdgeClass? {
        EdgeClass(rawValue: s.lowercased())
    }

    /// 在 timeJson 新增边缘节次节点:
    ///   - Before: 无前置时 = 0, 否则 = (现有前置最小值) - 1
    ///   - After:  无后置时 = maxContiguous + 1, 否则 = (现有后置最大值) + 1
    static func insertEdgeNode(timeJson: String, edgeClass: EdgeClass, start: String, end: String) -> String {
        let rows = parseTimeSlotRows(timeJson)
        let newNode: Int
        switch edgeClass {
        case .before:
            let eb = rows.filter { $0.edgeClass == .before }
            newNode = eb.isEmpty ? 0 : (eb.map { $0.node }.min() ?? 0) - 1
        case .after:
            let maxStd = maxContiguousFromOne(rows)
            let ea = rows.filter { $0.edgeClass == .after }
            newNode = ea.isEmpty ? maxStd + 1 : (ea.map { $0.node }.max() ?? 0) + 1
        }
        return buildTimeJsonFromRows(rows + [TimeSlotRow(node: newNode, start: start, end: end, edgeClass: edgeClass)])
    }

    /// 删除边缘节次节点 — 仅当 (a) 确实是边缘节点 (b) 无课程引用时才回收; 否则原样返回
    static func removeEdgeNodeIfUnused(timeJson: String, edgeNode: Int, usedNodes: Set<Int>) -> String {
        let rows = parseTimeSlotRows(timeJson)
        guard let target = rows.first(where: { $0.node == edgeNode }) else { return timeJson }
        if target.edgeClass == nil { return timeJson }
        if usedNodes.contains(edgeNode) { return timeJson }
        return buildTimeJsonFromRows(rows.filter { $0.node != edgeNode })
    }

    /// 列出某方向的边缘节点号: Before 降序 (0,-1,...), After 升序 (13,14,...)
    static func edgeNodesOf(timeJson: String, edgeClass: EdgeClass) -> [Int] {
        let nodes = parseTimeSlotRows(timeJson)
            .filter { $0.edgeClass == edgeClass }
            .map { $0.node }
        if edgeClass == .before {
            return nodes.sorted(by: >)
        }
        return nodes.sorted()
    }

    /**
     * 扫描全部边缘节次节点, 逐个回收未被引用的 — 从 before + after 两个方向。
     * 被引用的判定: 某门课的 startNode..startNode+step-1 区间包含该节点号。
     * 标准节点(1..N) 绝不回收(removeEdgeNodeIfUnused 内部有 edgeClass!=nil 硬闸)。
     * 删课/删组/编辑 diff 后必须把结果回写课表 timeJson, 否则节点残留
     * (用户 2026-09-06: "课程表恢复到之前的状态"; ← Android reclaimUnusedEdgeNodes:624)。
     */
    static func reclaimUnusedEdgeNodes(timeJson: String, usedNodes: Set<Int>) -> String {
        var json = timeJson
        for n in edgeNodesOf(timeJson: json, edgeClass: .before) {
            json = removeEdgeNodeIfUnused(timeJson: json, edgeNode: n, usedNodes: usedNodes)
        }
        for n in edgeNodesOf(timeJson: json, edgeClass: .after) {
            json = removeEdgeNodeIfUnused(timeJson: json, edgeNode: n, usedNodes: usedNodes)
        }
        return json
    }

    /**
     * issue#28 P3: 作息表变更后的课程节次自适应(← Android remapCourseNodes:501)。
     *
     * 节次编号只是旧表绝对时间窗的载体: 取课程首节在旧表的 start 与末节在旧表的
     * end, 在新表上找与之重叠的节点区间 — 首节 = 第一个 end 晚于课程起点的节,
     * 末节 = 最后一个 start 早于课程终点的节。旧表缺行(课程锚的节次不存在)或
     * 新表无任何重叠 → 返回原值(孤儿课保持原节次, 不猜不丢)。
     * (ScheduleRepository.swift 现有一份同款私有静态实现; 集成者可删除该副本改调此处。)
     */
    static func remapCourseNodes(startNode: Int, step: Int,
                                 oldTimeJson: String, newTimeJson: String) -> (Int, Int) {
        if startNode < 1 || step < 1 { return (startNode, step) }
        let oldRows = parseTimeSlotRows(oldTimeJson).sorted { $0.node < $1.node }
        let newRows = parseTimeSlotRows(newTimeJson).sorted { $0.node < $1.node }
        let oldStart = oldRows.first(where: { $0.node == startNode })?.start ?? ""
        let oldEnd = oldRows.first(where: { $0.node == startNode + step - 1 })?.end ?? ""
        // ← Android isBlank(): 纯空白 = 缺行
        if oldStart.isBlank || oldEnd.isBlank { return (startNode, step) }
        guard let firstIdx = newRows.firstIndex(where: { $0.end > oldStart }) else { return (startNode, step) }
        guard let lastIdx = newRows.lastIndex(where: { $0.start < oldEnd }) else { return (startNode, step) }
        if lastIdx < firstIdx { return (startNode, step) }
        let firstNode = newRows[firstIdx].node
        let lastNode = newRows[lastIdx].node
        return (firstNode, max(lastNode - firstNode + 1, 1))
    }

    /**
     * 确认导入时真正生效的节次行(v1.0.56 T6 绑表真源; ← Android effectiveRowsForConfirm:543)。
     *
     * 用户在确认对话框选了「作息表」Tab → bindId 即绑定的作息表 id:
     *  - bindId > 0 (绑了既有表) → 该表的 timeJson 解析出的 rows 是真源, 手动 rows 仅供参考;
     *  - bindId == -1 (本次导入自动建表, 合成项) → 用手动 rows, 落库即建;
     *  - bindId == nil (未绑 / 用本表内置) → 用手动 rows。
     *
     * 历史上只把 bindId 记下, 校验/落库却无条件走手动 rows, 教务协议没回节次时间时
     * 手动 rows 全是空 → 误报「第 X 节时间不能为空」(用户反馈 2026-09-20)。
     * 此函数是确认流的唯一真源, 校验和落库 timeJson 都从这里拿。
     * (ImportSheet.swift 现有一份同款静态实现; 集成者可删除该副本改调此处。)
     */
    static func effectiveRowsForConfirm(manualRows: [TimeSlotRow], bindId: Int64?,
                                        tables: [(Int64, String)]) -> [TimeSlotRow] {
        guard let id = bindId else { return manualRows }
        if id <= 0 { return manualRows }
        guard let json = tables.first(where: { $0.0 == id })?.1 else { return manualRows }
        return parseTimeSlotRows(json)
    }

    // MARK: - issue#23 逐卡非常规 (← effectiveCourseTime / maxStandardNode / EdgeCandidate / edgeCandidates / updateEdgeNodeTimes)

    /**
     * issue#23 §3.3 逐卡 effective 时间解析 — validateCourseDraft / buildCourseEntity /
     * blockRangeMinutes 共用契约, 四处解析必须一致:
     *   1. isIrregularTime=true → 课程自带覆盖起止直接生效 (不受槽位默认时间窗口约束, §2.3)
     *   2. startNode 为边缘槽位 (edgeClass != null) → 槽位默认时间
     *   3. 否则 → 标准 1..N 节次时间 (startNode..startNode+step-1)
     * 无法解析 (时间无效 / 节次不存在) → nil, 由调用方校验报错, 不静默给值。
     */
    static func effectiveCourseTime(isIrregularTime: Bool, startTime: String, endTime: String,
                                    startNode: Int, step: Int, timeJson: String) -> (String, String)? {
        if isIrregularTime {
            guard let s = normalizedHm(startTime), let e = normalizedHm(endTime) else { return nil }
            return (s, e)
        }
        let rows = parseTimeSlotRows(timeJson)
        guard let first = rows.first(where: { $0.node == startNode }),
              let last = rows.first(where: { $0.node == startNode + step - 1 }) else { return nil }
        return (first.start, last.end)
    }

    /// "HH:mm" → 当日分钟数 (widget 窗口/冲突聚簇共用的时间域刻度); 非法 → nil
    static func hmMinutes(_ v: String) -> Int? {
        let parts = v.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return h * 60 + m
    }

    /// "H:mm" 以外一律按 LocalTime.parse 严格语义 → "HH:mm"(秒非零时保留 ":ss",
    /// LocalTime.toString 语义); 非法 → nil。
    /// 旧实现只收两段 parts.count == 2 → 拒绝 "08:00:30" 这类 Android 接受的输入。
    private static func normalizedHm(_ v: String) -> String? {
        let t = v.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        var sec = 0
        if parts.count == 3 {
            guard parts[2].count == 2, let ss = Int(parts[2]), (0...59).contains(ss) else { return nil }
            sec = ss
        }
        // LocalTime.toString: 秒=0 省略, 否则保留
        return sec == 0
            ? String(format: "%02d:%02d", h, m)
            : String(format: "%02d:%02d:%02d", h, m, sec)
    }

    /// 标准 1..N 连续节次上界 (edge 行不参与) — 逐卡重构后标准卡片只允许 1..maxStd
    static func maxStandardNode(_ timeJson: String) -> Int {
        maxContiguousFromOne(parseTimeSlotRows(timeJson))
    }

    /// 候选节次: exists=true = 复用已有槽位(带默认时间); exists=false = 新建(时间待用户填)
    struct EdgeCandidate: Hashable {
        let node: Int
        let start: String
        let end: String
        let exists: Bool
        /// 候选归属: Before 组节点 <= 0, After 组节点 > 0 (edgeCandidates 构造保证)
        var edgeClass: EdgeClass { node <= 0 ? .before : .after }
    }

    /**
     * 候选节次集合 (§2.2): Before 组升序(-2,-1,0...) + After 组升序(N+1,N+2...)。
     * 每组 = 该方向全部已有边缘槽位 + 紧贴边界的一个「新建」候选;
     * 无任何槽位时新建候选 = 0 / maxContiguous+1。禁止跳号。
     */
    static func edgeCandidates(_ timeJson: String) -> [EdgeCandidate] {
        let rows = parseTimeSlotRows(timeJson)
        let beforeSlots = rows.filter { $0.edgeClass == .before }.sorted { $0.node < $1.node }
        let afterSlots = rows.filter { $0.edgeClass == .after }.sorted { $0.node < $1.node }
        let maxStd = maxContiguousFromOne(rows)
        let newBefore = (beforeSlots.map { $0.node }.min() ?? 1) - 1
        let newAfter = (afterSlots.map { $0.node }.max() ?? maxStd) + 1
        let beforeGroup = [EdgeCandidate(node: newBefore, start: "", end: "", exists: false)] +
            beforeSlots.map { EdgeCandidate(node: $0.node, start: $0.start, end: $0.end, exists: true) }
        let afterGroup = afterSlots.map { EdgeCandidate(node: $0.node, start: $0.start, end: $0.end, exists: true) } +
            [EdgeCandidate(node: newAfter, start: "", end: "", exists: false)]
        return beforeGroup + afterGroup
    }

    /**
     * 修改某边缘槽位的默认时间 — 仅 edgeClass != nil 的行可改;
     * 节点不存在或为标准行时原样返回入参 (调用方无需预检)。
     */
    static func updateEdgeNodeTimes(timeJson: String, node: Int, start: String, end: String) -> String {
        let rows = parseTimeSlotRows(timeJson)
        guard let target = rows.first(where: { $0.node == node }) else { return timeJson }
        if target.edgeClass == nil { return timeJson }
        return buildTimeJsonFromRows(
            rows.map { $0.node == node ? TimeSlotRow(node: $0.node, start: start, end: end, edgeClass: $0.edgeClass) : $0 })
    }

    /// v7.10.16k 无损合并 — "哪个大用哪个"(用户 2026-09-03):
    /// 双方作息逐节合并, 结果 = max(两边节次数, requiredNodeCount), 任何一方不得把另一方压小。
    /// 同一节次: 导入源非空时间优先(空串视为没声明), 否则原表, 都没有用 smart 默认。
    /// 超出双方声明的节次(requiredNodeCount=导入课程实际到达的最大节)用 smart 默认铺底。
    static func mergeMostComplete(currentJson: String, incomingJson: String, requiredNodeCount: Int = 0) -> String {
        // 空串 = 没声明 — 不能进 parseTimeSlotRows(它会 catch 出 12 行 smart 伪声明,
        // 反过来把有真实作息的一方当"缺省"盖掉)。
        // ← Android takeIf { it.isNotBlank() }: 纯空白串同样 = 没声明(旧 !isEmpty
        // 让 " " 进 parseTimeSlotRows → JSON 解析失败 catch 出 12 行伪声明覆盖真实表)。
        var currentRows: [TimeSlotRow] = []
        if !currentJson.isBlank { currentRows = parseTimeSlotRows(currentJson) }
        var incomingRows: [TimeSlotRow] = []
        if !incomingJson.isBlank { incomingRows = parseTimeSlotRows(incomingJson) }
        let cur = Dictionary(currentRows.map { ($0.node, $0) }, uniquingKeysWith: { a, _ in a })
        let inc = Dictionary(incomingRows.map { ($0.node, $0) }, uniquingKeysWith: { a, _ in a })
        let declared = max(currentRows.map { $0.node }.max() ?? 0,
                           incomingRows.map { $0.node }.max() ?? 0)
        if declared == 0 && requiredNodeCount <= 0 { return DEFAULT_TIME_JSON }
        let count = max(declared, requiredNodeCount, 1)
        let rows = (1...count).map { node -> TimeSlotRow in
            let i = inc[node]
            let c = cur[node]
            // ← Android takeIf { it.isNotBlank() }: 纯空白时间 = 没声明
            return TimeSlotRow(
                node: node,
                start: i.flatMap { $0.start.isBlank ? nil : $0.start }
                    ?? c.flatMap { $0.start.isBlank ? nil : $0.start }
                    ?? smartStartDefault(node),
                end: i.flatMap { $0.end.isBlank ? nil : $0.end }
                    ?? c.flatMap { $0.end.isBlank ? nil : $0.end }
                    ?? smartEndDefault(node))
        }
        return buildTimeJsonFromRows(rows)
    }

    private static func smartStartDefault(_ node: Int) -> String {
        switch node {
        case ...2: return "08:00"
        case ...4: return "10:00"
        case ...6: return "14:00"
        case ...8: return "16:00"
        case ...10: return "19:00"
        default: return "20:50"
        }
    }

    private static func smartEndDefault(_ node: Int) -> String {
        switch node {
        case ...2: return "09:40"
        case ...4: return "11:40"
        case ...6: return "15:40"
        case ...8: return "17:40"
        case ...10: return "20:40"
        default: return "22:30"
        }
    }
}

// MARK: - 作息表改动预览 (← previewPeriodTableChange / CourseTimeChange / PeriodTablePreview, v1.0.60)

extension TimeTableUtils {

    /// 逐课时间变化(← data class CourseTimeChange)
    struct CourseTimeChange: Equatable {
        let courseId: Int64
        let courseName: String
        let startNode: Int
        let step: Int
        /// 旧表解释的 "HH:mm-HH:mm"; 旧表缺该节次行 = nil(无法解释)
        let oldTime: String?
        /// 新表解释的 "HH:mm-HH:mm"; 新表缺该节次行 = nil
        let newTime: String?
        /// 2026-09-16: 逐节对比 — 真正变化了的节次列表(空 = 首尾对变了但节次没变, 理论不出现)
        var changedNodes: [Int] = []
    }

    /// 预览结果(← data class PeriodTablePreview)
    struct PeriodTablePreview: Equatable {
        let changedCourses: [CourseTimeChange]
        let unchangedCount: Int
    }

    /**
     * 对一批课程, 用 oldTimeJson/newTimeJson 各自解释节次编号(§5.2:
     * "按新旧两份 timeJson 对同一批节次编号解析"), 产出逐课时间变化。
     *
     * 2026-09-16 逐节对比修复: 不只比 (首节.start, 末节.end) 一对 — 逐节次
     * (start,end) 对比, 任一节变了即变(连堂课改单节时长不再漏报)。
     *
     * 纯函数 — 不触库不写库; 取消保存时丢弃结果即可, 数据库零改动。
     */
    static func previewPeriodTableChange(
        oldTimeJson: String,
        newTimeJson: String,
        courses: [CourseEntity]
    ) -> PeriodTablePreview {
        var changed: [CourseTimeChange] = []
        var unchanged = 0
        let oldNodes = parseNodes(oldTimeJson)
        let newNodes = parseNodes(newTimeJson)

        func nodeTime(_ nodes: [NodeTime], _ n: Int) -> (String, String)? {
            nodes.first { $0.node == n }.map { (formatTime($0.start), formatTime($0.end)) }
        }

        for c in courses {
            if c.ownTime || c.isIrregularTime { continue }  // 自定义时间: 起止照旧, 不参与解释
            let endNode = c.startNode + c.step - 1
            var changedNodes: [Int] = []
            for n in c.startNode...max(endNode, c.startNode) {
                let o = nodeTime(oldNodes, n)
                let w = nodeTime(newNodes, n)
                // 元组无 Equatable — 逐分量对比(← Kotlin Pair ==)
                let differs: Bool
                switch (o, w) {
                case (nil, nil): differs = false
                case let (os?, ws?): differs = os.0 != ws.0 || os.1 != ws.1
                default: differs = true
                }
                if differs { changedNodes.append(n) }
            }
            let oldParts = courseTimeParts(courseStartNode: c.startNode, courseStep: c.step, timeJson: oldTimeJson)
            let newParts = courseTimeParts(courseStartNode: c.startNode, courseStep: c.step, timeJson: newTimeJson)
            if changedNodes.isEmpty {
                unchanged += 1
            } else {
                changed.append(CourseTimeChange(
                    courseId: c.id,
                    courseName: c.courseName,
                    startNode: c.startNode,
                    step: c.step,
                    oldTime: oldParts.map { "\($0.0)-\($0.1)" },
                    newTime: newParts.map { "\($0.0)-\($0.1)" },
                    changedNodes: changedNodes))
            }
        }
        return PeriodTablePreview(changedCourses: changed, unchangedCount: unchanged)
    }
}

// MARK: - 全局唯一名 (← isTableNameTaken / suggestUniqueName, v1.0.60)

extension TimeTableUtils {

    /**
     * 全局唯一名判定: 课表名 ∪ 作息表名。
     * excludeId 场景(重命名自己)传名单+byId 映射剔除"自己那一份"后判撞;
     * 其余场景(新建/复制/导入确认)传名单即可。
     * 纯函数 — DAO 全名列表由调用方查好传入, 本函数零库访问。
     */
    static func isTableNameTaken(
        _ name: String,
        courseTableNames: [String],
        periodTableNames: [String],
        excludeCourseTableId: Int64? = nil,
        courseTableNamesById: [Int64: String] = [:],
        excludePeriodTableId: Int64? = nil,
        periodTableNamesById: [Int64: String] = [:]
    ) -> Bool {
        if name.isBlank { return false }
        let courseHit: Bool
        if let excludeId = excludeCourseTableId {
            // 名单本身无 id, 用 byId 映射剔除"自己那一份"后判撞: 总出现次数 > 自己出现次数
            let selfCount = courseTableNamesById[excludeId] == name ? 1 : 0
            courseHit = courseTableNames.filter { $0 == name }.count > selfCount
        } else {
            courseHit = courseTableNames.contains(name)
        }
        let periodHit: Bool
        if let excludeId = excludePeriodTableId {
            let selfCount = periodTableNamesById[excludeId] == name ? 1 : 0
            periodHit = periodTableNames.filter { $0 == name }.count > selfCount
        } else {
            periodHit = periodTableNames.contains(name)
        }
        return courseHit || periodHit
    }

    /**
     * 撞名自动顺延: 原名 → 原名2 → 原名3…(导入自动建表/复制预填用)。
     * 兼容历史 "名字(2)" 形态, 顺延跳过 plain 与 paren 两种占用。
     * 空名回退 defaultName 参与顺延。
     */
    static func suggestUniqueName(
        _ base: String,
        courseTableNames: [String],
        periodTableNames: [String],
        defaultName: String = ""
    ) -> String {
        let effective = base.isBlank ? defaultName : base
        if !isTableNameTaken(effective, courseTableNames: courseTableNames, periodTableNames: periodTableNames) {
            return effective
        }
        var index = 2
        while isTableNameTaken("\(effective)\(index)", courseTableNames: courseTableNames, periodTableNames: periodTableNames)
            || isTableNameTaken("\(effective)(\(index))", courseTableNames: courseTableNames, periodTableNames: periodTableNames) {
            index += 1
        }
        return "\(effective)\(index)"
    }
}
