// JwKustParser.swift — ← JwKustParser.kt
//
// 昆明理工大学统一门户 (KMUST) 周课表网格解析器。
//
// 协议: JwProtocol.TYPE_KUST = "kust"
//
// 数据来源: GET /queryAWeekSchedule?XNXQ=<term>
//   返回: { data: { resultsJsonArr: [[col0,row1],[col1,row1],...], zs: weekNo } }
//   resultsJsonArr[0] = [null, "1节", "2节", ...]
//   resultsJsonArr[rowIndex] (rowIndex>=2): [null, col1_cell, col2_cell, ...]
//   单元格内容: "课名[,教室];教师[,教师2...]" — 分号后为教师, 无教师时为";"
//   字段: substringBefore(";").split(","): [0]=课名, [1]=教室(可缺省)
//   列索引 → 星期: columnIndex.coerceIn(1, 7)
//   行索引 → 节次: rowIndex - 1

import Foundation

final class JwKustParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objData = root["data"] as? [String: Any],
              let grid = objData["resultsJsonArr"] as? [Any] else {
            return []
        }
        // Android: data.string("zs").toIntOrNull() — contentOrNull 同时接受 JSON 数字与字符串, 并 trim
        let weekStr = (((objData["zs"] as? String) ?? (objData["zs"] as? NSNumber)?.stringValue) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let week = Int(weekStr) else { return [] }

        // Android linkedMapOf: 保持插入序输出
        var order: [String] = []
        var seen: [String: JwCourse] = [:]

        for (rowIndex, rowElement) in grid.enumerated() {
            // Android: rowElement as? JsonArray ?: continue — 单行坏数据跳过, 不影响其余行
            guard let row = rowElement as? [Any], rowIndex >= 2 else { continue }
            let section = rowIndex - 1
            for (colIndex, cellElement) in row.enumerated() {
                guard colIndex >= 1 else { continue }
                let cellText = (((cellElement as? String) ?? (cellElement as? NSNumber)?.stringValue) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cellText.isEmpty { continue }
                let day = min(max(colIndex, 1), 7)
                // Android: fields = cell.substringBefore(";").split(",")
                //          name = fields[0], room = fields.getOrNull(1), teacher = cell.substringAfter(';')
                let halves = cellText.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
                let fields = String(halves[0]).components(separatedBy: ",")
                let name = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if name.isEmpty { continue }
                let room = fields.count > 1 ? fields[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let teacher = halves.count > 1
                    ? String(halves[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                let key = [name, room, teacher, day.description, week.description]
                    .joined(separator: "|")
                if let existing = seen[key] {
                    if section == existing.endNode + 1 {
                        let merged = JwCourse(name: existing.name, room: existing.room, teacher: existing.teacher,
                            day: existing.day, startNode: existing.startNode, endNode: section,
                            startWeek: existing.startWeek, endWeek: existing.endWeek, type: existing.type)
                        seen[key] = merged
                    }
                } else {
                    let c = JwCourse(name: name, room: room, teacher: teacher,
                        day: day, startNode: section, endNode: section,
                        startWeek: week, endWeek: week)
                    seen[key] = c
                    order.append(key)
                }
            }
        }

        return order.compactMap { seen[$0] }
    }

    // MARK: - T8

    var confidenceValue: Int {
        guard let data = source.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let objData = root["data"] as? [String: Any],
              objData["resultsJsonArr"] is [Any] else { return 0 }
        return 90
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("queryAWeekSchedule") { out.append("queryAWeekSchedule") }
        if source.contains("resultsJsonArr") { out.append("resultsJsonArr") }
        if source.contains("weekcount") { out.append("weekcount") }
        return out
    }
}
