// Android v1.0.64 CPPU: actual lesson dates and the two-period block before @.
import Foundation
import CoreFoundation

final class JwCppuParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }

    func generateCourseList() throws -> [JwCourse] {
        guard let root = try JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any],
              let start = JwSourceCalendar.parseDate(root["startDate"] as? String) else {
            throw JwParseError(message: "缺少有效的开学日期")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let offset = (calendar.component(.weekday, from: start) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: start)!
        guard let rows = root["rows"] as? [Any] else { return [] }
        var result: [JwCourse] = [], seen = Set<JwCourse>()
        for case let row as [String: Any] in rows {
            let name = (row["KCMC"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            guard let date = JwSourceCalendar.parseDate(row["SKRQ"] as? String) else {
                throw JwParseError(message: "课程缺少有效的上课日期")
            }
            let days = calendar.dateComponents([.day], from: monday, to: date).day ?? -1
            guard (0..<(366 * 7)).contains(days), let raw = row["JC"] as? String,
                  let block = Int((raw.components(separatedBy: "@").first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
                  let nodes = explicitSchedulePair(block) else { continue }
            let credit: Float
            let value = row["XF"]
            if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { credit = 0 }
            else if let parsed = Float(jw1064String(row, "XF")), parsed.isFinite, parsed >= 0 { credit = parsed }
            else { credit = 0 }
            let course = JwCourse(name: name,
                room: (row["DDMC"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                teacher: (row["JS"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                day: (calendar.component(.weekday, from: date) + 5) % 7 + 1,
                startNode: nodes.lowerBound, endNode: nodes.upperBound,
                startWeek: days / 7 + 1, endWeek: days / 7 + 1, credit: credit)
            if seen.insert(course).inserted { result.append(course) }
        }
        return result
    }

    var confidenceValue: Int { source.contains("\"startDate\"") && source.contains("\"SKRQ\"") ? 100 : 0 }
    var matchedFeatureList: [String] { confidenceValue > 0 ? ["CPPU/startDate/SKRQ"] : [] }
}
