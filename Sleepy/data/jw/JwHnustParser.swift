// JwHnustParser.swift — ← JwHnustParser.kt
//
// 湖南科技大学 / 湖南科技大学潇湘学院 / 东北石油大学（HNUST）解析器 — T3。
//
// 协议：JwProtocol.TYPE_HNUST = "hnust"
// 上游：dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) HNUSTParser.kt
//
// 页面结构：table[id=kbtable]，行=节次，列=星期；课程数据在 td 内的 div 里：
//   <div id="1-1" style="display: none;">课名<br>教师<br>1-16周<br>教室</div>
//   div id 前段 N = 大节序号 → startNode = N*2-1, endNode = N*2（第 1 大节 = 1-2 节）
//
// oldQzType: -1=默认保留全部课程；CSS 可见性不决定课表内容。
//            0=兼容旧调用：style="display: none;" 的 div 才是课
//            1=东北石油大学：style != "display: none;" 的 div 才是课
//
// 对上游偏离：kbtable null 返回空；style 比较去空格+小写（兼容 "display:none;" 与 "display: none;"）；
// split 越界保护；周次/id 数字解析 toIntOrNull 防崩；div.html() 的 "<br />" 归一化为 "<br>" 再切分
// （SwiftSoup 序列化 void 元素带斜杠，Jsoup 不带，不归一化则 split 失配、任何 div 都 0 产出）。

import Foundation
import SwiftSoup

final class JwHnustParser: JwParser, JwParserConfidenceReporting {

    let source: String
    let oldQzType: Int

    init(_ source: String, oldQzType: Int = -1) {
        self.source = source
        self.oldQzType = oldQzType
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let table = try SwiftSoup.parse(source).getElementById("kbtable") else { return [] }
        var courses: [JwCourse] = []
        for row in jw1064Elements(table, "tr") where ((try? row.parents().array()) ?? []).first(where: { $0.tagName() == "table" }) == table {
            for (day, cell) in row.children().array().filter({ $0.tagName() == "td" }).enumerated() {
                guard (1...7).contains(day) else { continue }
                for div in jw1064Elements(cell, "div[id]") {
                    let id = jw1064Attribute(div, "id")
                    guard id.range(of: #"^[0-9]+-[^\s]+$"#, options: .regularExpression) != nil,
                          let pair = jw1064Integer(id.components(separatedBy: "-")[0]), (1...15).contains(pair),
                          !jw1064Elements(div, "div[id]").contains(where: { $0 != div }) else { continue }
                    let hidden = jw1064Attribute(div, "style").range(of: #"(?i)(?:^|;)\s*display\s*:\s*none\s*(?:;|$)"#, options: .regularExpression) != nil
                    if oldQzType == 0 && !hidden || oldQzType == 1 && hidden { continue }
                    // Only BR separates protocol fields. Formatting newlines in
                    // source HTML or SwiftSoup serialization are whitespace.
                    let fields = ((try? div.html()) ?? "")
                        .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\u{001E}", options: .regularExpression)
                        .components(separatedBy: "\u{001E}")
                        .map { (try? SwiftSoup.parseBodyFragment($0).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "" }
                    var blockStart = 0
                    for i in fields.indices {
                        guard i >= blockStart + 2, i + 1 < fields.count, fields[i].contains("周") else { continue }
                        let start = blockStart
                        blockStart = i + 2
                        let headings = Array(fields[start..<(i - 1)].drop(while: { $0.isEmpty }))
                        guard let name = headings.first, !name.isEmpty else { continue }
                        for (from, to, parity) in schoolWeekRanges(fields[i]) {
                            courses.append(JwCourse(name: name, room: fields[i + 1], teacher: fields[i - 1], day: day,
                                                    startNode: pair * 2 - 1, endNode: pair * 2,
                                                    startWeek: from, endWeek: to, type: parity,
                                                    note: headings.dropFirst().joined(separator: "\n")))
                        }
                    }
                }
            }
        }
        var seen = Set<JwCourse>()
        return courses.filter { seen.insert($0).inserted }
    }

    /// T8: kbtable + div(style) + div id 前段数字 = 100; 仅 kbtable = 60
    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        guard ((try? doc.getElementById("kbtable")) ?? nil) != nil else { return 0 }
        let hiddenDivs = (try? doc.getElementsByAttribute("style")) ?? Elements()
        let hasIdDiv = (((try? doc.select("div[id]")) ?? Elements()).isEmpty() == false)
        if !hiddenDivs.isEmpty() && hasIdDiv { return 100 }
        if !hiddenDivs.isEmpty() { return 80 }
        return 60
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("kbtable") { out.append("id=kbtable") }
        if source.contains("display:none") || source.contains("display: none") { out.append("div[style=display:none]") }
        if source.range(of: #"div[^>]+id="\d+-\d+""#, options: .regularExpression) != nil { out.append("div id=N-M") }
        return out
    }
}
