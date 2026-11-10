import Foundation
import SwiftSoup

/// Each lay-tips attribute contains one labelled NTSS lesson table.
final class JwCfNewHtmlParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }
    private var tips: [String] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        return jw1064Elements(doc, "[lay-tips]").map { jw1064Attribute($0, "lay-tips") }.filter { $0.contains("上课任务[") }
    }
    func generateCourseList() -> [JwCourse] {
        var courses: [JwCourse] = []
        for tip in tips {
            guard let doc = try? SwiftSoup.parse(tip) else { continue }
            let labels = jw1064Elements(doc, "th"), values = jw1064Elements(doc, "td")
            guard labels.count == values.count else { continue }
            var fields: [String: String] = [:]
            for index in labels.indices {
                var label = jw1064Text(labels[index])
                if label.hasSuffix("：") || label.hasSuffix(":") { label.removeLast() }
                fields[label] = jw1064Text(values[index])
            }
            let rawName = fields["课程"] ?? ""
            let suffix = rawName.range(of: "]").map { String(rawName[$0.upperBound...]) } ?? rawName
            let name = suffix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? rawName : suffix
            guard let day = jw1064Integer(fields["星期"]), (1...7).contains(day), !name.isEmpty,
                  let nodes = jw1064Matches(#"^第?\s*([0-9]+)(?:\s*-\s*([0-9]+))?\s*节$"#, fields["节次"] ?? "").first,
                  let first = jw1064Integer(nodes[1]), let last = jw1064Integer(nodes[2].isEmpty ? nodes[1] : nodes[2]), first > 0, last >= first else { continue }
            let weeks = schoolWeekRanges(fields["上课周次"] ?? "")
            for (from, to, parity) in weeks {
                courses.append(JwCourse(name: name, room: fields["教学场地"] ?? "", teacher: fields["授课教师"] ?? "",
                                        day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: parity))
            }
        }
        var seen = Set<JwCourse>()
        return courses.filter { seen.insert($0).inserted }
    }
    var confidenceValue: Int { tips.isEmpty ? 0 : 100 }
    var matchedFeatureList: [String] { tips.isEmpty ? [] : ["lay-tips", "上课任务["] }
}
