// JwOldQzSuperParser.swift — ← JwOldQzSuperParser.kt
//
// 老强智 (qz_old) 结构化变体解析器 — 三种互相独立的页面形态:
//   1. CCSU 固定格 id (group-day-2 编码节次组与星期, 恰 35 个 distinct id 才启用);
//   2. JLICT 标题表 (#kb 内 table, a[title] 七字段, 行号即两节组);
//   3. #kbtable 周次[节次] 字段序 (含 CCUT 分组格 id 变体)。
//
// 源事实与许可记录在跨仓核验台账 docs/old-qz-super-cross-verify-2026-10-13。
// JwOldQzParser (TYPE_QZ_OLD) 是本 parser 的稳定入口薄壳。
//
// 与 Android 的实现差异(等价翻译):
//   a. Jsoup Element.parents()/select() → SwiftSoup 同名 API (try? 包裹)。
//   b. 正则一律 [0-9] 字符类 (PR #22 教训)。

import Foundation
import SwiftSoup

final class JwOldQzSuperParser: JwParser, JwParserConfidenceReporting {

    let source: String
    private let doc: Document?

    init(_ source: String) {
        self.source = source
        self.doc = try? SwiftSoup.parse(source)
    }

    // MARK: - 正则常量

    /// "1-4,9-12周[0102节]" / "3周[3节]" → (周次段, 节次段)。
    private static let reWeekNode = try! NSRegularExpression(
        pattern: "^(.+?)周\\[([0-9]{1,4}(?:[-~][0-9]{1,2})?)节]$")
    /// "1-16" / "3"。
    private static let reRange = try! NSRegularExpression(
        pattern: "^([0-9]{1,2})(?:[-~]([0-9]{1,2}))?$")
    /// 表头星期单元格。
    private static let reWeekday = try! NSRegularExpression(
        pattern: "^(?:星期|周)([一二三四五六日天])$")
    /// CCSU 固定格 id: "group-day-2"。
    private static let reFixedId = try! NSRegularExpression(
        pattern: "^([1-5])-([1-7])-2$")
    /// CCUT 分组格 id: "group-day" 或 "group-day-n"。
    private static let reGroupDayId = try! NSRegularExpression(
        pattern: "^([1-9]|1[0-5])-([1-7])(?:-[0-9]+)?$")
    /// <br> 切分 (大小写/自闭合兼容)。
    private static let reBr = try! NSRegularExpression(
        pattern: "<br\\s*/?>", options: [.caseInsensitive])
    /// display:none (含 !important 前缀形态)。
    private static let reDisplayNone = try! NSRegularExpression(
        pattern: "(?:^|;)\\s*display\\s*:\\s*none\\s*(?:!important)?\\s*(?:;|$)", options: [.caseInsensitive])

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        var result: [JwCourse] = []
        guard let doc = doc else { return result }

        // ── 变体 1: CCSU 固定格 id 显式编码节次组与星期 ──
        let allIded = ((try? doc.select("[id]")) ?? Elements()).array()
            .filter { Self.matchesEntire(Self.reFixedId, (try? $0.id()) ?? "") }
        let distinctIds = Set(allIded.compactMap { try? $0.id() })
        if distinctIds.count == 35 {
            for cell in allIded {
                if Self.isHidden(cell) { continue }
                let f = Self.fields(cell)
                let idStr = (try? cell.id()) ?? ""
                guard let idGroups = Self.matchEntire(Self.reFixedId, idStr) else { continue }
                guard let group = Int(idGroups[1] ?? "") else { continue }
                var i = 0
                while i < f.count {
                    if i + 4 >= f.count { i += 5; continue }
                    Self.add(&result, name: f[i], teacher: f[i + 2], room: f[i + 4],
                             day: Int(idGroups[2] ?? "") ?? 0,
                             nodes: (group * 2 - 1, group * 2), weekText: f[i + 3])
                    i += 5
                }
            }
        }

