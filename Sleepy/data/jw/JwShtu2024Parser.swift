// Declared ShanghaiTech graduate 2024 layout, Android v1.0.64.
import Foundation

final class JwShtu2024Parser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }
    private let periods = [("08:15", "09:00"), ("09:10", "09:55"), ("10:15", "11:00"), ("11:10", "11:55"),
                           ("13:00", "13:45"), ("13:55", "14:40"), ("15:00", "15:45"), ("15:55", "16:40"),
                           ("16:50", "17:35"), ("18:00", "18:45"), ("18:55", "19:40"), ("19:50", "20:35"), ("20:45", "21:30")]
    func generateCourseList() throws -> [JwCourse] {
        WakeUpCompat.parseJzPost(source).compactMap { course in
            guard periods.indices.contains(course.startNode - 1), periods.indices.contains(course.endNode - 1) else { return nil }
            var result = course
            result.startTime = periods[course.startNode - 1].0; result.endTime = periods[course.endNode - 1].1
            return result
        }
    }
    var confidenceValue: Int { Jw64.first(Jw64.doc(source), "[id^=jsTbl_] .arrage, table.MsoNormalTable.mtt_table .arrage") != nil ? 100 : 0 }
    var matchedFeatureList: [String] { confidenceValue > 0 ? ["declared-shtu-post-2024", "arrage"] : [] }
}

extension WakeUpCompat {
    static func parseJzPost(_ source: String) -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "[id^=jsTbl_], table.MsoNormalTable.mtt_table") else { return [] }
        var out: [JwCourse] = []
        for cell in Jw64.select(table, "td[xq][jc]") {
            if Jw64.attr(cell, "style").range(of: #"display\s*:\s*none"#, options: [.regularExpression, .caseInsensitive]) != nil { continue }
            guard let day = Int(Jw64.trim(Jw64.attr(cell, "xq"))), (1...7).contains(day),
                  let node = Int(Jw64.trim(Jw64.attr(cell, "jc"))), node > 0 else { continue }
            let span = Int(Jw64.trim(Jw64.attr(cell, "rowspan"))) ?? 1
            guard span > 0, let end = explicitScheduleEnd(node, span) else { continue }
            for item in Jw64.select(cell, ".arrage") {
                let raw = Jw64.children(item).map { Jw64.text($0) }
                let fields = ["", "本", "研", "本研"].contains(raw.first ?? "") ? Array(raw.dropFirst()) : raw
                guard fields.count >= 3 else { continue }
                let name = Jw64.trim(String(fields[1].split(separator: "(", omittingEmptySubsequences: false).first ?? ""))
                guard !name.isEmpty else { continue }
                let mode = fields.count > 3 ? fields[3] : ""
                let teacher = mode == "面授讲课" ? String(fields[0].split(separator: "(", omittingEmptySubsequences: false).last ?? "").components(separatedBy: ")")[0] : fields[2]
                let room = mode == "面授讲课" ? fields[2] : mode
                let weeks = fields[0].components(separatedBy: CharacterSet(charactersIn: ",，、\\")).map { token in
                    String(token.split(separator: "(", omittingEmptySubsequences: false).first ?? "").replacingOccurrences(of: "研", with: "")
                        + (token.contains("单") ? "单" : token.contains("双") ? "双" : "")
                }.joined(separator: ",")
                for token in weeks.replacingOccurrences(of: "周", with: "").components(separatedBy: CharacterSet(charactersIn: ",，;；")) {
                    let numbers = Jw64.matches(#"[0-9]+"#, token).compactMap { Int($0[0]) }
                    guard let from = numbers.first else { continue }
                    let to = numbers.count > 1 ? numbers[1] : from
                    let parity = token.contains("单") ? 1 : token.contains("双") ? 2 : 0
                    guard from > 0, to >= from else { continue }
                    out.append(JwCourse(name: name, room: room, teacher: teacher, day: day,
                                        startNode: node, endNode: end, startWeek: from, endWeek: to, type: parity))
                }
            }
        }
        return out
    }
}
