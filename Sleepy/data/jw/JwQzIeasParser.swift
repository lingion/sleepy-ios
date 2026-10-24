// JwQzIeasParser.swift — ← JwQzIeasParser.kt 1:1 translation (GPL-3.0) — 1.0.52 alignment
// 强智 iEAS 网络版 (/ieas2.1/...) 解析器。
//
// 学校样本: 北京航空航天大学 (jwxt.buaa.edu.cn:7001/ieas2.1)。
// 数据来源: GET /ieas2.1/kbcx/queryGrkb 返回 HTML 表格 (非 JSON),
//           5 仓 cross-verified (BUAA SOP cross-verify 2026-09-06)。
// 解析约定: 优先读行 data-* 字段; 无字段时回退五列文本
//           (课程名、教师、教室、周次、时间)。
//
// 上游参考 (代码自写, 不复用):
//   - SE2020-TopUnderstanding/BUAA-Campus-Tools-Backend web.py (Python, BeautifulSoup)
//   - APassbyDreg/BUAA_JW_Utils (Python, requests + cookie)

import Foundation
import SwiftSoup

final class JwQzIeasParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        let table: Element?
        do {
            table = try doc.select("table#queryGrkb").first() ?? doc.getElementsByTag("table").first()
        } catch { table = nil }
        guard let table = table else { return [] }

        let rows = ((try? table.getElementsByTag("tr")) ?? nil)?.array() ?? []
        var out: [JwCourse] = []
        for row in rows {
            guard let courses = parseRow(row) else { continue }
            out.append(contentsOf: courses)
        }
        return out
    }

    /// ← confidence() (iOS 检测层不消费, 保留供对齐): table#queryGrkb 命中 = 90
    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        return (((try? doc.select("table#queryGrkb")) ?? nil)?.array().isEmpty == false) ? 90 : 0
    }

    var matchedFeatureList: [String] {
        var f: [String] = []
        if let doc = try? SwiftSoup.parse(source),
           ((try? doc.select("table#queryGrkb")) ?? nil)?.array().isEmpty == false {
            f.append("table#queryGrkb")
        }
        if source.contains("/ieas2.1/") { f.append("path:/ieas2.1/") }
        return f
    }

    // MARK: - row parsing

    private func parseRow(_ row: Element) -> [JwCourse]? {
        let cells: [String]
        do {
            let els = try row.select("th,td")
            cells = try els.array().map { try $0.text().trimmingCharacters(in: .whitespaces) }
        } catch { return nil }

        let name = ifBlank(attrOf(row, "data-course-name"), cells.first ?? "")
            .trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return nil }

        // ← Kotlin: ifBlank { cells }.trim().cleanNull() —— 先 trim 后 cleanNull,
        // 使 " null " 这类带空白的 null 字面量同样被清成空串。
        let teacher = cleanNull(ifBlank(attrOf(row, "data-teacher"), cells.count > 1 ? cells[1] : "")
            .trimmingCharacters(in: .whitespaces))
        let room = cleanNull(ifBlank(attrOf(row, "data-room"), cells.count > 2 ? cells[2] : "")
            .trimmingCharacters(in: .whitespaces))
        let weeks = ifBlank(attrOf(row, "data-weeks"), cells.count > 3 ? cells[3] : "")
        let timeText = cells.count > 4 ? cells[4] : ""

        // ← Kotlin toIntOrNull(): 严格整数, 不做预 trim —— " 3" 这类带空白值
        // 与 Kotlin 一致地落回 parseDay/parseNodes 文本兜底。Swift Int("+3")=3
        // 与 Kotlin toIntOrNull("+3")=3 同为接受符号。
        let day = Int(attrOf(row, "data-day")) ?? parseDay(timeText)
        let parsedNodes = parseNodes(timeText)
        let start = Int(attrOf(row, "data-start-node")) ?? parsedNodes.0
        let end = Int(attrOf(row, "data-end-node")) ?? parsedNodes.1
        guard (1...7).contains(day), start >= 1, end >= start else { return nil }

        let triples = parseWeeks(weeks)
        if triples.isEmpty { return [] }
        return triples.map { sw, ew, type in
            JwCourse(name: name.trimmingCharacters(in: .whitespaces),
                     room: room.trimmingCharacters(in: .whitespaces),
                     teacher: teacher.trimmingCharacters(in: .whitespaces),
                     day: day, startNode: start, endNode: end,
                     startWeek: sw, endWeek: ew, type: type)
        }
    }

    private func ifBlank(_ v: String, _ fallback: String) -> String {
        v.trimmingCharacters(in: .whitespaces).isEmpty ? fallback : v
    }

    /// SwiftSoup attr 是 throwing — 统一兜空串
    private func attrOf(_ el: Element, _ key: String) -> String {
        (try? el.attr(key)) ?? ""
    }

    /// Kotlin String.cleanNull(): "null" (忽略大小写) -> ""
    private func cleanNull(_ v: String) -> String {
        v.caseInsensitiveCompare("null") == .orderedSame ? "" : v
    }

    /// 周([一二三四五六日天1-7]) -> 1..7; 不命中 = 0
    private func parseDay(_ text: String) -> Int {
        let ns = text as NSString
        let re = try? NSRegularExpression(pattern: "周([一二三四五六日天1-7])")
        guard let m = re?.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return 0 }
        let c = ns.substring(with: m.range(at: 1))
        switch c {
        case "一", "1": return 1
        case "二", "2": return 2
        case "三", "3": return 3
        case "四", "4": return 4
        case "五", "5": return 5
        case "六", "6": return 6
        default: return 7
        }
    }

    /// 第 N / 第 N-M / 第 N~M (含全角逗号顿号) -> (start, end)
    private func parseNodes(_ text: String) -> (Int, Int) {
        guard let m = text.range(of: "第\\s*(\\d+)(?:\\s*[-~,，、]\\s*(\\d+))?", options: .regularExpression) else { return (0, 0) }
        let seg = String(text[m])
        let nums = matchesInts(seg)
        guard nums.count >= 1 else { return (0, 0) }
        let start = nums[0]
        return (start, nums.count >= 2 ? nums[1] : start)
    }

    /// 周次段解析: "1-15单,17双" -> [(1,15,1),(17,17,2)]
    private func parseWeeks(_ raw: String) -> [(Int, Int, Int)] {
        let normalized = raw
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
        var out: [(Int, Int, Int)] = []
        let segments = normalized.split(whereSeparator: { $0 == "," || $0 == "，" })
        for segment0 in segments {
            let segment = segment0.trimmingCharacters(in: .whitespaces)
            if segment.isEmpty { continue }
            let type: Int
            if segment.contains("单") { type = 1 }
            else if segment.contains("双") { type = 2 }
            else { type = 0 }
            let numbers = matchesInts(segment)
            if numbers.isEmpty { continue }
            if segment.contains("-") && numbers.count >= 2 {
                var start = numbers[0]
                if type == 1 && start % 2 == 0 { start += 1 }
                if type == 2 && start % 2 == 1 { start += 1 }
                out.append((start, Swift.max(start, numbers[1]), type))
            } else {
                out.append((numbers[0], numbers[0], type))
            }
        }
        return out
    }

    private func matchesInts(_ s: String) -> [Int] {
        let ns = s as NSString
        let re = try? NSRegularExpression(pattern: "\\d+")
        let ranges = re?.matches(in: s, range: NSRange(location: 0, length: ns.length))
        return (ranges ?? []).compactMap { m in
            m.range.location == NSNotFound ? nil : Int(ns.substring(with: m.range))
        }
    }
}
