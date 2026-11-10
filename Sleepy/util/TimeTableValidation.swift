import Foundation
import CoreFoundation

extension TimeTableUtils {
    enum PeriodValidationResult: Equatable {
        case valid
        case empty
        case invalidFormat(node: Int, rawStart: String, rawEnd: String)
        case endBeforeStart(node: Int, start: String, end: String)
        case invalidData
        case duplicateNode(node: Int)
        case overlap(prevNode: Int, prevEnd: String, nextNode: Int, nextStart: String)

        var errorMessage: String {
            switch self {
            case .valid: return ""
            case .empty: return L10n.t("period_validation_empty")
            case let .invalidFormat(node, _, _):
                return L10n.format("period_validation_invalid_format", node)
            case let .endBeforeStart(node, start, end):
                return L10n.format("period_validation_end_before_start", node, start, end)
            case .invalidData: return L10n.t("period_validation_invalid_data")
            case let .duplicateNode(node):
                return L10n.format("period_validation_duplicate_node", node)
            case let .overlap(prevNode, prevEnd, nextNode, nextStart):
                return L10n.format("period_validation_overlap", prevNode, prevEnd, nextNode, nextStart)
            }
        }
    }

    /// Bell schedules persist minute clocks only. Actual-time courses retain their separate seconds contract.
    static func parsePeriodClock(_ raw: String) -> Int? {
        let value = Array(raw.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard value.count == 5, value[2] == 58,
              value[0] >= 48, value[0] <= 50,
              value[1] >= 48, value[1] <= 57,
              value[3] >= 48, value[3] <= 53,
              value[4] >= 48, value[4] <= 57 else { return nil }
        let hour = Int(value[0] - 48) * 10 + Int(value[1] - 48)
        guard hour < 24 else { return nil }
        return hour * 60 + Int(value[3] - 48) * 10 + Int(value[4] - 48)
    }

    /// Strict persisted decoder: missing identities use legacy positions; supplied values never receive defaults.
    static func strictPeriodRows(_ timeJson: String) -> [TimeSlotRow]? {
        guard let data = timeJson.data(using: .utf8),
              let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return nil }
        var rows: [TimeSlotRow] = []
        rows.reserveCapacity(array.count)
        for (index, item) in array.enumerated() {
            let node: Int
            if let supplied = item["node"] {
                let raw: String
                if let value = supplied as? String { raw = value }
                else if let value = supplied as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
                        !["f", "d"].contains(String(cString: value.objCType)) {
                    raw = value.stringValue
                } else { return nil }
                guard let value = Int32(raw) else { return nil }
                node = Int(value)
            } else { node = index + 1 }
            guard let start = item["start"] as? String, let end = item["end"] as? String else { return nil }
            rows.append(TimeSlotRow(node: node, start: start, end: end,
                                    edgeClass: (item["edge"] as? String).flatMap { EdgeClass(rawValue: $0.lowercased()) }))
        }
        return rows
    }

    static func validatePeriodRows(_ rows: [TimeSlotRow]) -> PeriodValidationResult {
        guard !rows.isEmpty else { return .empty }
        var seen = Set<Int>()
        var parsed: [(row: TimeSlotRow, start: Int, end: Int)] = []
        for row in rows {
            guard seen.insert(row.node).inserted else { return .duplicateNode(node: row.node) }
            guard let start = parsePeriodClock(row.start), let end = parsePeriodClock(row.end) else {
                return .invalidFormat(node: row.node, rawStart: row.start, rawEnd: row.end)
            }
            guard end > start else { return .endBeforeStart(node: row.node, start: row.start, end: row.end) }
            parsed.append((row, start, end))
        }
        let ordered = parsed.sorted { $0.row.node < $1.row.node }
        for (previous, next) in zip(ordered, ordered.dropFirst()) where next.start < previous.end {
            return .overlap(prevNode: previous.row.node, prevEnd: previous.row.end,
                            nextNode: next.row.node, nextStart: next.row.start)
        }
        return .valid
    }

    static func validateTimeJson(_ timeJson: String) -> PeriodValidationResult {
        periodValidationCache.value(for: timeJson) {
            guard !timeJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
            guard let rows = strictPeriodRows(timeJson) else { return .invalidData }
            return validatePeriodRows(rows)
        }
    }

