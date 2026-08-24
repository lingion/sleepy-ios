// JwNewZfParser.swift — ← JwNewZfParser.kt
// 正方教务(新版)课表解析器。
//
// 适配 zf_new 协议学校(52所)。正方新版教务(基于 SpringMVC / Vue)课表页:
//   1. 数据可能嵌入在 `<script>` 标签 JSON 中(API 响应直出 / Vue data)
//   2. 或渲染为标准 HTML 表格(`<div class="kbcontent">` + `<font title="...">`)
//
// 解析策略:JSON 优先 → HTML 表格兜底(兼容 QZ 结构 + zf_new kbgrid 结构)。
//
// 参考:
//   - dIT8Zv/WakeupSchedule_BUPT NewZfParser.kt
//   - nKEatonxuan/CourseAdapter 正方协议适配

import Foundation
import SwiftSoup

final class JwNewZfParser: JwParser {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() -> [JwCourse] {
        // 1. 尝试从页面提取嵌入的 JSON
        let embedded = parseEmbeddedJson()
        if !embedded.isEmpty { return embedded }

        // 2. HTML 表格解析
        return parseHtmlTable()
    }

    // ─── JSON 提取 ────────────────────────────────────────────

    /// 从 HTML 中提取正方新版课表 JSON。
    ///
    /// 常见嵌入方式:
    ///   - `<script>var kbxx = [...];</script>`
    ///   - `<script>window.__INITIAL_STATE__ = {…"kbxx":[…]…};</script>`
    ///   - API 响应直接嵌入(纯 JSON 页面 `{"kbxx":[…]}`)
    ///   - `var xskbcx_json = {"tmp_list":[…]};`(部分版本)
    private func parseEmbeddedJson() -> [JwCourse] {
        // 标记关键字 → 多种正方版本的字段名
        let markers = ["\"kbxx\"", "\"tmp_list\"", "\"xskbcx\"", "xskbcx_json"]

        for marker in markers {
            guard let idxRange = source.range(of: marker) else { continue }
            let idx = source.distance(from: source.startIndex, to: idxRange.lowerBound)

            // 找到 marker 后的数组开始位置 '[' 或 '{'
            let chars = Array(source)
            var arrStart = idx + marker.count
            while arrStart < chars.count && chars[arrStart] != "[" && chars[arrStart] != "{" { arrStart += 1 }
            if arrStart >= chars.count { continue }

            guard let jsonStr = Self.extractBalanced(source, arrStart) else { continue }
            let courses = parseCourseJsonArray(jsonStr)
            if !courses.isEmpty { return courses }
        }

        // 尝试纯 JSON 页面(API 响应被 WebView 直接渲染)
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            let courses = parseCourseJsonArray(trimmed)
            if !courses.isEmpty { return courses }
        }