        // ── 变体 2: JLICT 链接标题七字段, 行号即文档化的两节组 ──
        if let kb = (try? doc.getElementById("kb")) ?? nil,
           let table = (try? kb.select("table").first()) ?? nil {
            let rows = ((try? table.select("tr")) ?? Elements()).array()
                .filter { Self.nearestTable($0) === table }
            for (index, row) in rows.dropFirst().enumerated() {
                let cells = row.children().filter { $0.tagNameNormal() == "td" || $0.tagNameNormal() == "th" }
                if cells.count != 8 || index >= 15 { continue }
                for day in 1...7 {
                    guard day < cells.count else { continue }
                    for link in ((try? cells[day].select("a[title]")) ?? Elements()).array() {
                        if Self.isHidden(link) { continue }
                        let title = (try? link.attr("title")) ?? ""
                        let f = Self.splitNewlines(title)
                            .map { Self.afterColon($0).trimmingCharacters(in: .whitespaces) }
                        if f.count >= 7 {
                            Self.add(&result, name: f[2], teacher: f[3], room: f[6],
                                     day: day, nodes: (index * 2 + 1, index * 2 + 2), weekText: f[5])
                        }
                    }
                }
            }
        }

        // ── 变体 3: #kbtable 周次[节次] 字段序 (含 CCUT 分组格 id) ──
        if let table = (try? doc.getElementById("kbtable")) ?? nil {
            let rows = ((try? table.select("tr")) ?? Elements()).array()
                .filter { Self.nearestTable($0) === table }
            let header = rows.first { row -> Bool in
                let children = row.children()
                return children.contains { Self.matchesEntire(Self.reWeekday, ((try? $0.text()) ?? "") as String) }
            }
            var days: [Int?]?
            if let header = header {
                days = header.children().map { child -> Int? in
                    guard let g = Self.matchEntire(Self.reWeekday, ((try? child.text()) ?? "") as String),
                          let d = g[1]?.first else { return nil }
                    guard let idx = "一二三四五六日天".firstIndex(of: d) else { return nil }
                    let offset = "一二三四五六日天".distance(from: "一二三四五六日天".startIndex, to: idx)
                    return offset >= 6 ? 7 : offset + 1
                }
            }
            for row in rows {
                if row === header { continue }
                let cells = row.children().filter { $0.tagNameNormal() == "td" || $0.tagNameNormal() == "th" }
                // 无表头时只认文档化的 标签+七日 布局, 其余列数形态一律不猜。
                if days == nil && cells.count != 8 { continue }
                if let days = days, cells.count != days.count { continue }
                for (column, cell) in cells.enumerated() {
                    let day: Int
                    if let days = days {
                        guard let d = days[column] else { continue }
                        day = d
                    } else {
                        day = column
                    }
                    guard (1...7).contains(day) else { continue }
                    for block in Self.blocks(cell) {
                        if Self.isHidden(block) { continue }
                        let f = Self.fields(block)
                        let blockId = (try? block.id()) ?? ""
                        var recordStart = 0
                        var previousName = ""
                        for i in f.indices {
                            if let m = Self.matchEntire(Self.reWeekNode, f[i]), i >= 2, i + 1 < f.count {
                                let raw = m[2] ?? ""
                                let nodes: (Int, Int)?
                                if raw.count == 4 && raw.allSatisfy({ $0.isNumber }) {
                                    let s = raw.prefix(2)
                                    let e = raw.suffix(2)
                                    nodes = Self.bounds("\(s)-\(e)", max: 30)
                                } else {
                                    nodes = Self.bounds(raw, max: 30)
                                }
                                let name = (i - recordStart >= 2) ? f[recordStart] : previousName
                                if let nodes = nodes {
                                    Self.add(&result, name: name, teacher: f[i - 1], room: f[i + 1],
                                             day: day, nodes: nodes, weekText: m[1] ?? "")
                                }
                                previousName = name
                                recordStart = i + 2
                            } else if Self.matchEntire(Self.reWeekNode, f[i]) == nil,
                                      f[i].hasSuffix("周"), i >= 3, i + 1 < f.count {
                                // CCUT: 分组格 id 显式给节次, 绝不从文本顺序推断。
                                guard let idGroups = Self.matchEntire(Self.reGroupDayId, blockId) else { continue }
                                guard Int(idGroups[2] ?? "") == day else { continue }
                                guard let group = Int(idGroups[1] ?? "") else { continue }
                                Self.add(&result, name: f[i - 3], teacher: f[i - 1], room: f[i + 1],
                                         day: day, nodes: (group * 2 - 1, group * 2), weekText: f[i])
                                recordStart = i + 2
                            }
                        }
                    }
                }
            }
        }

