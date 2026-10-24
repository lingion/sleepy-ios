// JwUrpParser.swift — ← JwUrpParser.kt
// 老版 URP 教务系统解析器(HTML 表格版本)
//
// 数据来源:URP 综合教务(部分校)课表页用 HTML 表格展示,class 为
//   "displayTag" 或 "table table-striped table-bordered"。
// 表头:课程名/教师/星期/节次/周次/教学楼/教室/节数
//
// 基于 dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) UrpParser.kt 简化而来
// https://github.com/dIT8Zv/WakeupSchedule_BUPT/blob/master/app/src/main/java/com/suda/yzune/wakeupschedule/schedule_import/parser/UrpParser.kt

import Foundation
import SwiftSoup

final class JwUrpParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        var result: [JwCourse] = []
        guard let doc = try? SwiftSoup.parse(source) else { return result }
        // T10: URP 网格变体 (td[id='day_node'] + div.class_div) — 真实结构来自 urp_01.js
        let grid = Self.parseUrpGrid(doc)
        if !grid.isEmpty { return grid }

        var tables = (try? doc.getElementsByAttributeValue("class", "displayTag")) ?? Elements()
        if tables.isEmpty() {
            tables = (try? doc.getElementsByAttributeValue("class", "table table-striped table-bordered")) ?? Elements()
        }
        if tables.isEmpty() { return result }

        for table in tables {
            // 跳过非课表(第一行含"星期一"的是顶部信息行)
            if let text = try? table.text(), text.contains("星期一") { continue }

            guard let thead = (try? table.getElementsByTag("thead"))?.first() else { continue }
            let ths = (try? thead.getElementsByTag("th")) ?? Elements()
            let headSize = ths.count

            var nameIdx = -1
            var teacherIdx = -1
            var weekIdx = -1
            var dayIdx = -1
            var nodeIdx = -1
            var stepIdx = -1
            var buildingIdx = -1
            var roomIdx = -1

            // ← ths.eachText().forEachIndexed
            for (i, th) in ths.enumerated() {
                let s = ((try? th.text()) ?? "").trimmingCharacters(in: .whitespaces)
                switch s {
                case "课程名": nameIdx = i
                case "教师": teacherIdx = i
                case "周次": weekIdx = i
                case "星期": dayIdx = i
                case "节次": nodeIdx = i
                case "节数": stepIdx = i
                case "教学楼": buildingIdx = i
                case "教室": roomIdx = i
                default: break
                }
            }
            // ★ 周/节数列索引缺失时无法安全对齐列,跳过此表(避免越界崩溃)
            if weekIdx == -1 || nodeIdx == -1 || nameIdx == -1 { continue }

            guard let tbody = (try? table.getElementsByTag("tbody"))?.first() else { continue }
            var courseName = ""
            var teacher = ""

            let trs = (try? tbody.getElementsByTag("tr")) ?? Elements()
            for tr in trs {
                let tds = (try? tr.getElementsByTag("td")) ?? Elements()
                func tdText(_ i: Int) -> String {
                    guard i >= 0 && i < tds.count else { return "" }  // Kotlin 侧靠 try/catch 吞越界
                    return ((try? tds[i].text()) ?? "")
                }
                let wholeFlag = tds.count > headSize - weekIdx
                let acDayIdx = wholeFlag ? dayIdx : dayIdx - weekIdx
                if tdText(acDayIdx).trimmingCharacters(in: .whitespaces).isEmpty { continue }

                if wholeFlag {
                    courseName = tdText(nameIdx)
                    teacher = tdText(teacherIdx).trimmingCharacters(in: .whitespaces)
                }

                // ← try { bIdx/rIdx 越界 → "" } catch
                let room: String = {
                    let bIdx = wholeFlag ? buildingIdx : buildingIdx - weekIdx
                    let rIdx = wholeFlag ? roomIdx : roomIdx - weekIdx
                    guard bIdx >= 0 && bIdx < tds.count && rIdx >= 0 && rIdx < tds.count else { return "" }
                    return ((try? tds[bIdx].text()) ?? "").trimmingCharacters(in: .whitespaces) +
                        ((try? tds[rIdx].text()) ?? "").trimmingCharacters(in: .whitespaces)
                }()

                let nodeE = tds[wholeFlag ? nodeIdx : nodeIdx - weekIdx]
                let nodeText = (try? nodeE.text()) ?? ""
                let startNode = Self.getStartNode(nodeText)
                let step: Int
                if stepIdx != -1 {
                    let sIdx = wholeFlag ? stepIdx : stepIdx - weekIdx
                    step = Self.getStep(tdText(sIdx).trimmingCharacters(in: .whitespaces))
                } else {
                    // ← substringAfter('-').substringBefore('节').toIntOrNull() ?: startNode
                    let after = nodeText.trimmingCharacters(in: .whitespaces)
                        .components(separatedBy: "-").dropFirst().first ?? ""
                    let beforeJie = after.components(separatedBy: "节").first ?? ""
                    let end = Int(beforeJie.trimmingCharacters(in: .whitespaces)) ?? startNode
                    step = end - startNode + 1
                }
                let day = Self.getDay(tdText(acDayIdx))
                let acWeekIdx = wholeFlag ? weekIdx : 0
                let weekStr = tdText(acWeekIdx).trimmingCharacters(in: .whitespaces)

                let ranges = Self.weekStrToRanges(weekStr)
                for r in ranges {
                    result.append(JwCourse(
                        name: courseName,
                        room: room,
                        teacher: teacher,
                        day: day,
                        startNode: startNode,
                        endNode: startNode + step - 1,
                        startWeek: r.0,
                        endWeek: r.1,
                        type: r.2
                    ))
                }
            }
        }
        return result
    }

    private static func getDay(_ str: String) -> Int {
        let t = str.trimmingCharacters(in: .whitespaces)
        if let v = Int(t) { return v }
        switch t {
        case "星期一": return 1
        case "星期二": return 2
        case "星期三": return 3
        case "星期四": return 4
        case "星期五": return 5
        case "星期六": return 6
        case "星期日", "星期天": return 7
        default: return 1
        }
    }

    private static func getStartNode(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.contains("-") {
            // ← substringBefore('-')
            return Int(t.components(separatedBy: "-").first?.trimmingCharacters(in: .whitespaces) ?? "") ?? 1
        } else {
            // ← substringAfter('第').substringBefore('大').substringBefore('小')
            let afterDi = t.components(separatedBy: "第").dropFirst().first ?? ""
            let beforeDa = afterDi.components(separatedBy: "大").first ?? ""
            let beforeXiao = beforeDa.components(separatedBy: "小").first ?? ""
            return Int(beforeXiao.trimmingCharacters(in: .whitespaces)) ?? 1
        }
    }

    private static func getStep(_ s: String) -> Int { Int(s) ?? 1 }

    private static func weekStrToRanges(_ weekStr: String) -> [(Int, Int, Int)] {
        var result: [(Int, Int, Int)] = []
        if weekStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {  // ← isBlank
            result.append((1, 20, 0))
            return result
        }
        // 支持 "1-16周", "1-16周(单)", "2,4,6,8,10周"(逗号列表按上游 weekIntList2WeekBeanList 归并)
        let type: Int
        if weekStr.contains("单") { type = 1 }
        else if weekStr.contains("双") { type = 2 }
        else { type = 0 }
        let cleaned = weekStr.replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "单", with: "")
            .replacingOccurrences(of: "双", with: "")
            .trimmingCharacters(in: .whitespaces)
        if cleaned.contains("-") {
            let parts = cleaned.components(separatedBy: "-")
            let s = Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 1
            let e = parts.count > 1 ? (Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? s) : s
            result.append((s, e, type))
        } else if cleaned.contains(",") {
            // 逗号列表: 归并成连续/单双周段 (T10 契约: "2,4,6,8,10周" → (2,10,type=2))
            let weeks = cleaned.components(separatedBy: ",")
                .map { Int($0.trimmingCharacters(in: .whitespaces)) }
                .compactMap { $0 }
            result += JwChengFangParser.weekIntList2WeekBeanList(weeks)
        } else {
            let v = Int(cleaned.trimmingCharacters(in: .whitespaces)) ?? 1
            result.append((v, v, type))
        }
        return result
    }

    ///
    /// T10: URP 网格变体解析 — td[id='<day>_<node>'] 定位, div.class_div 含 >=5 个 <p>:
    /// p[0]=课名, p[1]=星号占位, p[2]=教师, p[3]=周次串, p[4]=节次串, p[5]=教室(可选)
    ///
    private static func parseUrpGrid(_ doc: Document) -> [JwCourse] {
        var result: [JwCourse] = []
        let gridTds = (try? doc.select("td[id]")) ?? Elements()
        for td in gridTds {
            let id = (try? td.attr("id")) ?? ""
            let parts = id.components(separatedBy: "_")
            if parts.count != 2 { continue }
            guard let day = Int(parts[0].trimmingCharacters(in: .whitespaces)), (1...7).contains(day) else { continue }
            guard let node = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { continue }
            let divs = (try? td.getElementsByClass("class_div")) ?? Elements()
            for div in divs {
                let ps = (try? div.getElementsByTag("p")) ?? Elements()
                if ps.count < 5 { continue }
                let name = ((try? ps[0].text()) ?? "").trimmingCharacters(in: .whitespaces)
                if name.isEmpty { continue }
                let teacher = ((try? ps[2].text()) ?? "").trimmingCharacters(in: .whitespaces)
                let weekStr = ((try? ps[3].text()) ?? "").trimmingCharacters(in: .whitespaces)
                let nodeStr = ((try? ps[4].text()) ?? "").trimmingCharacters(in: .whitespaces)
                let ranges = gridWeekRanges(weekStr)
                if ranges.isEmpty { continue }
                // 节次串 "N-M节" → start/end
                let nParts = nodeStr.replacingOccurrences(of: "节", with: "")
                    .components(separatedBy: "-")
                let startNode = Int((nParts.first ?? "").trimmingCharacters(in: .whitespaces)) ?? node
                let endNode = nParts.count > 1 ? (Int(nParts[1].trimmingCharacters(in: .whitespaces)) ?? startNode) : startNode
                let room = ps.count >= 6 ? ((try? ps[5].text()) ?? "").trimmingCharacters(in: .whitespaces) : ""
                for r in ranges {
                    result.append(JwCourse(
                        name: name, room: room, teacher: teacher, day: day,
                        startNode: startNode, endNode: endNode,
                        startWeek: r.0, endWeek: r.1, type: r.2
                    ))
                }
            }
        }
        return result
    }

    /// 网格变体周次串: "1-16周" / "2-14周单周" / "1-8,10-17周" / "3-12周双周" → 归并段
    private static func gridWeekRanges(_ weekStr: String) -> [(Int, Int, Int)] {
        if weekStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        var result: [(Int, Int, Int)] = []
        let cleaned = weekStr.replacingOccurrences(of: "周", with: "")
        // ← cleaned.split(',', '，', ';', '；'): Swift 手工切分四个分隔符
        var segments: [String] = []
        var current = ""
        for ch in cleaned {
            if ch == "," || ch == "，" || ch == ";" || ch == "；" {
                segments.append(current); current = ""
            } else {
                current.append(ch)
            }
        }
        segments.append(current)
        for seg0 in segments {
            let trimmed = seg0.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let type: Int
            if trimmed.contains("单") { type = 1 }
            else if trimmed.contains("双") { type = 2 }
            else { type = 0 }
            // ← seg.filter { it.isDigit() || it == '-' } (isDigit 仅 ASCII 0-9)
            let digits = String(trimmed.filter { $0.isASCII && $0.isNumber || $0 == "-" })
            if digits.contains("-") {
                let parts = digits.components(separatedBy: "-")
                // ← parts.getOrNull(0)?.toIntOrNull() ?: return@forEach
                guard let s = Int(parts.first ?? "") else { continue }
                // ← parts.getOrNull(1)?.toIntOrNull() ?: s (第二段坏值回退到 s, 不跳过)
                let e: Int
                if parts.count > 1 {
                    e = Int(parts[1]) ?? s
                } else {
                    e = s
                }
                if type == 0 {
                    result.append((s, e, 0))
                } else {
                    // 单/双周: 展开成奇/偶周序列再归并 ("2-14周单周" → (3,13,1))
                    let weeks = (s...e).filter { type == 1 ? $0 % 2 == 1 : $0 % 2 == 0 }
                    result += JwChengFangParser.weekIntList2WeekBeanList(weeks)
                }
            } else {
                guard let v = Int(digits) else { continue }
                result.append((v, v, type))
            }
        }
        return result
    }

    // MARK: - T8 置信度

    /// URP: td[id=N_M]+class_div 或 displayTag = 100; table-striped = 90
    var confidenceValue: Int {
        if source.range(of: #"td[^>]+id="\d+_\d+""#, options: .regularExpression) != nil && source.contains("class_div") { return 100 }
        if source.contains("displayTag") { return 100 }
        if source.contains("table-striped") { return 90 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("displayTag") { out.append("class=displayTag") }
        if source.contains("table-striped") { out.append("class=table table-striped table-bordered") }
        return out
    }
}
