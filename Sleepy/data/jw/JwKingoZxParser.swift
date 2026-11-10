// JwKingoZxParser.swift — ← JwKingoZxParser.kt
//
// Kingosoft 正选报表 (table#pageRpt) 与老式星期网格 (table#mytable td.td /
// #xkinfo table / #reportArea table) 解析器 — 青果教务 ZX 子变体。
//
// 原版本 侧证据: v1.0.62 新增, 注册于 TYPE_KINGO_ZX (priority 205);
// JwKingoParser 在 td.td 网格形态下会委托本 parser 保持 ZX 语义。
//
// 与 原版本 的实现差异(等价翻译, 详见各函数注释):
//   a. Jsoup `clone() + select("br").replaceWith(TextNode("\n")) + wholeText()`
//      在 SwiftSoup 下改用 `html()` + `<br>` 正则替换为换行 + 逐行 parse().text()
//      (SwiftSoup 的 Node 替换 API 与 Jsoup 不同构, 字符串层转换行为等价)。
//   b. 正则一律 [0-9] 字符类 (Kotlin Regex \d 默认 ASCII, 与 [0-9] 同义;
//      iOS 26 ICU 的 \d 会吞全角数字, 见 PR #22 教训)。

import Foundation
import SwiftSoup

final class JwKingoZxParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    // MARK: - 正则常量

    /// 周次 token: "1-16" / "5" / "1-18 单" / "2-8 双"。
    private static let reWeekToken = try! NSRegularExpression(
        pattern: "^([0-9]+)(?:-([0-9]+))?\\s*(单|双)?$")
    /// 节次 token: "5-6节" / "第3节"。
    private static let reSectionToken = try! NSRegularExpression(
        pattern: "^(?:\\[\\s*)?(?:第)?([0-9]+(?:\\s*[-,]\\s*[0-9]+)*)节\\s*\\]?")
    /// 网格块内 "[5-6]" / "[5-6节]"; "[傍晚]" 特殊形态由调用方单独判断。
    private static let reBracketSection = try! NSRegularExpression(
        pattern: "\\[([0-9]+)(?:-([0-9]+))?节?\\]")
    /// 星期 token: "周一" / "星期日"。
    private static let reDayToken = try! NSRegularExpression(
        pattern: "(?:星期|周)([一二三四五六日天])")
    private static let dayNumbers: [Character: Int] =
        ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7]

    // MARK: - 匹配辅助 (NSRegularExpression capture wrapper)

    /// 返回 group index → captured string; entire=true 时锚定全串 (matchEntire)。
    private static func groups(_ re: NSRegularExpression, _ s: String, entire: Bool = false)
        -> [Int: String]? {
        let ns = s as NSString
        let range = entire ? NSRange(location: 0, length: ns.length) : NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: s, options: [], range: range) else { return nil }
        if entire && m.range.location != 0 { return nil }
        var out: [Int: String] = [:]
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            guard r.location != NSNotFound, r.length > 0 else { continue }
            out[i] = ns.substring(with: r)
        }
        return out
    }

    /// Kotlin `substringBefore(delim)`: 缺分隔符返回原串。
    private static func before(_ s: String, _ delim: String) -> String {
        guard let r = s.range(of: delim) else { return s }
        return String(s[s.startIndex..<r.lowerBound])
    }

    /// Kotlin `substringAfter(delim, "")`: 缺分隔符返回 ""。
    private static func after(_ s: String, _ delim: String) -> String {
        guard let r = s.range(of: delim) else { return "" }
        return String(s[r.upperBound...])
    }

    /// Kotlin `trim('[', ']', ' ')`: 去两端指定字符。
    private static func trimChars(_ s: String, _ chars: String) -> String {
        var start = s.startIndex, end = s.endIndex
        while start < end, chars.contains(s[start]) { start = s.index(after: start) }
        while end > start, chars.contains(s[s.index(before: end)]) { end = s.index(before: end) }
        return String(s[start..<end])
    }

    /// `<br>`/`<br/>` → 换行后逐行取文本 (等价 Jsoup br→TextNode + wholeText().lines())。
    private static func linesAfterBreaks(_ html: String) -> [String] {
        let withBreaks = html.replacingOccurrences(
            of: #"<br\s*/?\s*>"#, with: "\n", options: .regularExpression)
        return withBreaks.components(separatedBy: "\n").compactMap { raw -> String? in
            let d = (try? SwiftSoup.parse(raw)) ?? Document("")
            let t = ((try? d.text()) ?? "").trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? nil : t
        }
    }

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        for (selector, timingColumn) in [("#pageRpt", 10), ("#reportArea", 12)] {
            guard let outer = jw1064Elements(doc, selector).first else { continue }
            var seen = Set<JwCourse>()
            let reports = jw1064Elements(outer, "table").flatMap { Self.parseReport($0, timingColumn: timingColumn) }.filter { seen.insert($0).inserted }
            if !reports.isEmpty { return reports }
        }
        if !jw1064Elements(doc, "table#mytable").isEmpty { return WakeUpCompat.parseKingoSuperHtml(source) }
        let grid = jw1064Elements(doc, "#xkinfo table").first ?? jw1064Elements(doc, "#reportArea table").first
        if let grid { return Self.parseGrid(grid) }
        return []
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        if ((try? doc.select("#pageRpt table, #reportArea table").first()) ?? nil) != nil { return 90 }
        let tdGrid = (try? doc.select("table#mytable td.td, #xkinfo table td.td, #reportArea table td.td")) ?? Elements()
        if !tdGrid.isEmpty() { return 85 }
        return 0
    }

    var matchedFeatureList: [String] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        var out: [String] = []
        if !jw1064Elements(doc, "#pageRpt table").isEmpty { out.append("pageRpt-report") }
        if !jw1064Elements(doc, "#reportArea table").isEmpty { out.append("reportArea-report") }
        if !((try? doc.select("table#mytable td.td")) ?? Elements()).isEmpty() { out.append("mytable-grid") }
        if !((try? doc.select("#xkinfo table td.td")) ?? Elements()).isEmpty() { out.append("xkinfo-grid") }
        if !((try? doc.select("#reportArea table td.td")) ?? Elements()).isEmpty() { out.append("reportArea-grid") }
        return out
    }

    // MARK: - 报表解析 (pageRpt)

    private static func parseReport(_ table: Element, timingColumn: Int) -> [JwCourse] {
        var out: [JwCourse] = []
        for row in jw1064Elements(table, "tr") where ((try? row.parents().array()) ?? []).first(where: { $0.tagName() == "table" }) == table {
            let cells = row.children().array().filter { $0.tagName() == "td" }
            guard cells.count > timingColumn else { continue }
            let name = after(jw1064Text(cells[1]), "]").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let teachers = jw1064Elements(cells[4], "a")
            let teacher = teachers.isEmpty ? before(jw1064Text(cells[4]), "[").trimmingCharacters(in: .whitespacesAndNewlines)
                : teachers.map { before(jw1064Text($0), "[").trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: " & ")
            let amount = Float(jw1064Text(cells[2])) ?? 0
            let credit: Float = amount.isFinite && amount >= 0 ? amount : 0
            for line in linesAfterBreaks((try? cells[timingColumn].html()) ?? "") {
                let timing = before(before(line, "/"), " ").trimmingCharacters(in: .whitespacesAndNewlines)
                let ns = timing as NSString
                let dayPattern = #"(?:星期|周)([一二三四五六日天])|^([一二三四五六日天])(?=\s)"#
                guard let regex = try? NSRegularExpression(pattern: dayPattern),
                      let dayMatch = regex.firstMatch(in: timing, range: NSRange(location: 0, length: ns.length)) else { continue }
                let single = dayMatch.range(at: 1).location == NSNotFound
                let group = single ? 2 : 1
                guard let dayChar = ns.substring(with: dayMatch.range(at: group)).first, let day = dayNumbers[dayChar] else { continue }
                let afterDay = ns.substring(from: dayMatch.range.upperBound).trimmingCharacters(in: .whitespacesAndNewlines)
                let afterNs = afterDay as NSString
                guard let section = reSectionToken.firstMatch(in: afterDay, range: NSRange(location: 0, length: afterNs.length)) else { continue }
                let sections = schoolNodeRanges(afterNs.substring(with: section.range(at: 1)))
                guard !sections.isEmpty, sections.allSatisfy({ (1...366).contains($0.0) && ($0.0...366).contains($0.1) }) else { continue }
                let beforeDay = trimChars(ns.substring(to: dayMatch.range.location), "[] ")
                let prefixWeeks = beforeDay.contains(where: { $0.isNumber })
                let weekSpec = prefixWeeks ? beforeDay : trimChars(afterNs.substring(from: section.range.upperBound), "[] ")
                var room = (line.contains("/") ? after(line, "/") : after(line, " ")).trimmingCharacters(in: .whitespacesAndNewlines)
                if room.isEmpty && name.hasSuffix("m") { room = "在线" }
                for (from, to, parity) in weekRuns(weekSpec, singletonIsExplicit: single, parityAppliesToAll: prefixWeeks) {
                    for (start, end) in sections {
                        out.append(JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: start, endNode: end,
                                            startWeek: from, endWeek: to, type: parity, credit: credit))
                    }
                }
            }
        }
        return out
    }

    // MARK: - 网格解析 (mytable td.td)

    private static func parseGrid(_ table: Element) -> [JwCourse] {
        var out: [JwCourse] = []
        var seen: Set<JwCourse> = []
        for row in (try? table.select("tr")) ?? Elements() {
            let columns = row.children().filter { $0.tagNameNormal() == "td" }
            if columns.count < 2 { continue }
            let firstText = ((try? columns[0].text()) ?? "").trimmingCharacters(in: .whitespaces)
            let firstHasTd = ((try? columns[0].hasClass("td")) ?? false)
            let firstDayIndex = (!firstHasTd && (firstText.hasPrefix("第") || firstText == "节次" || firstText == "时间")) ? 1 : 0
            for (index, cell) in columns.dropFirst(firstDayIndex).enumerated() {
                let day = index + 1
                if day > 7 { break }
                guard ((try? cell.hasClass("td")) ?? false) else { continue }
                for block in cell.children().filter({ $0.tagNameNormal() == "div" }) {
                    let parts = linesAfterBreaks((try? block.html()) ?? "")
                    if parts.count != 4 { continue }
                    let secGroups = groups(reBracketSection, parts[2])
                    // "[傍晚]" 形态 → 固定第 9 节 (傍晚课)。
                    let afterBracket = after(parts[2], "[")
                    let firstSection: Int
                    if afterBracket.hasPrefix("傍晚") {
                        firstSection = 9
                    } else if let g = secGroups, let v = Int(g[1] ?? "") {
                        firstSection = v
                    } else { continue }
                    let lastSection = (secGroups.flatMap { Int($0[2] ?? "") }) ?? firstSection
                    guard (1...366).contains(firstSection), (firstSection...366).contains(lastSection) else { continue }
                    let weekSpec = before(parts[2], "[")
                    for (first, last, type) in weekRuns(weekSpec) {
                        let course = JwCourse(name: parts[0], room: parts[3], teacher: parts[1],
                                              day: day, startNode: firstSection, endNode: lastSection,
                                              startWeek: first, endWeek: last, type: type)
                        if seen.insert(course).inserted { out.append(course) }
                    }
                }
            }
        }
        return out
    }

    // MARK: - 周次段归并

    /// "1-16" / "5,7,9,13-16,1-18 单" → 连续段 (单双周步长 2 归并)。
    static func weekRuns(_ spec: String, singletonIsExplicit: Bool = false, parityAppliesToAll: Bool = false) -> [(Int, Int, Int)] {
        var weeks: Set<Int> = []
        var normalized = spec.replacingOccurrences(of: "周", with: "").replacingOccurrences(of: "，", with: ",")
            .filter { !$0.isWhitespace }.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
        var globalParity = ""
        if normalized.filter({ $0 == "单" || $0 == "双" }).count == 1 {
            let marker = normalized.first(where: { parityAppliesToAll && ($0 == "单" || $0 == "双") })
                ?? normalized.first.flatMap { $0 == "单" || $0 == "双" ? $0 : nil }
                ?? normalized.last.flatMap { $0 == "单" || $0 == "双" ? $0 : nil }
            if let marker { globalParity = String(marker); normalized = normalized.replacingOccurrences(of: globalParity, with: "") }
        }
        for part in normalized.components(separatedBy: ",") {
            guard let g = groups(reWeekToken, part, entire: true), let first = jw1064Integer(g[1]) else { return [] }
            let last = g[2].flatMap { jw1064Integer($0) } ?? first
            let parity = singletonIsExplicit && first == last ? "" : (g[3] ?? globalParity)
            guard (1...366).contains(first), (first...366).contains(last) else { return [] }
            for week in first...last {
                if parity == "单" && week % 2 == 0 { continue }
                if parity == "双" && week % 2 == 1 { continue }
                weeks.insert(week)
            }
        }
        if weeks.isEmpty { return [] }
        let ordered = weeks.sorted()
        var runs: [(Int, Int, Int)] = []
        var i = 0
        while i < ordered.count {
            let step = (i + 1 < ordered.count && ordered[i + 1] - ordered[i] == 2) ? 2 : 1
            var j = i
            while j + 1 < ordered.count && ordered[j + 1] - ordered[j] == step { j += 1 }
            let type: Int = step == 2 ? (ordered[i] % 2 == 1 ? 1 : 2) : 0
            runs.append((ordered[i], ordered[j], type))
            i = j + 1
        }
        return runs
    }
}
