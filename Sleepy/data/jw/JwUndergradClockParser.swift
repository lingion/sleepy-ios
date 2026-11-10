import Foundation

final class JwUndergradClockParser: JwParser {
    let source: String
    let protocolType: String
    init(_ source: String, protocolType: String) { self.source = source; self.protocolType = protocolType }
    func generateCourseList() -> [JwCourse] {
        guard let root = JwSgSourceMetadata.object(source) else { return [] }
        switch protocolType { case "shsmu": return shsmu(root); case "ygu": return ygu(root); default: return [] }
    }
    private static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private static func dateTime(_ value: String) -> Date? {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        let f = DateFormatter(); f.calendar = calendar; f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = calendar.timeZone; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.isLenient = false
        let normalized = value.replacingOccurrences(of: " ", with: "T")
        guard let date = f.date(from: normalized), f.string(from: date) == normalized else { return nil }; return date
    }
    private func shsmu(_ root: [String: Any]) -> [JwCourse] {
        guard let referenceDate = JwShsmuCaptureCalendar.resolve(root), let list = root["list"] as? [Any] else { return [] }
        var output: [JwCourse] = []
        let calendar = Self.calendar
        for item in list.compactMap({ $0 as? [String: Any] }) {
            let name = jw1064String(item, "Curriculum")
            guard !name.isEmpty, let start = Self.dateTime(jw1064String(item, "Start")), let end = Self.dateTime(jw1064String(item, "End")),
                  calendar.isDate(start, inSameDayAs: end), end > start,
                  let days = calendar.dateComponents([.day], from: referenceDate, to: calendar.startOfDay(for: start)).day,
                  days >= 0, days < 366 * 7 else { continue }
            let a = calendar.dateComponents([.hour, .minute], from: start), b = calendar.dateComponents([.hour, .minute], from: end)
            let startTime = String(format: "%02d:%02d", a.hour!, a.minute!), endTime = String(format: "%02d:%02d", b.hour!, b.minute!)
            guard JwCourse.isValidTimeRange(startTime, endTime) else { continue }
            let first = Self.shsmuPeriods.firstIndex { $0.0 == startTime }.map { $0 + 1 } ?? 0
            let last = Self.shsmuPeriods.firstIndex { $0.1 == endTime }.map { $0 + 1 } ?? 0
            let week = days / 7 + 1
            output.append(JwCourse(name: name, room: jw1064String(item, "ClassroomAcademy"), teacher: jw1064String(item, "Teacher"), day: (calendar.component(.weekday, from: start) + 5) % 7 + 1, startNode: first > 0 && last >= first ? first : 1, endNode: first > 0 && last >= first ? last : 2, startWeek: week, endWeek: week, startTime: startTime, endTime: endTime))
        }
        return output
    }
    private func ygu(_ root: [String: Any]) -> [JwCourse] {
        guard let data = root["data"] as? [Any] else { return [] }
        var output: [JwCourse] = [], seen: Set<JwCourse> = []
        for day in data.compactMap({ $0 as? [String: Any] }) {
            for week in (day["weekList"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
                for record in (week["kcbVoList"] as? [Any] ?? []).compactMap({ $0 as? [String: Any] }) {
            let name = jw1064String(record, "kcmc"), parityText = jw1064String(record, "dsz")
            guard !name.isEmpty, let weekday = jw1064Integer(jw1064String(record, "xq")), (1...7).contains(weekday), ["", "全", "单", "双"].contains(parityText) else { continue }
            let parity = jw1064Parity(parityText), nodes = schoolNodeRanges(jw1064String(record, "jcs")), weeks = schoolWeekRanges(jw1064String(record, "zcs"))
            guard !nodes.isEmpty, nodes.allSatisfy({ $0.1 <= 11 }), !weeks.isEmpty else { continue }
            let room = jw1064String(record, "jsmc").replacingOccurrences(of: " ", with: "")
            let special = ["文科楼", "商学楼", "音艺楼", "行政楼", "操场"].contains { room.contains($0) }
            var periods = Self.yguPeriods
            if special { periods[2] = ("10:05", "10:50"); periods[3] = ("10:55", "11:40") }
            for (a, b) in nodes { for (first, last, _) in weeks {
                guard parity == 0 || first % 2 == parity % 2 || last > first else { continue }
                let course = JwCourse(name: name, room: room, teacher: jw1064String(record, "rkls"), day: weekday, startNode: a, endNode: b, startWeek: first, endWeek: last, type: parity, startTime: periods[a - 1].0, endTime: periods[b - 1].1)
                if seen.insert(course).inserted { output.append(course) }
            } }
        } } }
        return output
    }
    static let shsmuPeriods: [(String, String)] = [
        ("08:00", "08:40"), ("08:50", "09:30"), ("09:40", "10:20"), ("10:30", "11:10"), ("11:20", "12:00"), ("13:30", "14:10"), ("14:20", "15:00"), ("15:10", "15:50"), ("16:00", "16:40"), ("16:50", "17:30"), ("17:40", "18:20"), ("18:30", "19:10"), ("19:20", "20:00")
    ]
    private static let yguPeriods: [(String, String)] = [
        ("08:10", "08:55"), ("09:00", "09:45"), ("10:20", "11:05"), ("11:15", "12:00"), ("14:00", "14:45"), ("14:50", "15:35"), ("15:55", "16:40"), ("16:45", "17:30"), ("18:30", "19:15"), ("19:20", "20:05"), ("20:10", "20:55")
    ]
}
