import Foundation
import SwiftSoup

/// Declared undergraduate layouts from Android v1.0.64.
final class JwUndergradSchoolParser: JwParser {
    let source: String
    let protocolType: String
    init(_ source: String, protocolType: String) { self.source = source; self.protocolType = protocolType }
    func generateCourseList() -> [JwCourse] {
        let rows: [JwCourse]
        switch protocolType {
        case "hniu": rows = hniu()
        case "sustech": rows = sustech()
        case "uic": rows = uic()
        case "cityu": rows = cityu()
        case "stu": rows = stu()
        case "nfu": rows = nfu()
        default: rows = []
        }
        return jw1064Valid(rows)
    }
    private func hniu() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source), let table = try? doc.select("[bordercolordark=#FFFFFF]").first() else { return [] }
        var output: [JwCourse] = []
        let body = try? table.select("tbody").first()
        for row in jw1064Elements(body, "tr") {
            var day = 0
            for cell in jw1064Elements(row, "td") {
                if jw1064Attribute(cell, "align") == "center" || jw1064Attribute(cell, "valign") != "top" { continue }
                day += 1
                let parts = jw1064Lines(cell)
                guard parts.count > 1 else { continue }
                for index in 1..<parts.count {
                    guard let schedule = jw1064Matches(#"\[([^]]+)周]\[([^]]+)节]"#, parts[index]).first,
                          let nodes = jw1064Range(schedule[2]) else { continue }
                    let name = parts[index - 1].components(separatedBy: " ").first ?? ""
                    let teacher = parts[index].components(separatedBy: " ").first ?? ""
                    let room = index + 1 < parts.count && !parts[index + 1].isEmpty ? parts[index + 1] : parts[index].components(separatedBy: " ").last ?? ""
                    for week in schedule[1].components(separatedBy: ",") {
                        guard let weeks = jw1064Range(week) else { continue }
                        output.append(JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: nodes.0, endNode: nodes.1, startWeek: weeks.0, endWeek: weeks.1))
                    }
                }
            }
        }
        return output
    }
    private func sustech() -> [JwCourse] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(source.utf8)) as? [Any] else { return [] }
        var output: [JwCourse] = []
        for item in root.compactMap({ $0 as? [String: Any] }) {
            let key = jw1064String(item, "KEY")
            guard key != "bz", let dayText = jw1064Matches(#"xq(\d+)_jc\d+"#, key).first?[1], let day = Int(dayText) else { continue }
            let text = jw1064String(item, "SKSJ"), fields = jw1064Matches(#"\[(.*?)]"#, jw1064String(item, "SKSJ")).map { $0[1] }
            guard fields.count == 5, let nodes = jw1064Range(fields[4].replacingOccurrences(of: "[第节]", with: "", options: .regularExpression)) else { continue }
            let note = fields[1].contains("-") ? fields[1].components(separatedBy: "-").dropFirst().joined(separator: "-") : ""
            for raw in fields[2].replacingOccurrences(of: "周", with: "").components(separatedBy: ",") {
                guard let weeks = jw1064Range(raw.replacingOccurrences(of: "[单双]", with: "", options: .regularExpression)) else { continue }
                output.append(JwCourse(name: text.components(separatedBy: "[")[0].trimmingCharacters(in: .whitespacesAndNewlines), room: fields[3], teacher: fields[0], day: day, startNode: nodes.0, endNode: nodes.1, startWeek: weeks.0, endWeek: weeks.1, type: jw1064Parity(raw), note: note))
            }
        }
        return output
    }
    private func uic() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        var teachers: [String: String] = [:]
        for row in jw1064Elements(try? doc.select(".tablestyle-2").first(), "tbody tr") {
            let cells = jw1064Elements(row, "td")
            if cells.count >= 4 { teachers[jw1064Text(cells[2])] = jw1064Text(cells[3]) }
        }
        var output: [JwCourse] = []
        for (node, row) in jw1064Elements(try? doc.getElementById("mytimetable"), "tr").enumerated() where node > 0 {
            for (column, cell) in jw1064Elements(row, "td").enumerated() {
                let parts = jw1064Lines(cell)
                if !jw1064Text(cell).isEmpty && parts.count >= 2 {
                    output.append(JwCourse(name: parts[0], room: parts[1], teacher: teachers[parts[0]] ?? "", day: column + 1, startNode: node, endNode: node, startWeek: 1, endWeek: 20))
                }
            }
        }
        return output
    }
    private func cityu() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source), let table = try? doc.select(".ctt-matrix").first() else { return [] }
        var occupied = Array(repeating: 0, count: 7), output: [JwCourse] = []
        for (node, row) in jw1064Elements(table, "tr").enumerated() where (1...366).contains(node) {
            var column = 0
            for cell in jw1064Elements(row, "td") {
                if ((try? cell.className()) ?? "").lowercased() == "ctt-matrix-td-time" { continue }
                while column < 7 && occupied[column] >= node { column += 1 }
                if column >= 7 { break }
                let span = max(1, jw1064Integer(jw1064Attribute(cell, "rowspan")) ?? 1)
                let last = explicitScheduleEnd(node, span)
                occupied[column] = last ?? 366
                guard let last else { column += 1; continue }
                let parts = jw1064Lines(cell)
                if !jw1064Text(cell).isEmpty && parts.count >= 3 {
                    output.append(JwCourse(name: parts[1], room: parts[2], day: column + 1, startNode: node, endNode: last, startWeek: 1, endWeek: 20)); column += 1
                }
            }
        }
        return output
    }
    private func stu() -> [JwCourse] {
        for fragment in source.components(separatedBy: "<head>").flatMap({ $0.components(separatedBy: "</head>") }) {
            guard let doc = try? SwiftSoup.parse(fragment), let table = try? doc.getElementById("DataGrid1") else { continue }
            var output: [JwCourse] = []
            for row in jw1064Elements(table, "tr") {
                if ["DGHeaderStyle", "DGFooterStyle"].contains((try? row.className()) ?? "") { continue }
                let cells = jw1064Elements(row, "td")
                guard cells.count >= 7, let weeks = jw1064Range(jw1064Text(cells[5])) else { continue }
                for column in 6..<cells.count {
                    let raw = jw1064Text(cells[column]), nodes = raw.replacingOccurrences(of: "[单双]", with: "", options: .regularExpression)
                    guard !nodes.isEmpty, !(raw.contains("单") && raw.contains("双")) else { continue }
                    func node(_ c: Character) -> Int { let n = Int(c.asciiValue ?? 0); return c.isLetter ? n - 54 : n - 48 }
                    let advertised: [Int]
                    if nodes.contains("-") {
                        guard nodes.range(of: #"^[0-9A-Z]-[0-9A-Z]$"#, options: .regularExpression) != nil,
                              let a = nodes.first, let b = nodes.last, node(a) >= 1, node(b) >= node(a), node(b) <= 366 else { continue }
                        advertised = Array(node(a)...node(b))
                    } else {
                        guard nodes.range(of: #"^[0-9A-Z]+$"#, options: .regularExpression) != nil else { continue }
                        advertised = nodes.map(node)
                        if !advertised.allSatisfy({ (1...366).contains($0) }) { continue }
                    }
                    var runs: [(Int, Int)] = []
                    for section in Set(advertised).sorted() {
                        if let last = runs.last, section == last.1 + 1 { runs[runs.count - 1] = (last.0, section) } else { runs.append((section, section)) }
                    }
                    let value = Float(jw1064Text(cells[2])) ?? 0, credit = value.isFinite && value >= 0 ? value : 0
                    let title = jw1064Text(cells[1]), name = title.contains("]") ? title.components(separatedBy: "]").dropFirst().joined(separator: "]") : title
                    for (first, last) in runs { output.append(JwCourse(name: name.trimmingCharacters(in: .whitespacesAndNewlines), room: jw1064Text(cells[4]), teacher: jw1064Text(cells[3]), day: column == 6 ? 7 : column - 6, startNode: first, endNode: last, startWeek: weeks.0, endWeek: weeks.1, type: jw1064Parity(raw), credit: credit)) }
                }
            }
            if !output.isEmpty { return output }
        }
        return []
    }
    private func nfu() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        var output: [JwCourse] = []
        for row in jw1064Elements(doc, "tr.ui-widget-content") {
            let spans = jw1064Elements(row, "span"); guard spans.count >= 10 else { continue }
            for column in 3...9 {
                for raw in jw1064Text(spans[column]).replacingOccurrences(of: "/ ", with: "/").components(separatedBy: "/") {
                    let parts = raw.replacingOccurrences(of: " 单周", with: "").replacingOccurrences(of: " 双周", with: "").components(separatedBy: " ")
                    guard (3...4).contains(parts.count), !(raw.contains("单") && raw.contains("双")),
                          let weeks = jw1064Range(parts[0].replacingOccurrences(of: #"^第|周$"#, with: "", options: .regularExpression)),
                          let nodes = jw1064Range(parts[1].replacingOccurrences(of: #"^第|节$"#, with: "", options: .regularExpression)) else { continue }
                    output.append(JwCourse(name: jw1064Text(spans[0]), room: parts.count == 4 ? parts[3] : "", teacher: parts[2], day: column - 2, startNode: nodes.0, endNode: nodes.1, startWeek: weeks.0, endWeek: weeks.1, type: jw1064Parity(raw)))
                }
            }
        }
        return output
    }
}