        return Self.dedup(result)
    }

    // MARK: - JwParserConfidenceReporting

    /// ← Kotlin: generateCourseList 非空 → 100; 有 kbtable → 50; 否则 0。
    var confidenceValue: Int {
        let courses = (try? generateCourseList()) ?? []
        if !courses.isEmpty { return 100 }
        if ((try? doc?.getElementById("kbtable")) ?? nil) != nil { return 50 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if ((try? doc?.getElementById("kbtable")) ?? nil) != nil { out.append("id=kbtable") }
        if ((try? doc?.getElementById("kb")) ?? nil) != nil { out.append("old-qz:title-table") }
        if let doc = doc,
           ((try? doc.select("[id]")) ?? Elements()).array().contains(where: { el in
               Self.matchesEntire(Self.reFixedId, (try? el.id()) ?? "")
           }) {
            out.append("old-qz:fixed-cell-id")
        }
        return out
    }

    // MARK: - 字段/结构辅助

    /// 周次段 → [(start, end, type)]; 任一 token 非法 → 整条记录拒绝 (空数组)。
    private static func weeks(_ text: String) -> [(Int, Int, Int)] {
        var clean = text.trimmingCharacters(in: .whitespaces)
        clean = clean.trimmingCharacters(in: CharacterSet(charactersIn: "()[]（）"))
        clean = clean.replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: " ", with: "")
        let tokens = clean.components(separatedBy: CharacterSet(charactersIn: ",，"))
        var result: [(Int, Int, Int)] = []
        for token in tokens {
            let type: Int
            if token.hasSuffix("单") { type = 1 }
            else if token.hasSuffix("双") { type = 2 }
            else { type = 0 }
            var bare = token
            if bare.hasSuffix("单") || bare.hasSuffix("双") {
                bare = String(bare.dropLast())
            }
            guard let b = bounds(bare, max: 64) else { return [] }
            result.append((b.0, b.1, type))
        }
        return result
    }

    /// "1-16" / "3" → (start, end); 越界 → nil。
    private static func bounds(_ text: String, max: Int) -> (Int, Int)? {
        guard let g = Self.matchEntire(reRange, text), let start = Int(g[1] ?? "") else { return nil }
        let end = Int(g[2] ?? "") ?? start
        guard (1...max).contains(start), (start...max).contains(end) else { return nil }
        return (start, end)
    }

    /// 单元格 → 叶子 div 列表 (无 div 后代); 无 div 时整格自成一个块。
    /// ← Kotlin: cell.select("div").filter { it.select("div").none { child -> child !== it } }
    /// (select 取的是后代, 后代永远 ≠ 自身, 故条件即"无 div 后代")
    private static func blocks(_ cell: Element) -> [Element] {
        let divs = ((try? cell.select("div")) ?? Elements()).array()
        let leaves = divs.filter { div -> Bool in
            ((try? div.select("div")) ?? Elements()).isEmpty()
        }
        return leaves.isEmpty ? [cell] : leaves
    }

    /// 块字段: html 按 <br> 切分后逐段取文本。
    private static func fields(_ block: Element) -> [String] {
        let html = (try? block.html()) ?? ""
        let ns = html as NSString
        let matches = reBr.matches(in: html, options: [], range: NSRange(location: 0, length: ns.length))
        var parts: [String] = []
        var cursor = 0
        for m in matches {
            if m.range.location > cursor {
                parts.append(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            cursor = m.range.upperBound
        }
        if cursor < ns.length { parts.append(ns.substring(from: cursor)) }
        return parts.map { fragment -> String in
            let d = (try? SwiftSoup.parse(fragment)) ?? Document("")
            return ((try? d.text()) ?? "").trimmingCharacters(in: .whitespaces)
        }
    }

    /// 块或任一祖先隐藏 → true。
    private static func isHidden(_ block: Element) -> Bool {
        var chain: [Element] = [block]
        if let parents = try? block.parents() { chain += parents.array() }
        return chain.contains { el -> Bool in
            let style = (try? el.attr("style")) ?? ""
            if reDisplayNone.firstMatch(in: style, options: [],
                                        range: NSRange(location: 0, length: (style as NSString).length)) != nil {
                return true
            }
            return el.hasAttr("hidden")
        }
    }

    /// 记录落表: 名称/星期/节次三重护栏 + 周次段展开。
    private static func add(_ result: inout [JwCourse], name: String, teacher: String, room: String,
                            day: Int, nodes: (Int, Int), weekText: String) {
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return }
        guard (1...7).contains(day), (1...30).contains(nodes.0), nodes.1 >= nodes.0, nodes.1 <= 30 else { return }
        let trimmedTeacher = teacher.trimmingCharacters(in: CharacterSet(charactersIn: "()[]"))
        for (start, end, type) in weeks(weekText) {
            result.append(JwCourse(name: name, room: room, teacher: trimmedTeacher,
                                   day: day, startNode: nodes.0, endNode: nodes.1,
                                   startWeek: start, endWeek: end, type: type))
        }
    }

    /// Kotlin `title.split(Regex("\\r?\\n"))` — \r\n 视为单个分隔符 (不产生空 token)。
    private static func splitNewlines(_ s: String) -> [String] {
        let ns = s as NSString
        let re = try! NSRegularExpression(pattern: "\r?\n")
        let matches = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        var parts: [String] = []
        var cursor = 0
        for m in matches {
            if m.range.location > cursor {
                parts.append(ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            cursor = m.range.upperBound
        }
        parts.append(ns.substring(from: cursor))
        return parts
    }

    /// Kotlin `it.substringAfter('：')` — 缺分隔符返回原串。
    private static func afterColon(_ line: String) -> String {
        guard let r = line.range(of: "：") else { return line }
        return String(line[r.upperBound...])
    }

    /// 最近 table 祖先 (等价 Jsoup closest("table"))。
    private static func nearestTable(_ el: Element) -> Element? {
        let parents = (try? el.parents()) ?? Elements()
        return parents.array().first { $0.tagNameNormal() == "table" }
    }

    /// Kotlin `result.distinct()` (JwCourse 全字段 Equatable)。
    private static func dedup(_ courses: [JwCourse]) -> [JwCourse] {
        var seen: Set<JwCourse> = []
        var out: [JwCourse] = []
        for c in courses where seen.insert(c).inserted { out.append(c) }
        return out
    }

    // MARK: - 正则辅助

    private static func matchEntire(_ re: NSRegularExpression, _ s: String) -> [Int: String]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)),
              m.range.location == 0, m.range.upperBound == ns.length else { return nil }
        var out: [Int: String] = [:]
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            guard r.location != NSNotFound, r.length > 0 else { continue }
            out[i] = ns.substring(with: r)
        }
        return out
    }

    private static func matchesEntire(_ re: NSRegularExpression, _ s: String) -> Bool {
        Self.matchEntire(re, s) != nil
    }
}
