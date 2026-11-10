// Declared table layouts from Android v1.0.64 (77b878fd).
import Foundation
import SwiftSoup

final class JwSchoolTableParser: JwParser {
    let source: String
    private let kind: String
    init(_ source: String, _ protocolName: String) { self.source = source; kind = protocolName }

    func generateCourseList() throws -> [JwCourse] {
        let result: [JwCourse]
        switch kind {
        case "hbut": result = hbut()
        case "hnjm": result = hnjm()
        case "lz": result = lz()
        case "nau": result = nau()
        case "nju": result = nju()
        case "cqupt": result = cqupt()
        default: result = []
        }
        return result.filter { c in
            !Jw64.trim(c.name).isEmpty && (1...7).contains(c.day) && c.startNode >= 1 && c.endNode >= c.startNode &&
            (1...366).contains(c.startWeek) && c.endWeek >= c.startWeek && c.endWeek <= 366 && (0...2).contains(c.type) &&
            (c.startWeek...c.endWeek).contains { c.type == 0 || $0 % 2 == c.type % 2 }
        }
    }

    private func hbut() -> [JwCourse] {
        guard let doc = Jw64.doc(source) else { return [] }
        var out: [JwCourse] = []
        if let table = Jw64.first(doc, ".table-Schedule table") {
            for (rowIndex, row) in Jw64.select(table, "tr").enumerated() where rowIndex > 0 {
                for (dayIndex, cell) in Jw64.select(row, "td").enumerated() {
                    for part in Self.split(Jw64.html(cell), #"(?i)<br\s*/?>\s*<br\s*/?>"#) {
                        let fields = Self.lines(part).filter { !$0.isEmpty }
                        guard fields.count >= 2, let tail = fields.last else { continue }
                        let last = tail.split(whereSeparator: \.isWhitespace).map(String.init)
                        let room = last.first { !$0.hasPrefix("第") || !$0.hasSuffix("周") } ?? ""
                        for week in last where week.hasPrefix("第") && week.hasSuffix("周") {
                            for (sw, ew, type) in schoolWeekRanges(week, trailingParityAppliesToAll: true) {
                                out.append(JwCourse(name: fields[0], room: room, teacher: fields.count > 2 ? fields[1] : "", day: dayIndex + 1,
                                                    startNode: (rowIndex - 1) * 2 + 1, endNode: (rowIndex - 1) * 2 + 2, startWeek: sw, endWeek: ew, type: type))
                            }
                        }
                    }
                }
            }
        }
        for row in Jw64.select(Jw64.first(doc, "#weekSchedule"), "tr") {
            let cells = Jw64.select(row, "td"); guard cells.count >= 5 else { continue }
            let days = Jw64.text(cells[2]).components(separatedBy: CharacterSet(charactersIn: "~～"))
            guard (1...2).contains(days.count), days.allSatisfy({ Jw64.full(#"(?:星期|周)[一二三四五六日天]"#, Jw64.trim($0)) != nil }) else { continue }
            let firstDay = Self.day(days.first ?? ""), lastDay = Self.day(days.last ?? "")
            guard (1...7).contains(firstDay), lastDay >= firstDay, lastDay <= 7 else { continue }
            let rawNodes = Jw64.text(cells[3]).replacingOccurrences(of: #"^第|节$"#, with: "", options: .regularExpression).replacingOccurrences(of: "[~～]", with: "-", options: .regularExpression)
            let weeks = schoolWeekRanges(Jw64.text(cells[1]).replacingOccurrences(of: "[~～]", with: "-", options: .regularExpression), trailingParityAppliesToAll: true)
            let rawName = Jw64.text(cells[0]), name = rawName.lastIndex(of: ",").map { String(rawName[..<$0]) } ?? rawName
            let rawRoom = Jw64.text(cells[4]), room = rawRoom.range(of: "地点:").map { String(rawRoom[$0.upperBound...]) } ?? ""
            for weekday in firstDay...lastDay { for (first, last) in schoolNodeRanges(rawNodes) { for (sw, ew, type) in weeks {
                out.append(JwCourse(name: Jw64.trim(name), room: Jw64.trim(room), day: weekday, startNode: first, endNode: last, startWeek: sw, endWeek: ew, type: type))
            } } }
        }
        return out
    }

    private func hnjm() -> [JwCourse] {
        guard let doc = Jw64.doc(source) else { return [] }
        let tables = Jw64.select(doc, "table"); var tableIndex = 0, out: [JwCourse] = []
        for header in Jw64.select(doc, ".Sub-kcbt") {
            if (try? header.nextElementSibling()?.tagNameNormal()) == "br" { continue }
            let weekday = Self.day(Jw64.text(header)); defer { tableIndex += 1 }
            guard tables.indices.contains(tableIndex), (1...7).contains(weekday) else { continue }
            for row in Jw64.select(tables[tableIndex], "tr") {
                let cells = Jw64.select(row, "td"); guard cells.count >= 3 else { continue }
                let rawNodes = Jw64.text(cells[0]).replacingOccurrences(of: "节$", with: "", options: .regularExpression), nodes = schoolNodeRanges(rawNodes)
                guard nodes.allSatisfy({ $0.1 <= EXPLICIT_SCHEDULE_RESOURCE_BOUND }) else { continue }
                let raw = Jw64.text(cells[1]); guard let week = Jw64.matches(#"([0-9]+(?:-[0-9]+)?)周"#, raw).first, let range = raw.range(of: week[0]) else { continue }
                let name = Jw64.trim(String(raw[..<range.lowerBound]))
                let room = Jw64.matches(#"[（(]([图0-9][0-9]{1,3})[）)]"#, raw).first?[1] ?? Jw64.matches(#"；([^】]+)】"#, raw).first?[1] ?? ""
                for (first, last) in nodes {
                    let complete = first >= 1 && last <= Self.hnjmPeriods.count
                    for (sw, ew, type) in schoolWeekRanges(week[1]) {
                        out.append(JwCourse(name: name, room: Jw64.trim(room), teacher: Jw64.text(cells[2]), day: weekday,
                                            startNode: first, endNode: last, startWeek: sw, endWeek: ew, type: type,
                                            startTime: complete ? Self.hnjmPeriods[first - 1].0 : "", endTime: complete ? Self.hnjmPeriods[last - 1].1 : ""))
                    }
                }
            }
        }
        return out
    }

    private func lz() -> [JwCourse] {
        guard let doc = Jw64.doc(source), let table = Jw64.first(doc, "#TableLCRoomOccupy") else { return [] }
        var out: [JwCourse] = []
        for row in Jw64.select(table, "tr") { for (dayIndex, cell) in Jw64.select(row, ".PuTongCell").enumerated() {
            let node = Jw64.full(#"jieci([0-9]+)day.*"#, Jw64.attr(cell, "id")).flatMap { jw1064Integer($0[1]) }
            if let node {
                for card in Jw64.select(cell, "div") where !Jw64.children(card).contains(where: { $0.tagNameNormal() == "div" }) {
                    let fields = Self.lines(Jw64.html(card)); guard fields.count >= 5 else { continue }
                    let roomTail = fields[2].range(of: "教室:").map { String(fields[2][$0.upperBound...]) } ?? ""
                    let room = roomTail.components(separatedBy: "(教室人数").first ?? ""
                    let raw = (fields[4].range(of: "周次:").map { String(fields[4][$0.upperBound...]) } ?? "").replacingOccurrences(of: #"\[([单双])(?:周)?]"#, with: "($1)", options: .regularExpression)
                    for (sw, ew, type) in schoolWeekRanges(raw) { out.append(JwCourse(name: fields[0], room: Jw64.trim(room), teacher: fields[1], day: dayIndex + 1, startNode: node, endNode: node, startWeek: sw, endWeek: ew, type: type)) }
                }
            } else {
                let fields = Self.lines(Jw64.html(cell)); guard fields.count >= 4, let m = Jw64.full(#"([^\[]+)\[([0-9,，\-]+)节]"#, fields[3]) else { continue }
                let weeks = schoolWeekRanges(m[1].replacingOccurrences(of: ",单周", with: "(单)").replacingOccurrences(of: ",双周", with: "(双)"))
                for (first, last) in schoolNodeRanges(m[2]) { for (sw, ew, type) in weeks { out.append(JwCourse(name: fields[0], room: fields[2], teacher: fields[1], day: dayIndex + 1, startNode: first, endNode: last, startWeek: sw, endWeek: ew, type: type)) } }
            }
        } }
        return out
    }

    private func nau() -> [JwCourse] {
        guard let doc = Jw64.doc(source), let content = Jw64.first(doc, "#content") else { return [] }
        let rows = Jw64.select(content, "tr"), headers = Jw64.select(rows.first, "th").map(Jw64.text)
        guard let nameColumn = headers.firstIndex(where: { $0.contains("课程名称") }), let timingColumn = headers.firstIndex(where: { $0.contains("上课时间及地点") }), let creditColumn = headers.firstIndex(where: { $0.contains("学分") }), let teacherColumn = headers.firstIndex(where: { $0.contains("任课教师") }) else { return [] }
        var out: [JwCourse] = []
        for row in rows.dropFirst() {
            let cells = Jw64.select(row, "td"); guard cells.count >= 8, cells.count > max(nameColumn, timingColumn, creditColumn, teacherColumn) else { continue }
            let credit = Float(Jw64.text(cells[creditColumn])).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
            for part in Jw64.text(cells[timingColumn]).components(separatedBy: "上课地点：").dropFirst() {
                let fields = part.components(separatedBy: "上课时间："); guard fields.count == 2, let m = Jw64.full(#"(\S+)\s+\S+\s+([1-7])\s+\S+\s+([0-9,，\-]+)节"#, Jw64.trim(fields[1])) else { continue }
                let weeks = schoolWeekRanges(m[1].replacingOccurrences(of: #"之([单双])周"#, with: "($1)", options: .regularExpression))
                for (first, last) in schoolNodeRanges(m[3]) { for (sw, ew, type) in weeks {
                    out.append(JwCourse(name: Jw64.text(cells[nameColumn]), room: Jw64.trim(fields[0]), teacher: Jw64.text(cells[teacherColumn]), day: Int(m[2])!, startNode: first, endNode: last, startWeek: sw, endWeek: ew, type: type, credit: credit))
                } }
            }
        }
        return out
    }

    private func nju() -> [JwCourse] {
        guard let doc = Jw64.doc(source) else { return [] }
        let rows = Array(Jw64.select(doc, "#kcb_container .wut_table tbody tr").dropFirst()); var periods: [Int:(String,String)] = [:], out: [JwCourse] = []
        for row in rows {
            guard let label = Jw64.first(row, "td.mtt_bgcolor_grey[data-unit]"), let node = jw1064Integer(Jw64.attr(label, "data-unit")), let m = Jw64.matches(#"\(([0-9]{2}:[0-9]{2})~([0-9]{2}:[0-9]{2})\)"#, Jw64.text(label)).first, JwCourse.isValidTimeRange(m[1], m[2]) else { continue }
            periods[node] = (m[1],m[2])
        }
        for row in rows {
            guard let label = Jw64.first(row, "td.mtt_bgcolor_grey[data-unit]"), let node = jw1064Integer(Jw64.attr(label, "data-unit")) else { continue }
            for card in Jw64.select(row, "td[data-role=item] .mtt_arrange_item") {
                let labelText = Jw64.trim(Jw64.text(Jw64.first(card, ".mtt_item_kcmc")).replacingOccurrences(of: #"^\S+\s+"#, with: "", options: .regularExpression))
                let name = Jw64.full(#"(.+?)(?:\s+[0-9]+班|[（(][0-9]+班[）)])"#, labelText).map { Jw64.trim($0[1]) } ?? labelText
                let text = Jw64.text(Jw64.first(card, ".mtt_item_sksj")); guard let dayText = Jw64.matches(#"周[一二三四五六日天]"#, text).first?[0] else { continue }
                let match = Jw64.matches(#"(?:第)?([0-9,，\-]+)节"#, text).first
                let nodes = match.map { schoolNodeRanges($0[1]) } ?? [(node,node)]
                var weeksText = text.replacingOccurrences(of: #"周[一二三四五六日天]"#, with: "", options: .regularExpression)
                if let match { weeksText = weeksText.replacingOccurrences(of: match[0], with: "") }
                for (first, last) in nodes { for (sw, ew, type) in schoolWeekRanges(Jw64.trim(weeksText)) {
                    let start = periods[first]?.0 ?? "", end = periods[last]?.1 ?? "", valid = JwCourse.isValidTimeRange(start, end)
                    out.append(JwCourse(name: name, room: Jw64.text(Jw64.first(card, ".mtt_item_room")), teacher: Jw64.text(Jw64.first(card, ".mtt_item_jxbmc")), day: Self.day(dayText), startNode: first, endNode: last, startWeek: sw, endWeek: ew, type: type, startTime: valid ? start : "", endTime: valid ? end : ""))
                } }
            }
        }
        return out
    }

    private func cqupt() -> [JwCourse] {
        guard let doc = Jw64.doc(source), let table = Jw64.first(doc, "#stuPanel") else { return [] }
        let starts = [0:1,1:3,3:5,4:7,6:9,7:11]; var out: [JwCourse] = []
        for (index,row) in Jw64.select(table, "tr[style=text-align:center]").enumerated() {
            guard let node = starts[index] else { continue }
            for (weekday,cell) in Jw64.select(row,"td").enumerated() where (1...7).contains(weekday) {
                for card in Jw64.select(cell,"div[zc]") {
                    let mask = Jw64.attr(card,"zc"); guard (1...366).contains(mask.count), mask.allSatisfy({ $0 == "0" || $0 == "1" }) else { continue }
                    let weeks = Self.ones(mask), fields = Self.split(Jw64.html(card), #"(<[^>]+>)+"#).map(Jw64.plain).filter { !$0.isEmpty }
                    guard fields.count >= 2 else { continue }
                    let name = fields[0].firstIndex(of: "-").map { String(fields[0][fields[0].index(after:$0)...]) } ?? fields[0]
                    let room = fields[1].range(of:"地点：").map { String(fields[1][$0.upperBound...]) } ?? ""
                    let creditField = fields.last { $0.contains("学分") }, teacher = creditField.map { String($0.split(separator:" ",omittingEmptySubsequences:false).first ?? "") } ?? ""
                    let creditRaw = creditField.map { String($0.split(separator:" ",omittingEmptySubsequences:false).last ?? "").components(separatedBy:"学分").first ?? "" } ?? ""
                    let credit = Float(creditRaw).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
                    let durationText = fields.compactMap { Jw64.full(#"([0-9]+)节连上"#, $0)?[1] }.first
                    guard let duration = durationText == nil ? 2 : jw1064Integer(durationText), duration >= 1, node <= Int(Int32.max) - duration + 1 else { continue }
                    for (sw,ew) in weeks { out.append(JwCourse(name:Jw64.trim(name),room:Jw64.trim(room),teacher:Jw64.trim(teacher),day:weekday,startNode:node,endNode:node+duration-1,startWeek:sw,endWeek:ew,credit:credit)) }
                }
            }
        }
        return out
    }

    private static func split(_ text: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern:pattern) else { return [] }
        let ns = text as NSString; var cursor = 0, out:[String] = []
        for match in re.matches(in:text,range:NSRange(location:0,length:ns.length)) { out.append(ns.substring(with:NSRange(location:cursor,length:match.range.location-cursor)));cursor=NSMaxRange(match.range) }
        out.append(ns.substring(from:cursor)); return out
    }
    private static func lines(_ html: String) -> [String] { split(html,#"(?i)<br\s*/?>"#).map(Jw64.plain) }
    private static func day(_ value: String) -> Int { Jw64.matches(#"(?:星期|周)([一二三四五六日天])"#,value).first.map { Jw64.day($0[1]) } ?? (Jw64.trim(value).count == 1 ? Jw64.day(Jw64.trim(value)) : 0) }
    private static func ones(_ mask:String) -> [(Int,Int)] { var out:[(Int,Int)] = [];var start:Int?;for (i,c) in mask.enumerated() {if c == "1" {if start == nil {start=i+1}} else if let first = start {out.append((first,i));start=nil}};if let first = start {out.append((first,mask.count))};return out }
    private static let hnjmPeriods = [("08:10","08:55"),("09:05","09:50"),("10:15","11:00"),("11:10","11:55"),("14:40","15:25"),("15:35","16:20"),("16:40","17:25"),("17:35","18:20"),("19:00","19:45"),("19:55","20:40")]
}
