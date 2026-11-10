import Foundation

/// AHU's source matrix keeps every declared period, including unused periods.
enum JwAhuSourcePeriods {
    static func resolve(_ source: String) -> [(Int, String, String)] {
        guard let root = JwSgSourceMetadata.object(source),
              let layout = root["timeTableLayout"] as? [String: Any], let units = layout["courseUnitList"] as? [Any],
              (1...366).contains(units.count) else { return [] }
        var indices = Set<Int>(), result: [(Int, String, String)] = []
        for unit in units {
            guard let row = unit as? [String: Any], let index = integer(row["indexNo"]), (1...366).contains(index), indices.insert(index).inserted,
                  let start = integer(row["startTime"]).flatMap(clock), let end = integer(row["endTime"]).flatMap(clock),
                  JwCourse.isValidTimeRange(start, end) else { return [] }
            result.append((index, start, end))
        }
        return result.sorted { $0.0 < $1.0 }
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let value, !(value is NSNull) else { return nil }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil ? Int(text) : nil
    }
    private static func clock(_ value: Int) -> String? {
        guard (0...2359).contains(value), value % 100 < 60 else { return nil }
        return String(format: "%02d:%02d", value / 100, value % 100)
    }
}
