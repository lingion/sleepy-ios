import Foundation

/// Resolves dated source schedules against a complete, stable base timetable.
/// Source differences replace clocks only; the base identities and edge metadata survive.
enum EffectivePeriodResolver {
    struct ValidatedSchedule {
        let name: String?
        let baseTimeJson: String
        let publicSchedules: [Rule]

        func resolve(date: String) throws -> String {
            let day = try EffectivePeriodResolver.parseDate(date)
            return publicSchedules.first { $0.startDate <= day && day <= $0.endDate }?.timeJson ?? baseTimeJson
        }
    }

    struct Rule {
        let name: String
        let startDate: String
        let endDate: String
        let defaultClassDuration: Int64
        let defaultBreakDuration: Int64
        let timeSlots: [TimeTableUtils.TimeSlotRow]
        let timeJson: String
    }

    struct ValidationError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func resolve(baseJson: String, comboJson: String, date: String) throws -> String {
        try validate(baseJson: baseJson, comboJson: comboJson).resolve(date: date)
    }

    static func validate(baseJson: String, comboJson: String) throws -> ValidatedSchedule {
        guard case let .array(baseArray) = try JSONReader.read(baseJson), (1...366).contains(baseArray.count),
              case let .object(first) = baseArray[0] else { throw invalid("base must contain 1..366 period objects") }
        let base = try parseRows(baseArray, source: first["number"] != nil)
        guard base.map(\.node) == Array(1...base.count) else { throw invalid("base periods must be ordered and consecutive from 1") }
        try validateCompleteRows(base)
        guard case let .object(combo) = try JSONReader.read(comboJson),
              case let .array(rulesArray)? = combo["publicSchedules"] else { throw invalid("combination.publicSchedules must be an array") }
        let name = try combo["name"].map { _ in try string(combo, "name") }
        let rules = try rulesArray.map { element -> Rule in
            guard case let .object(rule) = element,
                  case let .array(differencesArray)? = rule["timeSlots"],
                  differencesArray.count <= base.count else { throw invalid("rule must contain a valid timeSlots array") }
            let ruleName = try string(rule, "name")
            let start = try parseDate(string(rule, "startDate"))
            let end = try parseDate(string(rule, "endDate"))
            guard end >= start else { throw invalid("rule endDate precedes startDate") }
            let classDuration = try duration(rule, "defaultClassDuration", fallback: 45, minimum: 1)
            let breakDuration = try duration(rule, "defaultBreakDuration", fallback: 10, minimum: 0)
            let differences = try parseRows(differencesArray, source: true)
            guard Set(differences.map(\.node)).count == differences.count,
                  differences.allSatisfy({ (1...base.count).contains($0.node) }) else { throw invalid("difference periods must be unique and exist in base") }
            let byNumber = Dictionary(uniqueKeysWithValues: differences.map { ($0.node, $0) })
            let merged = base.map { row -> TimeTableUtils.TimeSlotRow in
                guard let change = byNumber[row.node] else { return row }
                var result = row
                result.start = change.start
                result.end = change.end
                return result
            }
            try validateCompleteRows(merged)
            return Rule(name: ruleName, startDate: start, endDate: end, defaultClassDuration: classDuration,
                        defaultBreakDuration: breakDuration, timeSlots: differences,
                        timeJson: TimeTableUtils.buildTimeJsonFromRows(merged))
        }
        return ValidatedSchedule(name: name, baseTimeJson: TimeTableUtils.buildTimeJsonFromRows(base), publicSchedules: rules)
    }

    private static func parseRows(_ array: [JSONValue], source: Bool) throws -> [TimeTableUtils.TimeSlotRow] {
        try array.map { element in
            guard case let .object(row) = element,
                  Set(row.keys).isDisjoint(with: source ? ["node", "start", "end"] : ["number", "startTime", "endTime"]) else {
                throw invalid("period must be an object with one field dialect")
            }
            let node = try integer(row[source ? "number" : "node"])
            guard (1...366).contains(node) else { throw invalid("period number must be in 1..366") }
            let start = try string(row, source ? "startTime" : "start")
            let end = try string(row, source ? "endTime" : "end")
            try validateClockPair(start, end)
            var edge: TimeTableUtils.EdgeClass?
            if !source, row["edge"] != nil {
                edge = TimeTableUtils.EdgeClass(rawValue: try string(row, "edge"))
                guard edge != nil else { throw invalid("edge must be before or after") }
            }
            return TimeTableUtils.TimeSlotRow(node: Int(node), start: start, end: end, edgeClass: edge)
        }
    }

    private static func validateCompleteRows(_ rows: [TimeTableUtils.TimeSlotRow]) throws {
        var previousEnd: String?
        for row in rows {
            try validateClockPair(row.start, row.end)
            if let previousEnd, row.start < previousEnd { throw invalid("periods overlap or precede previous period") }
            previousEnd = row.end
        }
    }

    private static func validateClockPair(_ start: String, _ end: String) throws {
        let pattern = "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"
        guard start.range(of: pattern, options: .regularExpression) != nil,
              end.range(of: pattern, options: .regularExpression) != nil,
              start.utf8.count == 5, end.utf8.count == 5, end > start else { throw invalid("clocks must be strict HH:mm with end after start") }
    }

