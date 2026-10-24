// JwChaoxingParser.swift — ← JwChaoxingParser.kt
//
// 超星学习通/ChaoXing「综合教务管理系统」课表 JSON 解析器。
//
// 适配学校：吉林工商学院 (jwxt.jlbtc.edu.cn, 2026-09-05 采集包实锤 —
// 页面页脚 "Powered by ChaoXing") 及其他超星综合教务部署。
// 与 JwCquParser / JwWiseduParser 同类：source 不是 HTML，而是课表
// API 的 JSON 响应（在 WebView 内通过 fetch 拿到，见
// JwWebViewLoginScreen 的 chaoxing 分支 CHAOXING_FETCH_JS）。
//
// 数据来源（WebView 内 fetch 两段）：
//   1) GET /pkgl/xskb/queryKbForGrdb?sf_request_type=ajax   → 个人课表 rows
//      （无参数，服务端按会话取学期；学生须已在课表页会话内）
//   2) GET /admin/api/getZclistByXnxq?xnxq=…&sf_request_type=ajax → 节次时间
//      （部分部署路径无 /admin 前缀，fetch JS 按学校 URL 推断）
//
// 输入 JSON 形态（fetch JS 组装）：
//   {"xnxq":"2026-2027-1","dqzc":1,
//    "rows":[{"kcmc":…,"xjc":"1","xingqi":1,"rqxl":"101","zcstr":"1,2,..",
//             "tmc":…,"croommc":…}],
//    "periods":[{"jc":"1","kssj":"8:20","jssj":"9:05"}]}
//
// 字段映射（超星 → JwCourse）：
//   kcmc    课程名（班级表形态带 <a onclick=openKckb(..)>，剥 HTML）→ name
//   croommc 教室（同上剥 HTML；可空——体育课常无固定教室）       → room
//   tmc     教师（同上剥 HTML）                                  → teacher
//   xingqi  星期 1..7（int）；缺位回退 rqxl/100                  → day
//   xjc     节号（字符串/数字皆容）；缺位回退 rqxl%100            → startNode=endNode
//   zcstr   周次串 "1,2,3" 逗号形态 / "1-16" 区间形态             → 周次段
//
// 合并规则 (闽江师范 2026-09-30 修正): 按 (课名,星期,教师) 分组, 节号连续段拉通
// 为 startNode..endNode, 周次取组内并集, 同节多教室用 "/" 连接 (超星按单节粒度
// 返回行, 连堂课拆多行; 同一节还可能因按周次换教室返回多行、各带不同周次串与
// 教室 — 若分组键含教室或周次, 同一节会渲染成两张重叠课程卡)。

import Foundation

