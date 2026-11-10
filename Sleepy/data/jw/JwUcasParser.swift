// JwUcasParser.swift — ← JwUcasParser.kt 1:1 translation (GPL-3.0) — 1.0.52 alignment
// UCAS (中国科学院大学) personal schedule parser — JSON (authoritative) + HTML (fallback).

import Foundation
import SwiftSoup

final class JwUcasParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    /// HTML path provisional weeks (详情页尚未捕获, 1-16 周占位)
    static let PROVISIONAL_START_WEEK = 1
    static let PROVISIONAL_END_WEEK = 16

    /// 组合源里详情页段的分段标记。UcasDetailFetch 把网格 HTML 与逐课详情页拼成一个
    /// source 喂给本 parser; 解析器按标记切段, 标记里的 URL 仅信息性。
    static let DETAIL_MARKER_OPEN = "<!--sleepy-ucas-detail:"
    static let DETAIL_MARKER_CLOSE = "<!--/sleepy-ucas-detail-->"

    /// UCAS 详情站 host (相对形态 /course/coursetime/<id> 补全用)
    static let DETAIL_HOST = "https://xkcts.ucas.ac.cn:8443"

    /// ldiex/UCAS_Course_Schedule_Convertor 实测 dayBits -> 星期 1..7 (POSITIVE 证据, hardcode 不发明新编码)
    static let DAY_BITS: [String: Int] = [
        "10": 1, "11": 1, "100": 2, "110": 3,
        "1000": 4, "1010": 5, "1100": 6, "1110": 7,
    ]

    /// 课程周次类型: 0=每周, 1=单周, 2=双周
    static let TYPE_DEFAULT = 0
    static let TYPE_ODD = 1
    static let TYPE_EVEN = 2

    func generateCourseList() throws -> [JwCourse] {
        return parseJson() ?? parseHtml()
    }

    /// ← confidence(): JSON 命中 95 / HTML 命中 90 (iOS 检测层不消费, 保留供对齐)
    var confidenceValue: Int {
        if !Self.parseDetailPages(source).isEmpty { return 100 }
        if source.contains("\"courseTimeList\"") && source.contains("\"selectedCourse\"") { return 95 }
        if source.contains("个人课表") && source.contains("/course/coursetime/") { return 90 }
        return 0
    }

    var matchedFeatureList: [String] {
        var f: [String] = []
        if !Self.parseDetailPages(source).isEmpty { f.append("ucas:explicit-detail") }
        if source.contains("\"courseTimeList\"") { f.append("json:courseTimeList") }
        if source.contains("\"selectedCourse\"") { f.append("json:selectedCourse") }
        if source.contains("个人课表") { f.append("title:个人课表") }
        if source.contains("/course/coursetime/") { f.append("href:/course/coursetime/") }
        return f
    }

    /// JSON path: pick courseTimeList array, decode each schedule.
    /// nil return = no parsable JSON, caller falls back to HTML path.
    private func parseJson() -> [JwCourse]? {
        guard let courseTimeList = JwUcasParser.extractCourseTimeList(source) else { return nil }
        var result: [JwCourse] = []
        for item in courseTimeList {
            guard let item = item as? [String: Any] else { continue }
            let name = trim(item["courseName"])
            let place = trim(item["coursePlace"])
            guard let weekInt = optInt(item, "courseWeek"), let timeInt = optInt(item, "courseTime") else { continue }
            if name.isEmpty { continue }

            let weeks = JwUcasParser.decodeWeeks(weekInt)
            if weeks.isEmpty { continue }
            guard let (day, nodes) = Self.decodeTimeNodes(timeInt) else { continue }
            for (startNode, endNode) in Self.nodeSegments(nodes) {
            for run in JwUcasParser.splitWeekRuns(weeks) {
                result.append(JwCourse(name: name, room: place, day: day,
                                       startNode: startNode, endNode: endNode,
                                       startWeek: run.startWeek, endWeek: run.endWeek,
                                       type: run.type))
            }
            }
        }
        return result
    }

    /// 兼容两种 JSON 形态: A. 顶层 courseTimeList (拼合文档) B. 嵌套 data 字段 / 顶层数组
    static func extractCourseTimeList(_ raw: String) -> [Any]? {
        let uncommented = htmlCommentRe.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "")
        let trimmed = uncommented.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let jsonBody: String
        if trimmed.hasPrefix("[") { jsonBody = trimmed }
        else if let start = trimmed.firstIndex(of: "{") ?? trimmed.firstIndex(of: "[") { jsonBody = String(trimmed[start...]) }
        else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(jsonBody.utf8)) else { return nil }
        if let dict = obj as? [String: Any] {
            return (dict["courseTimeList"] as? [Any])
                ?? ((dict["data"] as? [String: Any])?["courseTimeList"] as? [Any])
        }
        if let arr = obj as? [Any] { return arr }
        return nil
    }

    /// courseWeek 整数位图 -> 周次列表 (低位=第1周)。21 (0b10101) -> [1,3,5]
    static func decodeWeeks(_ weekInt: Int) -> [Int] {
        if weekInt <= 0 { return [] }
        var weeks: [Int] = []
        var bit = 0
        var n = weekInt
        while n > 0 {
            if n & 1 == 1 { weeks.append(bit + 1) }
            bit += 1
            n >>= 1
        }
        return weeks
    }

    /// courseTime 整数 -> (day, startNode, endNode)。dayBits 不在 DAY_BITS 内 = 数据异常, 返回 nil。
    static func decodeTime(_ timeInt: Int) -> (Int, Int, Int)? {
        guard let (day, nodes) = decodeTimeNodes(timeInt), let first = nodes.first, let last = nodes.last else { return nil }
        return (day, first, last)
    }

    private static func decodeTimeNodes(_ timeInt: Int) -> (Int, [Int])? {
        guard timeInt > 0 else { return nil }
        let binary = String(timeInt, radix: 2)
        guard binary.count > 12, let day = DAY_BITS[String(binary.dropLast(12))] else { return nil }
        let nodes = binary.suffix(12).reversed().enumerated().compactMap { $0.element == "1" ? $0.offset + 1 : nil }
        return nodes.isEmpty ? nil : (day, nodes)
    }

    private static func nodeSegments(_ nodes: [Int]) -> [(Int, Int)] {
        guard !nodes.isEmpty, nodes.allSatisfy({ (1...EXPLICIT_SCHEDULE_RESOURCE_BOUND).contains($0) }) else { return [] }
        var result: [(Int, Int)] = []
        for node in Set(nodes).sorted() {
            if let last = result.last, node == last.1 + 1 { result[result.count - 1] = (last.0, node) }
            else { result.append((node, node)) }
        }
        return result
    }

    /// weeks 列表归类 type: 全单周=1, 全双周=2, 混合=0
    static func weeksToType(_ weeks: [Int]) -> Int {
        if weeks.allSatisfy({ $0 % 2 == 1 }) { return TYPE_ODD }
        if weeks.allSatisfy({ $0 % 2 == 0 }) { return TYPE_EVEN }
        return TYPE_DEFAULT
    }

    // ---- HTML 详情路径 (v1.2 采集包, exact-week) ----

    /// 可表示周次段: startWeek..endWeek + type (每周/单周/双周)
    struct WeekRun: Equatable {
        let startWeek: Int
        let endWeek: Int
        let type: Int
    }

    /// 单个时间块: 星期 + 节次区间 + 教室 + 周次集合
    struct DetailBlock: Equatable {
        let day: Int
        let startNode: Int
        let endNode: Int
        var room: String = ""
        var weeks: [Int] = []
    }

    /// 详情页解析模型: 课程名 + 时间/地点/周次块列表
    struct DetailPage: Equatable {
        let courseName: String
        let blocks: [DetailBlock]
    }

    /// 数字列表 token: 纯数字或范围 (1-16 / 1~16 / 1至16)
    private static let numToken = try! NSRegularExpression(pattern: #"(\d+)\s*(?:[-–—~至]\s*(\d+))?"#)

    /// "2、3、4、5、7、8" → [2,3,4,5,7,8]。顿号枚举是实测唯一形态, 范围/逗号/全角逗号是宽容超集。
    static func parseNumberList(_ text: String) -> [Int] {
        var out: [Int] = []
        for token in text.components(separatedBy: CharacterSet(charactersIn: "、，,")) {
            let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let m = firstMatch(numToken, clean), m.range == NSRange(clean.startIndex..., in: clean),
                  let a = jw1064Integer(group(m, 1, clean)), let b = jw1064Integer(group(m, 2, clean) ?? group(m, 1, clean)),
                  (1...366).contains(a), (a...366).contains(b) else { return [] }
            out.append(contentsOf: a...b)
        }
        return Set(out).sorted()
    }

    static func parseDetailPages(_ html: String) -> [DetailPage] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }
        let panels = (try? doc.select(".mc-body").array()) ?? []
        return panels.isEmpty ? [parseDetailPage(html)].compactMap { $0 } : panels.compactMap { parseDetailPage((try? $0.outerHtml()) ?? "") }
    }

    /// 任意周次集合 → 可表示周次段。步长 1 → 每周段; 步长 2 → 单/双周段;
    /// 两种步长混排时在步长切换处断开, 缺口 > 2 也断开。单元素段 → 每周。
    static func splitWeekRuns(_ weeks: [Int]) -> [WeekRun] {
        let sorted = weeks.filter { $0 > 0 }.reduce(into: [Int]()) { acc, w in
            if !acc.contains(w) { acc.append(w) }
        }.sorted()
        if sorted.isEmpty { return [] }
        var runs: [WeekRun] = []
        var runStart = 0
        var prev = 0
        var step = 0  // 0=未定, 1=每周, 2=单/双周
        func flush() {
            if runStart == 0 { return }
            let type: Int
            if step == 2 { type = (runStart % 2 == 1) ? TYPE_ODD : TYPE_EVEN }
            else { type = TYPE_DEFAULT }
            runs.append(WeekRun(startWeek: runStart, endWeek: prev, type: type))
        }
        for w in sorted {
            if runStart == 0 {
                runStart = w; prev = w; step = 0
            } else if w == prev + 1 && step != 2 {
                prev = w; step = 1
            } else if w == prev + 2 && step != 1 {
                prev = w; step = 2
            } else {
                flush(); runStart = w; prev = w; step = 0
            }
        }
        flush()
        return runs
    }

    /// 详情页 URL: 绝对形态 (网格真实形态) / 相对形态容错
    private static let detailUrlAbs = try! NSRegularExpression(pattern: #"https?://[^\s"'<>]+/course/coursetime/\d+"#)
    private static let detailUrlRel = try! NSRegularExpression(pattern: #"["'\s](/course/coursetime/\d+)"#)

    /// 从网格 HTML 提取详情页 URL 列表 (绝对 + 相对, 去重保序) ← UcasDetailFetch 的抓取清单
    static func extractDetailUrls(_ gridHtml: String) -> [String] {
        var found: [String] = []
        func add(_ s: String) { if !found.contains(s) { found.append(s) } }
        for m in matches(detailUrlAbs, gridHtml) { add(range(m, gridHtml)) }
        for m in matches(detailUrlRel, gridHtml) { add(DETAIL_HOST + (group(m, 1, gridHtml) ?? "")) }
        return found
    }

    /// 组合源切段: 取每个详情页 HTML 段 (标记内 URL 不参与解析)
    static func detailSections(_ source: String) -> [String] {
        let re = try! NSRegularExpression(
            pattern: NSRegularExpression.escapedPattern(for: DETAIL_MARKER_OPEN) + "(.*?)" +
                NSRegularExpression.escapedPattern(for: "-->") + "(.*?)" +
                NSRegularExpression.escapedPattern(for: DETAIL_MARKER_CLOSE),
            options: [.dotMatchesLineSeparators])
        return matches(re, source).compactMap { group($0, 2, source) }
    }

    /// 详情页行标签 (真实页面形态, 2026-09-08 v1.2 采集包)
    private static let LABEL_NAME = "课程名称"
    private static let LABEL_TIME = "上课时间"
    private static let LABEL_PLACE = "上课地点"
    private static let LABEL_WEEKS = "上课周次"

    /// 星期X → 1..7 (日/天 都算第 7 天)
    private static let dayNames: [String: Int] = [
        "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7,
    ]

    private static let detailTimeRe = try! NSRegularExpression(
        pattern: #"^星期\s*([一二三四五六日天])\s*[：:]\s*第?\s*([\d、，,\s\-–—~至]+?)\s*节[。.]?$"#)
    private static let detailNameRe = try! NSRegularExpression(pattern: #"课程名称\s*[：:]\s*([^<\r\n]+?)\s*<"#)
    private static let htmlCommentRe = try! NSRegularExpression(
        pattern: #"<!--.*?-->"#, options: [.dotMatchesLineSeparators])

    /// 解析一个 /course/coursetime/<id> 详情页 HTML → DetailPage。
    /// 三行一组 (上课时间/上课地点/上课周次) 按顺序组装; 缺时间行或周次行不完整的组丢弃。
    /// nil = 页面没有 课程名称 或一个完整块都没有 (非详情页/异常页)。
    static func parseDetailPage(_ html: String) -> DetailPage? {
        let doc = try? SwiftSoup.parse(html)
        var name: String?
        for paragraph in (try? doc?.select("p").array()) ?? [] {
            let text = (try? paragraph.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let match = Jw64.full(#"课程名称\s*[：:]\s*(.+)"#, text) { name = Jw64.trim(match[1]); break }
        }
        if name?.isEmpty ?? true {
            name = nil
            for tr in (try? doc?.select("tr").array()) ?? [] where cellText(tr, "th") == LABEL_NAME {
                if let td = cellText(tr, "td"), !td.isEmpty { name = td; break }
            }
        }
        guard let courseName = name, !courseName.isEmpty else { return nil }

        var blocks: [DetailBlock] = []
        var pendingDay = 0
        var pendingNodes: [Int] = []
        var pendingRoom = ""
        var pendingValid = false
        let rows = ((try? doc?.select("tr")) ?? nil)?.array() ?? []
        for tr in rows {
            let th = cellText(tr, "th")
            let td = cellText(tr, "td") ?? ""
            switch th {
            case LABEL_TIME:
                let m = firstMatch(detailTimeRe, td)
                let nodes = m.flatMap { parseNumberList(group($0, 2, td) ?? "") } ?? []
                pendingDay = m.flatMap { dayNames[group($0, 1, td) ?? ""] } ?? 0
                pendingNodes = nodes
                pendingRoom = ""
                pendingValid = pendingDay > 0 && !nodes.isEmpty
            case LABEL_PLACE:
                if pendingValid { pendingRoom = td }
            case LABEL_WEEKS:
                if pendingValid {
                    let weeks = parseNumberList(td).filter { $0 > 0 }
                    if !weeks.isEmpty && !pendingNodes.isEmpty {
                        for (first, last) in nodeSegments(pendingNodes) {
                            blocks.append(DetailBlock(day: pendingDay, startNode: first, endNode: last,
                                                      room: pendingRoom, weeks: weeks))
                        }
                    }
                }
                pendingValid = false
            default:
                break
            }
        }
        if blocks.isEmpty { return nil }
        return DetailPage(courseName: courseName, blocks: blocks)
    }

    // ---- SwiftSoup / NSRegularExpression 小工具 ----

    /// ← Jsoup: tr.selectFirst(tag)?.text()?.trim()
    private static func cellText(_ tr: Element, _ tag: String) -> String? {
        guard let el = ((try? tr.select(tag)) ?? nil)?.first() else { return nil }
        return ((try? el.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        re.matches(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func firstMatch(_ re: NSRegularExpression, _ s: String) -> NSTextCheckingResult? {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s))
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        guard i < m.numberOfRanges else { return nil }
        let r = m.range(at: i)
        guard r.location != NSNotFound, let rng = Range(r, in: s) else { return nil }
        return String(s[rng])
    }

    private static func firstGroup(_ re: NSRegularExpression, _ s: String, _ i: Int) -> String? {
        guard let m = firstMatch(re, s) else { return nil }
        return group(m, i, s)
    }

    private static func range(_ m: NSTextCheckingResult, _ s: String) -> String {
        guard let rng = Range(m.range, in: s) else { return "" }
        return String(s[rng])
    }

    private struct GridEntry: Hashable {
        let name: String
        let id: String
        let day: Int
        let node: Int
    }
    private struct DetailRef {
        let name: String
        let id: String
        let block: DetailBlock
    }
    private static let detailIdPattern = #"/course/coursetime/([0-9]+)"#

    private func parseHtml() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        guard let table = findScheduleTable(doc) else {
            return Jw64.distinct(Self.parseDetailPages(source).flatMap { page in page.blocks.flatMap { block in
                Self.splitWeekRuns(block.weeks).map { run in
                    JwCourse(name: page.courseName, room: block.room, day: block.day, startNode: block.startNode,
                             endNode: block.endNode, startWeek: run.startWeek, endWeek: run.endWeek, type: run.type)
                }
            } })
        }
        var entries: [GridEntry] = []
        for row in Jw64.select(table, "tbody tr") {
            guard let node = jw1064Integer(Jw64.text(Jw64.first(row, "th"))), (1...EXPLICIT_SCHEDULE_RESOURCE_BOUND).contains(node) else { continue }
            for (index, cell) in Jw64.children(row).filter({ $0.tagNameNormal() == "td" }).enumerated() where index < 7 {
                for link in Jw64.select(cell, "a[href*=/course/coursetime/]") {
                    let name = Jw64.text(link)
                    guard !name.isEmpty, let id = Jw64.matches(Self.detailIdPattern, Jw64.attr(link, "href")).first?[1] else { continue }
                    let entry = GridEntry(name: name, id: id, day: index + 1, node: node)
                    if !entries.contains(entry) { entries.append(entry) }
                }
            }
        }
        let marker = NSRegularExpression.escapedPattern(for: Self.DETAIL_MARKER_OPEN) + "(.*?)-->(.*?)" + NSRegularExpression.escapedPattern(for: Self.DETAIL_MARKER_CLOSE)
        let allBlocks: [DetailRef] = Jw64.matches(marker, source).flatMap { section in
            let id = Jw64.matches(Self.detailIdPattern, section[1]).first?[1] ?? ""
            return Self.parseDetailPages(section[2]).flatMap { page in page.blocks.map { DetailRef(name: page.courseName, id: id, block: $0) } }
        }
        struct Group: Hashable { let name: String; let day: Int; let block: Int }
        var order: [Group] = [], grouped: [Group: [Int]] = [:]
        for entry in entries {
            for (index, ref) in allBlocks.enumerated() where ref.id == entry.id && ref.name == entry.name && ref.block.day == entry.day && (ref.block.startNode...ref.block.endNode).contains(entry.node) {
                let key = Group(name: entry.name, day: entry.day, block: index)
                if grouped[key] == nil { order.append(key) }
                grouped[key, default: []].append(entry.node)
            }
        }
        var result: [JwCourse] = []
        for key in order {
            let block = allBlocks[key.block].block
            for (first, last) in Self.nodeSegments(grouped[key] ?? []) {
                for run in Self.splitWeekRuns(block.weeks) {
                    result.append(JwCourse(name: key.name, room: block.room, day: key.day, startNode: first, endNode: last,
                                           startWeek: run.startWeek, endWeek: run.endWeek, type: run.type))
                }
            }
        }
        return Jw64.distinct(result)
    }

    private func findScheduleTable(_ doc: Document) -> Element? {
        let tables = ((try? doc.getElementsByTag("table")) ?? nil)?.array() ?? []
        for t in tables {
            guard tableHasHeader(t) else { continue }
            let links = (try? t.select("a[href*=/course/coursetime/]")) ?? nil
            if (links?.array().count ?? 0) > 0 { return t }
        }
        return nil
    }

    private func tableHasHeader(_ t: Element) -> Bool {
        guard let thead = (try? t.getElementsByTag("thead").first()) ?? nil else { return false }
        let ths = ((try? thead.getElementsByTag("th")) ?? nil)?.array() ?? []
        return ths.contains { ((try? $0.text()) ?? "").contains("节次/星期") }
    }

    private func trim(_ v: Any?) -> String {
        (v as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func optInt(_ d: [String: Any], _ k: String) -> Int? {
        guard let value = d[k], !(value is NSNull) else { return nil }
        return jw1064Integer(Jw64.text(d, k))
    }
}
