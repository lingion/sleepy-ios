// JwKingoZxParser.swift — ← JwKingoZxParser.kt
//
// Kingosoft 正选报表 (table#pageRpt) 与老式星期网格 (table#mytable td.td /
// #xkinfo table / #reportArea table) 解析器 — 青果教务 ZX 子变体。
//
// Android 侧证据: v1.0.62 新增, 注册于 TYPE_KINGO_ZX (priority 205);
// JwKingoParser 在 td.td 网格形态下会委托本 parser 保持 ZX 语义。
//
// 与 Android 的实现差异(等价翻译, 详见各函数注释):
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
        pattern: "(?:第)?([0-9]+)(?:-([0-9]+))?节")
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
        // 1. pageRpt 报表: 内层第 2 张表优先, 退第 1 张 (← listOfNotNull(getOrNull(1), firstOrNull()))
        if let outer = (try? doc.select("table#pageRpt").first()) ?? nil {
            let tables = ((try? outer.select("table")) ?? Elements()).array().filter { $0 !== outer }
            var candidates: [Element] = []
            if tables.count > 1 { candidates.append(tables[1]) }
            if let first = tables.first { candidates.append(first) }
            for table in candidates {
                let parsed = JwKingoZxParser.parseReport(table)
                if !parsed.isEmpty { return parsed }
            }
        }
        // 2. 老式网格: #mytable → #xkinfo table → #reportArea table
        let grid = (try? doc.select("table#mytable").first()) ?? nil
            ?? (try? doc.select("#xkinfo table").first()) ?? nil
            ?? (try? doc.select("#reportArea table").first()) ?? nil
        if let grid = grid {
            return JwKingoZxParser.parseGrid(grid)
        }
        return []
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        if ((try? doc.select("table#pageRpt table").first()) ?? nil) != nil { return 90 }
        let tdGrid = (try? doc.select("table#mytable td.td, #xkinfo table td.td, #reportArea table td.td")) ?? Elements()
        if !tdGrid.isEmpty() { return 85 }
        return 0
    }

    var matchedFeatureList: [String] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        var out: [String] = []
        if ((try? doc.select("table#pageRpt table").first()) ?? nil) != nil { out.append("pageRpt-report") }
        if !((try? doc.select("table#mytable td.td")) ?? Elements()).isEmpty() { out.append("mytable-grid") }
        if !((try? doc.select("#xkinfo table td.td")) ?? Elements()).isEmpty() { out.append("xkinfo-grid") }
        if !((try? doc.select("#reportArea table td.td")) ?? Elements()).isEmpty() { out.append("reportArea-grid") }
        return out
    }

    // MARK: - 报表解析 (pageRpt)

    private static func parseReport(_ table: Element) -> [JwCourse] {
        var out: [JwCourse] = []
        for row in (try? table.select("tr")) ?? Elements() {
            let cells = row.children().filter { $0.tagNameNormal() == "td" }
            if cells.count <= 10 { continue }
            let name = (((try? cells[1].text()) ?? "") as String)
                .split(separator: "]", maxSplits: 1, omittingEmptySubsequences: false)
                .dropFirst().joined(separator: "]")
                .trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }
            let teacher = ((try? cells[4].select("a")) ?? Elements()).array()
                .map { a -> String in
                    let t = ((try? a.text()) ?? "") as String
                    return before(t, "[").trimmingCharacters(in: .whitespaces)
                }
                .joined(separator: " & ")
            for line in linesAfterBreaks((try? cells[10].html()) ?? "") {
                guard let dayMatch = reDayToken.firstMatch(
                    in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length))
                else { continue }
                let lineNs = line as NSString
                guard let dayChar = lineNs.substring(with: dayMatch.range(at: 1)).first,
                      let day = dayNumbers[dayChar] else { continue }
                guard let secMatch = reSectionToken.firstMatch(
                    in: line, options: [], range: NSRange(location: 0, length: (line as NSString).length))
                else { continue }
                guard let start = Int(lineNs.substring(with: secMatch.range(at: 1))) else { continue }
                let end = secMatch.range(at: 2).location != NSNotFound
                    ? (Int(lineNs.substring(with: secMatch.range(at: 2))) ?? start) : start
                guard (1...30).contains(start), (start...30).contains(end) else { continue }
                // 源码同时支持 [周次] 星期 [节次] 与 星期 节次 周次 两种顺序。
                // (NSRange 偏移是 UTF-16 口径, 统一用 NSString 切片避免混用 String.Index)
                let beforeDay = trimChars(lineNs.substring(to: dayMatch.range.location), "[] ")
                let afterSection = lineNs.substring(from: secMatch.range.upperBound)
                let weekSpec: String
                if beforeDay.contains(where: { $0.isNumber }) {
                    weekSpec = beforeDay
                } else {
                    weekSpec = trimChars(before(afterSection, "/"), "[] ")
                }
                let room = line.contains("/") ? after(line, "/").trimmingCharacters(in: .whitespaces) : ""
                for (first, last, type) in weekRuns(weekSpec) {
                    out.append(JwCourse(name: name, room: room, teacher: teacher,
                                        day: day, startNode: start, endNode: end,
                                        startWeek: first, endWeek: last, type: type))
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
                    guard (1...30).contains(firstSection), (firstSection...30).contains(lastSection) else { continue }
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
    static func weekRuns(_ spec: String) -> [(Int, Int, Int)] {
        var weeks: Set<Int> = []
        let normalized = spec.replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: "，", with: ",")
        for part in normalized.components(separatedBy: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let g = groups(reWeekToken, trimmed, entire: true) else { continue }
            guard let first = Int(g[1] ?? "") else { continue }
            let last = Int(g[2] ?? "") ?? first
            let parity = g[3] ?? ""
            guard (1...30).contains(first), (first...30).contains(last) else { continue }
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
