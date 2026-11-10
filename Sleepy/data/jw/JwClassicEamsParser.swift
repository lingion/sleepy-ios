// Exact TaskActivity semantics from Android v1.0.64.
import Foundation

final class JwClassicEamsParser: JwParser, JwParserConfidenceReporting {
    let source: String
    private let transformWeekBitmap: (String) -> String
    init(_ source: String, transformWeekBitmap: @escaping (String) -> String = { $0 }) {
        self.source = source
        self.transformWeekBitmap = transformWeekBitmap
    }
    struct Activity {
        let name: String, teacher: String, room: String
        let weeks: [Int]
        let indices: [(Int, Int)]
    }
    private struct Task {
        let teacher: String, name: String, room: String
        let weeks: [Int]
        let blockStart: Int
        let nameExpr: String?
    }
    func decodedActivities(defaultUnitCount: Int? = nil) -> [Activity] {
        guard let count = unitCountFromPage() ?? defaultUnitCount, count > 0 else { return [] }
        return blocks(count).compactMap { task, indices in
            let name = resolveCourseName(task)
            guard task.teacher != "-1", task.room != "停课", !Jw64.trim(name).isEmpty else { return nil }
            return Activity(name: name, teacher: task.teacher, room: task.room, weeks: task.weeks, indices: indices)
        }
    }
    func generateCourseList() throws -> [JwCourse] {
        if !source.containsMatch(#"new\s+TaskActivity\("#), source.contains("newActivity("), source.contains("addActivityByTime(") {
            return try JwEcuplScriptParser(source).generateCourseList()
        }
        var out: [JwCourse] = []
        for activity in decodedActivities() {
            for (day, first, last) in mergeConsecutiveNodes(activity.indices) {
                for week in activity.weeks {
                    out.append(JwCourse(name: activity.name, room: activity.room, teacher: activity.teacher,
                                        day: day, startNode: first, endNode: last, startWeek: week, endWeek: week))
                }
            }
        }
        return out
    }
    private func unitCountFromPage() -> Int? {
        Jw64.matches(#"\bvar\s+unitCount\s*=\s*(\d+)\s*;"#, source).first.flatMap { Int($0[1]) }
    }
    private func blocks(_ unitCount: Int) -> [(Task, [(Int, Int)])] {
        let ns = source as NSString
        let matches = regex(#"new\s+TaskActivity\("#, source)
        var result: [(Task, [(Int, Int)])] = []
        for (i, match) in matches.enumerated() {
            let (args, close) = splitArgs(ns, NSMaxRange(match.range))
            guard args.count >= 7, close >= 0 else { continue }
            let rawTeacher = Jw64.trim(args[1])
            let teacher = !isQuoted(rawTeacher) && rawTeacher.contains("join(")
                ? resolveTeachersFromActTeachers(match.range.location) : unquote(rawTeacher)
            let bitmap = transformWeekBitmap(unquote(args[6]))
            guard !bitmap.isEmpty, bitmap.allSatisfy({ $0 == "0" || $0 == "1" }) else { continue }
            let weeks = bitmap.enumerated().compactMap { $0.offset > 0 && $0.element == "1" ? $0.offset : nil }
            guard !weeks.isEmpty else { continue }
            let nameArg = args[3]
            let task = Task(teacher: Jw64.trim(teacher), name: isQuoted(nameArg) ? unquote(nameArg) : "",
                            room: Jw64.trim(unquote(args[5])), weeks: weeks, blockStart: match.range.location,
                            nameExpr: isQuoted(nameArg) ? nil : Jw64.trim(nameArg))
            let end = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let tail = ns.substring(with: NSRange(location: NSMaxRange(match.range), length: end - NSMaxRange(match.range)))
            var indices: [(Int, Int)] = []
            for m in Jw64.matches(#"index\s*=\s*(?:(\d+)\s*\*\s*(unitCount|\d+)\s*\+\s*(\d+)|(\d+))\s*;"#, tail) {
                if let day = Int(m[1]), let node = Int(m[3]) {
                    if m[2] == "unitCount" {
                        if (0..<7).contains(day), (0..<unitCount).contains(node) { indices.append((day, node)) }
                    } else if let stride = Int64(m[2]), stride > 0,
                              let d = Int64(m[1]), let n = Int64(m[3]) {
                        let product = d.multipliedReportingOverflow(by: stride)
                        let linear = product.partialValue.addingReportingOverflow(n)
                        if !product.overflow, !linear.overflow, linear.partialValue >= 0,
                           linear.partialValue / Int64(unitCount) < 7 {
                            indices.append((Int(linear.partialValue / Int64(unitCount)), Int(linear.partialValue % Int64(unitCount))))
                        }
                    }
                } else if let linear = Int(m[4]), linear >= 0, linear / unitCount < 7 {
                    indices.append((linear / unitCount, linear % unitCount))
                }
            }
            if !indices.isEmpty { result.append((task, indices)) }
        }
        return result
    }
    private func regex(_ pattern: String, _ text: String) -> [NSTextCheckingResult] {
        (try? NSRegularExpression(pattern: pattern).matches(in: text, range: NSRange(text.startIndex..., in: text))) ?? []
    }
    private func splitArgs(_ source: NSString, _ start: Int) -> ([String], Int) {
        var args: [String] = [], buffer: [UInt16] = [], quote: UInt16?, depth = 0, i = start, close = -1
        while i < source.length {
            let ch = source.character(at: i)
            if let active = quote {
                if ch == active, !isEscaped(source, i) { quote = nil }
                buffer.append(ch)
            } else if ch == 34 || ch == 39 { quote = ch; buffer.append(ch) }
            else if ch == 40 { depth += 1; buffer.append(ch) }
            else if ch == 41 {
                if depth == 0 { close = i; break }
                depth -= 1; buffer.append(ch)
            } else if ch == 44, depth == 0 {
                args.append(Jw64.trim(String(decoding: buffer, as: UTF16.self))); buffer = []
            } else { buffer.append(ch) }
            i += 1
        }
        if !buffer.isEmpty || !args.isEmpty { args.append(Jw64.trim(String(decoding: buffer, as: UTF16.self))) }
        return (args, close)
    }
    private func isEscaped(_ source: NSString, _ offset: Int) -> Bool {
        var count = 0, i = offset - 1
        while i >= 0, source.character(at: i) == 92 { count += 1; i -= 1 }
        return count % 2 == 1
    }
    private func resolveTeachersFromActTeachers(_ start: Int) -> String {
        let preceding = (source as NSString).substring(to: start)
        guard let array = Jw64.matches(#"var\s+actTeachers\s*=\s*\[([^\]]*)\]\s*;"#, preceding).last else { return "" }
        return Jw64.matches(#"(?:["']name["']|\bname)\s*:\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')"#, array[1])
            .map { unquote($0[1]) }.filter { !Jw64.trim($0).isEmpty }.joined(separator: "/")
    }
    private func resolveCourseName(_ task: Task) -> String {
        if !Jw64.trim(task.name).isEmpty { return task.name }
        guard task.nameExpr?.contains("courseNameLessonNo") == true else { return "" }
        let pattern = #"var\s+courseNameLessonNo\s*=\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')\s*;"#
        let ns = source as NSString
        if let preceding = Jw64.matches(pattern, ns.substring(to: task.blockStart)).last { return unquote(preceding[1]) }
        let rest = ns.substring(from: task.blockStart)
        let next = regex(#"new\s+TaskActivity\("#, rest).dropFirst().first?.range.location ?? (rest as NSString).length
        return Jw64.matches(pattern, (rest as NSString).substring(to: next)).first.map { unquote($0[1]) } ?? ""
    }
    private func mergeConsecutiveNodes(_ pairs: [(Int, Int)]) -> [(Int, Int, Int)] {
        var out: [(Int, Int, Int)] = []
        for day in Set(pairs.map(\.0)).sorted() {
            let nodes = Set(pairs.filter { $0.0 == day }.map { $0.1 + 1 }).sorted()
            guard var start = nodes.first else { continue }
            var end = start
            for node in nodes.dropFirst() {
                if node == end + 1 { end = node }
                else { out.append((day + 1, start, end)); start = node; end = node }
            }
            out.append((day + 1, start, end))
        }
        return out
    }
    private func isQuoted(_ value: String) -> Bool { value.count >= 2 && (value.first == "\"" || value.first == "'") && value.first == value.last }
    private func unquote(_ value: String) -> String {
        let raw = Jw64.trim(value)
        guard isQuoted(raw) else { return raw }
        if raw.first == "\"", let parsed = Jw64.json(raw) as? String { return parsed }
        let inner = Array(raw.dropFirst().dropLast().utf16)
        var result: [UInt16] = [], i = 0
        while i < inner.count {
            if inner[i] != 92 { result.append(inner[i]); i += 1; continue }
            i += 1
            guard i < inner.count else { return "" }
            let escaped = inner[i]
            if escaped == 117, i + 4 < inner.count,
               let code = UInt16(String(decoding: inner[(i + 1)...(i + 4)], as: UTF16.self), radix: 16) { result.append(code); i += 5; continue }
            result.append([UInt16(98): 8, 102: 12, 110: 10, 114: 13, 116: 9][escaped] ?? escaped); i += 1
        }
        return String(decoding: result, as: UTF16.self)
    }
    var confidenceValue: Int {
        let unit = unitCountFromPage() != nil
        if source.contains("manualArrangeCourseTable"), source.contains("new TaskActivity(") { return unit ? 95 : 90 }
        return source.contains("new TaskActivity(") ? (unit ? 70 : 55) : 0
    }
    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("manualArrangeCourseTable") { out.append("table#manualArrangeCourseTable") }
        if source.contains("new TaskActivity(") { out.append("new TaskActivity(...)") }
        if unitCountFromPage() != nil { out.append("var unitCount = N") }
        if source.contains("marshalTable") { out.append("table0.marshalTable") }
        if source.contains("courseTableForStd") { out.append("courseTableForStd") }
        return out
    }
}

private extension String {
    func containsMatch(_ regex: String) -> Bool { range(of: regex, options: .regularExpression) != nil }
}
