import Foundation
import SwiftSoup

/// ChaoXing rows are individual periods; preserve each week's exact node set.
final class JwChaoxingParser: JwParser {
    let source: String
    init(_ source: String) { self.source = source }
    private func stripHtml(_ text: String) -> String { (try? SwiftSoup.parseBodyFragment(text).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "" }
    private func expandWeeks(_ value: Any?) -> [Int] {
        if let array = value as? [Any] {
            let weeks = array.compactMap { jw1064Integer($0) }
            guard weeks.count == array.count, weeks.allSatisfy({ (1...366).contains($0) }) else { return [] }
            return Set(weeks).sorted()
        }
        guard let value else { return [] }
        var text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("周") { text.removeLast(); text = text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !text.isEmpty else { return [] }
        var weeks = Set<Int>()
        for part in text.replacingOccurrences(of: "，", with: ",").components(separatedBy: ",") {
            guard let match = jw1064Matches(#"^([0-9]+)(?:\s*[-～~]\s*([0-9]+)(?:\s*\(([单双])\))?)?$"#, part.trimmingCharacters(in: .whitespacesAndNewlines)).first,
                  let first = jw1064Integer(match[1]), let last = jw1064Integer(match[2].isEmpty ? match[1] : match[2]),
                  first > 0, last >= first, last <= 366 else { return [] }
            for week in first...last where match[3].isEmpty || week % 2 == (match[3] == "单" ? 1 : 0) { weeks.insert(week) }
        }
        return weeks.sorted()
    }
    private func weekRuns(_ weeks: [Int]) -> [(Int, Int, Int)] {
        guard let first = weeks.first else { return [] }
        var runs: [(Int, Int)] = [], start = first, previous = first
        for week in weeks.dropFirst() {
            if week == previous + 1 { previous = week }
            else { runs.append((start, previous)); start = week; previous = week }
        }
        runs.append((start, previous))
        if runs.count == 1 { return [(runs[0].0, runs[0].1, 0)] }
        if weeks.count >= 2 && zip(weeks, weeks.dropFirst()).allSatisfy({ $1 - $0 == 2 }) {
            return [(first, weeks.last!, first % 2 == 1 ? 1 : 2)]
        }
        return runs.map { ($0.0, $0.1, 0) }
    }
    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        guard let rows = (root as? [Any]) ?? (root as? [String: Any])?["rows"] as? [Any] else { return [] }
        struct Key: Hashable { let name: String; let day: Int; let teacher: String; let room: String }
        var order: [Key] = [], groups: [Key: [Int: Set<Int>]] = [:]
        for element in rows {
            guard let row = element as? [String: Any] else { continue }
            func field(_ keys: String...) -> Any? {
                keys.compactMap { row[$0] }.first { value in
                    !(value is NSNull) && (!(value is String) || !(value as! String).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            func integer(_ value: Any?) -> Int? { value.flatMap { jw1064Integer(String(describing: $0).trimmingCharacters(in: .whitespacesAndNewlines)) } }
            let name = stripHtml(jw1064String(row, "kcmc"))
            let explicitDay = field("xingqi"), explicitNode = field("xjc", "djc")
            let fallback = integer(field("rqxl"))
            guard !name.isEmpty, let day = explicitDay != nil ? integer(explicitDay) : fallback.map({ $0 / 100 }), (1...7).contains(day),
                  let node = explicitNode != nil ? integer(explicitNode) : fallback.map({ $0 > 99 ? $0 % 100 : $0 }), (1...366).contains(node) else { continue }
            let weeks = expandWeeks(field("zcstr", "zc"))
            guard !weeks.isEmpty else { continue }
            let campus = field("xjc") == nil && field("djc") != nil ? stripHtml(jw1064String(row, "xqmc")) : ""
            let room = stripHtml(jw1064String(row, "croommc")) + (campus.isEmpty ? "" : "（\(campus)）")
            let key = Key(name: name, day: day, teacher: stripHtml(jw1064String(row, "tmc")), room: room)
            if groups[key] == nil { order.append(key); groups[key] = [:] }
            for week in weeks { groups[key, default: [:]][week, default: []].insert(node) }
        }
        var result: [JwCourse] = []
        for key in order {
            var nodeOrder: [[Int]] = [], nodeGroups: [[Int]: [Int]] = [:]
            for (week, nodeSet) in (groups[key] ?? [:]).sorted(by: { $0.key < $1.key }) {
                let nodes = nodeSet.sorted()
                if nodeGroups[nodes] == nil { nodeOrder.append(nodes); nodeGroups[nodes] = [] }
                nodeGroups[nodes]!.append(week)
            }
            for nodes in nodeOrder {
                var blocks: [(Int, Int)] = []
                for node in nodes {
                    if let previous = blocks.last, node == previous.1 + 1 { blocks[blocks.count - 1] = (previous.0, node) }
                    else { blocks.append((node, node)) }
                }
                for (first, last) in blocks {
                    for (from, to, parity) in weekRuns(nodeGroups[nodes] ?? []) {
                        result.append(JwCourse(name: key.name, room: key.room, teacher: key.teacher, day: key.day,
                                               startNode: first, endNode: last, startWeek: from, endWeek: to, type: parity))
                    }
                }
            }
        }
        return result.sorted { ($0.day, $0.startNode, $0.name) < ($1.day, $1.startNode, $1.name) }
    }
}
