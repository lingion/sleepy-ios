// Android v1.0.64 studentRecordTable has six explicit fields.
import Foundation
import SwiftSoup

final class JwBfaParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }
    private lazy var body = Jw64.first(Jw64.doc(source), "#studentRecordTable tbody")

    func generateCourseList() throws -> [JwCourse] {
        guard let body else { return [] }
        var result: [JwCourse] = []
        for row in Jw64.children(body) where row.tagNameNormal() == "tr" {
            let cells = Jw64.children(row).filter { $0.tagNameNormal() == "td" }
            guard cells.count == 6 else { continue }
            let name = Jw64.text(cells[0])
            guard !name.isEmpty, let day = jw1064Integer(Jw64.text(cells[3])), (1...7).contains(day) else { continue }
            let rawRoom = Jw64.text(cells[5])
            for (first, last) in schoolNodeRanges(Jw64.text(cells[4])) {
                for (from, to, type) in schoolWeekRanges(Jw64.text(cells[2])) {
                    result.append(JwCourse(name: name, room: rawRoom == "-" ? "" : rawRoom, teacher: Jw64.text(cells[1]), day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: type))
                }
            }
        }
        return Jw64.distinct(result)
    }

    var confidenceValue: Int { body == nil ? 0 : 100 }
    var matchedFeatureList: [String] { body == nil ? [] : ["studentRecordTable"] }
}
