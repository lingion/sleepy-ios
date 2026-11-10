import Foundation
import SwiftSoup

final class JwUndergradHtmlParser: JwParser {
    let source: String
    let protocolType: String
    init(_ source: String, protocolType: String) { self.source = source; self.protocolType = protocolType }
    func generateCourseList() -> [JwCourse] {
        let rows: [JwCourse]
        switch protocolType {
        case "jmucy": rows = jmucy()
        case "nuaajc": rows = nuaajc()
        case "qmu": rows = qmu()
        case "javtc": rows = javtc()
        case "hitsz": rows = hitsz()
        default: rows = []
        }
        return jw1064Valid(rows)
    }
    private var fragments: [String] { source.components(separatedBy: "<head>").flatMap { $0.components(separatedBy: "</head>") } }
    private func jmucy() -> [JwCourse] {
        for fragment in fragments {
            guard let doc = try? SwiftSoup.parse(fragment), let table = try? doc.getElementById("ctl00_ContentPlaceHolder3_ScheduleTable") else { continue }
            var output: [JwCourse] = []
            for (rowIndex, row) in jw1064Elements(table, "tr").enumerated() {
                guard let nodes = explicitSchedulePair(rowIndex) else { continue }
                for (day, cell) in jw1064Elements(row, "td").enumerated() where (1...7).contains(day) {
                    for block in jw1064Text(cell).components(separatedBy: "★") {
                        let fields = block.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
                        guard fields.count >= 3 else { continue }
                        for (first, last, parity) in schoolWeekRanges(fields.last!) { output.append(JwCourse(name: fields[0], room: fields.count > 3 ? fields[1] : "", teacher: fields[fields.count - 2], day: day, startNode: nodes.lowerBound, endNode: nodes.upperBound, startWeek: first, endWeek: last, type: parity)) }
                    }
                }
            }
            if !output.isEmpty { return output }
        }
        return []
    }
    private func nuaajc() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source), let table = try? doc.getElementById("GrwCourseTablePrint") else { return [] }
        var columns: [String: Int] = [:], output: [JwCourse] = []
        for (index, header) in jw1064Elements(table, "th").enumerated() { columns[jw1064Text(header)] = index }
        for row in jw1064Elements(table, "tr").dropFirst() {
            let cells = jw1064Elements(row, "td")
            func value(_ key: String) -> String { guard let index = columns[key], cells.indices.contains(index) else { return "" }; return jw1064Text(cells[index]) }
            guard let day = jw1064Integer(value("week")), let node = jw1064Integer(value("unit")), let last = explicitScheduleEnd(node, jw1064Integer(value("lsjs")) ?? 1) else { continue }
            for (first, end, parity) in schoolWeekRanges(value("weekly")) { output.append(JwCourse(name: value("kcm"), room: value("roomid"), teacher: value("jsm"), day: day, startNode: node, endNode: last, startWeek: first, endWeek: end, type: parity)) }
        }
        return output
    }
    private func qmu() -> [JwCourse] {
        for fragment in fragments {
            guard let doc = try? SwiftSoup.parse(fragment), let table = try? doc.select("table[frame=box]").first() else { continue }
            var output: [JwCourse] = [], rowIndex = 0
            for row in jw1064Elements(table, "tr") {
                let cells = jw1064Elements(row, "td[valign=top]"); if cells.isEmpty { continue }
                guard let nodes = explicitSchedulePair(rowIndex + 1) else { break }
                for (dayIndex, cell) in cells.enumerated() {
                    let lines = jw1064Lines(cell); guard lines.count > 3 else { continue }
                    for index in 3..<lines.count {
                        guard let m = jw1064Matches(#"^([0-9.\-]+)周\s+([^ ]*)\s+([0-9]+)节$"#, lines[index]).first,
                              let length = jw1064Integer(m[3]), let last = explicitScheduleEnd(nodes.lowerBound, min(2, length)) else { continue }
                        for (first, end, _) in schoolWeekRanges(m[1].replacingOccurrences(of: ".", with: ",")) { output.append(JwCourse(name: lines[index - 3], room: lines[index - 1], teacher: lines[index - 2], day: dayIndex + 1, startNode: nodes.lowerBound, endNode: last, startWeek: first, endWeek: end, type: jw1064Parity(m[2]))) }
                    }
                }
                rowIndex += 1
            }
            if !output.isEmpty { return output }
        }
        return []
    }
    private func javtc() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source), let table = try? doc.select("table[border=1][width=98%]").first() else { return [] }
        var output: [JwCourse] = []
        let labels = ["第一二节", "第三四节", "第五六节", "第七八节"]
        for row in jw1064Elements(table, "tr").dropFirst() {
            let cells = jw1064Elements(row, "td"); guard cells.count >= 8, let pair = labels.firstIndex(where: { jw1064Text(cells[0]).contains($0) }) else { continue }
            for day in 1...7 { for link in jw1064Elements(cells[day], "a[title]") {
                let fields = jw1064Attribute(link, "title").components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }; guard fields.count >= 8 else { continue }
                for (first, last, parity) in schoolWeekRanges(fields[5].components(separatedBy: "上课周次：").last ?? "") { output.append(JwCourse(name: fields[2].components(separatedBy: "课程名称：").last ?? "", room: fields[6].components(separatedBy: "开课地点：").last ?? "", teacher: fields[3].components(separatedBy: "授课教师：").last ?? "", day: day, startNode: pair * 2 + 1, endNode: pair * 2 + 2, startWeek: first, endWeek: last, type: parity)) }
            } }
        }
        return output
    }
    private func hitsz() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source), let table = try? doc.select(".ivu-table-tbody").first() else { return [] }
        var output: [JwCourse] = []
        for row in jw1064Elements(table, "tr") { for (day, cell) in jw1064Elements(row, "td").enumerated() where (1...7).contains(day) {
            for card in jw1064Elements(cell, ".ivu-card-body") {
                let fields = jw1064Text(card).components(separatedBy: " "); guard fields.count >= 3 else { continue }
                let lab = fields[0].hasPrefix("【实验】"), brackets = jw1064Matches(#"\[([^]]*)]"#, fields[fields.count - 2]).map { $0[1] }
                guard brackets.count >= 2 else { continue }
                let rawNodes = lab ? brackets[0] : fields.last!, weekText = lab ? brackets.last! : brackets[0]
                let nodes = schoolNodeRanges(rawNodes.replacingOccurrences(of: #"^第|节$"#, with: "", options: .regularExpression))
                func unbracket(_ s: String) -> String { s.hasPrefix("[") && s.hasSuffix("]") ? String(s.dropFirst().dropLast()) : s }
                for (first, last, parity) in schoolWeekRanges(weekText) { for (a, b) in nodes { output.append(JwCourse(name: fields[0], room: lab ? unbracket(fields.last!) : brackets.last!, teacher: lab ? "" : unbracket(fields[fields.count - 3]), day: day, startNode: a, endNode: b, startWeek: first, endWeek: last, type: parity)) } }
            }
        } }
        return output
    }
}
