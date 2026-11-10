// SIMC's TaskActivity variant, Android v1.0.64.
import Foundation

final class JwSimcParser: JwParser, JwParserConfidenceReporting {
    let source: String
    init(_ source: String) { self.source = source }
    private struct Identity: Hashable {
        let name: String, teacher: String, room: String, day: Int, credit: Float, start: String, end: String
    }
    private let periods = [("08:30", "09:15"), ("09:15", "10:00"), ("10:15", "11:00"), ("11:00", "11:45"),
                           ("13:00", "13:45"), ("13:45", "14:30"), ("14:45", "15:30"), ("15:30", "16:15"),
                           ("16:15", "17:00"), ("17:00", "17:45")]
    private var marshal: [Int]? {
        guard let m = Jw64.matches(#"\btable\s*\.\s*marshalTable\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)\s*;"#, source).first else { return nil }
        let values = m.dropFirst().compactMap(Int.init)
        return values.count == 3 ? values : nil
    }
    private func weeks(_ bitmap: String) -> String {
        guard let values = marshal else { return "" }
        let origin = values[0], from = values[1], to = values[2], bits = Array(bitmap)
        guard !bits.isEmpty, bits.allSatisfy({ $0 == "0" || $0 == "1" }), origin > 0, from > 0, to >= from,
              origin <= Int.max - to, origin + from >= 2, origin + to - 2 < bits.count * 2 else { return "" }
        let repeated = bits + bits
        return "0" + String((1...to).map { $0 < from ? Character("0") : repeated[origin + $0 - 2] })
    }
    func generateCourseList() throws -> [JwCourse] {
        guard marshal != nil else { return [] }
        let table = Jw64.first(Jw64.doc(source), ".grid > table")
        let credits: [(String, Float)] = Jw64.select(table, "tr").dropFirst().compactMap { row in
            let cells = Jw64.select(row, "td")
            guard cells.count >= 4, let credit = Float(Jw64.text(cells[3])), credit.isFinite, credit >= 0 else { return nil }
            let code = Jw64.text(cells[0]), name = Jw64.text(cells[2])
            return name.isEmpty ? nil : (name + (code.isEmpty ? "" : "(\(code))"), credit)
        }
        var order: [Identity] = [], schedules: [Identity: [Int: Set<Int>]] = [:]
        for activity in JwClassicEamsParser(source, transformWeekBitmap: weeks).decodedActivities(defaultUnitCount: 14) {
            let credit = credits.last { activity.name.hasPrefix($0.0) }?.1 ?? 0
            let days = Set(activity.indices.map(\.0)).sorted()
            for day in days {
                let nodes = Set(activity.indices.filter { $0.0 == day }.map { raw in raw.1 == 13 ? 10 : raw.1 < 9 ? raw.1 + 1 : raw.1 + 2 })
                let special: (ClosedRange<Int>, String, String)?
                switch nodes.count == 1 ? nodes.first : nil {
                case 11: special = (1...5, "07:00", "13:30")
                case 12: special = (6...10, "14:00", "20:30")
                case 13: special = (1...8, "08:15", "15:30")
                case 14: special = (9...10, "16:00", "22:00")
                default: special = nil
                }
                let key = Identity(name: activity.name, teacher: activity.teacher, room: activity.room,
                                   day: day + 1, credit: credit, start: special?.1 ?? "", end: special?.2 ?? "")
                if schedules[key] == nil { order.append(key); schedules[key] = [:] }
                for week in activity.weeks { schedules[key, default: [:]][week, default: []].formUnion(special.map { Set($0.0) } ?? nodes) }
            }
        }
        var out: [JwCourse] = []
        for key in order {
            for week in (schedules[key] ?? [:]).keys.sorted() {
                let nodes = (schedules[key]?[week] ?? []).sorted()
                var ranges: [(Int, Int)] = []
                for node in nodes {
                    if let last = ranges.last, last.1 != 4, node == last.1 + 1 { ranges[ranges.count - 1].1 = node }
                    else { ranges.append((node, node)) }
                }
                for (first, last) in ranges {
                    let clock: (String, String)
                    if !key.start.isEmpty, !key.end.isEmpty { clock = (key.start, key.end) }
                    else if periods.indices.contains(first - 1), periods.indices.contains(last - 1) { clock = (periods[first - 1].0, periods[last - 1].1) }
                    else { clock = ("", "") }
                    out.append(JwCourse(name: key.name.replacingOccurrences(of: #"\(([0-9]{4})\)\((.*?)\)"#, with: "", options: .regularExpression),
                                        room: key.room, teacher: key.teacher, day: key.day, startNode: first, endNode: last,
                                        startWeek: week, endWeek: week, startTime: clock.0, endTime: clock.1, credit: key.credit))
                }
            }
        }
        return out
    }
    var confidenceValue: Int { marshal != nil && source.contains("TaskActivity") ? 100 : 0 }
    var matchedFeatureList: [String] { marshal != nil ? ["declared-simc", "table.marshalTable(origin,from,to)"] : [] }
}
