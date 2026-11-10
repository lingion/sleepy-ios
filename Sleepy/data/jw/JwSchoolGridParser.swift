// Declared grid layouts from Android v1.0.64 (77b878fd).
import Foundation
import SwiftSoup

final class JwSchoolGridParser: JwParser {
    let source: String
    private let kind: String
    init(_ source: String, _ protocolName: String) { self.source = source; kind = protocolName }

    func generateCourseList() throws -> [JwCourse] {
        let result: [JwCourse]
        switch kind {
        case "gxic": result = gxic()
        case "gxnu": result = gxnu()
        case "jxnu": result = jxnu()
        case "nnutc": result = nnutc()
        default: result = []
        }
        return result.filter { c in
            !Jw64.trim(c.name).isEmpty && (1...7).contains(c.day) && c.startNode >= 1 && c.endNode >= c.startNode &&
            (1...366).contains(c.startWeek) && c.endWeek >= c.startWeek && c.endWeek <= 366 &&
            (c.startWeek...c.endWeek).contains { c.type == 0 || $0 % 2 == c.type % 2 }
        }
    }

    private func gxic() -> [JwCourse] {
        guard let doc = Jw64.doc(source), let table = Jw64.first(doc, "table[width=98%]") else { return [] }
        let headers = Jw64.select(table, "th").map(Jw64.text)
        let sunday = headers.firstIndex { $0.contains("星期天") || $0.contains("星期日") }
        let monday = headers.firstIndex { $0.contains("星期一") }
        let sundayFirst = sunday != nil && monday != nil && sunday! < monday!
        let sections = ["第0102节":1, "第0304节":3, "第0506节":5, "第0708节":7, "第0910节":9]
        var out: [JwCourse] = []
        for row in Jw64.select(table, "tr") {
            let cells = Jw64.select(row, "td")
            guard let first = sections[Jw64.text(cells.first)] else { continue }
            for (column, cell) in cells.dropFirst().enumerated() where column <= 6 {
                let day = sundayFirst ? (column == 0 ? 7 : column) : column + 1
                for link in Jw64.select(cell, "a[title]") {
                    let name = Jw64.lines(link).first ?? ""
                    let fields = Jw64.attr(link, "title").components(separatedBy: .newlines).map(Jw64.trim)
                    func field(_ label: String) -> String? { fields.first { $0.hasPrefix(label) }.map { Jw64.trim(String($0.dropFirst(label.count))) } }
                    guard let weeks = field("上课周次：") else { continue }
                    for (sw, ew, type) in schoolWeekRanges(weeks) {
                        out.append(JwCourse(name: name, room: field("开课地点：") ?? "", teacher: field("授课教师：") ?? "", day: day,
                                            startNode: first, endNode: first + 1, startWeek: sw, endWeek: ew, type: type,
                                            startTime: Self.gxicPeriods[first - 1].0, endTime: Self.gxicPeriods[first].1))
                    }
                }
            }
        }
        return out
    }

