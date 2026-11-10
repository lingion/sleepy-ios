import Foundation
import CoreFoundation
import SwiftSoup

let EXPLICIT_SCHEDULE_RESOURCE_BOUND = 366
func explicitScheduleEnd(_ first: Int, _ length: Int) -> Int? {
    guard (1...366).contains(first), (1...366).contains(length), first <= 367-length else { return nil }
    return first+length-1
}
func explicitSchedulePair(_ group: Int) -> ClosedRange<Int>? {
    guard (1...183).contains(group) else { return nil }
    return (group*2-1)...(group*2)
}
func schoolWeekRanges(_ raw: String, trailingParityAppliesToAll: Bool = false) -> [(Int,Int,Int)] {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
        .replacingOccurrences(of: #"\s+"#,with: "",options: .regularExpression)
    guard !text.isEmpty else { return [] }
    var global = ""
    if trailingParityAppliesToAll && text.filter({ $0 == "单" || $0 == "双" }).count == 1,
       let match = jw1064Matches(#"(?:\(([单双])周?\)|([单双])周?)$"#,text).first {
        global = match[1].isEmpty ? match[2] : match[1]
        if let range = text.range(of: #"(?:\(([单双])周?\)|([单双])周?)$"#,options: .regularExpression) { text.removeSubrange(range) }
    }
    var result: [(Int,Int,Int)] = []
    for token in text.replacingOccurrences(of: "，",with: ",").components(separatedBy: ",") {
        guard let m = jw1064Matches(#"^第?([0-9]+)(?:-([0-9]+))?([单双])?周?(?:\(([单双])周?\))?$"#,token).first,
              let first = Int(m[1]), let last = Int(m[2].isEmpty ? m[1] : m[2]), (1...366).contains(first), (first...366).contains(last) else { return [] }
        let markers = Set([global,m[3],m[4]].filter { !$0.isEmpty }); guard markers.count <= 1 else { return [] }
        let row = (first,last,markers.first == "单" ? 1 : markers.first == "双" ? 2 : 0)
        if !result.contains(where: { $0 == row }) { result.append(row) }
    }
    return result
}
func schoolNodeRanges(_ raw: String) -> [(Int,Int)] {
    var ranges: [(Int,Int)] = []
    for token in raw.replacingOccurrences(of: "，",with: ",").components(separatedBy: ",") {
        guard let m = jw1064Matches(#"^([0-9]+)(?:\s*-\s*([0-9]+))?$"#,token.trimmingCharacters(in: .whitespacesAndNewlines)).first,
              let first = jw1064Integer(m[1]), let last = jw1064Integer(m[2].isEmpty ? m[1] : m[2]), first >= 1, last >= first else { return [] }
        ranges.append((first,last))
    }
    var result: [(Int,Int)] = []
    for row in ranges.sorted(by: { $0.0 < $1.0 }) {
        if let previous = result.last, row.0 <= previous.1 || row.0-1 == previous.1 { result[result.count-1] = (previous.0,max(previous.1,row.1)) }
        else { result.append(row) }
    }
    return result
}
func jw1064Matches(_ pattern: String, _ text: String) -> [[String]] {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = text as NSString
    return re.matches(in: text,range: NSRange(location: 0,length: ns.length)).map { match in
        (0..<match.numberOfRanges).map { match.range(at: $0).location == NSNotFound ? "" : ns.substring(with: match.range(at: $0)) }
    }
}
func jw1064Text(_ element: Element?, _ selector: String? = nil) -> String {
    guard let element else { return "" }
    if let selector { return (try? element.select(selector).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "" }
    return (try? element.text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
}
func jw1064Lines(_ element: Element) -> [String] {
    ((try? element.html()) ?? "").replacingOccurrences(of: #"(?i)<br\s*/?>"#,with: "\n",options: .regularExpression)
        .components(separatedBy: "\n").map { (try? SwiftSoup.parseBodyFragment($0).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "" }
}
func jw1064Valid(_ rows: [JwCourse]) -> [JwCourse] {
    rows.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...7).contains($0.day) &&
        (1...366).contains($0.startNode) && $0.endNode >= $0.startNode && $0.endNode <= 366 &&
        (1...366).contains($0.startWeek) && $0.endWeek >= $0.startWeek && $0.endWeek <= 366 && (0...2).contains($0.type) }
}
func jw1064String(_ object: [String: Any], _ key: String) -> String {
    guard let value = object[key], !(value is NSNull) else { return "" }
    return String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Kotlin Int transport semantics: no booleans, fractional values or whitespace coercion.
func jw1064Integer(_ value: Any?) -> Int? {
    let text: String
    if let value = value as? String { text = value }
    else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
            !["f", "d"].contains(String(cString: value.objCType)) { text = value.stringValue }
    else { return nil }
    guard text.range(of: #"^[+-]?[0-9]+$"#, options: .regularExpression) != nil,
          let value = Int(text), value >= Int(Int32.min), value <= Int(Int32.max) else { return nil }
    return value
}

func jw1064Weeks(_ course: JwCourse, _ first: Int, _ last: Int, _ parity: Int) -> JwCourse {
    JwCourse(name: course.name, room: course.room, teacher: course.teacher, day: course.day,
             startNode: course.startNode, endNode: course.endNode, startWeek: first, endWeek: last,
             type: parity, startTime: course.startTime, endTime: course.endTime, credit: course.credit, note: course.note)
}

/// Union weeks only when every arrangement field agrees; preserve encounter order.
func mergeCourseWeeks(_ courses: [JwCourse]) -> [JwCourse] {
    var order: [JwCourse] = [], groups: [JwCourse: Set<Int>] = [:]
    for course in courses {
        guard (1...366).contains(course.startWeek), course.endWeek >= course.startWeek,
              course.endWeek <= 366, (0...2).contains(course.type) else { continue }
        let key = jw1064Weeks(course, 1, 1, 0)
        if groups[key] == nil { order.append(key); groups[key] = [] }
        for week in course.startWeek...course.endWeek where course.type == 0 || week % 2 == course.type % 2 {
            groups[key, default: []].insert(week)
        }
    }
    return order.flatMap { course in
        JwUcasParser.splitWeekRuns(Array(groups[course] ?? [])).map { jw1064Weeks(course, $0.startWeek, $0.endWeek, $0.type) }
    }
}

func jw1064Elements(_ element: Element?, _ selector: String) -> [Element] {
    guard let element else { return [] }
    return (try? element.select(selector).array()) ?? []
}
func jw1064Attribute(_ element: Element, _ key: String) -> String { (try? element.attr(key)) ?? "" }
func jw1064Range(_ raw: String) -> (Int, Int)? {
    guard let m = jw1064Matches(#"^([0-9]+)(?:\s*-\s*([0-9]+))?$"#, raw.trimmingCharacters(in: .whitespacesAndNewlines)).first,
          let first = jw1064Integer(m[1]), let last = jw1064Integer(m[2].isEmpty ? m[1] : m[2]),
          (1...366).contains(first), last >= first, last <= 366 else { return nil }
    return (first, last)
}
func jw1064Parity(_ text: String) -> Int { text.contains("单") ? 1 : text.contains("双") ? 2 : 0 }

func jw1064Split(_ pattern: String, _ text: String) -> [String] {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
    let ns = text as NSString
    var start = 0, output: [String] = []
    for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        output.append(ns.substring(with: NSRange(location: start, length: match.range.location - start)))
        start = match.range.location + match.range.length
    }
    output.append(ns.substring(from: start)); return output
}
func jw1064Plain(_ raw: String) -> String { (try? SwiftSoup.parseBodyFragment(raw).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "" }
func jw1064Day(_ raw: String) -> Int {
    let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"^(?:星期|周)"#, with: "", options: .regularExpression)
    return jw1064Integer(s) ?? ["一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"日":7,"天":7][s] ?? 0
}
