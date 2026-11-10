// JwScauParser.swift — ← JwScauParser.kt
//
// 华南农业大学 (SCAU, jwxt.scau.edu.cn) 教务解析器。
//
// 原版本 侧证据与限制: docs/scau-cross-verify-2026-10-13/。
//
// 三条互相独立设门的页面形态:
//   1. Element UI (greyovo/Njw2017 固定样本) — `.el-table__body-wrapper table.el-table__body`
//      七个星期单元格跟在节次单元格之后; 每格内是 style 含 `position: relative` 的 div 块,
//      块内 8 个 div 依次为 [空,空,空,课程名,教师,班级,时间,教室]。
//   2. 主路径 (WakeUp o00OOO00 — 强智新教务 lyuap HTML grid) — `table[border=1]`
//      且带 `td[valign=top]`; 单元格文本按 `<br>` 拆成 课程名/教师/周次/教室 四行字段。
//   3. 降级路径 (WakeUp SCAUParser 老视图残留) — `table[border=1][bordercolor=#000000]`
//      节次标题行 + 紧随其后的数据行成对出现; 数据格首行是 `课程名：教师` (全角冒号)。
//
// 与 原版本 的两处实现差异(均有据可依, 详见各函数注释):
//   a. 单元格分字段用 `html()` + `<br>` 正则切分, 不用 `text()`。
//      Jsoup 的 `html()` 把 `<br>` 输出成字面 "<br>", SwiftSoup 输出自闭合 "<br />",
//      故 原版本 的字面量 `split("<br>")` 在 Swift 上永远切不开 → 整格塌成一行。
//      正则切分 `<br\s*/?>` 是与 Jsoup 行为等价的翻译。
//   b. 单双周 type 取值沿用 原版本 原样(单→1 / 双→2 / 其余→0), 与 `JwCourse.type`
//      的 0=每周 / 1=单周 / 2=双周 语义一致(原版本 的 UMOOC/YL 解析器把 双→0 是笔误)。

import Foundation
import SwiftSoup

final class JwScauParser: JwParser, JwParserConfidenceReporting {

    // MARK: - 常量(与 原 companion object 一致)

    /// 节次正则: 匹配如 "5节)" / "12节)"。
    /// 暴露为 internal 供契约测试直接断言(与 原 companion object 的 RE_SECTION 同型)。
    static let reSectionProbe = try! NSRegularExpression(pattern: "(\\d+)节\\)")
    /// 半角/全角 单/双周 标注。
    private static let reParityHalf = try! NSRegularExpression(pattern: "[(（](单|双)[)）]")

    /// 主路径容器选择器(无 bordercolor 限定)。
    static let selectPrimaryTable = "table[border=1]"
    /// 降级路径容器选择器(含 bordercolor=#000000)。
    static let selectFallbackTable = "table[border=1][bordercolor=#000000]"
    /// 单元选择器。
    static let selectTdValignTop = "td[valign=top]"

    /// 节次行标签: "1-2节" / "3节"。
    private static let reRowLabel = try! NSRegularExpression(pattern: "^([0-9]+)(?: *[-－~至] *([0-9]+))?节$")
    /// 节次文本前缀截断后的同一形状。
    private static let reSectionLabel = try! NSRegularExpression(pattern: "^([0-9]+)(?: *[-－~至] *([0-9]+))?节$")
    /// 周次片段: 纯数字/逗号/横线。
    private static let reWeekSegment = try! NSRegularExpression(pattern: "[\\d,\\-]+")
    /// 括号内文本(周次)。
    private static let reBracket = try! NSRegularExpression(pattern: "[（(]([^）)]+)[）)]")
    /// style 里的 position: relative。
    private static let rePositionRelative = try! NSRegularExpression(
        pattern: "(?:^|;) *position *: *relative *(?:;|$)", options: [.caseInsensitive])
    /// 周次区间的完整匹配。
    private static let reWeekRange = try! NSRegularExpression(pattern: "^ *([0-9]+)(?: *[-－—~至] *([0-9]+))? *$")

