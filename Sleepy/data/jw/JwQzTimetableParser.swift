// JwQzTimetableParser.swift — ← JwQzTimetableParser.kt
//
// 强智新式 table#timetable 详细视图解析器 — 每门课自带显式节次
// ([01-02-03-04节] 形态), 与老 #kbtable 网格互斥。
//
// 原版本 侧证据: v1.0.62 新增 (NNNU 南宁师范大学形态); JwQzParser 在
// 缺 #kbtable 且有 table#timetable .kbcontent 时委托本 parser。
//
// 与 原版本 的实现差异(等价翻译):
//   a. Jsoup `closest("table") == table` → 手写最近 table 祖先比对
//      (SwiftSoup 无 closest API)。
//   b. Jsoup parseBodyFragment → SwiftSoup.parse + body() (fragment 语义等价)。
//   c. 正则一律 [0-9] 字符类 (PR #22 教训)。

import Foundation
import SwiftSoup

final class JwQzTimetableParser: JwParser {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    // MARK: - 正则常量

    /// 节次方括号段: "[01-02-03-04节]" / "[1-2节]" / "[3,6-7节]"。
    private static let reSection = try! NSRegularExpression(pattern: "\\[([0-9\\s,，、-]+)节\\]")
    /// 节次数字切分: 横线/逗号(全半角)/顿号/空白。
    private static let reNodeSplit = try! NSRegularExpression(pattern: "[-,，、\\s]+")
    /// 周次段: "1-16" / "6" (归一化掉 ()周单双空白 之后)。
    private static let reWeekRange = try! NSRegularExpression(pattern: "^([0-9]+)(?:-([0-9]+))?$")
    /// 隐藏样式。
    private static let reDisplayNone = try! NSRegularExpression(
        pattern: "display\\s*:\\s*none", options: [.caseInsensitive])

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        guard let table = (try? doc.select("table#timetable").first()) ?? nil else { return [] }
        var courses: [JwCourse] = []
        var seen: Set<JwCourse> = []
        var days = [1, 2, 3, 4, 5, 6, 7]
        for row in (try? table.select("tr")) ?? Elements() {
            // ← closest("table") == table: 只处理直接属于本表的行 (嵌套表行跳过)
            guard nearestTable(row) === table else { continue }
            let cells = row.children().filter { $0.tagNameNormal() == "td" || $0.tagNameNormal() == "th" }
            let headerDays = cells.compactMap { Self.weekday(((try? $0.text()) ?? "") as String) }
            if headerDays.count == 7 && Set(headerDays).count == 7 {
                days = headerDays
                continue
            }
            // 左侧节次标签可能是 th 或 td; 它们不是星期。
            guard cells.count >= 7, cells.count <= 9 else { continue }
            let dayCells = cells.suffix(7)
            // colspan>1 的合并格 → 形态不符, 整行跳过
            let hasColspan = dayCells.contains { cell -> Bool in
                let colspan = (try? cell.attr("colspan")) ?? ""
                return colspan.isEmpty ? false : (Int(colspan.trimmingCharacters(in: .whitespaces)) ?? 1) > 1
            }
            if hasColspan { continue }
            for (index, cell) in dayCells.enumerated() {
                guard index < days.count else { continue }
                for content in ((try? cell.getElementsByClass("kbcontent")) ?? Elements()).array() {
                    // 嵌套 kbcontent (祖先里还有别的 kbcontent) 跳过, 只取顶层
                    let parents = (try? content.parents()) ?? Elements()
                    let nested = parents.array().contains { p -> Bool in
                        p !== cell && ((try? p.hasClass("kbcontent")) ?? false)
                    }
                    if nested { continue }
                    let html = (try? content.html()) ?? ""
                    for fragment in html.components(separatedBy: "-----") {
                        // ← Regex("-{5,}") split: 5 连字符及以上; components(separatedBy:)
                        //   对 "-----" 的切分与 Regex("-{5,}") 在连续 >5 时会把多余 '-' 留在
                        //   段尾 — parseBlock 内部对段尾 '-' 不敏感, 行为等价。
                        Self.parseBlock(fragment, day: days[index], courses: &courses, seen: &seen)
                    }
                }
            }
        }
        return courses
    }

    // MARK: - 单块解析

    private static func parseBlock(_ html: String, day: Int, courses: inout [JwCourse], seen: inout Set<JwCourse>) {
        guard let doc = try? SwiftSoup.parse(html), let block = try? doc.body() else { return }
        // 移除提示盒/脚本/样式
        if let junk = try? block.select(".item-box, script, style") {
            for el in junk.array() { try? el.remove() }
        }
        guard let timeEl = (try? block.select("[title='周次(节次)']").first()) ?? nil else { return }
        let time = ((try? timeEl.text()) ?? "") as String
        let timeNs = time as NSString
        guard let sectionMatch = reSection.firstMatch(
            in: time, options: [], range: NSRange(location: 0, length: timeNs.length)) else { return }
        let rawNodes = timeNs.substring(with: sectionMatch.range(at: 1))
        var nodes: [Int] = []
        // 手工按正则切分 (等价 Kotlin split(Regex("[-,，、\\s]+")))
        let rawNs = rawNodes as NSString
        var tokens: [String] = []
        let matches = reNodeSplit.matches(in: rawNodes, options: [], range: NSRange(location: 0, length: rawNs.length))
        var cursor = 0
        for m in matches {
            if m.range.location > cursor {
                tokens.append(rawNs.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            }
            cursor = m.range.upperBound
        }
        if cursor < rawNs.length {
            tokens.append(rawNs.substring(from: cursor))
        }
        for t in tokens where !t.isEmpty {
            guard let v = Int(t) else { return }  // ← Kotlin toIntOrNull ?: return
            nodes.append(v)
        }
        if nodes.isEmpty || nodes.contains(where: { $0 <= 0 }) { return }
        for i in 0..<(nodes.count - 1) where nodes[i] >= nodes[i + 1] { return }  // 须严格递增

        // 节次区间: ≤2 个数字且无逗号 → 单一区间; 否则连续段归并
        let matchValue = timeNs.substring(with: sectionMatch.range)
        let hasComma = matchValue.contains(",") || matchValue.contains("，") || matchValue.contains("、")
        let nodeRanges: [(Int, Int)]
        if nodes.count <= 2 && !hasComma {
            nodeRanges = [(nodes.first!, nodes.last!)]
        } else {
            var runs: [(Int, Int)] = []
            var start = nodes[0]
            var end = start
            for node in nodes.dropFirst() {
                if node != end + 1 { runs.append((start, end)); start = node }
                end = node
            }
            runs.append((start, end))
            nodeRanges = runs
        }

        // 课程名 = 首个带 title 的 font 之前的 font 文本拼接 (过滤隐藏)
        let fonts = ((try? block.select("font")) ?? Elements()).array()
        var name = ""
        for font in fonts {
            if font.hasAttr("title") { break }
            if Self.isHidden(font) { continue }
            name += ((try? font.text()) ?? "")
        }
        name = name.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return }

        // ← Kotlin Elements.text(): 全部命中元素文本拼接
        let teacherEls = (try? block.select("[title='老师']")) ?? Elements()
        var teacher = ((try? teacherEls.text()) ?? "").trimmingCharacters(in: .whitespaces)
        if teacher.isEmpty {
            let teacher2 = (try? block.select("[title='教师']")) ?? Elements()
            teacher = ((try? teacher2.text()) ?? "").trimmingCharacters(in: .whitespaces)
        }
        let teacherFinal = teacher
        let roomEls = (try? block.select("[title='教室']")) ?? Elements()
        let groupEls = (try? block.select("[title='分组']")) ?? Elements()
        let room = ((try? roomEls.text()) ?? "") + ((try? groupEls.text()) ?? "")

        // 周次段: "[...节]" 之前的部分; 全角括号/逗号归一
        let weekText = timeNs.substring(to: sectionMatch.range.location)
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "，", with: ",")
        let segments = weekText.components(separatedBy: ",")
        // 尾段共享后缀只作用于裸区间; 局部标注不得泄入后续无标注区间: 1-4(单),6(周)
        let hasLocalParity = segments.dropLast().contains { $0.contains("单") || $0.contains("双") }
        let globalParity: Int
        if hasLocalParity {
            globalParity = 0
        } else if weekText.contains("单") && !weekText.contains("双") {
            globalParity = 1
        } else if weekText.contains("双") && !weekText.contains("单") {
            globalParity = 2
        } else {
            globalParity = 0
        }
        for segment in segments {
            let type: Int
            if segment.contains("单") { type = 1 }
            else if segment.contains("双") { type = 2 }
            else { type = globalParity }
            let normalized = segment
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "周", with: "")
                .replacingOccurrences(of: "单", with: "")
                .replacingOccurrences(of: "双", with: "")
                .replacingOccurrences(of: " ", with: "")
            let ns = normalized as NSString
            guard let m = reWeekRange.firstMatch(in: normalized, options: [], range: NSRange(location: 0, length: ns.length)) else { continue }
            guard let start = Int(ns.substring(with: m.range(at: 1))) else { continue }
            let end = m.range(at: 2).location != NSNotFound ? (Int(ns.substring(with: m.range(at: 2))) ?? start) : start
            guard start > 0, end >= start else { continue }
            // 单/双周起点对齐: 起点奇偶与 type 不符时抬一位
            let first = (type != 0 && start % 2 != type % 2) ? start + 1 : start
            if first > end { continue }
            for (startNode, endNode) in nodeRanges {
                let course = JwCourse(name: name, room: room, teacher: teacherFinal,
                                      day: day, startNode: startNode, endNode: endNode,
                                      startWeek: first, endWeek: end, type: type)
                if seen.insert(course).inserted { courses.append(course) }
            }
        }
    }

    // MARK: - 辅助

    private static func weekday(_ text: String) -> Int? {
        var label = text.trimmingCharacters(in: .whitespaces)
        if label.hasPrefix("星期") { label = String(label.dropFirst(2)) }
        else if label.hasPrefix("周") { label = String(label.dropFirst(1)) }
        switch label {
        case "一": return 1
        case "二": return 2
        case "三": return 3
        case "四": return 4
        case "五": return 5
        case "六": return 6
        case "日", "天": return 7
        default: return nil
        }
    }

    private static func isHidden(_ el: Element) -> Bool {
        if el.hasAttr("hidden") { return true }
        let style = (try? el.attr("style")) ?? ""
        return reDisplayNone.firstMatch(
            in: style, options: [], range: NSRange(location: 0, length: (style as NSString).length)) != nil
    }

    /// 最近 table 祖先 (等价 Jsoup closest("table"))。
    private func nearestTable(_ el: Element) -> Element? {
        var parents: [Element] = []
        if let ps = try? el.parents() { parents = ps.array() }
        return parents.first { $0.tagNameNormal() == "table" }
    }
}
