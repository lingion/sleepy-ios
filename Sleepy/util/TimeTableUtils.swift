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

    /// 解析 timeJson -> 按 node 排序的 list
    static func parseNodes(_ timeJson: String) -> [NodeTime] {
        guard let data = timeJson.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        return arr.compactMap { o -> NodeTime? in
            guard let node = (o["node"] as? NSNumber)?.intValue,
                  let startS = o["start"] as? String,
                  let endS = o["end"] as? String,
                  let start = parseTime(startS, base: today),
                  let end = parseTime(endS, base: today) else { return nil }
            return NodeTime(node: node, start: start, end: end)
        }.sorted { $0.node < $1.node }
    }

    private static func parseTime(_ s: String, base: Date) -> Date? {
        // "HH:mm" (也容忍 "HH:mm:ss")
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: base)
        comps.hour = parts[0]; comps.minute = parts[1]; comps.second = parts.count > 2 ? parts[2] : 0
        return Calendar.current.date(from: comps)
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
        if ownTime && !startTime.isEmpty && !endTime.isEmpty {
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
    /// - endNode   = 时间表中 end   ≥ courseEnd   的最小节点（向上取）
    /// - step      = endNode - startNode + 1
    /// - 若 StartTime 早于第一节，用第1节；endTime 晚于最后一节，用最后一节
    /// 返回 nil 表示无法映射（时间格式错误或时间表为空）。
    static func timeToNode(_ startTime: String, _ endTime: String, _ timeJson: String) -> (Int, Int)? {
        let nodes = parseNodes(timeJson)
        if nodes.isEmpty { return nil }
        let refDay = Calendar.current.startOfDay(for: nodes[0].start)
        guard let st = parseTime(startTime, base: refDay),
              let et = parseTime(endTime, base: refDay) else { return nil }

        let startNode = nodes.filter { $0.start <= st }.max { $0.node < $1.node }?.node
            ?? nodes.first!.node
        let endNode = nodes.filter { $0.end >= et }.min { $0.node < $1.node }?.node
            ?? nodes.last!.node

        if endNode < startNode { return nil }
        return (startNode, endNode - startNode + 1)
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
                end: (o["end"] as? String) ?? smartEndDefault(i + 1)
            )
        }
    }

    /// rows -> timeJson
    static func buildTimeJsonFromRows(_ rows: [TimeSlotRow]) -> String {
        let arr: [[String: Any]] = rows.map { row in
            ["node": row.node, "start": row.start, "end": row.end]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
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
