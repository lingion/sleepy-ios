// Android v1.0.64 curriculum items are isolated within each weekday cell.
import Foundation
import SwiftSoup

final class JwCnuParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }
    private lazy var tables = Jw64.select(Jw64.doc(source), "tbody").filter { Jw64.first($0, ".curriculum-item") != nil }

    func generateCourseList() throws -> [JwCourse] {
        var result: [JwCourse] = []
        for table in tables {
            for row in Jw64.children(table) where row.tagNameNormal() == "tr" {
                let cells = Jw64.children(row).filter { $0.tagNameNormal() == "td" }
                let gutters: Int
                switch cells.count { case 8: gutters = 1; case 9: gutters = 2; default: continue }
                for (index, cell) in cells.enumerated() {
                    let day = index - gutters + 1
                    guard (1...7).contains(day) else { continue }
                    let items = Jw64.select(cell, ".curriculum-item").filter { item in
                        var parent = item.parent()
                        while let node = parent, node !== cell {
                            if node.hasClass("curriculum-item") { return false }
                            parent = node.parent()
                        }
                        return true
                    }
                    for item in items {
                        let fields = Jw64.select(item, "div")
                        guard fields.count == 5 else { continue }
                        let name = jw1064Text(item, "span").components(separatedBy: " 查看更多").first.map(Jw64.trim) ?? ""
                        guard !name.isEmpty, let timing = Jw64.full(#"(.+)周\[([^\[\]]+)节]"#, Jw64.text(fields[3])) else { continue }
                        let weeks = schoolWeekRanges(timing[1]), nodes = schoolNodeRanges(timing[2])
                        for (from, to, type) in weeks {
                            for (first, last) in nodes {
                                result.append(JwCourse(name: name, room: Jw64.text(fields[4]), teacher: Jw64.text(fields[2]), day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: type))
                            }
                        }
                    }
                }
            }
        }
        return mergeCourseWeeks(result)
    }

    var confidenceValue: Int { tables.isEmpty ? 0 : 100 }
    var matchedFeatureList: [String] { tables.isEmpty ? [] : ["CNU/curriculum-item"] }
}
