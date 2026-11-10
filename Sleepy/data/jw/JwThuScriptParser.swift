// Android v1.0.64 THU script records and explicitly captured semester calendar.
import Foundation
import CoreFoundation
import SwiftSoup

final class JwThuScriptParser: JwParser, JwParserConfidenceReporting {
    let source: String
    private let semesterDataJson: String?
    private(set) var skippedCourseCount = 0
    init(_ source: String, _ semesterDataJson: String? = nil) { self.source = source; self.semesterDataJson = semesterDataJson }
    static func validSemesterData(_ raw: String) -> Bool { JwThuScriptParser("", raw).semester() != nil }
    private struct Move: Hashable { var week: Int; var day: Int; var targetWeek = 0; var targetDay = 0 }
    private struct Semester { var weeks = 16; var moves: [Move] = [] }
    private struct Metadata: Hashable { var name = ""; var id = ""; var teacher = ""; var note = "" }
    private struct Pending { var id = ""; var name = ""; var params: [String] = []; var room = ""; var weeks = ""; var time = ""; var special = false }
    private struct Coordinate: Hashable { var week: Int; var day: Int }
    private let starts = [0, 1, 3, 6, 8, 10, 12], ends = [0, 2, 5, 7, 9, 11, 14]
    private let courseKinds: Set<String> = ["任选","专必","通必","公共基础必修课","学科基础必修课","公共基础选修课","学科基础选修课","限选","实践","实践选修","必修课","选修课","必修","选修","专基","专选","公必","公选","义修","选","必","主干","专限","公基","值班","通选","思政必","思政选","自基必","自基选","语技必","语技选","体育必","体育选","专业基础课","双创必","双创选","新生必","新生选","学科必修","学科选修","通识必修","通识选修","公共基础","第二课堂","学科实践","专业实践","专业必修","辅修","专业选修","外语","方向","专业必修课","全选","专业","学必","学选"]
    var confidenceValue: Int { source.contains("function setInitValue") && source.contains("getElementById") ? 100 : 0 }
    var matchedFeatureList: [String] { confidenceValue > 0 ? ["thu:script-records"] : [] }