    private func gxnu() -> [JwCourse] {
        guard let doc = Jw64.doc(source), let table = Jw64.first(doc, "#xkjbgzszGridIdGrid") else { return [] }
        var out: [JwCourse] = []
        for row in Jw64.select(table, "tbody tr") {
            func field(_ key: String) -> String { Jw64.text(Jw64.first(row, "td[aria-describedby=xkjbgzszGridIdGrid_\(key)]")) }
            let credit = Float(field("xf")).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
            for arrangement in field("sksjdd").components(separatedBy: CharacterSet(charactersIn: ";；")) {
                guard let m = Jw64.full(#"(.+?)\s*星期([一二三四五六日天])\s+([0-9,，\-]+)节\s*【([^】]*)】"#, Jw64.trim(arrangement)) else { continue }
                let rawWeek = Jw64.trim(m[1]); let weeks = schoolWeekRanges(rawWeek.hasSuffix("周") ? String(rawWeek.dropLast()) : rawWeek)
                for (first, last) in schoolNodeRanges(m[3]) { for (sw, ew, type) in weeks {
                    out.append(JwCourse(name: field("kcmc"), room: Jw64.trim(m[4]), teacher: field("rkjs"), day: Jw64.day(m[2]),
                                        startNode: first, endNode: last, startWeek: sw, endWeek: ew, type: type, credit: credit))
                } }
            }
        }
        return out
    }

    private func jxnu() -> [JwCourse] {
        guard let doc = Jw64.doc(source), let table = Jw64.first(doc, "#_ctl1_NewKcb") else { return [] }
        var teachers: [String: String] = [:]
        for row in Jw64.select(Jw64.first(doc, "#_ctl1_dgStudentLesson"), "tr") {
            let cells = Jw64.select(row, "td")
            let name = cells.count > 1 ? Jw64.text(cells[1]) : ""
            if !name.isEmpty { let primary = cells.count > 3 ? Jw64.text(cells[3]) : ""; teachers[name] = primary.isEmpty && cells.count > 4 ? Jw64.text(cells[4]) : primary }
        }
        let blocks = [1:(1,2), 2:(3,3), 3:(4,4), 4:(5,5), 6:(6,7), 7:(8,9), 8:(10,10)]
        var out: [JwCourse] = []
        for (index, row) in Jw64.select(table, "tr").enumerated() {
            guard let nodes = blocks[index], Jw64.attr(row, "bgcolor").lowercased() != "#00ccff" else { continue }
            var day = 0
            for cell in Jw64.select(row, "td") {
                if ["#00ccff", "#cccccc"].contains(Jw64.attr(cell, "bgcolor").lowercased()) { continue }
                day += 1
                for card in Jw64.select(cell, "div") where !Jw64.children(card).contains(where: { $0.tagNameNormal() == "div" }) {
                    let lines = Jw64.lines(card), name = lines.first ?? ""
                    let room = lines.count > 1 ? (Jw64.matches(#"\(([^)]*)\)"#, lines[1]).first?[1] ?? "") : ""
                    out.append(JwCourse(name: name, room: Jw64.trim(room), teacher: teachers[name] ?? "", day: day,
                                        startNode: nodes.0, endNode: nodes.1, startWeek: 1, endWeek: 20))
                }
            }
        }
        return out
    }

    private func nnutc() -> [JwCourse] {
        guard let doc = Jw64.doc(source), let body = Jw64.first(doc, "tbody") else { return [] }
        var out: [JwCourse] = []
        for row in Jw64.select(body, "tr") { for (day, cell) in Jw64.select(row, "td").enumerated() where (1...7).contains(day) {
            for card in Jw64.select(cell, "div[class]") where !Jw64.children(card).contains(where: { $0.tagNameNormal() == "div" && $0.hasAttr("class") }) {
                let labels = Jw64.select(card, "label").map(Jw64.text), icons = Jw64.select(card, "svg").map { Jw64.attr($0, "data-icon") }
                guard !labels.isEmpty, labels.count == icons.count, let rawNodes = Jw64.full(#"第([0-9,，\-]+)节"#, labels.last!)?[1] else { continue }
                let nodes = schoolNodeRanges(rawNodes), starts = icons.indices.filter { icons[$0] == "calculator" }
                for (segment, begin) in starts.enumerated() {
                    let until = segment + 1 < starts.count ? starts[segment + 1] : labels.count
                    let indices = begin..<until, teacher = indices.first { icons[$0] == "user" }.map { labels[$0] } ?? ""
                    for index in indices where icons[index] == "environment" {
                        guard let room = Jw64.full(#"([^\[]*)\[([^]]+)]"#, labels[index]) else { continue }
                        for (first, last) in nodes { for (sw, ew, type) in schoolWeekRanges(room[2], trailingParityAppliesToAll: true) {
                            out.append(JwCourse(name: labels[begin], room: Jw64.trim(room[1]), teacher: teacher, day: day,
                                                startNode: first, endNode: last, startWeek: sw, endWeek: ew, type: type))
                        } }
                    }
                }
            }
        } }
        return out
    }

    private static let gxicPeriods = [("08:40","09:20"),("09:30","10:10"),("10:30","11:10"),("11:20","12:00"),("14:30","15:10"),("15:20","16:00"),("16:10","16:50"),("17:00","17:40"),("19:40","20:20"),("20:30","21:10")]
}