    static func isPeriodTableValid(_ timeJson: String) -> Bool { validateTimeJson(timeJson) == .valid }

    /// Trim valid clocks for display only. Preserve malformed values, identities, metadata and unchanged bytes.
    static func sanitizeTimeJsonForDisplay(_ timeJson: String) -> String {
        periodDisplayCache.value(for: timeJson) {
            guard let data = timeJson.data(using: .utf8),
                  var array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return timeJson }
            var changed = false
            for index in array.indices {
                guard var item = array[index] as? [String: Any] else { continue }
                for key in ["start", "end"] {
                    guard let raw = item[key] as? String, parsePeriodClock(raw) != nil else { continue }
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed != raw { item[key] = trimmed; changed = true }
                }
                array[index] = item
            }
            guard changed, let encoded = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
                  let result = String(data: encoded, encoding: .utf8) else { return timeJson }
            return result
        }
    }

    static func findConflictForSlot(_ rows: [TimeSlotRow], targetNode: Int) -> PeriodValidationResult? {
        guard let target = rows.first(where: { $0.node == targetNode }) else { return nil }
        if target.start.isBlank && target.end.isBlank { return nil }
        guard rows.filter({ $0.node == targetNode }).count == 1 else { return .duplicateNode(node: targetNode) }
        guard let start = parsePeriodClock(target.start), let end = parsePeriodClock(target.end) else {
            return .invalidFormat(node: targetNode, rawStart: target.start, rawEnd: target.end)
        }
        guard end > start else { return .endBeforeStart(node: targetNode, start: target.start, end: target.end) }
        let others = rows.filter { $0.node != targetNode && !$0.start.isBlank && !$0.end.isBlank }
        if let previous = others.filter({ $0.node < targetNode }).max(by: { $0.node < $1.node }),
           let previousEnd = parsePeriodClock(previous.end), start < previousEnd {
            return .overlap(prevNode: previous.node, prevEnd: previous.end, nextNode: targetNode, nextStart: target.start)
        }
        if let next = others.filter({ $0.node > targetNode }).min(by: { $0.node < $1.node }),
           let nextStart = parsePeriodClock(next.start), nextStart < end {
            return .overlap(prevNode: targetNode, prevEnd: target.end, nextNode: next.node, nextStart: next.start)
        }
        return nil
    }

    /// Walk declared nodes, so even a malformed enormous course span has bounded work.
    static func firstMissingCourseNode(courses: [CourseEntity], rows: [TimeSlotRow]) -> Int64? {
        let nodes = Set(rows.map { Int64($0.node) }).sorted()
        for course in courses where !course.ownTime && !course.isIrregularTime && course.step > 0 {
            var expected = Int64(course.startNode)
            let (last, overflow) = expected.addingReportingOverflow(Int64(course.step) - 1)
            var covered = false
            for node in nodes {
                if node < expected { continue }
                if node > expected { break }
                if expected == Int64.max { covered = !overflow; break }
                expected += 1
                if !overflow && expected > last { covered = true; break }
            }
            if covered { continue }
            if overflow || expected <= last { return expected }
        }
        return nil
    }
}

private let periodValidationCache = PeriodReadCache<TimeTableUtils.PeriodValidationResult>()
private let periodDisplayCache = PeriodReadCache<String>()

/// Small bounded caches match the repeated render reads without retaining large imported payloads.
final class PeriodReadCache<Value> {
    private let lock = NSLock()
    private var entries: [String: Value] = [:]
    private var order: [String] = []

    func value(for key: String, parse: () -> Value) -> Value {
        guard key.utf16.count <= 32_768 else { return parse() }
        lock.lock()
        if let value = entries[key] {
            order.removeAll { $0 == key }; order.append(key)
            lock.unlock()
            return value
        }
        lock.unlock()
        let value = parse()
        lock.lock()
        entries[key] = value
        order.removeAll { $0 == key }; order.append(key)
        if order.count > 16 { entries.removeValue(forKey: order.removeFirst()) }
        lock.unlock()
        return value
    }
}
