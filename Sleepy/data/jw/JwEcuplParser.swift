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
// 判定锚点(与 Android JwEcuplParser 一致):
//   r1  <table ... class="listTable" ...>      列表容器
//   r3  课程名 <td>(含 法|律|学|课)</td>
//   r4  教师   <td>(含 教授|老师|讲师|2-4 个汉字)</td>
//   r9  周次   "1-16(单|双|每周)"
//   r10 节次   "1-2节"
//
// 与 Android 的差异: Android 直接 return JwClassicEamsParser(source).generateCourseList()
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
        // Kotlin: 三重护栏 — 缺任一条都不是 ECUPL
        guard source.contains("new TaskActivity("),
              source.contains("table0.marshalTable"),
              matches(JwEcuplParser.reListTable) else { return [] }
        guard let parsed = try? JwClassicEamsParser(source).generateCourseList() else { return [] }
        return parsed
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
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
        if matches(JwEcuplParser.reListTable) { out.append("ecupl:r1-listTable") }
        if matches(JwEcuplParser.reCourseName) { out.append("ecupl:r3-courseName") }
        if matches(JwEcuplParser.reTeacher) { out.append("ecupl:r4-teacher") }
        if matches(JwEcuplParser.reWeekRange) { out.append("ecupl:r9-weekRange") }
        if matches(JwEcuplParser.reSection) { out.append("ecupl:r10-section") }
        if out.isEmpty { out.append("guard:no-ecupl-markers") }
        return out
    }
}
