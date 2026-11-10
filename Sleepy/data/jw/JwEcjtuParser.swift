// Android v1.0.64 table_border preserves sparse periods and logical day columns.
import Foundation
import SwiftSoup

final class JwEcjtuParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }
    private lazy var table = Jw64.first(Jw64.doc(source), "table.table_border")

    func generateCourseList() throws -> [JwCourse] {
        guard let table, let rows = legacyDhuEcjtuRows(table) else { return [] }
        var result: [JwCourse] = []
        for row in rows {
            if Jw64.text(row.first(where: { $0.column == 0 })?.element) == "节次" { continue }
            for cell in row where (1...7).contains(cell.column) && cell.columnSpan == 1 {
                let lines = Jw64.lines(cell.element).filter { !$0.isEmpty }
                var blockStart = 0
                for (index, line) in lines.enumerated() {
                    if line.contains("@") || index == blockStart { continue }
                    let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                    let previous = lines[index - 1]
                    let looksLikeSchedule = previous.contains("@") || ((2...3).contains(fields.count) && fields.last?.contains(where: \.isNumber) == true)
                    guard looksLikeSchedule else { continue }
                    let name = lines[blockStart], oldStart = blockStart
                    blockStart = index + 1
                    guard (2...3).contains(fields.count), !name.isEmpty, !name.contains("@") else { continue }
                    let weeks = schoolWeekRanges(fields[fields.count - 2]), nodes = schoolNodeRanges(fields[fields.count - 1])
                    guard !weeks.isEmpty, !nodes.isEmpty else { continue }
                    let teacher: String, room: String
                    if fields.count == 3 { teacher = fields[0]; room = "" }
                    else if index > oldStart + 1, let at = previous.firstIndex(of: "@") {
                        teacher = Jw64.trim(String(previous[..<at])); room = Jw64.trim(String(previous[previous.index(after: at)...]))
                    } else { teacher = ""; room = "" }
                    for (first, last) in nodes {
                        for (from, to, type) in weeks {
                            result.append(JwCourse(name: name, room: room, teacher: teacher, day: cell.column, startNode: first, endNode: last, startWeek: from, endWeek: to, type: type))
                        }
                    }
                }
            }
        }
        return mergeCourseWeeks(result)
    }

    var confidenceValue: Int { table == nil ? 0 : 90 }
    var matchedFeatureList: [String] { table == nil ? [] : ["ECJTU/table_border"] }
}
