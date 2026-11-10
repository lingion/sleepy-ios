// Android v1.0.64 CCIBE ResponseData and complete per-week collector envelopes.
import Foundation

final class JwCcibeParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }

    func generateCourseList() throws -> [JwCourse] {
        guard let root = try JSONSerialization.jsonObject(with: Data(source.utf8)) as? [String: Any] else {
            throw JwParseError(message: "课表数据格式不正确")
        }
        var result: [JwCourse] = [], seen = Set<JwCourse>()
        for (rows, requestWeek) in try pages(root) {
            for case let row as [String: Any] in rows {
                let name = (row["kcmc"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let rawDay = jw1064String(row, "xqj")
                let dayText = rawDay.replacingOccurrences(of: "七", with: "日").replacingOccurrences(of: "天", with: "日")
                guard !name.isEmpty, rawDay.count == 1,
                      let dayIndex = Array("一二三四五六日").firstIndex(of: Character(dayText)),
                      let from = requestWeek ?? jw1064Integer(row["qsz"]), (1...366).contains(from),
                      let to = requestWeek ?? jw1064Integer(row["jsz"]), (from...366).contains(to) else { continue }
                for (first, last) in schoolNodeRanges(jw1064String(row, "jc")) {
                    let course = JwCourse(name: name,
                        room: (row["jxdd"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        teacher: (row["jsxm"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        day: dayIndex + 1, startNode: first, endNode: last, startWeek: from, endWeek: to)
                    if seen.insert(course).inserted { result.append(course) }
                }
            }
        }
        return result
    }

    private func pages(_ root: [String: Any]) throws -> [([Any], Int?)] {
        guard root.keys.contains("weeks") else {
            return (root["wdkb"] as? [Any]).map { [($0, nil)] } ?? []
        }
        guard let calendar = root["calendar"] as? [String: Any] else { throw JwParseError(message: "缺少学期日历") }
        guard let count = jw1064Integer(calendar["allWeek"]), (1...366).contains(count) else {
            throw JwParseError(message: "缺少有效的学期周数")
        }
        guard let id = calendar["id"] as? String, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw JwParseError(message: "缺少学期标识")
        }
        guard let pages = root["weeks"] as? [Any] else { throw JwParseError(message: "逐周课表格式不正确") }
        guard pages.count == count else { throw JwParseError(message: "逐周课表不完整") }
        var seen = Set<Int>(), result: [([Any], Int?)] = []
        for value in pages {
            guard let page = value as? [String: Any], let week = jw1064Integer(page["week"]), (1...count).contains(week) else {
                throw JwParseError(message: "课表周次无效")
            }
            guard seen.insert(week).inserted else { throw JwParseError(message: "逐周课表包含重复周次") }
            guard let data = page["data"] as? [String: Any] else { throw JwParseError(message: "缺少逐周课表数据") }
            if let ownCalendar = data["calendar"] as? [String: Any], (ownCalendar["id"] as? String ?? ownCalendar["id"].map { String(describing: $0) } ?? "") != id {
                throw JwParseError(message: "逐周课表学期不一致")
            }
            guard let rows = data["wdkb"] as? [Any] else { throw JwParseError(message: "缺少课程数组") }
            result.append((rows, week))
        }
        return result
    }

    var confidenceValue: Int { source.contains("\"wdkb\"") && source.contains("\"calendar\"") ? 100 : 0 }
    var matchedFeatureList: [String] { confidenceValue > 0 ? ["CCIBE/calendar/wdkb"] : [] }
}
