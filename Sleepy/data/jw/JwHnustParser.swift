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
// oldQzType: 0=湖南科技大学/潇湘学院：style="display: none;" 的 div 才是课
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

    init(_ source: String, oldQzType: Int = 0) {
        self.source = source
        self.oldQzType = oldQzType
    }

    func generateCourseList() throws -> [JwCourse] {
        var courseList: [JwCourse] = []
        let doc = try SwiftSoup.parse(source)
        guard let kbtable = (try? doc.getElementById("kbtable")) ?? nil else { return courseList }   // H1
        let trs = (try? kbtable.getElementsByTag("tr")) ?? Elements()

        for tr in trs {
            let tds = (try? tr.getElementsByTag("td")) ?? Elements()
            if tds.isEmpty() { continue }

            var day = -1
            for td in tds {
                day += 1
                let divs = (try? td.getElementsByTag("div")) ?? Elements()
                for div in divs {
                    let style = ((try? div.attr("style")) ?? "")
                        .replacingOccurrences(of: " ", with: "").lowercased()   // H2
                    if ((try? div.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    if oldQzType == 0 {
                        if style != "display:none;" { continue }
                    } else {
                        if style == "display:none;" { continue }
                    }

                    // H6: SwiftSoup 把 void 元素序列化为 "<br />"（Jsoup 输出 "<br>"），
                    // 先归一化再按 "<br>" 切分，语义与 Android 侧 div.html().split("<br>") 一致
                    let split = ((try? div.html()) ?? "")
                        .replacingOccurrences(of: #"<br\s*/?>"#, with: "<br>", options: .regularExpression)
                        .components(separatedBy: "<br>")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    var preIndex = -1

                    for i in split.indices {
                        if split[i].range(of: Self.WEEK_PATTERN2, options: .regularExpression) != nil {
                            if preIndex != -1 { toCourse(split, preIndex, div, day, &courseList) }
                            preIndex = i
                        }
                        if i == split.count - 1 { toCourse(split, preIndex, div, day, &courseList) }
                    }
                }
            }
        }
        return courseList
    }

    private func toCourse(
        _ split: [String], _ preIndex: Int, _ div: Element,
        _ day: Int, _ out: inout [JwCourse]
    ) {
        if preIndex == -1 { return }
        if preIndex - 1 < 0 || preIndex + 1 >= split.count { return }   // H3/H5
        let courseName = ((try? SwiftSoup.parse(split[0]).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let room = ((try? SwiftSoup.parse(split[preIndex + 1]).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let teacher = ((try? SwiftSoup.parse(split[preIndex - 1]).text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let timeInfo = ((try? SwiftSoup.parse(split[preIndex]).text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: ",")
        for t in timeInfo {
            let s = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { continue }
            // ← substringBefore('周')
            let weekStr: String
            if let r = s.firstIndex(of: "周") {
                weekStr = String(s[s.startIndex..<r]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                weekStr = s
            }
            if weekStr.isEmpty { continue }
            let startWeek: Int
            let endWeek: Int
            if weekStr.contains("-") {
                guard let sw = Int(weekStr.components(separatedBy: "-").first?.filter { $0.isNumber } ?? "") else { continue }  // H4
                startWeek = sw
                let after = weekStr.components(separatedBy: "-").dropFirst().joined(separator: "-")
                endWeek = Int(after.filter { $0.isNumber }) ?? startWeek
            } else {
                guard let sw = Int(weekStr.filter { $0.isNumber }) else { continue }
                startWeek = sw
                endWeek = startWeek
            }
            // ← div.attr("id").split('-').firstOrNull()?.filter{digit}.toIntOrNull()
            let idPart = ((try? div.attr("id")) ?? "").components(separatedBy: "-").first ?? ""
            guard let nodeIdx = Int(idPart.filter { $0.isNumber }) else { continue }   // H4
            let startNode = nodeIdx * 2 - 1
            out.append(JwCourse(
                name: courseName, room: room, teacher: teacher,
                day: min(max(day, 1), 7),
                startNode: max(startNode, 1),
                endNode: max(startNode + 1, startNode),
                startWeek: max(startWeek, 1),
                endWeek: max(endWeek, startWeek),
                type: 0))
        }
    }

    /// 上游 Common.weekPattern2 原文，不可改字符
    private static let WEEK_PATTERN2 = #"\d{1,2}周"#

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
