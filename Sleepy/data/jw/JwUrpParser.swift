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
        guard let doc = Jw64.doc(source) else { return [] }
        let grid = Self.parseUrpGrid(doc)
        if !grid.isEmpty { return grid }
        return Jw64.select(doc, "table.displayTag,table.table.table-striped.table-bordered,table#tb").flatMap(Self.parseTable)
    }

    private static func parseTable(_ table: Element) -> [JwCourse] {
        let headers = Jw64.select(table, "thead th").map(Jw64.text)
        func column(_ label: String) -> Int { headers.firstIndex(where: { $0.contains(label) }) ?? -1 }
        let nameIndex = column("课程名"), teacherIndex = column("教师"), weekIndex = column("周次"), dayIndex = column("星期"), nodeIndex = column("节次"), stepIndex = column("节数"), buildingIndex = column("教学楼"), roomIndex = column("教室"), creditIndex = column("学分")
        guard [nameIndex, weekIndex, dayIndex, nodeIndex].allSatisfy({ $0 >= 0 }) else { return [] }
        let rows = Jw64.select(table, "tbody > tr").filter { Jw64.ancestor($0, css: "table") === table }
        var carried: [Int: (Element, Int)] = [:], previousMetadata: [Int: String]?, courses: [JwCourse] = []
        for (rowIndex, row) in rows.enumerated() {
            var cells = Array<Element?>(repeating: nil, count: headers.count)
            for (index, entry) in carried where entry.1 >= rowIndex { cells[index] = entry.0 }
            let directCells = Jw64.children(row).filter { $0.tagNameNormal() == "td" }
            let continuation = previousMetadata != nil && weekIndex > 0 && [nameIndex, teacherIndex, creditIndex].filter { $0 >= 0 }.allSatisfy { $0 < weekIndex } && cells.allSatisfy { $0 == nil } && directCells.count == headers.count - weekIndex && directCells.allSatisfy { cell in ["rowspan", "colspan"].allSatisfy { !cell.hasAttr($0) || Jw64.attr(cell, $0) == "1" } }
            var cursor = continuation ? weekIndex : 0
            for cell in Jw64.children(row) {
                guard cell.tagNameNormal() == "td" else { return [] }
                let span = cell.hasAttr("rowspan") ? jw1064Integer(Jw64.attr(cell, "rowspan")) : 1
                let width = cell.hasAttr("colspan") ? jw1064Integer(Jw64.attr(cell, "colspan")) : 1
                guard let span, (1...(rows.count - rowIndex)).contains(span), width == 1 else { return [] }
                while cursor < cells.count && cells[cursor] != nil { cursor += 1 }
                guard cursor < cells.count else { return [] }
                cells[cursor] = cell
                if span > 1 { carried[cursor] = (cell, rowIndex + span - 1) }
                cursor += 1
            }
            if cells.indices.contains(where: { cells[$0] == nil && (!continuation || $0 >= weekIndex) }) { continue }
            func text(_ index: Int) -> String {
                if continuation && index >= 0 && index < weekIndex { return previousMetadata?[index] ?? "" }
                return index >= 0 && index < cells.count ? Jw64.text(cells[index]) : ""
            }
            let name = text(nameIndex)
            guard !name.isEmpty else { continue }
            if !continuation { previousMetadata = Dictionary(uniqueKeysWithValues: (0..<weekIndex).map { ($0, text($0)) }) }
            guard let day = dayNumber(text(dayIndex)) else { continue }
            let ranges = nodeRanges(text(nodeIndex))
            guard !ranges.isEmpty else { continue }
            let step: Int?
            if stepIndex < 0 { step = nil }
            else { guard let value = smallNumber(text(stepIndex)), (1...366).contains(value) else { continue }; step = value }
            let weekText = text(weekIndex), parsedWeeks = schoolWeekRanges(weekText, trailingParityAppliesToAll: true)
            let weeks: [(Int, Int, Int)]
            if weekText.contains(",") || weekText.contains("，") {
                let values = parsedWeeks.flatMap { first, last, parity in (first...last).filter { parity == 0 || $0 % 2 == parity % 2 } }
                weeks = JwChengFangParser.weekIntList2WeekBeanList(Array(Set(values)).sorted())
            } else { weeks = parsedWeeks }
            let credit = Float(text(creditIndex)) ?? 0
            for (start, end) in ranges {
                guard let last = step.flatMap({ explicitScheduleEnd(start, $0) }) ?? (step == nil ? end : nil), (1...366).contains(start), (start...366).contains(last) else { continue }
                for (firstWeek, lastWeek, parity) in weeks { courses.append(JwCourse(name: name, room: text(buildingIndex) + text(roomIndex), teacher: text(teacherIndex), day: day, startNode: start, endNode: last, startWeek: firstWeek, endWeek: lastWeek, type: parity, credit: credit.isFinite && credit >= 0 ? credit : 0)) }
            }
        }
        return courses
    }

    private static func dayNumber(_ raw: String) -> Int? {
        if let value = jw1064Integer(raw), (1...7).contains(value) { return value }
        var text = raw
        if text.hasPrefix("星期") { text = String(text.dropFirst(2)) }; if text.hasPrefix("周") { text.removeFirst() }
        let day = Jw64.day(text); return day == 0 ? nil : day
    }
    private static func smallNumber(_ raw: String) -> Int? {
        jw1064Integer(raw) ?? ["一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9,"十":10,"十一":11,"十二":12,"十三":13,"十四":14,"十五":15][raw]
    }
    private static func nodeRanges(_ raw: String) -> [(Int, Int)] {
        var cleaned = raw
        if cleaned.hasPrefix("第") { cleaned.removeFirst() }; if cleaned.hasSuffix("节") { cleaned.removeLast() }
        if cleaned.hasSuffix("大") {
            guard let value = smallNumber(String(cleaned.dropLast())), let pair = explicitSchedulePair(value) else { return [] }
            return [(pair.lowerBound, pair.lowerBound)]
        }
        let value = smallNumber(cleaned.hasSuffix("小") ? String(cleaned.dropLast()) : cleaned)
        if let value, (1...366).contains(value) { return [(value, value)] }
        return schoolNodeRanges(cleaned)
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
