// 拾光桥课程合同：ShiGuangSchedule/shiguang_warehouse (MIT，星河欲转)。
// JS 只传输原始课程 JSON，节次/周次解码的唯一落点在此。
import Foundation
import CoreFoundation

final class JwSgAssetParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }

    private var rows: [[String: Any]] {
        let text: String
        if let root = JwSgSourceMetadata.object(source) {
            guard root["sleepySgAsset"] as? Bool == true, let courses = root["coursesJson"] as? String else { return [] }
            text = courses
        } else { text = source }
        guard let data = text.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return array.compactMap { $0 as? [String: Any] }
    }

    private func integer(_ value: Any?) -> Int? {
        if let string = value as? String { return Int(string) }
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue else { return nil }
        return Int(exactly: number.doubleValue)
    }

    func generateCourseList() throws -> [JwCourse] {
        var result: [JwCourse] = []
        for row in rows {
            let name = (row["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let customTime = row["isCustomTime"] as? Bool == true || row["isCustomTime"] as? String == "true"
            let startTime = customTime ? (row["customStartTime"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            let endTime = customTime ? (row["customEndTime"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if customTime && !JwCourse.isValidTimeRange(startTime, endTime) { continue }
            let start = integer(row["startSection"]) ?? (customTime ? 1 : 0)
            let end = integer(row["endSection"]) ?? (customTime ? start : 0)
            guard !name.isEmpty, let day = integer(row["day"]), (1...7).contains(day),
                  start > 0, end >= start else { continue }
            let rawCredit = (row["credit"] as? NSNumber)?.floatValue ?? Float(row["credit"] as? String ?? "") ?? 0
            let credit: Float = rawCredit.isFinite ? rawCredit : 0
            let weeks = Array(Set((row["weeks"] as? [Any] ?? []).compactMap { integer($0) }.filter { $0 > 0 })).sorted()
            guard let first = weeks.first, let last = weeks.last else { continue }
            let room = (row["position"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let teacher = (row["teacher"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            func append(_ a: Int, _ b: Int, _ type: Int) {
                result.append(JwCourse(name: name, room: room, teacher: teacher, day: day,
                                       startNode: start, endNode: end, startWeek: a, endWeek: b, type: type,
                                       startTime: startTime, endTime: endTime, credit: credit))
            }
            // 只有完整步长 2 的集合才压成单双周；[1,5] 不能凭空补出第 3 周。
            if weeks.count > 1 && zip(weeks, weeks.dropFirst()).allSatisfy({ $0.1 - $0.0 == 2 }) {
                append(first, last, first % 2 == 1 ? 1 : 2)
            } else {
                var a = first
                var b = first
                for week in weeks.dropFirst() {
                    if week - b == 1 { b = week }
                    else { append(a, b, 0); a = week; b = week }
                }
                append(a, b, 0)
            }
        }
        return result
    }

    var confidenceValue: Int {
        rows.contains { $0["name"] is String && $0["weeks"] is [Any]
            && integer($0["day"]) != nil && integer($0["startSection"]) != nil
            && integer($0["endSection"]) != nil } ? 90 : 0
    }
    var matchedFeatureList: [String] { confidenceValue > 0 ? ["sg-asset-courses-json"] : [] }
}