final class JwChaoxingParser: JwParser {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    /// 剥离 <a href=.. onclick=..>名字</a> 等标签，留纯文本（班级表接口形态）
    private func stripHtml(_ s: String) -> String {
        if s.contains("<") {
            return s.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 周次串 → 连续段列表（1..16 逗号/区间/混合形态）
    private func expandWeeks(_ zcstr: String) -> [Int] {
        var weeks = Set<Int>()
        for part in zcstr.split(whereSeparator: { $0 == "," || $0 == "，" }) {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if t.contains("-") || t.contains("～") || t.contains("~") {
                let se = t.split(whereSeparator: { $0 == "-" || $0 == "～" || $0 == "~" })
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if se.count == 2, let a = Int(se[0]), let b = Int(se[1]), a <= b {
                    for w in a...b { weeks.insert(w) }
                }
            } else if let v = Int(t) {
                weeks.insert(v)
            }
        }
        return weeks.sorted()
    }

    /// 周次列表 → 连续段 [(startWeek, endWeek, type)]，口径与 JwWiseduParser.weekRuns 一致：
    /// 单连续段=每周(0)；整体等差 step=2=单周(1)/双周(2)；其余拆多段每段 0。
    private func weekRuns(_ weeks: [Int]) -> [(Int, Int, Int)] {
        if weeks.isEmpty { return [] }
        var runs: [(Int, Int)] = []
        var start = weeks[0]
        var prev = weeks[0]
        for w in weeks.dropFirst() {
            if w == prev + 1 {
                prev = w
            } else {
                runs.append((start, prev))
                start = w
                prev = w
            }
        }
        runs.append((start, prev))
        if runs.count == 1 { return [(runs[0].0, runs[0].1, 0)] }
        if weeks.count >= 2 && (1..<weeks.count).allSatisfy({ weeks[$0] - weeks[$0 - 1] == 2 }) {
            let type = weeks.first! % 2 == 1 ? 1 : 2
            return [(weeks.first!, weeks.last!, type)]
        }
        return runs.map { ($0.0, $0.1, 0) }
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return []
        }
        // 逐元素取字典: 单个非对象元素只跳过该行 (对齐 Android el.jsonObject runCatching ?: continue)
        let rows = (root["rows"] as? [Any]) ?? []

        struct Row {
            let name: String
            let day: Int
            let node: Int
            let weeks: [Int]
            let room: String
            let teacher: String
        }

        var parsed: [Row] = []
        for element in rows {
            guard let o = element as? [String: Any] else { continue }
            func str(_ k: String) -> String {
                ((o[k] as? String) ?? (o[k] as? NSNumber)?.stringValue ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let name = stripHtml(str("kcmc"))
            if name.isEmpty { continue }

            // 星期: xingqi 优先, 缺位回退 rqxl 前缀 (rqxl = 星期*100 + 节号)
            let dayOpt = str("xingqi").toInt() ?? str("rqxl").toInt().map { $0 / 100 }
            guard let day = dayOpt, (1...7).contains(day) else { continue }

            // 节号: xjc 优先, 缺位回退 rqxl 后两位
            let nodeOpt = str("xjc").toInt() ?? str("rqxl").toInt().map { $0 > 99 ? $0 % 100 : $0 }
            guard let node = nodeOpt else { continue }

            let weeks = expandWeeks(str("zcstr"))
            if weeks.isEmpty { continue }

            parsed.append(Row(
                name: name, day: day, node: node, weeks: weeks,
                room: stripHtml(str("croommc")), teacher: stripHtml(str("tmc"))))
        }

        // 合并: 按 (课名,星期,教师) 分组 → 节号连续段拉通, 周次取并集, 同节多教室
        // 用 "/" 连接。必要性 (闽江师范 2026-09-30 采集实锤): 同一节因按周次换教室
        // 返回多行、各带不同周次串与教室 (如 5..15 周 A 室 + 17,19 周 B 室);
        // 若按 (含周次或含教室) 的行分组, 同一节会渲染成两张重叠课程卡。
        struct Key: Hashable {
            let name: String
            let day: Int
            let teacher: String
        }
        var groupOrder: [Key] = []
        var groups: [Key: [Row]] = [:]
        for r in parsed {
            let k = Key(name: r.name, day: r.day, teacher: r.teacher)
            if groups[k] == nil { groupOrder.append(k) }
            groups[k, default: []].append(r)
        }
        var result: [JwCourse] = []
        for key in groupOrder {
            let group = groups[key]!
            let weeks = Array(Set(group.flatMap { $0.weeks })).sorted()
            // 每节点教室: 组内该 node 各行教室去空白后按出现序去重, "/" 连接
            var roomsByNodeRows: [Int: [String]] = [:]
            var nodeOrder: [Int] = []
            for r in group {
                if roomsByNodeRows[r.node] == nil { nodeOrder.append(r.node) }
                roomsByNodeRows[r.node, default: []].append(r.room)
            }
            var roomsByNode: [Int: String] = [:]
            for node in nodeOrder {
                var distinctRooms: [String] = []
                for room in roomsByNodeRows[node]! where !room.isEmpty {
                    if !distinctRooms.contains(room) { distinctRooms.append(room) }
                }
                roomsByNode[node] = distinctRooms.joined(separator: "/")
            }
            let nodes = Array(Set(group.map { $0.node })).sorted()
            var start = nodes.first!
            var prev = nodes.first!
            var blocks: [(Int, Int)] = []
            for n in nodes.dropFirst() {
                if n == prev + 1 {
                    prev = n
                } else {
                    blocks.append((start, prev))
                    start = n
                    prev = n
                }
            }
            blocks.append((start, prev))
            for (bs, be) in blocks {
                var blockRooms: [String] = []
                for n in bs...be {
                    guard let room = roomsByNode[n], !room.isEmpty,
                          !blockRooms.contains(room) else { continue }
                    blockRooms.append(room)
                }
                let room = blockRooms.joined(separator: "/")
                // 周次段: 并集展开后可能多段 (非连续周次, 如 1-3周 + 8-9周)
                for (sw, ew, type) in weekRuns(weeks) {
                    result.append(JwCourse(
                        name: key.name, room: room, teacher: key.teacher,
                        day: key.day, startNode: bs, endNode: be,
                        startWeek: sw, endWeek: ew,
                        type: type))
                }
            }
        }
        // 稳定排序 (day, startNode, name), 口径与 Kotlin sortWith(compareBy) 一致
        return result.enumerated()
            .sorted { a, b in
                if a.element.day != b.element.day { return a.element.day < b.element.day }
                if a.element.startNode != b.element.startNode { return a.element.startNode < b.element.startNode }
                if a.element.name != b.element.name { return a.element.name < b.element.name }
                return a.offset < b.offset
            }
            .map { $0.element }
    }
}

private extension String {
    /// Kotlin String.toIntOrNull() 语义
    func toInt() -> Int? {
        let t = trimmingCharacters(in: .whitespaces)
        return Int(t)
    }
}