    let source: String

    init(_ source: String) {
        self.source = source
    }

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        let elementUi = parseElementUiStrategy()
        if !elementUi.isEmpty { return elementUi }
        let explicit = parseExplicitSectionStrategy()
        if !explicit.isEmpty { return explicit }
        let primary = parsePrimaryStrategy()
        if !primary.isEmpty { return primary }
        let paired = parseFallbackStrategy()
        return paired.isEmpty ? parseIndexedFallbackStrategy() : paired
    }

    private func parseExplicitSectionStrategy() -> [JwCourse] {
        guard let doc = Jw64.doc(source) else { return [] }
        var output: [JwCourse] = []
        for table in Jw64.select(doc, Self.selectPrimaryTable) {
            for row in Jw64.select(table, "tr") {
                for (dayIndex, cell) in Jw64.select(row, Self.selectTdValignTop).enumerated() where dayIndex < 7 {
                    let lines = Self.cellLines(cell)
                    for (index, line) in lines.enumerated() {
                        guard let section = Jw64.matches(#"\(([^()]+)节\)"#, line).first else { continue }
                        let packed = Jw64.trim(section[1])
                        let sections: [(Int, Int)]
                        if packed.contains("-") { sections = schoolNodeRanges(packed) }
                        else {
                            let pair: (String, String)
                            switch packed.count {
                            case 1: pair = (packed, packed)
                            case 2: pair = (String(packed.prefix(1)), String(packed.suffix(1)))
                            case 3: pair = (String(packed.prefix(1)), String(packed.suffix(2)))
                            case 4: pair = (String(packed.prefix(2)), String(packed.suffix(2)))
                            default: continue
                            }
                            sections = schoolNodeRanges(pair.0 + "-" + pair.1)
                        }
                        let first = index == 0
                        let nameIndex = first ? index : index - 1
                        let roomIndex = index + (first ? 1 : 2)
                        guard lines.indices.contains(nameIndex), !lines[nameIndex].isEmpty,
                              lines.indices.contains(roomIndex), lines.indices.contains(index + 3), first || lines.indices.contains(index + 1) else { continue }
                        let parity = line.contains("(单)") || line.contains("（单）") ? 1 : (line.contains("(双)") || line.contains("（双）") ? 2 : 0)
                        for (sw, ew, type) in parseWeekRuns(lines[index + 3], parity: parity, globalParity: true) {
                            for (start, end) in sections {
                                output.append(JwCourse(name: lines[nameIndex], room: lines[roomIndex], teacher: first ? "" : lines[index + 1],
                                                       day: dayIndex + 1, startNode: start, endNode: end, startWeek: sw, endWeek: ew, type: type))
                            }
                        }
                    }
                }
            }
        }
        return output
    }

    private func parseIndexedFallbackStrategy() -> [JwCourse] {
        guard let doc = Jw64.doc(source) else { return [] }
        var output: [JwCourse] = []
        for table in Jw64.select(doc, Self.selectFallbackTable) {
            let rows = Jw64.rows(table)
            if rows.contains(where: { row in Jw64.select(row, "td").contains { Self.reSectionProbe.firstMatch(in: Jw64.text($0), range: NSRange(Jw64.text($0).startIndex..., in: Jw64.text($0))) != nil } }) { continue }
            for (index, row) in rows.dropFirst(2).enumerated() {
                guard let nodes = explicitSchedulePair(index + 1) else { continue }
                for (dayIndex, cell) in Jw64.select(row, Self.selectTdValignTop).enumerated() where dayIndex < 7 {
                    let fields = Self.cellLines(cell)
                    guard fields.count >= 3 else { continue }
                    var name = Jw64.trim(fields[0].components(separatedBy: "：").first ?? "")
                    let teacher = fields[0].contains("：") ? Jw64.trim(fields[0].components(separatedBy: "：").dropFirst().joined(separator: "：")) : ""
                    let suffix = name.contains(" ") ? String(name.split(separator: " ", omittingEmptySubsequences: false).last ?? "") : ""
                    let suffixRange = NSRange(suffix.startIndex..., in: suffix)
                    let weekText: String
                    if let match = Self.reWeekSegment.firstMatch(in: suffix, range: suffixRange), match.range == suffixRange {
                        name = name.components(separatedBy: " ").dropLast().joined().replacingOccurrences(of: " ", with: "")
                        weekText = suffix
                    } else { weekText = fields[2].components(separatedBy: "周").first ?? "" }
                    guard !name.isEmpty, !(fields[2].contains("单") && fields[2].contains("双")) else { continue }
                    let parity = fields[2].contains("单") ? 1 : (fields[2].contains("双") ? 2 : 0)
                    for (sw, ew, type) in parseWeekRuns(weekText, parity: parity, globalParity: true) {
                        output.append(JwCourse(name: name, room: fields[1], teacher: teacher, day: dayIndex + 1,
                                               startNode: nodes.lowerBound, endNode: nodes.upperBound, startWeek: sw, endWeek: ew, type: type))
                    }
                }
            }
        }
        return output
    }

    // MARK: - 策略一: Element UI

    /// 固定 greyovo/ScheduleXParser_SCAU 样本: Element UI 的七个星期单元格跟在节次单元格之后。
    func parseElementUiStrategy() -> [JwCourse] {
        var out: [JwCourse] = []
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        guard let tables = try? doc.select(".el-table__body-wrapper table.el-table__body"), !tables.isEmpty() else { return [] }
        let defaults: [(Int, Int)] = [(1, 2), (3, 5), (6, 7), (8, 9), (10, 12), (13, 15)]
        for table in tables {
            guard let rows = try? table.select("tbody > tr"), !rows.isEmpty() else { continue }
            for (rowIndex, tr) in rows.enumerated() {
                let cells = tr.children().filter { $0.tagNameNormal() == "td" }
                if cells.count < 8 { continue }
                let firstText = (try? cells[0].text())?.trimmingCharacters(in: .whitespaces) ?? ""
                let rowNodes: (Int, Int)?
                if let m = JwScauParser.reRowLabel.firstMatch(
                    in: firstText, range: NSRange(firstText.startIndex..., in: firstText)),
                    let s = jw1064Integer(JwScauParser.group(1, m, in: firstText)) {
                    let rawEnd = JwScauParser.group(2, m, in: firstText)
                    let e = rawEnd.isEmpty ? s : jw1064Integer(rawEnd) ?? 0
                    rowNodes = (1...366).contains(s) && e >= s && e <= 366 ? (s, e) : nil
                } else if firstText.isEmpty, rowIndex < defaults.count {
                    rowNodes = defaults[rowIndex]
                } else {
                    rowNodes = nil
                }
                for day in 1...7 {
                    let cell = cells[day]
                    guard let blocks = try? cell.select("div[style]") else { continue }
                    for block in blocks {
                        let style = (try? block.attr("style")) ?? ""
                        let styleRange = NSRange(style.startIndex..., in: style)
                        guard JwScauParser.rePositionRelative.firstMatch(in: style, options: [], range: styleRange) != nil else { continue }
                        let fields = block.children().filter { $0.tagNameNormal() == "div" }
                        if fields.count < 8 { continue }
                        let name = ((try? fields[3].text()) ?? "")
                            .trimmingCharacters(in: .whitespaces)
                            .replacingOccurrences(of: "*", with: "", options: [.anchored])
                            .trimmingCharacters(in: .whitespaces)
                        let teacher = ((try? fields[4].text()) ?? "").trimmingCharacters(in: .whitespaces)
                        let timing = ((try? fields[6].text()) ?? "").trimmingCharacters(in: .whitespaces)
                        let weekText = JwScauParser.bracketContent(timing)
                        let room = ((try? fields[7].text()) ?? "").trimmingCharacters(in: .whitespaces)
                        if name.isEmpty || weekText.isEmpty { continue }
                        let parity = weekText.contains("单") ? 1 : (weekText.contains("双") ? 2 : 0)
                        let head = timing
                            .components(separatedBy: "(").first ?? ""
                            .components(separatedBy: "（").first ?? ""
                            .trimmingCharacters(in: .whitespaces)
                        let nodes: (Int, Int)
                        if let m = JwScauParser.reSectionLabel.firstMatch(
                            in: head, range: NSRange(head.startIndex..., in: head)),
                            let s = jw1064Integer(JwScauParser.group(1, m, in: head)) {
                            let rawEnd = JwScauParser.group(2, m, in: head)
                            let e = rawEnd.isEmpty ? s : jw1064Integer(rawEnd) ?? 0
                            nodes = (s, e)
                        } else if timing.contains("节") {
                            continue
                        } else if let rn = rowNodes {
                            nodes = rn
                        } else {
                            continue
                        }
                        if nodes.0 < 1 || nodes.0 > 366 || nodes.1 < nodes.0 || nodes.1 > 366 { continue }
                        for (sw, ew, type) in parseWeekRuns(weekText, parity: parity) {
                            out.append(JwCourse(name: name, room: room, teacher: teacher, day: day,
                                                startNode: nodes.0, endNode: nodes.1,
                                                startWeek: sw, endWeek: ew, type: type))
                        }
                    }
                }
            }
        }
        return out
    }

    // MARK: - 策略二: 主路径

    /// WakeUp o00OOO00 形态: `table[border=1]` + `td[valign=top]`, 字段按 `<br>` 拆行。
    private func parsePrimaryStrategy() -> [JwCourse] {
        var out: [JwCourse] = []
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        guard let tables = try? doc.select(JwScauParser.selectPrimaryTable) else { return [] }
        for table in tables {
            // SwiftSoup 的 `table[border=1]` 同时命中带 bordercolor 的表(与 Jsoup 同),
            // 原版本 侧显式排除 → 这里同样排除。
            if table.hasAttr("bordercolor") { continue }
            var courseRow = 0
            guard let rows = try? table.select("tr") else { continue }
            for tr in rows {
                let allChildren = tr.children()
                let cells = allChildren.filter { $0.tagNameNormal() == "td" }
                if cells.isEmpty || allChildren.contains(where: { $0.tagNameNormal() == "th" }) { continue }
                let firstCellText = ((try? cells[0].text()) ?? "").trimmingCharacters(in: .whitespaces)
                for (tdIndex, td) in cells.enumerated() {
                    let valign = (try? td.attr("valign")) ?? ""
                    if valign.lowercased() != "top" { continue }
                    let hasSectionColumn = cells.count > 7
                        || (cells.count != 7 && firstCellText.isEmpty && !cells[0].hasAttr("valign"))
                    let day = tdIndex + (hasSectionColumn ? 0 : 1)
                    if !(1...7).contains(day) { continue }
                    let parsed = JwScauParser.cellLines(td)
                    var sectionFound = false
                    for line in parsed {
                        if JwScauParser.reSectionProbe.firstMatch(
                            in: line, range: NSRange(line.startIndex..., in: line)) != nil {
                            sectionFound = true
                            break
                        }
                    }
                    if !sectionFound { continue }
                    let joinedText = parsed.count > 2 ? parsed[2] : ""
                    let type: Int
                    if joinedText.contains("(单)") || joinedText.contains("（单）") {
                        type = 1
                    } else if joinedText.contains("(双)") || joinedText.contains("（双）") {
                        type = 2
                    } else {
                        type = 0
                    }
                    let name = parsed.count > 0 ? parsed[0].trimmingCharacters(in: .whitespaces) : ""
                    let teacher = parsed.count > 1 ? parsed[1].trimmingCharacters(in: .whitespaces) : ""
                    let runs = parseWeekRuns(parsed.count > 2 ? parsed[2] : "", parity: type)
                    if name.isEmpty || runs.isEmpty { continue }
                    let room = parsed.count > 3 ? parsed[3].trimmingCharacters(in: .whitespaces) : ""
                    for (sw, ew, parity) in runs {
                        out.append(JwCourse(name: name, room: room, teacher: teacher, day: day,
                                            startNode: courseRow * 2 + 1, endNode: courseRow * 2 + 2,
                                            startWeek: sw, endWeek: ew, type: parity))
                    }
                }
                courseRow += 1
            }
        }
        return out
    }

    // MARK: - 策略三: 降级路径

    /// WakeUp SCAUParser 老视图: `table[border=1][bordercolor=#000000]`,
    /// 节次标题行与紧随的数据行成对; 数据格首行 `课程名：教师`。
    private func parseFallbackStrategy() -> [JwCourse] {
        var out: [JwCourse] = []
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        guard let tables = try? doc.select(JwScauParser.selectFallbackTable) else { return [] }
        for table in tables {
            guard let trList = try? table.select("tr"), trList.count >= 2 else { continue }
            for rowIndex in 0..<(trList.count - 1) {
                let trSection = trList[rowIndex]
                if trSection.children().contains(where: { $0.tagNameNormal() == "th" }) { continue }
                guard let sectionTds = try? trSection.select("td"),
                      sectionTds.contains(where: {
                          let t = (try? $0.text()) ?? ""
                          return JwScauParser.reSectionProbe.firstMatch(
                              in: t, range: NSRange(t.startIndex..., in: t)) != nil
                      }) else { continue }
                let trData = trList[rowIndex + 1]
                let tdSectionList = trSection.children().filter { $0.tagNameNormal() == "td" }
                let tdDataList = trData.children().filter { $0.tagNameNormal() == "td" }
                for (tdIdx, tdData) in tdDataList.enumerated() {
                    let valign = (try? tdData.attr("valign")) ?? ""
                    if valign.lowercased() != "top" { continue }
                    let day = tdIdx + (tdDataList.count > 7 ? 0 : 1)
                    if !(1...7).contains(day) { continue }
                    let parsed = JwScauParser.cellLines(tdData)
                    let checkText = parsed.count > 1 ? parsed[1] : ""
                    let type: Int
                    if checkText.contains("单") { type = 1 }
                    else if checkText.contains("双") { type = 2 }
                    else { type = 0 }
                    let firstLine = parsed.count > 0 ? parsed[0] : ""
                    var name = firstLine.trimmingCharacters(in: .whitespaces)
                    var teacher = ""
                    if firstLine.contains("：") {
                        let parts = firstLine.components(separatedBy: "：")
                        name = (parts.first ?? "").trimmingCharacters(in: .whitespaces)
                        teacher = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
                    }
                    let runs = parseWeekRuns(parsed.count > 1 ? parsed[1] : "", parity: type)
                    if name.isEmpty || runs.isEmpty { continue }
                    let room = parsed.count > 2 ? parsed[2].trimmingCharacters(in: .whitespaces) : ""
                    guard tdIdx < tdSectionList.count else { continue }
                    let tdSection = tdSectionList[tdIdx]
                    let sectionText = (try? tdSection.text()) ?? ""
                    guard let m = JwScauParser.reSectionProbe.firstMatch(
                        in: sectionText, range: NSRange(sectionText.startIndex..., in: sectionText)),
                        let sectionNum = jw1064Integer(JwScauParser.group(1, m, in: sectionText)),
                          let sectionNodes = explicitSchedulePair(sectionNum) else { continue }
                    for (sw, ew, parity) in runs {
                        out.append(JwCourse(name: name, room: room, teacher: teacher, day: day,
                                            startNode: sectionNodes.lowerBound, endNode: sectionNodes.upperBound,
                                            startWeek: sw, endWeek: ew, type: parity))
                    }
                }
            }
        }
        return out
    }

    // MARK: - 周次

    /// 取首段起点 + 末段终点(与 原 parseWeekRange 一致)。
    func parseWeekRange(_ parsed: [String], weeksLineIndex: Int) -> (Int, Int) {
        let runs = parseWeekRuns(weeksLineIndex < parsed.count ? parsed[weeksLineIndex] : "")
        guard let first = runs.first, let last = runs.last else { return (0, 0) }
        return (first.0, last.1)
    }

    /// 稀疏周次保持为独立区间(与 原 parseWeekRuns 一致)。
    ///
    /// 返回三元组 (起始周, 结束周, 单双标记)。
    func parseWeekRuns(_ text: String, parity: Int = 0, globalParity: Bool = false) -> [(Int, Int, Int)] {
        var runs: [(Int, Int, Int)] = []
        let tokens = JwScauParser.splitTokens(text)
        for token in tokens {
            let explicit = token.contains("单") ? 1 : (token.contains("双") ? 2 : 0)
            if globalParity && parity != 0 && explicit != 0 && parity != explicit { return [] }
            let tokenParity = explicit != 0 ? explicit : (globalParity || tokens.count == 1 ? parity : 0)
            var clean = token
            for token2 in ["（单）", "（双）", "(单)", "(双)", "单周", "双周", "周"] {
                clean = clean.replacingOccurrences(of: token2, with: "")
            }
            guard let m = JwScauParser.reWeekRange.firstMatch(
                in: clean, range: NSRange(clean.startIndex..., in: clean)) else { return [] }
            guard let start = jw1064Integer(JwScauParser.group(1, m, in: clean)) else { return [] }
            let rawEnd = JwScauParser.group(2, m, in: clean)
            guard let end = rawEnd.isEmpty ? start : jw1064Integer(rawEnd),
                  (1...366).contains(start), end >= start, end <= 366 else { return [] }
            var weeks: [Int] = []
            for w in start...end where tokenParity == 0 || w % 2 == tokenParity % 2 {
                weeks.append(w)
            }
            if weeks.isEmpty { continue }
            var first = weeks[0]
            var last = first
            for week in weeks.dropFirst() {
                let gap = week - last
                if gap != 1 && !(tokenParity != 0 && gap == 2) {
                    runs.append((first, last, tokenParity))
                    first = week
                }
                last = week
            }
            runs.append((first, last, tokenParity))
        }
        let sorted = runs.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        var merged: [(Int, Int, Int)] = []
        for run in sorted {
            if let last = merged.last {
                let step = run.2 == 0 ? 1 : 2
                if last.2 == run.2 && run.0 <= last.1 + step {
                    merged[merged.count - 1] = (last.0, max(last.1, run.1), run.2)
                    continue
                }
            }
            merged.append(run)
        }
        return merged
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        var hits = 0
        let primaryTables = (try? doc.select(JwScauParser.selectPrimaryTable)) ?? Elements()
        let hasPrimary = primaryTables.contains { !$0.hasAttr("bordercolor") }
        let fallbackTables = (try? doc.select(JwScauParser.selectFallbackTable)) ?? Elements()
        let hasFallback = !fallbackTables.isEmpty
        if hasFallback { hits += 3 }
        if hasPrimary { hits += 2 }
        let valignTds = (try? doc.select("table[border=1] td[valign=top]")) ?? Elements()
        if !valignTds.isEmpty { hits += 2 }
        let allTds = (try? doc.select("table[border=1] td")) ?? Elements()
        if allTds.contains(where: {
            let t = (try? $0.text()) ?? ""
            return JwScauParser.reSectionProbe.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
        }) { hits += 2 }
        if source.contains("<head>") && source.contains("</head>") { hits += 1 }
        if fallbackTables.contains(where: {
            let t = (try? $0.text()) ?? ""
            return t.contains("：")
        }) { hits += 1 }
        switch hits {
        case 8...: return 95
        case 6...: return 80
        case 4...: return 60
        case 2...: return 30
        default: return 0
        }
    }

    var matchedFeatureList: [String] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        var out: [String] = []
        let primaryTables = (try? doc.select(JwScauParser.selectPrimaryTable)) ?? Elements()
        let fallbackTables = (try? doc.select(JwScauParser.selectFallbackTable)) ?? Elements()
        if !fallbackTables.isEmpty { out.append("scau:bordercolor-fallback") }
        if primaryTables.contains(where: { !$0.hasAttr("bordercolor") }) { out.append("scau:border-primary") }
        let valignTds = (try? doc.select(JwScauParser.selectTdValignTop)) ?? Elements()
        if !valignTds.isEmpty { out.append("scau:valign-top-td") }
        if JwScauParser.reSectionProbe.firstMatch(
            in: source, range: NSRange(source.startIndex..., in: source)) != nil {
            out.append("scau:section-regex")
        }
        if source.contains("<head>") && source.contains("</head>") { out.append("scau:head-slice") }
        if source.contains("：") { out.append("scau:fullwidth-colon") }
        if JwScauParser.reParityHalf.firstMatch(
            in: source, range: NSRange(source.startIndex..., in: source)) != nil {
            out.append("scau:parity-marker")
        }
        if JwScauParser.reWeekSegment.firstMatch(
            in: source, range: NSRange(source.startIndex..., in: source)) != nil {
            out.append("scau:week-segment")
        }
        return out
    }

    // MARK: - 工具

    /// 取正则第 `idx` 组(1-based)。
    private static func group(_ idx: Int, _ match: NSTextCheckingResult, in s: String) -> String {
        groupValue(idx, match, in: s)
    }

    /// 取正则第 `idx` 组(1-based) — 供契约测试断言。
    static func groupValue(_ idx: Int, _ match: NSTextCheckingResult, in s: String) -> String {
        guard idx < match.numberOfRanges else { return "" }
        let r = match.range(at: idx)
        guard r.location != NSNotFound, let range = Range(r, in: s) else { return "" }
        return String(s[range])
    }

    /// 括号内文本(如 "(1-8周)" → "1-8周")。
    private static func bracketContent(_ s: String) -> String {
        guard let m = reBracket.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return "" }
        return group(1, m, in: s)
    }

    /// 周次串按 "," / "，" / "、" / ";" / "；" 分段。
    private static func splitTokens(_ s: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",，、;；")
        return s.components(separatedBy: separators)
    }

    /// 单元格分字段: 取 `html()` 后按 `<br>` 正则切分, 每段再取文本。
    ///
    /// 原版本 用 `td.html().split("<br>")`; Jsoup 输出字面 "<br>", SwiftSoup 输出 "<br />",
    /// 故用正则 `<br\s*/?>` 切 — 与 Jsoup 行为等价。
    private static func cellLines(_ td: Element) -> [String] {
        let html = (try? td.html()) ?? ""
        let chunks = splitByRegex(html, #"<br\s*/?>"#)
        return chunks.map { chunk -> String in
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return "" }
            guard let doc = try? SwiftSoup.parse(trimmed) else { return trimmed }
            return ((try? doc.text()) ?? trimmed).trimmingCharacters(in: .whitespaces)
        }
    }

    /// 正则切分(与 WakeUpCompat.splitByRegex 同型; 那份是 fileprivate, 这里自带一份)。
    private static func splitByRegex(_ s: String, _ pattern: String) -> [String] {
        let re = try! NSRegularExpression(pattern: pattern, options: [])
        let full = NSRange(s.startIndex..., in: s)
        var parts: [String] = []
        var cursor = s.startIndex
        for m in re.matches(in: s, options: [], range: full) {
            guard let r = Range(m.range, in: s) else { continue }
            parts.append(String(s[cursor..<r.lowerBound]))
            cursor = r.upperBound
        }
        parts.append(String(s[cursor...]))
        return parts
    }
}
