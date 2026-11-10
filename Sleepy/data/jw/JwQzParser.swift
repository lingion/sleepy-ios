// JwQzParser.swift — ← JwQzParser.kt
// 强智教务系统解析器(基础版)。
//
// 基于 dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) QzParser.kt
// 简化而来(去掉了 CourseBaseBean/CourseDetailBean 转换层)。
//
// 源仓库:https://github.com/dIT8Zv/WakeupSchedule_BUPT/blob/master/app/src/main/java/com/suda/yzune/wakeupschedule/schedule_import/parser/qz/QzParser.kt
//
// 抓取对象:教务系统课表页的 `id="kbtable"` 节点,
// 遍历 tr/td/div[class="tableName"],用 `title="老师"` / `title="教室"` /
// `title="周次(节次)"` 三个属性提数据。同格内多门课用 "-----" 分隔。
//
// 子类(如 JwQzCrazyParser)可重写 tableName 适配不同变体。
// (SwiftSoup = Jsoup API 1:1,方法名同形)

import Foundation
import SwiftSoup

class JwQzParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    /// 课表单元格内 class 名(多数强智学校为 "kbcontent",部分 crazy 变体为 "kbcontent1")
    /// ← open val tableName = "kbcontent";子类 override
    var tableName: String { "kbcontent" }

    var usesSchoolRowMapping: Bool { false }
    func rowNodes(_ row: Int) -> (Int, Int) { (row * 2 - 1, row * 2) }

    func parseCourseName(_ infoStr: String) -> String {
        let prefix = infoStr.range(of: #"(?i)<(?:font|span)\b[^>]*\btitle\s*="#, options: .regularExpression).map { String(infoStr[..<$0.lowerBound]) } ?? infoStr
        let lines = Self.brLines(prefix).map(Jw64.plain).filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        if first.hasPrefix("节次:") {
            if let value = lines.first(where: { $0.contains("学时]") }) { return Jw64.trim(value.components(separatedBy: "[").first!.components(separatedBy: "课序号").first!) }
            return lines.last(where: { !$0.hasPrefix("节次:") && Jw64.full(#"分组[0-9]+"#, $0) == nil }) ?? ""
        }
        return Jw64.trim(lines.joined(separator: " ").components(separatedBy: "课序号").first ?? "")
    }

    func convert(day: Int, nodeCount: Int, infoStr: String, courseList: inout [JwCourse]) {
        guard let html = Jw64.doc(infoStr) else { return }
        let name = parseCourseName(infoStr)
        guard !name.isEmpty, (1...7).contains(day) else { return }
        func field(_ title: String) -> String { jw1064Text(html, "[title='\(title)']") }
        let rawTeacher = field("老师"), teacher = rawTeacher.isEmpty ? field("教师") : rawTeacher
        let rawRoom = field("教室") + field("分组"), room = rawRoom.isEmpty ? field("上课地点") : rawRoom
        let combined = field("周次(节次)"), separate = field("周次")
        let enrollment = Jw64.first(html, "[title='选课人数']").map { Self.brLines(Jw64.html($0)) } ?? []
        let raw = !combined.isEmpty ? combined : !separate.isEmpty ? separate : enrollment.count > 1 ? Jw64.plain(enrollment[1]) : ""
        let time = raw.replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
        guard !time.isEmpty else { return }
        let bracket = jw1064Matches(#"\[([^]]*)]"#, time).first
        let tail = bracket == nil ? jw1064Matches(#"(?:\s+|(?<=\)))(第?[0-9][0-9,，、\s-]*节)\s*$"#, time).first : nil
        let matched = bracket ?? tail
        let weekText = matched.flatMap { time.range(of: $0[0]) }.map { String(time[..<$0.lowerBound]) } ?? time
        let independent = field("节次").replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
        let explicit = bracket?[1] ?? tail?[1] ?? (independent.isEmpty ? nil : independent.components(separatedBy: ")").last)
        let nodes = explicit.map(Self.parseNodes) ?? [rowNodes(nodeCount)]
        guard !nodes.isEmpty else { return }
        for segment in weekText.components(separatedBy: CharacterSet(charactersIn: ",，、\\")) {
            let type = jw1064Parity(segment)
            let normalized = segment.replacingOccurrences(of: #"[第周单双()\s]"#, with: "", options: .regularExpression)
            guard let range = Jw64.full(#"([0-9]+)(?:-([0-9]+))?"#, normalized), let start = jw1064Integer(range[1]), let end = jw1064Integer(range[2].isEmpty ? range[1] : range[2]), start > 0, end >= start else { continue }
            for (first, last) in nodes { courseList.append(JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: first, endNode: last, startWeek: start, endWeek: end, type: type)) }
        }
    }

    private static func parseNodes(_ text: String) -> [(Int, Int)] {
        var cleaned = Jw64.trim(text)
        if cleaned.hasPrefix("[") && cleaned.hasSuffix("]") { cleaned = String(cleaned.dropFirst().dropLast()) }
        if cleaned.hasPrefix("第") { cleaned.removeFirst() }; if cleaned.hasSuffix("节") { cleaned.removeLast() }
        var values = Set<Int>()
        for part in cleaned.components(separatedBy: CharacterSet(charactersIn: ",，、")) {
            let token = part.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
            guard let match = Jw64.full(#"([0-9]+)(?:-([0-9]+))?"#, token) else { return [] }
            let packed = match[2].isEmpty && token.count == 4
            guard let start = jw1064Integer(packed ? String(token.prefix(2)) : match[1]), let end = jw1064Integer(packed ? String(token.suffix(2)) : match[2].isEmpty ? match[1] : match[2]), (1...366).contains(start), (start...366).contains(end) else { return [] }
            values.formUnion(start...end)
        }
        var runs: [(Int, Int)] = []
        for node in values.sorted() { if let last = runs.last, last.1 + 1 == node { runs[runs.count - 1] = (last.0, node) } else { runs.append((node, node)) } }
        return runs
    }

    private static func brLines(_ html: String) -> [String] { html.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression).components(separatedBy: "\n") }
    private static func courseBlocks(_ html: String) -> [String] {
        var result: [String] = []
        for part in html.replacingOccurrences(of: #"-{5,}"#, with: "\u{1F}", options: .regularExpression).components(separatedBy: "\u{1F}") {
            var buffer = "", hasFields = false
            for line in brLines(part) {
                let fragment = Jw64.doc(line), text = Jw64.text(fragment)
                if buffer.isEmpty && text.isEmpty { continue }
                let isField = !Jw64.select(fragment, "[title]").isEmpty || line.contains("xsks") || Jw64.full(#"[0-9].*\[.+].*"#, text) != nil
                if hasFields && !isField && !text.isEmpty { result.append(buffer); buffer = ""; hasFields = false }
                buffer += line + "<br>"; hasFields = hasFields || isField
            }
            if hasFields { result.append(buffer) }
        }
        return result
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let doc = Jw64.doc(source) else { return [] }
        if !usesSchoolRowMapping && tableName == "kbcontent", let modern = JwQzModernHtml.parse(doc) { return modern }
        if !usesSchoolRowMapping && tableName == "kbcontent", Jw64.first(doc, "#kbtable") == nil, Jw64.first(doc, "table#timetable .kbcontent") != nil { return try JwQzTimetableParser(source).generateCourseList() }
        guard let table = Jw64.first(doc, "#kbtable") ?? Jw64.first(doc, "#timetable") else {
            throw JwParseError(message: "页面缺少 #kbtable，可能未到达课表页/选错教务类型", attempts: [ParserAttemptSnapshot(parserName: "JwQzParser", type: JwProtocol.TYPE_QZ, courseCount: 0, confidence: confidenceValue, matchedFeatures: matchedFeatureList, exception: JwParseError.NO_TABLE_CONTAINER_MARKER)])
        }
        var courses: [JwCourse] = [], nodeCount = 0, days = Array(1...7)
        for row in Jw64.rows(table) {
            let cells = Jw64.cells(row), headerDays = cells.compactMap { Self.weekday(Jw64.text($0)) }
            if headerDays.count == 7 && Set(headerDays).count == 7 { days = headerDays; continue }
            let tds = cells.filter { $0.tagNameNormal() == "td" }
            guard !tds.isEmpty else { continue }
            let dayCells = tds.count >= 7 ? Array(tds.suffix(7)) : Array(tds.drop(while: { Jw64.first($0, ".\(tableName)") == nil && Jw64.full(#"(?:第?[一二三四五六七八九十0-9-]+节|上午|下午|晚上)"#, Jw64.text($0)) != nil }))
            guard !dayCells.isEmpty, !dayCells.contains(where: { (jw1064Integer(Jw64.attr($0, "colspan")) ?? 1) > 1 }) else { continue }
            nodeCount += 1
            for (index, cell) in dayCells.enumerated() where index < days.count {
                for content in Jw64.select(cell, ".\(tableName)") {
                    var parent = content.parent(), nested = false
                    while let node = parent, node !== cell { if node.hasClass(tableName) { nested = true; break }; parent = node.parent() }
                    if nested || Jw64.text(content).isEmpty { continue }
                    for block in Self.courseBlocks(Jw64.html(content)) { convert(day: days[index], nodeCount: nodeCount, infoStr: block, courseList: &courses) }
                }
            }
        }
        return courses
    }

    private static func weekday(_ text: String) -> Int? {
        var label = Jw64.trim(text)
        if label.hasPrefix("星期") { label = String(label.dropFirst(2)) }; if label.hasPrefix("周") { label.removeFirst() }
        let day = Jw64.day(label); return day == 0 ? nil : day
    }

    // MARK: - T8 置信度

    /// 命中 #kbtable 与 font[title=老师/教室/周次(节次)] 三件套 = 100；
    /// 仅命中 kbtable+kbcontent = 70；仅命中 kbtable = 30。
    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        if !usesSchoolRowMapping && tableName == "kbcontent" && !JwQzModernHtml.features(doc).isEmpty { return 100 }
        if Jw64.first(doc, "#kbtable") == nil, Jw64.first(doc, "table#timetable .kbcontent [title='周次(节次)']") != nil { return 100 }
        guard let kbtable = Jw64.first(doc, "#kbtable") ?? Jw64.first(doc, "#timetable") else { return 0 }
        if Jw64.select(kbtable, ".\(tableName)").contains(where: { Jw64.first($0, "[title='周次(节次)'],[title='周次'],[title='选课人数']") != nil }) { return 100 }
        // v1.0.62: #timetable 视图 (新强智) — 周次(节次) 列锚点即满分。
        if ((try? doc.select("table#timetable .kbcontent [title='周次(节次)']").first()) ?? nil) != nil {
            return 100
        }
        let fontCount = ((try? doc.getElementsByAttributeValue("title", "老师").size()) ?? 0)
            + ((try? doc.getElementsByAttributeValue("title", "教师").size()) ?? 0)
            + ((try? doc.getElementsByAttributeValue("title", "教室").size()) ?? 0)
            + ((try? doc.getElementsByAttributeValue("title", "周次(节次)").size()) ?? 0)
        if fontCount >= 3 { return 100 }
        if ((try? kbtable.getElementsByClass(tableName)) ?? Elements()).isEmpty() == false { return 70 }
        return 30
    }

    var matchedFeatureList: [String] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        var out: [String] = !usesSchoolRowMapping && tableName == "kbcontent" ? JwQzModernHtml.features(doc) : []
        if ((try? doc.getElementById("kbtable")) ?? nil) != nil { out.append("id=kbtable") }
        if ((try? doc.getElementsByClass(tableName)) ?? Elements()).isEmpty() == false { out.append("class=\(tableName)") }
        if ((try? doc.getElementsByAttributeValue("title", "老师")) ?? Elements()).isEmpty() == false { out.append("title=老师") }
        if ((try? doc.getElementsByAttributeValue("title", "教师")) ?? Elements()).isEmpty() == false { out.append("title=教师") }
        if ((try? doc.getElementsByAttributeValue("title", "教室")) ?? Elements()).isEmpty() == false { out.append("title=教室") }
        if ((try? doc.getElementsByAttributeValue("title", "周次(节次)")) ?? Elements()).isEmpty() == false { out.append("title=周次(节次)") }
        if ((try? doc.select("table#timetable .kbcontent").first()) ?? nil) != nil { out.append("id=timetable") }
        return out
    }
}
