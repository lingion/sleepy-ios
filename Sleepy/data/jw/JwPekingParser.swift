// JwPekingParser.swift — ← JwPekingParser.kt
//
// 北京大学（PKU）解析器 — T3。
//
// 协议：JwProtocol.TYPE_PKU = "pku"
// 上游：dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) PekingParser.kt
//
// 页面结构：table[class=datagrid] > tbody > tr > 11 列 td
//   tds[0]=课名  tds[4]=教师(整行共用)  tds[7]=时段(<br> 分隔多段)
//   tds[8]=选课状态(含"未"跳过)
// 时段块按空格切 token：
//   timeInfo[0]="1~16周"  timeInfo[1]="周一1~2节"或"周一1~2节(单)"
//   timeInfo[2]=教室（缺失时从 timeInfo[1] 括号内取）
//
// 对上游偏离：kbtable/tbody null 时返回空而非 NPE（pku_login.html 登录页）。

import Foundation
import SwiftSoup

final class JwPekingParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "table[class=datagrid]"), let body = Jw64.first(table, "tbody") else { return [] }
        var result: [JwCourse] = []
        for row in Jw64.select(body, "tr") {
            let cells = Jw64.select(row, "td")
            guard cells.count >= 11, !Jw64.text(cells[8]).contains("未") else { continue }
            for line in Jw64.lines(cells[7]) {
                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                guard fields.count >= 2 else { continue }
                let raw = fields[0].hasSuffix("周") ? String(fields[0].dropLast()) : fields[0]
                var weeks: [(Int, Int)] = []
                for token in raw.components(separatedBy: ",") {
                    guard let m = Jw64.full(#"([0-9]+)(?:~([0-9]+))?"#, token),
                          let first = jw1064Integer(m[1]), let last = jw1064Integer(m[2].isEmpty ? m[1] : m[2]), first > 0, last >= first else { weeks = []; break }
                    weeks.append((first, last))
                }
                guard !weeks.isEmpty, let timing = Jw64.full(#"周([一二三四五六日天])([0-9]+)(?:~([0-9]+))?节(?:[（(]([^）)]*)[）)])?"#, fields[1]),
                      let firstNode = jw1064Integer(timing[2]), let lastNode = jw1064Integer(timing[3].isEmpty ? timing[2] : timing[3]) else { continue }
                let bracket = timing[4], parity = jw1064Parity(bracket)
                let room = fields.count > 2 ? fields[2] : ["单", "双", "单周", "双周"].contains(bracket) ? "" : bracket
                for (first, last) in weeks {
                    let course = JwCourse(name: Jw64.text(cells[0]), room: room, teacher: Jw64.text(cells[4]), day: Jw64.day(timing[1]), startNode: firstNode, endNode: lastNode, startWeek: first, endWeek: last, type: parity)
                    if Jw64.valid(course) { result.append(course) }
                }
            }
        }
        return result
    }

    // MARK: - companion ← static

    /// 上游 Common.nodePattern1 的 ASCII 口径等价形 (iOS 26 ICU 实测 `\d` 命中
    /// CJK 数字 一 U+4E00/NBSP 域数字, Kotlin Regex 默认仅 [0-9] — 同
    /// SleepyNativeFormat §2 文法注记): 语义逐字符对齐 原版本, 仅数字类换 [0-9]。
    private static let NODE_PATTERN1 = #"[0-9]{1,2}[~]*[0-9]*节"#
    private static let CHINESE_WEEK_LIST = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// T8: table[class=datagrid] = 100; elective.pku = 90
    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        if ((try? doc.select("table[class=datagrid]").first()) ?? nil) != nil { return 100 }
        if source.contains("elective.pku") { return 90 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("datagrid") { out.append("class=datagrid") }
        if source.contains("elective.pku") { out.append("URL=elective.pku") }
        return out
    }
}