    private static func parseDate(_ raw: String) throws -> String {
        guard raw.utf8.count == 10, raw.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else {
            throw invalid("date must be strict YYYY-MM-DD")
        }
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0, (1...12).contains(parts[1]) else { throw invalid("date must exist") }
        let leap = parts[0] % 4 == 0 && (parts[0] % 100 != 0 || parts[0] % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...days[parts[1] - 1]).contains(parts[2]) else { throw invalid("date must exist") }
        return raw
    }

    private static func string(_ object: [String: JSONValue], _ key: String) throws -> String {
        guard case let .string(value)? = object[key] else { throw invalid("\(key) must be a string") }
        return value
    }

    private static func integer(_ element: JSONValue?) throws -> Int64 {
        guard case let .number(raw)? = element,
              raw.range(of: "^-?(?:0|[1-9][0-9]*)$", options: .regularExpression) != nil,
              let value = Int64(raw) else { throw invalid("value must be an integer literal") }
        return value
    }

    private static func duration(_ object: [String: JSONValue], _ key: String, fallback: Int64, minimum: Int64) throws -> Int64 {
        guard let element = object[key] else { return fallback }
        let result = try integer(element)
        guard result >= minimum && result <= 9_007_199_254_740_991 else { throw invalid("duration outside allowed range") }
        return result
    }

    private static func invalid(_ message: String) -> ValidationError { ValidationError(message: message) }

    private indirect enum JSONValue {
        case object([String: JSONValue]), array([JSONValue]), string(String), number(String), other
    }

    /// Keeps numeric lexemes and rejects duplicate decoded keys before Foundation can
    /// coerce 1.0/1e0 to integer values or discard an earlier object field.
    private struct JSONReader {
        let bytes: [UInt8]
        var index = 0

        static func read(_ raw: String) throws -> JSONValue {
            var reader = JSONReader(bytes: Array(raw.utf8))
            let value = try reader.value()
            reader.whitespace()
            guard reader.index == reader.bytes.count else { throw invalid("trailing JSON input") }
            return value
        }

        mutating func whitespace() {
            while index < bytes.count && [9, 10, 13, 32].contains(bytes[index]) { index += 1 }
        }

        mutating func take(_ byte: UInt8) -> Bool {
            guard index < bytes.count && bytes[index] == byte else { return false }
            index += 1
            return true
        }

        mutating func value() throws -> JSONValue {
            whitespace()
            guard index < bytes.count else { throw invalid("incomplete JSON") }
            switch bytes[index] {
            case 123:
                index += 1
                whitespace()
                var object: [String: JSONValue] = [:]
                var keys = Set<[UInt16]>()
                if take(125) { return .object(object) }
                while true {
                    whitespace()
                    let key = try quotedString()
                    guard keys.insert(Array(key.utf16)).inserted else { throw invalid("duplicate JSON key") }
                    whitespace()
                    guard take(58) else { throw invalid("missing JSON colon") }
                    object[key] = try value()
                    whitespace()
                    if take(125) { return .object(object) }
                    guard take(44) else { throw invalid("missing JSON comma") }
                }
            case 91:
                index += 1
                whitespace()
                var array: [JSONValue] = []
                if take(93) { return .array(array) }
                while true {
                    array.append(try value())
                    whitespace()
                    if take(93) { return .array(array) }
                    guard take(44) else { throw invalid("missing JSON comma") }
                }
            case 34: return .string(try quotedString())
            case 116: try literal("true"); return .other
            case 102: try literal("false"); return .other
            case 110: try literal("null"); return .other
            default:
                let start = index
                _ = take(45)
                guard index < bytes.count else { throw invalid("incomplete JSON number") }
                if !take(48) {
                    guard (49...57).contains(bytes[index]) else { throw invalid("invalid JSON number") }
                    repeat { index += 1 } while index < bytes.count && (48...57).contains(bytes[index])
                }
                if take(46) { try digits() }
                if take(101) || take(69) { if !take(43) { _ = take(45) }; try digits() }
                return .number(String(decoding: bytes[start..<index], as: UTF8.self))
            }
        }

        mutating func digits() throws {
            let start = index
            while index < bytes.count && (48...57).contains(bytes[index]) { index += 1 }
            guard index > start else { throw invalid("incomplete JSON number") }
        }

        mutating func literal(_ literal: String) throws {
            let expected = Array(literal.utf8)
            guard bytes.count - index >= expected.count, Array(bytes[index..<(index + expected.count)]) == expected else { throw invalid("invalid JSON literal") }
            index += expected.count
        }

        mutating func quotedString() throws -> String {
            let start = index
            guard take(34) else { throw invalid("JSON object key must be a string") }
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                if byte == 34 {
                    guard let decoded = try JSONSerialization.jsonObject(with: Data(bytes[start..<index]), options: [.fragmentsAllowed]) as? String else {
                        throw invalid("invalid JSON string")
                    }
                    return decoded
                }
                guard byte >= 32 else { throw invalid("unescaped JSON control character") }
                if byte == 92 {
                    guard index < bytes.count else { throw invalid("incomplete JSON escape") }
                    index += 1
                }
            }
            throw invalid("unterminated JSON string")
        }
    }
}
