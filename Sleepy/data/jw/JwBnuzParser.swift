// JwBnuzParser.swift — ← JwBnuzParser.kt
//
// 北京师范大学珠海分校（BNUZ）解析器 — T3。
//
// 协议：JwProtocol.TYPE_BNUZ = "bnuz"
// 上游：dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) BNUZParser.kt
//
// 页面结构：table[id=table1]，列=星期(countDay 1..7)，行=节次。
// 表头行 td="时间"/"星期一".. 被 OTHER_HEADER 跳过；纯数字 td 是节次行头。
// 课程 td html 形如：
//   <span>&nbsp;</span>课名<br>教师{1-16周}<br>教室(2节)<br>[教师{周次}<br>教室(2节)<br>]...
//   substringAfter("</span>").substringBeforeLast("<br>").split("<br>")
//   → infos[0]=课名, (infos[i], infos[i+1]) i=1,3,5.. = (教师+周次, 教室+节数) 对
// 周次 item：含 '-' → 范围；单值 → start=end；含'单'→type=1 含'双'→type=2。
//
// 对上游偏离：table1 null 返回空；无 </span> 的 td 跳过；step 解析 toIntOrNull 防崩。

import Foundation
import SwiftSoup

final class JwBnuzParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        var result: [JwCourse] = []
        let doc = try SwiftSoup.parse(source)
        guard let table1 = (try? doc.getElementById("table1")) ?? nil else { return result }
        let trs = (try? table1.getElementsByTag("tr")) ?? Elements()

        var node = 0
        for tr in trs {
            var countFlag = false
            var countDay = 1
            let tds = (try? tr.getElementsByTag("td")) ?? Elements()
            for td in tds {
                let courseValue = ((try? td.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.OTHER_HEADER.contains(courseValue) { continue }
                if courseValue.isEmpty { if countFlag { countDay += 1 }; continue }
                if courseValue.range(of: #"^\d+$"#, options: .regularExpression) != nil {
                    // ← Android courseValue.toInt(): 32 位解析,溢出抛 NumberFormatException → 整表解析中止
                    guard let parsedNode = Int32(courseValue) else {
                        throw JwParseError(message: "JwBnuzParser: node row '\(courseValue)' exceeds Int32 range")
                    }
                    node = Int(parsedNode)
                    countFlag = true
                    continue
                }

                let tdHtml = (try? td.html()) ?? ""
                if !tdHtml.contains("</span>") { countDay += 1; continue }   // B2 修复
                // ← substringAfter("</span>").substringBeforeLast("<br>").split("<br>")
                let afterSpan: String
                if let r = tdHtml.range(of: "</span>") {
                    afterSpan = String(tdHtml[r.upperBound...])
                } else {
                    afterSpan = tdHtml
                }
                let beforeLastBr: String
                if let r = afterSpan.range(of: "<br>", options: .backwards) {
                    beforeLastBr = String(afterSpan[afterSpan.startIndex..<r.lowerBound])
                } else {
                    beforeLastBr = afterSpan
                }
                let infos = beforeLastBr.components(separatedBy: "<br>")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }                                  // B4 规范化
                if infos.isEmpty { countDay += 1; continue }
                let courseName = infos[0]

                var i = 1
                while i < infos.count {
                    if i + 1 >= infos.count { break }
                    let teacherAndWeek = infos[i]
                    let roomStr = infos[i + 1]
                    if !teacherAndWeek.contains("{") || !teacherAndWeek.contains("}") { i += 2; continue }

                    let teacher = teacherAndWeek.components(separatedBy: "{").first ?? ""
                    let teacherTrimmed = teacher.trimmingCharacters(in: .whitespacesAndNewlines)
                    // ← Android substringAfter('{'): 取第一个 '{' 之后(非最后一个)
                    let afterBrace: String
                    if let r = teacherAndWeek.range(of: "{") {
                        afterBrace = String(teacherAndWeek[r.upperBound...])
                    } else {
                        afterBrace = teacherAndWeek
                    }
                    let weekStr = (afterBrace.components(separatedBy: "}").first ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    // B3 修复：无 "(N节)" 后缀时丢弃该 section（上游抛 NumberFormatException 整表崩）
                    let stepStr: String
                    if let r = roomStr.range(of: "(", options: .backwards) {
                        stepStr = String(roomStr[r.upperBound...])
                    } else {
                        stepStr = roomStr
                    }
                    // ← Android substringBeforeLast('节'): 以最后一个 '节' 截断(无 '节' 时保留整串)
                    let stepCore: String
                    if let r = stepStr.range(of: "节", options: .backwards) {
                        stepCore = String(stepStr[stepStr.startIndex..<r.lowerBound])
                    } else {
                        stepCore = stepStr
                    }
                    // ← Android toIntOrNull(): 32 位范围外返回 null → 丢弃该 section(不抛)
                    let step = Int32(stepCore.trimmingCharacters(in: .whitespacesAndNewlines)).map { Int($0) }
                    if step == nil { i += 2; continue }   // continue 作用于 while：跳过此 section 继续扫
                    let room: String
                    if let r = roomStr.range(of: "(", options: .backwards) {
                        room = String(roomStr[roomStr.startIndex..<r.lowerBound])
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } else {
                        room = roomStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    for wp in weekStr.components(separatedBy: ",") {
                        let item = wp.trimmingCharacters(in: .whitespacesAndNewlines)
                        if item.isEmpty { continue }
                        let type: Int = {
                            if item.contains("单") { return 1 }
                            if item.contains("双") { return 2 }
                            return 0
                        }()
                        let startWeek: Int
                        let endWeek: Int
                        if item.contains("-") {
                            guard let sw = Int(item.components(separatedBy: "-").first?.filter { $0.isNumber } ?? "") else { continue }
                            startWeek = sw
                            let afterPart = item.components(separatedBy: "-").dropFirst().joined(separator: "-")
                            endWeek = Int(afterPart.filter { $0.isNumber }) ?? startWeek
                        } else {
                            guard let sw = Int(item.filter { $0.isNumber }) else { continue }
                            startWeek = sw
                            endWeek = startWeek
                        }
                        result.append(JwCourse(
                            name: courseName, room: room, teacher: teacherTrimmed,
                            day: min(max(countDay, 1), 7),
                            startNode: node, endNode: node + step! - 1,
                            startWeek: max(startWeek, 1),
                            endWeek: max(endWeek, startWeek),
                            type: type))
                    }
                    i += 2
                }
                countDay += 1
            }
        }
        return result
    }

    // MARK: - companion ← static

    private static let OTHER_HEADER: Set<String> = [
        "时间", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日",
        "早晨", "上午", "下午", "晚上",
    ]

    /// T8: #table1 + span 结构 = 100; es.bnuz = 90
    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        let table1 = (try? doc.getElementById("table1")) ?? nil
        if table1 != nil && source.contains("</span>") { return 100 }
        if source.contains("es.bnuz") { return 90 }
        if table1 != nil { return 70 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("table1") { out.append("id=table1") }
        if source.contains("</span>") { out.append("<span>课程名</span>") }
        if source.contains("es.bnuz") { out.append("URL=es.bnuz") }
        if source.contains("{") && source.contains("周") { out.append("{N-M周}") }
        return out
    }
}