    func generateCourseList() throws -> [JwCourse] {
        skippedCourseCount = 0
        guard let semester = semester() else { return [] }
        let scripts = Jw64.select(Jw64.doc(source), "script")
        let script = Self.withoutComments(scripts.isEmpty ? source : scripts.map { $0.data() }.joined(separator: "\n"))
        let metadata = metadata(script)
        guard let start = script.range(of: #"function\s+setInitValue\s*\(\s*\)"#, options: .regularExpression) else { return [] }
        let rest = String(script[start.lowerBound...]), block = rest.range(of: #"Event\.observe"#, options: .regularExpression).map { String(rest[..<$0.lowerBound]) } ?? rest
        let matches = jw1064Matches(#"(strHTML1|strHTML)\s*(\+=|=)\s*("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|(?:document\.)?getElementById\(\s*['"]a([1-6])_([1-7])['"]\s*\)\.innerHTML\s*\+=\s*strHTML"#, block)
        var result: [JwCourse] = [], found: [String: Pending] = [:], pending = Pending(), active = false, inherited = false
        for match in matches {
            if !match[4].isEmpty {
                if active {
                    if let emitted = emit(pending, Int(match[4])!, Int(match[5])!, metadata, semester) { result += emitted; if !pending.id.isEmpty { found[pending.id] = pending } }
                    else { skippedCourseCount += 1 }
                }
                pending = Pending(); active = false; inherited = false; continue
            }
            guard let value = Self.decode(match[3]) else { continue }
            if match[1] == "strHTML1" {
                if !pending.name.isEmpty {
                    if inherited { pending.params = []; inherited = false }
                    var text = Jw64.plain(value); while text.hasPrefix("；") || text.hasPrefix(";") { text.removeFirst() }
                    pending.params.append(Jw64.trim(text))
                }
                continue
            }
            if value.contains("blue_red_none") {
                if active { skippedCourseCount += 1 }
                pending = Pending(id: Self.identifier(value), special: true); active = true; inherited = false
                let fonts = Jw64.select(Jw64.doc(value), "font[color=blue]")
                pending.name = fonts.first.map(Jw64.text) ?? ""
                let detail = (fonts.count > 1 ? Jw64.text(fonts[1]) : "").replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
                guard let bracket = detail.firstIndex(of: "("), detail.hasSuffix(")") else { continue }
                let prefix = Jw64.trim(String(detail[..<bracket])), pieces = String(detail[detail.index(after: bracket)...].dropLast()).components(separatedBy: CharacterSet(charactersIn: "；;")).map(Jw64.trim)
                var rooms: [String] = []
                for piece in pieces {
                    if piece.contains("周") { pending.weeks = piece }
                    else if piece.hasPrefix("时间：") || piece.hasPrefix("时间:") { pending.time = String(piece.dropFirst(3)) }
                    else if !piece.isEmpty { rooms.append(piece) }
                }
                pending.room = rooms.joined(separator: "；") + (prefix.isEmpty ? "" : "(\(prefix))")
            } else if value.contains("<a ") {
                if active { skippedCourseCount += 1 }
                let id = Self.identifier(value); pending = found[id] ?? Pending(id: id); active = true; inherited = found[id] != nil
            } else if value.contains("<b>") { pending.name = Jw64.text(Jw64.first(Jw64.doc(value), "b")) }
            else if match[2] == "=" && Jw64.trim(value).isEmpty { if active { skippedCourseCount += 1 }; pending = Pending(); active = false }
        }
        if active { skippedCourseCount += 1 }
        return Jw64.distinct(result)
    }

    private func emit(_ pending: Pending, _ big: Int, _ day: Int, _ metadata: [Metadata], _ semester: Semester) -> [JwCourse]? {
        guard !pending.name.isEmpty else { return nil }
        let byId = Set(metadata.filter { !pending.id.isEmpty && $0.id == pending.id }), byName = Set(metadata.filter { $0.name == pending.name })
        let info = byId.count == 1 ? byId.first! : byName.count == 1 ? byName.first! : Metadata()
        var teacher = info.teacher, room = pending.room, weekText = pending.weeks
        if !pending.special {
            guard let index = pending.params.lastIndex(where: { knownWeeks($0, semester.weeks) != nil }) else { return nil }
            weekText = pending.params[index]; room = pending.params.dropFirst(index + 1).filter { !$0.isEmpty }.joined(separator: "；")
            let before = pending.params.prefix(index).filter { !courseKinds.contains($0) && !$0.isEmpty }
            if !before.isEmpty { teacher = before.joined(separator: "；") }
        }
        guard let weeks = knownWeeks(weekText, semester.weeks) else { return nil }
        var startTime = "", endTime = ""
        if !pending.time.isEmpty {
            let pieces = pending.time.replacingOccurrences(of: "：", with: ":").replacingOccurrences(of: "～", with: "-").replacingOccurrences(of: "~", with: "-").components(separatedBy: "-")
            guard pieces.count == 2, let first = Self.clock(pieces[0]), let last = Self.clock(pieces[1]), JwCourse.isValidTimeRange(first, last) else { return nil }
            startTime = first; endTime = last
        }
        func course(_ first: Int, _ last: Int, _ parity: Int, _ day: Int) -> JwCourse { JwCourse(name: pending.name, room: room, teacher: teacher, day: day, startNode: starts[big], endNode: ends[big], startWeek: first, endWeek: last, type: parity, startTime: startTime, endTime: endTime, note: info.note) }
        if semester.moves.isEmpty { return weekSlots(weekText, semester.weeks)?.map { course($0.0, $0.1, $0.2, day) } }
        let original = Set(weeks.map { Coordinate(week: $0, day: day) }), destinations = Set(semester.moves.filter { $0.targetWeek > 0 }.map { Coordinate(week: $0.targetWeek, day: $0.targetDay) })
        let moves = Dictionary(uniqueKeysWithValues: semester.moves.map { (Coordinate(week: $0.week, day: $0.day), $0) })
        var occurrences = Set(original.filter { !destinations.contains($0) && moves[$0] == nil })
        for (coordinate, move) in moves where original.contains(coordinate) && move.targetWeek > 0 { occurrences.insert(Coordinate(week: move.targetWeek, day: move.targetDay)) }
        let groups = Dictionary(grouping: occurrences, by: \.day)
        return groups.keys.sorted().flatMap { day in Self.contiguous(groups[day]!.map(\.week)).map { course($0.0, $0.1, 0, day) } }
    }

    private func weekSlots(_ raw: String, _ count: Int) -> [(Int, Int, Int)]? {
        let slots: [(Int, Int, Int)]
        switch Jw64.trim(raw) {
        case "全周": slots = [(1, count, 0)]
        case "前八周": slots = [(1, min(8, count), 0)]
        case "后八周": slots = count >= 9 ? [(9, count, 0)] : []
        case "单周": slots = [(1, count, 1)]
        case "双周": slots = count >= 2 ? [(2, count, 2)] : []
        default: slots = schoolWeekRanges(Jw64.trim(raw), trailingParityAppliesToAll: true)
        }
        let result = slots.compactMap { first, last, parity -> (Int, Int, Int)? in let adjusted = parity != 0 && first % 2 != parity % 2 ? first + 1 : first; return adjusted <= last ? (adjusted, last, parity) : nil }
        return result.isEmpty ? nil : result
    }
    private func knownWeeks(_ raw: String, _ count: Int) -> [Int]? {
        guard let ranges = weekSlots(raw, count) else { return nil }
        return Array(Set(ranges.flatMap { first, last, parity in (first...last).filter { parity == 0 || $0 % 2 == parity % 2 } })).sorted()
    }
    private static func contiguous(_ values: [Int]) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for value in Set(values).sorted() { if let last = result.last, last.1 + 1 == value { result[result.count - 1] = (last.0, value) } else { result.append((value, value)) } }
        return result
    }
    private func semester() -> Semester? {
        guard let raw = semesterDataJson else { return Semester() }
        guard let root = Jw64.json(raw) as? [String: Any] else { return nil }
        func integer(_ value: Any?) -> Int? { guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite, number.doubleValue == number.doubleValue.rounded(), number.doubleValue >= Double(Int32.min), number.doubleValue <= Double(Int32.max) else { return nil }; return number.intValue }
        let count: Int
        if root["weekCount"] == nil || root["weekCount"] is NSNull { count = 16 } else { guard let value = integer(root["weekCount"]) else { return nil }; count = value }
        guard (1...366).contains(count) else { return nil }
        let rows: [Any]
        if root["reschedule"] == nil || root["reschedule"] is NSNull { rows = [] } else { guard let value = root["reschedule"] as? [Any] else { return nil }; rows = value }
        var moves: [Move] = []
        for value in rows {
            guard let row = value as? [Any], row.count == 2 || row.count == 4, let week = integer(row[0]), let day = integer(row[1]), (1...366).contains(week), (1...7).contains(day) else { return nil }
            var move = Move(week: week, day: day)
            if row.count == 4 { guard let targetWeek = integer(row[2]), let targetDay = integer(row[3]), (targetWeek == 0 && targetDay == 0) || ((1...366).contains(targetWeek) && (1...7).contains(targetDay)) else { return nil }; move.targetWeek = targetWeek; move.targetDay = targetDay }
            if moves.contains(where: { $0.week == week && $0.day == day && $0 != move }) { return nil }
            if !moves.contains(move) { moves.append(move) }
        }
        return Semester(weeks: count, moves: moves)
    }
    private static func clock(_ raw: String) -> String? {
        guard let m = Jw64.full("([0-9]+):([0-9]+)", Jw64.trim(raw)), let hour = jw1064Integer(m[1]), let minute = jw1064Integer(m[2]), (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }
    private static func identifier(_ value: String) -> String { jw1064Matches(#"(?:;|[?&]p_id=)([0-9A-Z]{8})(?=['"&#?<>]|$)"#, value).first?[1] ?? "" }
    private func metadata(_ script: String) -> [Metadata] {
        guard let columns = Self.array(script, "gridColumns").map(Self.split), let name = columns.firstIndex(where: { $0.contains("课程名") }), let rows = Self.array(script, "gridData").map(Self.split) else { return [] }
        let teacher = columns.firstIndex { $0.contains("任课教师") }, note = columns.firstIndex { $0.contains("选课文字说明") }
        return rows.compactMap { row in
            let row = Jw64.trim(row); guard row.hasPrefix("["), row.hasSuffix("]") else { return nil }
            let fields = Self.split(String(row.dropFirst().dropLast())).map { Self.decode(Jw64.trim($0)) ?? Jw64.trim($0) }
            guard name < fields.count, !fields[name].isEmpty else { return nil }
            return Metadata(name: Jw64.plain(fields[name]), id: Self.identifier(fields[name]), teacher: teacher.flatMap { $0 < fields.count ? fields[$0] : nil } ?? "", note: note.flatMap { $0 < fields.count ? fields[$0] : nil } ?? "")
        }
    }
    private static func array(_ script: String, _ name: String) -> String? {
        guard let match = script.range(of: "\\bvar\\s+\(name)\\s*=\\s*\\[", options: .regularExpression) else { return nil }
        let values = Array(script[match.upperBound...]); var depth = 1, quote: Character?, escape = false
        for (index, c) in values.enumerated() {
            if let q = quote { if escape { escape = false } else if c == "\\" { escape = true } else if c == q { quote = nil } }
            else if c == "'" || c == "\"" { quote = c } else if c == "[" { depth += 1 } else if c == "]" { depth -= 1; if depth == 0 { return String(values[..<index]) } }
        }
        return nil
    }
    private static func split(_ value: String) -> [String] {
        let values = Array(value); var result: [String] = [], start = 0, depth = 0, quote: Character?, escape = false
        for (index, c) in values.enumerated() {
            if let q = quote { if escape { escape = false } else if c == "\\" { escape = true } else if c == q { quote = nil } }
            else if c == "'" || c == "\"" { quote = c } else if c == "[" || c == "{" { depth += 1 } else if c == "]" || c == "}" { depth -= 1 }
            else if c == "," && depth == 0 { result.append(String(values[start..<index])); start = index + 1 }
        }
        result.append(String(values[start...])); return result
    }
    private static func decode(_ value: String) -> String? {
        let values = Array(value); guard values.count >= 2, values[0] == "'" || values[0] == "\"", values.last == values.first else { return nil }
        var result = "", index = 1
        while index < values.count - 1 {
            let c = values[index]; index += 1
            if c != "\\" { result.append(c); continue }
            guard index < values.count - 1 else { return nil }; let next = values[index]; index += 1
            switch next {
            case "n": result += "\n"
            case "r": result += "\r"
            case "t": result += "\t"
            case "\\", "\"", "'", "/": result.append(next)
            case "u": guard index + 4 <= values.count - 1, let code = UInt32(String(values[index..<(index + 4)]), radix: 16), let scalar = UnicodeScalar(code) else { return nil }; result.unicodeScalars.append(scalar); index += 4
            default: return nil
            }
        }
        return result
    }
    private static func withoutComments(_ input: String) -> String {
        let values = Array(input); var output = "", index = 0, quote: Character?, escape = false
        while index < values.count {
            let c = values[index]
            if let q = quote { output.append(c); if escape { escape = false } else if c == "\\" { escape = true } else if c == q { quote = nil }; index += 1 }
            else if c == "'" || c == "\"" { quote = c; output.append(c); index += 1 }
            else if c == "/" && index + 1 < values.count && values[index + 1] == "/" { while index < values.count && values[index] != "\n" { output += " "; index += 1 } }
            else if c == "/" && index + 1 < values.count && values[index + 1] == "*" {
                output += "  "; index += 2
                while index < values.count && !(values[index] == "*" && index + 1 < values.count && values[index + 1] == "/") { output += values[index] == "\n" ? "\n" : " "; index += 1 }
                if index < values.count { output += "  "; index += 2 }
            } else { output.append(c); index += 1 }
        }
        return output
    }
}
