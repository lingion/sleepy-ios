// Android v1.0.64 serialized fields. _nodesLi is not an authoritative schedule field.
import Foundation

final class JwFstvcParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }

    func generateCourseList() throws -> [JwCourse] {
        guard let rows = try JSONSerialization.jsonObject(with: Data(source.utf8)) as? [Any] else {
            throw JwParseError(message: "课程数据格式不正确")
        }
        var result: [JwCourse] = [], seen = Set<JwCourse>()
        for case let row as [String: Any] in rows {
            let name = (row["kcmc"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let week = jw1064Integer(row["zc"]), (1...366).contains(week),
                  let day = jw1064Integer(row["xqs"]), (1...7).contains(day), let nodes = row["jcshow"] as? String else { continue }
            for (first, last) in schoolNodeRanges(nodes) {
                let course = JwCourse(name: name,
                    room: (row["skcdmc"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    teacher: (row["skjsxm"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    day: day, startNode: first, endNode: last, startWeek: week, endWeek: week,
                    note: (row["sknl"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
                if seen.insert(course).inserted { result.append(course) }
            }
        }
        return result
    }

    var confidenceValue: Int { source.contains("\"jcshow\"") && source.contains("\"xqs\"") ? 100 : 0 }
    var matchedFeatureList: [String] { confidenceValue > 0 ? ["FSTVC/jcshow/zc/xqs"] : [] }
}
