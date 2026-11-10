// Android v1.0.64 AHNUInfo fields. skcd is a length; jsz is inclusive.
import Foundation

final class JwAhmuParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }

    func generateCourseList() throws -> [JwCourse] {
        guard let rows = try JSONSerialization.jsonObject(with: Data(source.utf8)) as? [Any] else {
            throw JwParseError(message: "课程数据格式不正确")
        }
        var result: [JwCourse] = [], seen = Set<JwCourse>()
        for case let row as [String: Any] in rows {
            let name = (row["kcmc"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, let day = jw1064Integer(row["xqj"]), (1...7).contains(day),
                  let first = jw1064Integer(row["sjd"]), first > 0,
                  let length = jw1064Integer(row["skcd"]), length > 0,
                  let last = explicitScheduleEnd(first, length),
                  let from = jw1064Integer(row["qsz"]), (1...366).contains(from),
                  let to = jw1064Integer(row["jsz"]), (from...366).contains(to) else { continue }
            let course = JwCourse(name: name,
                room: (row["jsmc"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: (row["xm"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                day: day, startNode: first, endNode: last, startWeek: from, endWeek: to)
            if seen.insert(course).inserted { result.append(course) }
        }
        return result
    }

    var confidenceValue: Int {
        source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") &&
            source.contains("\"qsz\"") && source.contains("\"skcd\"") ? 90 : 0
    }
    var matchedFeatureList: [String] { confidenceValue > 0 ? ["AHNUInfo/qsz/jsz/skcd"] : [] }
}
