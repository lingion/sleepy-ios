// Android v1.0.64 semester grid: empty rows still reserve their period.
import Foundation
import SwiftSoup

final class JwAicParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }

    private lazy var table: Element? = {
        guard let pattern = try? NSRegularExpression(pattern: #"<table\b[^>]*\bid\s*=\s*(?:"table"|'table'|table(?=[\s>]))[^>]*>"#, options: .caseInsensitive) else { return nil }
        let text = source as NSString
        let starts = pattern.matches(in: source, range: NSRange(location: 0, length: text.length))
        for (index, start) in starts.enumerated() {
            let end = index + 1 < starts.count ? starts[index + 1].range.location : text.length
            let fragment = text.substring(with: NSRange(location: start.range.location, length: end - start.range.location))
            if fragment.contains("getScheduleNew.do"), let table = Jw64.first(Jw64.doc(fragment), "table#table") { return table }
        }
        return nil
    }()

    func generateCourseList() throws -> [JwCourse] {
        guard let table else { throw JwParseError(message: "请选择学期课表后再导入") }
        var result: [JwCourse] = []
        for (node, row) in Jw64.rows(table).enumerated() where (1...EXPLICIT_SCHEDULE_RESOURCE_BOUND).contains(node) {
            let cells = Jw64.children(row).filter { $0.tagNameNormal() == "td" }
            for (day, cell) in cells.enumerated() where (1...7).contains(day) {
                for item in Jw64.select(cell, ".courseInfo") {
                    let name = Jw64.text(Jw64.children(item).first)
                    guard !name.isEmpty else { continue }
                    guard let weekDetail = Jw64.first(item, ".weekDetail") else { throw JwParseError(message: "请选择学期课表后再导入") }
                    for (from, to, type) in schoolWeekRanges(Jw64.text(weekDetail)) {
                        result.append(JwCourse(name: name, room: jw1064Text(item, ".place"), teacher: jw1064Text(item, ".teacher"), day: day, startNode: node, endNode: node, startWeek: from, endWeek: to, type: type))
                    }
                }
            }
        }
        return Jw64.distinct(result)
    }

    var confidenceValue: Int { table == nil ? 0 : 100 }
    var matchedFeatureList: [String] { table == nil ? [] : ["table/getScheduleNew.do"] }
}
