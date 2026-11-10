// JwEcuplParser.swift — ← JwEcuplParser.kt
//
// 华东政法大学 (ECUPL) 教务解析器。
//
// 页面形态与经典 EAMS 相同(内嵌 JS 块):
//   var table0 = new CourseTable(...);
//   activity = new TaskActivity(...);
//   table0.marshalTable(...);
// 但课程列表容器 class 固定为 "listTable",且额外带 <td> 行的课程名/教师/周次结构,
// 因此单独做一个薄壳:先用特征正则确认"这是 ECUPL",再委派给 JwClassicEamsParser 解析。
//
// 判定锚点(与 原版本 JwEcuplParser 一致):
//   r1  <table ... class="listTable" ...>      列表容器
//   r3  课程名 <td>(含 法|律|学|课)</td>
//   r4  教师   <td>(含 教授|老师|讲师|2-4 个汉字)</td>
//   r9  周次   "1-16(单|双|每周)"
//   r10 节次   "1-2节"
//
// 与原实现的差异: 原版本 直接 return JwClassicEamsParser(source).generateCourseList()
// (Kotlin 无 checked exception),iOS 需 try 传播,故用 `try?` 兜底为空列表。

import Foundation

final class JwEcuplParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    // MARK: - 特征正则

    // reListTable 为 internal: JwEcuplSuperParser.HAS_LIST_TABLE 复用
    // (← Kotlin companion 直接引用 JwEcuplParser.RE_LIST_TABLE)。
    static let reListTable = try! NSRegularExpression(pattern: "<table[^>]*class=\"listTable\"[^>]*>", options: [])
    private static let reCourseName = try! NSRegularExpression(pattern: "<td[^>]*>([^<]*(?:法|律|学|课)[^<]*)</td>", options: [])
    private static let reTeacher = try! NSRegularExpression(pattern: "<td[^>]*>([^<]*(?:教授|老师|讲师|[一-龥]{2,4})[^<]*)</td>", options: [])
    private static let reWeekRange = try! NSRegularExpression(pattern: "(\\d+)\\s*[-~]\\s*(\\d+)\\s*(?:(单|双)|每周)?", options: [])
    private static let reSection = try! NSRegularExpression(pattern: "(\\d+)\\s*[-~]\\s*(\\d+)\\s*节?", options: [])

    /// 静态包含判定 (供 JwEcuplSuperParser 等外部复用)。
    static func contains(_ re: NSRegularExpression, _ s: String) -> Bool {
        let r = NSRange(s.startIndex..., in: s)
        return re.firstMatch(in: s, options: [], range: r) != nil
    }

    private func matches(_ re: NSRegularExpression) -> Bool {
        JwEcuplParser.contains(re, source)
    }

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        guard source.contains("new TaskActivity("), source.contains("table0.marshalTable"), matches(Self.reListTable) else {
            return try JwEcuplScriptParser(source).generateCourseList()
        }
        guard let marshal = jw1064Matches(#"table0\.marshalTable\s*\(\s*(\d+)\s*,\s*\d+\s*,\s*(\d+)\s*\)"#, source).first,
              let origin = jw1064Integer(marshal[1]), (2...54).contains(origin),
              let count = jw1064Integer(marshal[2]), (1...64).contains(count),
              let yearText = jw1064Matches(#"new CourseTable\(\s*(\d{4})\s*,\s*\d+\s*\)"#, source).first?[1], let year = Int(yearText) else { return [] }
        let december31 = JwEcuplScriptParser.epochDay((year, 12, 31))
        let yearOffset = ((december31 + 3) % 7 + 7) % 7 + 1 == 6 ? 55 : 54
        let courses = try JwClassicEamsParser(source, transformWeekBitmap: { bitmap in
            guard bitmap.allSatisfy({ $0 == "0" || $0 == "1" }), bitmap.count >= origin - 1 else { return "" }
            if !bitmap.prefix(origin - 1).contains("1") { return String(bitmap.dropFirst(origin - 2).prefix(count + 1)) }
            return String((String(repeating: "0", count: yearOffset - origin) + bitmap).prefix(count + 1))
        }).generateCourseList()
        let details = ecuplDetails(source)
        return courses.map { course in
            let code = course.name.range(of: "(", options: .backwards).map { String(course.name[$0.upperBound...]).replacingOccurrences(of: #"\)$"#, with: "", options: .regularExpression) } ?? ""
            guard let detail = details[code] else { return course }
            return JwCourse(name: detail.name, room: course.room, teacher: detail.teacher, day: course.day,
                            startNode: course.startNode, endNode: course.endNode, startWeek: course.startWeek,
                            endWeek: course.endWeek, type: course.type, startTime: course.startTime, endTime: course.endTime,
                            credit: detail.credit, note: detail.note)
        }
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        if matches(Self.reListTable), source.contains("table0.marshalTable"), source.contains("new TaskActivity("),
           !jw1064Matches(#"new CourseTable\(\s*\d{4}\s*,\s*\d+\s*\)"#, source).isEmpty { return 100 }
        var hits = 0
        if matches(JwEcuplParser.reListTable) { hits += 3 }
        if matches(JwEcuplParser.reCourseName) { hits += 2 }
        if matches(JwEcuplParser.reTeacher) { hits += 1 }
        if matches(JwEcuplParser.reWeekRange) { hits += 2 }
        switch hits {
        case 7...: return 95
        case 5...: return 80
        case 3...: return 60
        case 1...: return 30
        default: return 0
        }
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("table0.marshalTable") && source.contains("new TaskActivity(") { out.append("ecupl:annual-week-origin") }
        if matches(JwEcuplParser.reListTable) { out.append("ecupl:r1-listTable") }
        if matches(JwEcuplParser.reCourseName) { out.append("ecupl:r3-courseName") }
        if matches(JwEcuplParser.reTeacher) { out.append("ecupl:r4-teacher") }
        if matches(JwEcuplParser.reWeekRange) { out.append("ecupl:r9-weekRange") }
        if matches(JwEcuplParser.reSection) { out.append("ecupl:r10-section") }
        if out.isEmpty { out.append("guard:no-ecupl-markers") }
        return out
    }
}
