import Foundation

/// Absolute lesson dates require an explicit teaching-calendar origin.
enum JwShsmuCaptureCalendar {
    enum Basis: String { case USER_CONFIRMED, EXISTING_TABLE }
    private static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    static func date(_ text: String) -> Date? {
        guard text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        return JwSourceCalendar.parseDate(text)
    }
    static func monday(_ text: String) -> Date? { guard date(text) != nil, let monday = JwSourceCalendar.monday(text) else { return nil }; return date(monday) }
    static func isDatedCapture(_ source: String) -> Bool { JwSgSourceMetadata.object(source)?["sleepyShsmuCapture"] as? Bool == true }
    static func resolve(_ root: [String: Any]) -> Date? {
        if !root.keys.contains("sleepyShsmuCapture") { return date("2025-09-15") }
        guard root["sleepyShsmuCapture"] as? Bool == true,
              let first = root["rangeStart"] as? String, let startRange = date(first),
              let last = root["rangeEnd"] as? String, let endRange = date(last), endRange >= startRange,
              let basis = root["semesterStartBasis"] as? String, Basis(rawValue: basis) != nil,
              let raw = root["semesterStartDate"] as? String, let start = date(raw), monday(raw) == start else { return nil }
        return start
    }
    static func bind(_ source: String, firstWeekDate: String, basis: Basis) throws -> String {
        guard var root = JwSgSourceMetadata.object(source), root["sleepyShsmuCapture"] as? Bool == true else { throw JwParseError(message: "不是上海交通大学医学院日期课表") }
        guard let start = monday(firstWeekDate) else { throw JwParseError(message: "请确认第一周的日期") }
        guard let first = root["rangeStart"] as? String, let from = date(first),
              let last = root["rangeEnd"] as? String, let to = date(last), to >= from else { throw JwParseError(message: "采集日期范围无效") }
        guard let list = root["list"] as? [Any] else { throw JwParseError(message: "缺少日期课程") }
        for item in list {
            guard let row = item as? [String: Any], !Jw64.text(row, "Curriculum").isEmpty,
                  let lesson = date(String(Jw64.text(row, "Start").prefix(10))) else { continue }
            let days = calendar.dateComponents([.day], from: start, to: lesson).day ?? 0
            guard lesson >= start, days / 7 + 1 <= 366 else { throw JwParseError(message: "第一周日期必须覆盖全部已采集课程，请核对开学日期") }
        }
        root["semesterStartDate"] = JwSourceCalendar.stamp(start); root["semesterStartBasis"] = basis.rawValue
        return try JwSgSourceMetadata.stringify(root)
    }
    static func rebase(_ courses: [JwCourse], oldOrigin: String, firstWeekDate: String) throws -> [JwCourse] {
        guard let old = date(oldOrigin), monday(oldOrigin) == old else { throw JwParseError(message: "日期课程缺少原始学期起点") }
        guard let next = monday(firstWeekDate) else { throw JwParseError(message: "请确认第一周的日期") }
        let shift = (calendar.dateComponents([.day], from: next, to: old).day ?? 0) / 7
        return try courses.map { course in
            guard course.type == 0, course.startWeek == course.endWeek, (1...7).contains(course.day) else { throw JwParseError(message: "日期课程格式无效，请重新采集") }
            let week = course.startWeek + shift
            guard (1...366).contains(week) else { throw JwParseError(message: "第一周日期必须覆盖全部已采集课程，请核对开学日期") }
            return jw1064Weeks(course, week, week, 0)
        }
    }
}
