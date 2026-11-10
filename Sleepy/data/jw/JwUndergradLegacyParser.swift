import Foundation
import SwiftSoup

final class JwUndergradLegacyParser: JwParser {
    let source: String
    let protocolType: String
    init(_ source: String, protocolType: String) { self.source = source; self.protocolType = protocolType }
    func generateCourseList() -> [JwCourse] {
        switch protocolType {
        case "jnu": return jw1064Valid(jnu())
        case "swust": return jw1064Valid(swust())
        case "bjtu": return jw1064Valid(bjtu())
        default: return []
        }
    }
    private func jnu() -> [JwCourse] {
        let boundary = source.range(of: #"</html\s*>"#, options: .regularExpression)
        let remainder = boundary.map { String(source[$0.upperBound...]) } ?? ""
        let document = remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? source : remainder
        if let end = document.range(of: #"</html\s*>"#, options: [.regularExpression, .caseInsensitive]), !document[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        guard let doc = try? SwiftSoup.parse(document), let table = try? doc.select("#oReportCell .a8").first() else { return [] }
        let rows = jw1064Elements(table, "tr"); guard rows.count >= 10 else { return [] }
        var output: [JwCourse] = []
        for (dayIndex, row) in rows[3..<10].enumerated() {
            for (node, cell) in jw1064Elements(row, "td").enumerated() where (1...366).contains(node) {
                let text = jw1064Text(cell, "div")
                guard !text.isEmpty, text.contains("课程："), text.contains("(") else { continue }
                let weeks = jw1064Matches(#"从第(\d+)至(\d+)"#, text).first
                if text.contains("从第") && weeks == nil { continue }
                guard let first = weeks.flatMap({ Int($0[1]) }) ?? (weeks == nil ? 1 : nil), let last = weeks.flatMap({ Int($0[2]) }) ?? (weeks == nil ? 18 : nil) else { continue }
                let parity = text.contains("单周") ? 1 : text.contains("双周") ? 2 : 0
                let room: String
                if parity != 0 { room = (text.components(separatedBy: "单周").last ?? text).components(separatedBy: "双周").last?.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ").first ?? "" }
                else { room = text.components(separatedBy: " ").dropLast().last ?? text }
                let after = text.components(separatedBy: "课程：").dropFirst().joined(separator: "课程：")
                let name = after.components(separatedBy: "(").dropLast().joined(separator: "(")
                let course = JwCourse(name: name, room: room, day: dayIndex + 1, startNode: node, endNode: node, startWeek: first, endWeek: last, type: parity)
                if let p = output.last, p.name == course.name, p.day == course.day, p.room == course.room, p.teacher == course.teacher, p.startWeek == first, p.endWeek == last, p.type == parity, p.endNode == node - 1 {
                    output[output.count - 1] = JwCourse(name: p.name, room: p.room, day: p.day, startNode: p.startNode, endNode: node, startWeek: first, endWeek: last, type: parity)
                } else { output.append(course) }
            }
        }
        return output
    }
    private func swust() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source), let table = try? doc.select(".UICourseTable tbody").first() else { return [] }
        var output: [JwCourse] = []
        for (index, row) in jw1064Elements(table, "tr").enumerated() {
            let cells = jw1064Elements(row, "td"); guard cells.count >= 7 else { continue }
            for (column, cell) in cells.suffix(7).enumerated() {
                for lecture in jw1064Elements(cell, ".lecture") {
                    let raw = jw1064Text(lecture, ".week").components(separatedBy: "(")[0].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard let weeks = jw1064Range(raw) else { continue }
                    output.append(JwCourse(name: jw1064Text(lecture, ".course"), room: jw1064Text(lecture, ".place"), day: column + 1, startNode: index + 1, endNode: index + 1, startWeek: weeks.0, endWeek: weeks.1))
                }
            }
        }
        return output
    }
    private func bjtu() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source), let table = try? doc.select("table.table.table-bordered").first() else { return [] }
        var output: [JwCourse] = []
        for (node, row) in jw1064Elements(table, "tr").enumerated() {
            var firstNonempty = true, day = 1
            for cell in jw1064Elements(row, "td") {
                let text = jw1064Text(cell)
                if firstNonempty && !text.isEmpty { firstNonempty = false; continue }
                for block in jw1064Matches(#"\w{7}\s\S+\s[^\[]+\[.]\s[^A-Z]+\w{5}"#, text) {
                    let raw = block[0]
                    guard let m = jw1064Matches(#"]\s(.+)\s\["#, raw).first, let weeks = jw1064Matches(#"第([0-9,\-]+)周"#, raw).first else { continue }
                    let room = jw1064Matches(#"[A-Z]{2}\d\d\d"#, raw).first?[0] ?? "", teacher = jw1064Matches(#"\d\d周\s(\S+)"#, raw).first?[1] ?? ""
                    for (first, last, parity) in schoolWeekRanges(weeks[1]) { output.append(JwCourse(name: m[1], room: room, teacher: teacher, day: day, startNode: node, endNode: node, startWeek: first, endWeek: last, type: parity)) }
                }
                day += 1
            }
        }
        return output
    }
}