        return []
    }

    /// 从 start 位置提取配对的 JSON 数组/对象(括号匹配)
    private static func extractBalanced(_ s: String, _ start: Int) -> String? {
        let chars = Array(s)
        if start >= chars.count { return nil }
        let open = chars[start]
        let close: Character
        switch open {
        case "[": close = "]"
        case "{": close = "}"
        default: return nil
        }
        var depth = 0
        var inStr = false
        var esc = false
        for i in start..<chars.count {
            let c = chars[i]
            if esc { esc = false; continue }
            if c == "\\" { esc = true; continue }
            if c == "\"" { inStr = !inStr; continue }
            if inStr { continue }
            if c == open { depth += 1 }
            if c == close {
                depth -= 1
                if depth == 0 { return String(chars[start...i]) }
            }
        }
        return nil
    }

    private func parseCourseJsonArray(_ jsonStr: String) -> [JwCourse] {
        var result: [JwCourse] = []
        guard let data = jsonStr.data(using: .utf8),
              let obj0 = (try? JSONSerialization.jsonObject(with: data)) as? Any else { return result }
        // 可能是数组直接开始,也可能包在对象里
        let arr: [[String: Any]]
        if let a = obj0 as? [[String: Any]] {
            arr = a
        } else if let o = obj0 as? [String: Any] {
            // 找第一个非空数组属性
            var found: [[String: Any]]? = nil
            for (_, v) in o {
                if let a = v as? [[String: Any]], !a.isEmpty { found = a; break }
            }
            guard let f = found else { return result }
            arr = f
        } else {
            return result
        }

        for o in arr {
            // 课程名(正方多版本字段名)
            let name = Self.firstStr(o, "kcmc", "kcm", "kc_mc", "courseName", "rlkcmc", "jxbmc")
            if name.isEmpty { continue }

            let teacher = Self.firstStr(o, "jsxm", "jsmc", "teacher", "attendClassTeacher", "skjs")
            let room = Self.firstStr(o, "jasmc", "jsmc", "classroomName", "jxlh", "jasdm")

            // 星期
            guard let day = Self.firstInt(o, "kcxq", "xq", "xqj", "classDay", "skxq") else { continue }

            // 节次
            guard let startNode = Self.firstInt(o, "ksjcsd", "ksjc", "jc", "classSessions", "ksjcd")
                ?? Self.firstInt(o, "ksjc") else { continue }
            let endNode = Self.firstInt(o, "jsjcsd", "jsjc", "jsjssd", "continuingSession")
                .map { $0 < startNode ? startNode : $0 }
                ?? startNode  // 缺结束节次时按单节处理,不假设连上 2 节

            // 周次
            let zcStr = Self.firstStr(o, "zcd", "kkzc", "zc", "classWeek", "skzc")
            let ranges = Self.parseWeekStr(zcStr)

            for r in ranges {
                result.append(JwCourse(
                    name: name,
                    room: room,
                    teacher: teacher,
                    day: min(max(day, 1), 7),
                    startNode: max(startNode, 1),
                    endNode: max(endNode, startNode),
                    startWeek: r.0,
                    endWeek: r.1,
                    type: r.2
                ))
            }
        }
        return result
    }

    private static func firstStr(_ o: [String: Any], _ keys: String...) -> String {
        for k in keys {
            let v = (o[k] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        return ""
    }

    private static func firstInt(_ o: [String: Any], _ keys: String...) -> Int? {
        for k in keys {
            let raw = o[k]
            if let i = raw as? Int { return i }
            if let s = raw as? String {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { return Int(t) }
            }
            if let d = raw as? Double { return Int(d) }
        }
        return nil
    }

    /// 周次字符串 → (start, end, type) 范围列表
    private static func parseWeekStr(_ s: String) -> [(Int, Int, Int)] {
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [(1, 16, 0)] }
        var result: [(Int, Int, Int)] = []

        // bitmap 模式:11111111111100000(每位 = 第 N 周)
        if s.count >= 10 && s.allSatisfy({ $0 == "0" || $0 == "1" }) {
            let weeks = s.enumerated().compactMap { $0.element == "1" ? $0.offset + 1 : nil }
            return bitsToRanges(weeks)
        }

        // 范围/列表模式:"1-16" / "1-16周" / "1-16周(单)" / "1,3,5,7"
        // ← split(",", "，", ";", "；") 多分隔符
        let parts = s.split(whereSeparator: { ",，;；".contains($0) })
        for part in parts {
            let p = String(part)
            let cleaned = p.replacingOccurrences(of: "周", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .trimmingCharacters(in: .whitespaces)
            let type: Int
            if p.contains("单") { type = 1 }
            else if p.contains("双") { type = 2 }
            else { type = 0 }
            if cleaned.contains("-") {
                let segs = cleaned.components(separatedBy: "-")
                let start = Int((segs.first ?? "").filter { $0.isNumber }) ?? 1
                let end = segs.count > 1 ? (Int((segs[1]).filter { $0.isNumber }) ?? start) : start
                result.append((start, end, type))
            } else {
                guard let v = Int(cleaned.filter { $0.isNumber }) else { continue }
                result.append((v, v, type))
            }
        }
        return result.isEmpty ? [(1, 16, 0)] : result
    }

    private static func bitsToRanges(_ weeks: [Int]) -> [(Int, Int, Int)] {
        if weeks.isEmpty { return [] }
        var result: [(Int, Int, Int)] = []
        var i = 0
        while i < weeks.count {
            let start = weeks[i]
            var end = start
            if i + 1 < weeks.count && weeks[i + 1] - start == 2 {
                // 单/双周模式
                end = weeks[i + 1]
                var k = i + 1
                while k + 1 < weeks.count && weeks[k + 1] - weeks[k] == 2 { k += 1; end = weeks[k] }
                let type = start % 2 == 1 ? 1 : 2
                result.append((start, end, type))
                i = k + 1
            } else if i + 1 < weeks.count && weeks[i + 1] - start == 1 {
                // 连续周
                end = weeks[i + 1]
                var k = i + 1
                while k + 1 < weeks.count && weeks[k + 1] - weeks[k] == 1 { k += 1; end = weeks[k] }
                result.append((start, end, 0))
                i = k + 1
            } else {
                result.append((start, end, 0))
                i += 1
            }
        }
        return result
    }

    // ─── HTML 表格解析(兜底) ─────────────────────────────────

    /// 正方新版渲染后的 HTML 与强智类似但容器 ID 可能不同。
    /// 尝试 "kbtable" / "kbgrid" / class 选择器。
    private func parseHtmlTable() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source) else { return parseHtmlTableFromQz() }

        // 多种容器选择器
        // (SwiftSoup 2.7.3 无 selectFirst → select().first();Jsoup 侧 selectFirst 语义等价)
        let container: Element? = {
            if let el = try? doc.getElementById("kbtable") { return el }
            if let el = try? doc.getElementById("kbgrid") { return el }
            if let el = (try? doc.select("table.el-table__body"))?.first() { return el }
            if let el = (try? doc.select(".kbcapi-table"))?.first() { return el }
            if let el = (try? doc.select("[id*=kb]"))?.first() { return el }
            return nil
        }()
        guard let container else { return parseHtmlTableFromQz() }  // 完全 fallback 到 QZ 逻辑

        var result: [JwCourse] = []
        let trs = (try? container.getElementsByTag("tr")) ?? Elements()
        var nodeCount = 0

        for tr in trs {
            let tds = (try? tr.getElementsByTag("td")) ?? Elements()
            if tds.isEmpty() { continue }
            // 跳过节次表头行(第一格是"第N节"/"第N-M节"这类纯标签,无 kbcontent 课程单元)
            let firstCellText = ((try? tds.first()?.text()) ?? "").trimmingCharacters(in: .whitespaces)
            let hasKbcontent = tds.contains { td in
                !(((try? td.getElementsByClass("kbcontent")) ?? Elements()).isEmpty())
            }
            let isSectionHeader = firstCellText.contains("节") && !hasKbcontent
            if isSectionHeader { continue }
            nodeCount += 1

            var day = 0
            for td in tds {
                day += 1
                let cells = (try? td.getElementsByClass("kbcontent")) ?? Elements()
                if cells.isEmpty() { continue }

                for cell in cells {
                    let html = (try? cell.html()) ?? ""
                    if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    // 同格多门课用 "-----" 分隔(与 QZ 一致)
                    let parts = html.components(separatedBy: "-----")
                    for part in parts {
                        result += parseCell(part.trimmingCharacters(in: .whitespacesAndNewlines), day: day, nodeCount: nodeCount)
                    }
                }
            }
        }

        return result.isEmpty ? parseHtmlTableFromQz() : result
    }

    private func parseCell(_ html: String, day: Int, nodeCount: Int) -> [JwCourse] {
        let cellDoc = try! SwiftSoup.parse(html)
        let before = html.components(separatedBy: "<font").first ?? html
        let name = (try? SwiftSoup.parse(before.trimmingCharacters(in: .whitespaces)).text())
            ?? before.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return [] }

        let teacher = ((try? cellDoc.getElementsByAttributeValue("title", "老师").text().trimmingCharacters(in: .whitespacesAndNewlines))) ?? ""
        let room = ((try? cellDoc.getElementsByAttributeValue("title", "教室").text().trimmingCharacters(in: .whitespacesAndNewlines))) ?? ""
        let weekRaw = (try? cellDoc.getElementsByAttributeValue("title", "周次(节次)").text()) ?? ""
        let weekStr = weekRaw.components(separatedBy: "(周)").first ?? weekRaw

        let ranges = Self.parseWeekStr(weekStr)
        let node = nodeCount * 2 - 1

        // ★ 展开全部周次段(之前只取 ranges.first(),会丢失 "1-11周(单),13-16周" 的后半段)
        return ranges.map { r in
            JwCourse(
                name: name,
                room: room,
                teacher: teacher,
                day: day,
                startNode: node,
                endNode: node + 1,
                startWeek: r.0,
                endWeek: r.1,
                type: r.2
            )
        }
    }

    /// 完全 fallback 到 QZ 解析逻辑
    private func parseHtmlTableFromQz() -> [JwCourse] {
        JwQzParser(source).generateCourseList()
    }
}
