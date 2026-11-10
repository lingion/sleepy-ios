import Foundation
import SwiftSoup

extension WakeUpCompat {
    static func parseJzNativeChain(_ source: String) -> [JwCourse] {
        for parser: (String) -> [JwCourse] in [parseJzHtml, parseJzMtt, parseJzWist,
            { parseJzMttLayout($0, layout: .hqu) }, { parseJzMttLayout($0, layout: .xjtu) },
            parseJzX, parseJzPost, parseJzXTable, parseJzXmu] {
            let rows = parser(source)
            if !rows.isEmpty { return rows }
        }
        return []
    }
    static func parseJzHtml(_ source: String) -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "[id=1], .CourseFormTable, #CourseFormTable") else { return [] }
        var occupied = Array(repeating: 0, count: 7), out: [JwCourse] = []
        for (rowIndex, row) in Jw64.select(table, "tr").enumerated() {
            var dayIndex = 0
            for cell in Jw64.children(row).filter({ $0.tagNameNormal() == "td" }) {
                if Jw64.attr(cell, "style").lowercased().contains("center") || cell.hasClass("firstHiddenTd") { continue }
                if cell.hasClass("NotFixCourseTableTd") || cell.hasClass("commentAlign") { return out }
                while dayIndex < 7 && occupied[dayIndex] > rowIndex { dayIndex += 1 }
                if dayIndex >= 7 { break }
                let day = dayIndex + 1
                occupied[dayIndex] = rowIndex + max(1, Int(Jw64.attr(cell, "rowspan")) ?? 1); dayIndex += 1
                if Jw64.text(cell).isEmpty { continue }
                let html = Jw64.html(cell).replacingOccurrences(of: #"(?i)&nbsp;\s*<br\s*/?>|<br\s*/?>\s*&nbsp;"#, with: "<br>", options: .regularExpression)
                for chunk in nativeSplit(html, #"(?i)<hr\b[^>]*>"#) {
                    var fields = nativeSplit(chunk, "(?i)<br\\s*/?>|&nbsp;|\u{00a0}").map(Jw64.plain)
                    while fields.first?.isEmpty == true { fields.removeFirst() }; while fields.last?.isEmpty == true { fields.removeLast() }
                    guard fields.count >= 5 else { continue }
                    let name = beforeNative(fields[0], "[")
                    let weekIndex = fields[1].first?.isNumber == true ? 1 : 2
                    guard !name.isEmpty, let nodeIndex = (2...3).first(where: { fields[$0].contains("节") }),
                          let m = Jw64.matches(#"第\s*(\d+)(?:\s*[-~至]\s*(\d+))?\s*节"#, fields[nodeIndex]).first,
                          let first = Int(m[1]), let last = Int(m[2].isEmpty ? m[1] : m[2]), first > 0, last >= first,
                          let teacherIndex = (1...3).first(where: { $0 != weekIndex && $0 != nodeIndex }) else { continue }
                    var note = fields[nodeIndex].components(separatedBy: ")").dropFirst().joined(separator: ")")
                    if note.hasPrefix("("), note.hasSuffix(")") { note = String(note.dropFirst().dropLast()) }
                    for (from, to, parity) in nativeWeekTokens(fields[weekIndex]) where from > 0 && to >= from {
                        out.append(JwCourse(name: name, room: fields[4], teacher: fields[teacherIndex], day: day,
                                            startNode: first, endNode: last, startWeek: from, endWeek: to, type: parity, note: Jw64.trim(note)))
                    }
                }
            }
        }
        return out
    }
    static func parseJzX(_ source: String) -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), ".wut_tablex") else { return [] }
        var out: [JwCourse] = []
        for cell in Jw64.select(table, "td[data-role][data-week]") {
            guard let day = Int(Jw64.attr(cell, "data-week")), (1...7).contains(day) else { continue }
            for block in Jw64.children(cell) {
                let children = Jw64.children(block)
                guard children.count >= 3 else { continue }
                let title = Jw64.text(children[1]), name = beforeNative(afterNative(title, "《"), "》")
                let fields = nativeSplit(Jw64.html(children[2]), "&nbsp;|\u{00a0}")
                let shift = fields.count > 3 && fields[3].contains("节") ? 0 : 1
                guard fields.count >= 5 - shift, !name.isEmpty,
                      let nodes = nativeJzNodes(Jw64.plain(fields[3 - shift])) else { continue }
                for (from, to, parity) in nativeWeekTokens(Jw64.plain(fields[2 - shift])) where from > 0 && to >= from {
                    out.append(JwCourse(name: name, room: Jw64.plain(fields.dropFirst(4 - shift).joined()), teacher: Jw64.plain(fields[1 - shift]),
                                        day: day, startNode: nodes.0, endNode: nodes.1, startWeek: from, endWeek: to, type: parity))
                }
            }
        }
        return out
    }
    static func parseJzXTable(_ source: String) -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), ".x-table") else { return [] }
        var out: [JwCourse] = []
        for block in Jw64.select(table, "div") where !Jw64.children(block).contains(where: { $0.tagNameNormal() == "div" }) {
            let fields = nativeSplit(Jw64.html(block), #"(?i)<br\s*/?>"#).map(Jw64.plain)
            for i in 0..<max(0, fields.count - 2) where i == 0 || fields[i].hasPrefix(",") {
                let name = beforeNative(afterNative(fields[i], ","), "["), arrangement = fields[i + 2].components(separatedBy: "，").map(Jw64.trim)
                guard !name.isEmpty, arrangement.count >= 4, let day = nativeDay(arrangement[1]), let nodes = nativeJzNodes(arrangement[2]) else { continue }
                for (from, to, parity) in nativeWeekTokens(arrangement[0]) where from > 0 && to >= from {
                    out.append(JwCourse(name: name, room: arrangement.last ?? "", teacher: fields[i + 1], day: day,
                                        startNode: nodes.0, endNode: nodes.1, startWeek: from, endWeek: to, type: parity))
                }
            }
        }
        return Jw64.distinct(out)
    }
    private static func nativeJzNodes(_ text: String) -> (Int, Int)? {
        guard let m = Jw64.full(#"第?\s*([0-9一二三四五六七八九十]+)\s*节?(?:\s*[-~至]\s*第?\s*([0-9一二三四五六七八九十]+)\s*节?)?"#, Jw64.trim(text)) else { return nil }
        func number(_ raw: String) -> Int? {
            if let n = Int(raw) { return n }
            let digits = ["一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9]
            if raw == "十" { return 10 }; if raw == "二十" { return 20 }
            if raw.hasPrefix("十"), let last = digits[String(raw.dropFirst())] { return 10 + last }
            return digits[raw]
        }
        guard let first = number(m[1]), let last = number(m[2].isEmpty ? m[1] : m[2]), first > 0, last >= first else { return nil }
        return (first, last)
    }
    private enum NativeMttLayout { case comma, hqu, xjtu }
    static func parseJzMtt(_ source: String) -> [JwCourse] { parseJzMttLayout(source, layout: .comma) }
    private static func parseJzMttLayout(_ source: String, layout: NativeMttLayout) -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source.replacingOccurrences(of: "divclass=", with: "div class=")), ".wut_table") else { return [] }
        var out: [JwCourse] = []
        for cell in Jw64.select(table, "td") { for item in Jw64.select(cell, ".mtt_arrange_item") {
            guard let headingElement = Jw64.first(item, ".mtt_item_kcmc"), let roomElement = Jw64.first(item, ".mtt_item_room") else { continue }
            let heading = nativeSplit(Jw64.html(headingElement), "&nbsp;|\u{00a0}").map(Jw64.plain)
            let headingWeeks = heading.first { $0.range(of: #"\d周"#, options: .regularExpression) != nil }
            let roomText = Jw64.text(roomElement), space = !roomText.contains(",") && headingWeeks == nil
            let itemLayout: NativeMttLayout = headingWeeks != nil ? .xjtu : space ? .hqu : .comma
            guard itemLayout == layout else { continue }
            let fields = (space ? nativeSplit(roomText, #"\s+"#) : roomText.components(separatedBy: ",")).map(Jw64.trim)
            let dayIndex = fields.firstIndex { $0.hasPrefix("星期") }, day = Int(Jw64.attr(cell, "data-week")) ?? dayIndex.flatMap { nativeDay(fields[$0]) }
            let nodeIndex = fields.firstIndex { $0.contains("节") && nativeJzNodes($0) != nil }
            let nodes: (Int, Int)? = nodeIndex.flatMap { nativeJzNodes(fields[$0]) } ?? {
                guard let first = Int(Jw64.attr(cell, "data-begin-unit")), let last = Int(Jw64.attr(cell, "data-end-unit")), first > 0, last >= first else { return nil }; return (first, last)
            }()
            guard let day, (1...7).contains(day), let nodes else { continue }
            let own = Jw64.trim(headingElement.ownText())
            var name: String
            if headingWeeks != nil { name = afterNative(fields.first ?? "", " ") }
            else if Jw64.full(#"\[\d+]"#, own) != nil { name = Jw64.text(Jw64.children(headingElement).first) }
            else { name = own.replacingOccurrences(of: #"^\[\d+]\s*"#, with: "", options: .regularExpression) }
            let creditMatch = space ? Jw64.matches(#"\(([0-9.]+)学分\)"#, name).first : nil
            let credit = creditMatch.flatMap { Float($0[1]) }.flatMap { $0.isFinite ? $0 : nil } ?? 0
            if let creditMatch { name = Jw64.trim(name.replacingOccurrences(of: creditMatch[0], with: "")) }
            guard !name.isEmpty else { continue }
            let teacher = headingWeeks != nil ? beforeNative(heading.last ?? "", "[") : Jw64.select(item, ".mtt_item_jxbmc").map(Jw64.text).joined(separator: " ")
            let weekEnd = dayIndex ?? nodeIndex ?? -1
            let weeks: String
            if let headingWeeks { weeks = headingWeeks }
            else if space { weeks = fields.dropFirst().dropLast().joined(separator: ",") }
            else if weekEnd > 0 { weeks = fields.prefix(weekEnd).joined(separator: ",") }
            else if dayIndex == nil && nodeIndex == nil { weeks = fields.dropLast().joined(separator: ",") }
            else { continue }
            let room = space ? fields.first ?? "" : dayIndex.map { fields.count - $0 > 3 } == true ? fields[fields.count - 2] : fields.last ?? ""
            for (from, to, parity) in schoolWeekRanges(weeks) where from > 0 && to >= from {
                out.append(JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: nodes.0, endNode: nodes.1,
                                    startWeek: from, endWeek: to, type: parity, credit: credit))
            }
        } }
        return out
    }
    static func parseJzWist(_ source: String) -> [JwCourse] {
        var out: [JwCourse] = []
        let numeric = #"(中?[1-9]\d?)(-(中?[1-9]\d?))?"#
        func number(_ value: String) -> Int? { value == "中1" ? 5 : value == "中2" ? 6 : Int(value) }
        for cell in Jw64.select(Jw64.doc(source), "td[data-role=item]") {
            guard let day = Int(Jw64.attr(cell, "data-week")), (1...7).contains(day) else { continue }
            for item in Jw64.select(cell, "div.mtt_arrange_item") {
                guard let title = Jw64.first(item, ".mtt_item_kcmc"), let roomElement = Jw64.first(item, ".mtt_item_room") else { continue }
                let name = Jw64.trim(title.ownText()), teacher = Jw64.text(Jw64.first(item, ".mtt_item_jxbmc"))
                let fields = Jw64.text(roomElement).components(separatedBy: CharacterSet(charactersIn: ",，")).map(Jw64.trim)
                let nodes: (Int, Int)?
                if let first = Int(Jw64.attr(cell, "data-begin-unit")), let last = Int(Jw64.attr(cell, "data-end-unit")) { nodes = (first, last) }
                else if let token = fields.first(where: { Jw64.full(numeric, $0) != nil }) {
                    let parts = token.components(separatedBy: "-"); nodes = number(parts[0]).flatMap { first in number(parts.last ?? "").map { (first, $0) } }
                } else { nodes = nil }
                guard !name.isEmpty, let nodes, nodes.0 > 0, nodes.1 >= nodes.0 else { continue }
                let rooms = fields.filter { !$0.contains("周") && Jw64.full(numeric, $0) == nil }
                let room = rooms.first { $0.range(of: "实验室|教室|机房", options: .regularExpression) != nil } ?? rooms.first ?? ""
                for (from, to, parity) in schoolWeekRanges(fields.filter { $0.contains("周") }.joined(separator: ",")) {
                    for week in from...to where parity == 0 || week % 2 == parity % 2 {
                        out.append(JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: nodes.0, endNode: nodes.1, startWeek: week, endWeek: week))
                    }
                }
            }
        }
        var order: [JwCourse] = [], groups: [JwCourse: [JwCourse]] = [:]
        for course in Jw64.distinct(out) {
            let key = JwCourse(name: course.name, room: course.room, teacher: course.teacher, day: course.day, startNode: 0, endNode: 0,
                               startWeek: course.startWeek, endWeek: course.endWeek, type: course.type, credit: course.credit, note: course.note)
            if groups[key] == nil { order.append(key); groups[key] = [] }; groups[key, default: []].append(course)
        }
        return order.flatMap { key -> [JwCourse] in
            var merged: [JwCourse] = []
            for course in (groups[key] ?? []).sorted(by: { $0.startNode < $1.startNode }) {
                if let old = merged.last, course.startNode <= old.endNode + 1 {
                    merged[merged.count - 1] = JwCourse(name: old.name, room: old.room, teacher: old.teacher, day: old.day,
                        startNode: old.startNode, endNode: max(old.endNode, course.endNode), startWeek: old.startWeek, endWeek: old.endWeek, type: old.type)
                } else { merged.append(course) }
            }
            return merged
        }
    }
    static func parseJzXmu(_ source: String) -> [JwCourse] {
        guard let rows = Jw64.prefixJson(source, assignment: #"var\s+scheduleList\s*="#) as? [Any],
              source.range(of: #";\s*var\s+notArrangedList"#, options: .regularExpression) != nil else { return [] }
        var out: [JwCourse] = []
        for case let row as [String: Any] in rows {
            let name = Jw64.text(row, "KCM"), room = Jw64.text(row, "SKDD").isEmpty ? Jw64.text(row, "YPSJDD") : Jw64.text(row, "SKDD"), bitmap = Jw64.text(row, "SKZC")
            guard !name.isEmpty, let day = Jw64.int(row, "SKXQ"), (1...7).contains(day), let first = Jw64.int(row, "KSJC"), let last = Jw64.int(row, "JSJC"), first > 0, last >= first,
                  bitmap.allSatisfy({ $0 == "0" || $0 == "1" }) else { continue }
            for (i, bit) in bitmap.enumerated() where bit == "1" {
                out.append(JwCourse(name: name, room: room, teacher: Jw64.text(row, "SKJS"), day: day,
                                    startNode: first, endNode: last, startWeek: i + 1, endWeek: i + 1))
            }
        }
        return out
    }
    internal static func nativeSplit(_ text: String, _ pattern: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let ns = text as NSString; var offset = 0, out: [String] = []
        for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: offset, length: match.range.location - offset))); offset = NSMaxRange(match.range)
        }
        out.append(ns.substring(from: offset)); return out
    }
    internal static func nativeWeekTokens(_ text: String) -> [(Int, Int, Int)] {
        text.replacingOccurrences(of: "周", with: "").components(separatedBy: CharacterSet(charactersIn: ",，;；")).compactMap { raw in
            let numbers = Jw64.matches(#"\d+"#, raw).compactMap { Int($0[0]) }
            guard let first = numbers.first else { return nil }
            return (first, numbers.count > 1 ? numbers[1] : first, raw.contains("单") ? 1 : raw.contains("双") ? 2 : 0)
        }
    }
    internal static func beforeNative(_ text: String, _ separator: String) -> String { Jw64.trim(text.components(separatedBy: separator).first ?? text) }
    internal static func afterNative(_ text: String, _ separator: String) -> String { text.range(of: separator).map { Jw64.trim(String(text[$0.upperBound...])) } ?? text }
    internal static func nativeDay(_ text: String) -> Int? {
        guard let value = Jw64.matches(#"(?:星期|周)\s*([一二三四五六日天1-7])"#, text).first?[1] else { return nil }
        return Int(value) ?? ["一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"日":7,"天":7][value]
    }
}

extension WakeUpCompat {
    static func parseSouthSoft(_ source: String) -> [JwCourse] {
        if let body = Jw64.first(Jw64.doc(source), "#kb tbody") {
            var out: [JwCourse] = [], unnumbered = 0
            for (rowIndex, row) in Jw64.select(body, "tr").enumerated() {
                let cells = Jw64.children(row).filter { $0.tagNameNormal() == "td" }
                if Jw64.text(cells.first).contains("无节次") { unnumbered += 1 }
                let node = rowIndex + 1 - unnumbered; guard node > 0 else { continue }
                for (day, cell) in cells.enumerated() where (1...7).contains(day) {
                    for block in Jw64.select(cell, "div") {
                        let fields = nativeSplit(Jw64.html(block), #"(<[/]*((?!br).)*?> *)+"#).map(Jw64.plain)
                        for (index, field) in fields.enumerated() {
                            guard let m = Jw64.matches(#"(\d+)-(\d+)周"#, field).first, let from = Int(m[1]), let to = Int(m[2]), from > 0, to >= from else { continue }
                            func nameAt(_ delta: Int) -> String { let i = index + delta; return fields.indices.contains(i) ? beforeNative(beforeNative(fields[i], "班级："), "班级:") : "" }
                            let prior = nameAt(-1).isEmpty ? nameAt(-2) : nameAt(-1)
                            let name = beforeNative(afterNative(prior, "课程名称:").replacingOccurrences(of: "||##", with: ""), "||")
                            guard !name.isEmpty else { continue }
                            let teacher = fields.indices.contains(index + 1) ? fields[index + 1].replacingOccurrences(of: "(连续周)", with: "").replacingOccurrences(of: "连续周", with: "") : ""
                            out.append(JwCourse(name: name, room: fields.indices.contains(index + 2) ? fields[index + 2] : "", teacher: Jw64.trim(teacher),
                                                day: day, startNode: node, endNode: node, startWeek: from, endWeek: to))
                        }
                    }
                }
            }
            return Jw64.distinct(out)
        }
        guard let root = Jw64.json(source) else { return [] }
        let rows = (root as? [Any]) ?? (root as? [String: Any]).flatMap { ($0["value"] as? [Any]) ?? ($0["data"] as? [Any]) } ?? []
        var out: [JwCourse] = []
        for case let row as [String: Any] in rows {
            if Jw64.text(row, "KEY") == "bz" { continue }
            guard let rawDay = Jw64.matches(#"xq(\d+)_jc\d+"#, Jw64.text(row, "KEY")).first?[1], let day = Int(rawDay) else { continue }
            let fields = Jw64.matches(#"\[(.*?)\]"#, Jw64.text(row, "SKSJ")).map { Jw64.trim($0[1]) }
            guard fields.count >= 5 else { continue }
            let bounds = fields[4].replacingOccurrences(of: "第", with: "").replacingOccurrences(of: "节", with: "").components(separatedBy: "-")
            guard let first = Int(bounds[0]) else { continue }; let last = bounds.count > 1 ? Int(bounds[1]) ?? first : first
            let name = Jw64.text(row, "KCWZSM").isEmpty ? fields[0] : Jw64.text(row, "KCWZSM")
            for (from, to, parity) in nativeWeekTokens(fields[1]) {
                out.append(JwCourse(name: name, room: fields[3], teacher: fields[2], day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: parity))
            }
        }
        return out
    }
    static func parseShuwei(_ source: String) -> [JwCourse] {
        let input = source.range(of: "index.js');").map { String(source[$0.upperBound...]) } ?? source
        guard let root = Jw64.json(input) else { return [] }
        if let object = root as? [String: Any], let slots = object["activities"] as? [Any], slots.contains(where: { $0 is [Any] }) {
            let units = object.keys.contains("unitCount") ? Jw64.int(object, "unitCount") ?? 0 : (object["courseUnits"] as? [Any])?.count ?? 12
            guard units > 0 else { return [] }; var out: [JwCourse] = []
            for (index, slot) in slots.enumerated() {
                let day = index / units + 1, node = index % units + 1; guard (1...7).contains(day), let rows = slot as? [Any] else { continue }
                for case let row as [String: Any] in rows {
                    let name = Jw64.text(row, "courseName"), bits = Jw64.text(row, "vaildWeeks")
                    guard !name.isEmpty, bits.allSatisfy({ $0 == "0" || $0 == "1" }) else { continue }
                    for (week, bit) in bits.enumerated() where week > 0 && bit == "1" {
                        out.append(JwCourse(name: name, room: Jw64.text(row, "roomName"), teacher: Jw64.text(row, "teacherName"), day: day, startNode: node, endNode: node, startWeek: week, endWeek: week))
                    }
                }
            }
            return Jw64.distinct(out)
        }
        return parseShuweiLegacy(input)
    }
    static func parseSuda(_ source: String) -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "#DataGrid1, #MainWork_DataGrid1") else { return [] }
        var occupied = Array(repeating: 0, count: 7), node = 0, out: [JwCourse] = []
        for row in Jw64.rows(table) {
            if Jw64.attr(row, "align").lowercased() == "center" || Jw64.children(row).contains(where: { $0.tagNameNormal() == "th" }) { continue }
            if Jw64.children(row).contains(where: { Jw64.full(#"(?:星期|周)[一二三四五六日天]"#, Jw64.text($0)) != nil }) { continue }
            node += 1; if node > 366 { break }; var column = 0
            for cell in Jw64.children(row).filter({ $0.tagNameNormal() == "td" }) {
                if Jw64.attr(cell, "align").lowercased() == "center" { continue }
                while column < 7 && occupied[column] >= node { column += 1 }
                if column >= 7 { break }
                let day = column + 1, span: Int? = cell.hasAttr("rowspan") ? Int(Jw64.attr(cell, "rowspan")) : 1
                let end = span.flatMap { explicitScheduleEnd(node, $0) }
                occupied[column] = end ?? (span == nil || (span ?? 0) > 0 ? 366 : node); column += 1
                guard let end, !Jw64.text(cell).isEmpty else { continue }
                for block in nativeSplit(Jw64.html(cell), #"(?i)(?:<br\s*/?>\s*){2,}"#) {
                    let fields = nativeSplit(block, #"(?i)<br\s*/?>"#).map(Jw64.plain).filter { !$0.isEmpty }
                    let rawName = fields.first { $0.hasPrefix("课程:") || $0.hasPrefix("课程：") }
                    let name = rawName.map { afterNative(afterNative($0, ":"), "：") } ?? fields.first ?? ""
                    let room = fields.first { $0.hasPrefix("(") && !$0.contains("辅讲教师") }.map { beforeNative(afterNative($0, "("), ")") } ?? ""
                    let teacher = fields.first { $0.hasPrefix("主讲教师:") || $0.hasPrefix("主讲教师：") }.map { afterNative(afterNative($0, ":"), "：") } ?? ""
                    guard !name.isEmpty else { continue }
                    for line in fields where line.range(of: #"\d周"#, options: .regularExpression) != nil {
                        for token in line.components(separatedBy: CharacterSet(charactersIn: ";,；，")) {
                            guard let m = Jw64.matches(#"第?\s*(\d+)(?:\s*-\s*(\d+))?\s*周(?:单双|[单双])?"#, token).first,
                                  let from = Int(m[1]), let to = Int(m[2].isEmpty ? m[1] : m[2]), from > 0, to >= from else { continue }
                            out.append(JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: node, endNode: end,
                                                startWeek: from, endWeek: to, type: token.contains("单双") ? 0 : token.contains("单") ? 1 : token.contains("双") ? 2 : 0))
                        }
                    }
                }
            }
        }
        return Jw64.distinct(out)
    }
    static func parseUmooc(_ source: String) -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "#timetable") else { return [] }
        var out: [JwCourse] = []
        for row in Jw64.select(table, ".infolist_hr_common") {
            var header: Int?
            for cell in Jw64.children(row) {
                if cell.tagNameNormal() == "th" { header = Jw64.matches(#"第\s*(\d+)\s*节"#, Jw64.text(cell)).first.flatMap { Int($0[1]) } }
                guard Jw64.html(cell).contains("&lt;&lt;") else { continue }
                let identity = Jw64.attr(cell, "id").components(separatedBy: "-")
                guard identity.count == 2, let day = Int(Jw64.trim(identity[0])), (1...7).contains(day), let node = header ?? Int(Jw64.trim(identity[1])), (1...366).contains(node) else { continue }
                for block in Jw64.html(cell).components(separatedBy: "&lt;&lt;").dropFirst() {
                    var fields = nativeSplit(block, #"(?i)<br\s*/?>"#).map(Jw64.plain)
                    while fields.last?.isEmpty == true { fields.removeLast() }
                    guard fields.count >= 3 else { continue }
                    let name = beforeNative(fields[0], ">>"); guard !name.isEmpty else { continue }
                    let weeks = fields.reversed().first { line in
                        (line.range(of: #"\d"#, options: .regularExpression) != nil && !line.contains("学时") && !line.contains("补课") && line.range(of: #"\d.*节|T\d"#, options: .regularExpression) == nil) || line.range(of: "[全双单]周", options: .regularExpression) != nil
                    }.map { beforeNative($0, "【") } ?? ""
                    for week in umoocWeeks(weeks) {
                        out.append(JwCourse(name: name, room: fields[1], teacher: fields.count < 5 ? fields[1] : fields[2], day: day,
                                            startNode: node, endNode: node, startWeek: week, endWeek: week))
                    }
                }
            }
        }
        return mergeCourseWeeks(out)
    }
    static func parseYl(_ source: String) -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "div[class*=app-components-CourseTimeTable-styles-timeTable]"), let body = Jw64.first(table, "tbody") else { return [] }
        var out: [JwCourse] = []
        for row in Jw64.select(body, "tr") {
            for (day, cell) in Jw64.children(row).filter({ $0.tagNameNormal() == "td" }).enumerated() where (1...7).contains(day) {
                for box in Jw64.select(cell, "div[class*=app-components-CourseTimeTable-styles-courseBox]") {
                    let fields = Jw64.children(box); guard fields.count >= 5 else { continue }
                    let name = Jw64.text(fields[0]), timing = Jw64.children(fields[1]); guard !name.isEmpty, timing.count >= 3 else { continue }
                    let nodes = Jw64.matches(#"\d+"#, Jw64.text(timing[2])).compactMap { Int($0[0]) }
                    guard let first = nodes.first, let last = nodes.last, first > 0, last >= first else { continue }
                    for (from, to, parity) in nativeWeekTokens(Jw64.text(timing[1])) where from > 0 && to >= from {
                        out.append(JwCourse(name: name, room: beforeNative(Jw64.text(fields[3]), "("), teacher: Jw64.text(fields[4]), day: day,
                                            startNode: first, endNode: last, startWeek: from, endWeek: to, type: parity))
                    }
                }
            }
        }
        return Jw64.distinct(out)
    }
}

extension WakeUpCompat {
    static func parseKingoSuperHtml(_ source: String, errors: inout [String]) -> [JwCourse] {
        let doc = Jw64.doc(source)
        func nodes(_ text: String) -> (Int, Int)? {
            if Jw64.trim(text) == "傍晚" { return (9, 9) }
            guard let m = Jw64.full(#"\s*(\d+)(?:\s*[-~至]\s*(\d+))?\s*(?:节)?\s*"#, text),
                  let first = Int(m[1]), let last = Int(m[2].isEmpty ? m[1] : m[2]), (1...366).contains(first), (first...366).contains(last) else { return nil }
            return (first, last)
        }
        func emit(_ name: String, _ teacher: String, _ room: String, _ day: Int, _ nodeText: String, _ weekText: String, _ credit: Float = 0) -> [JwCourse] {
            guard !Jw64.trim(name).isEmpty, (1...7).contains(day), let node = nodes(nodeText) else { return [] }
            var weeks: [(Int, Int, Int)] = [], expanded: [Int] = []
            for raw in weekText.components(separatedBy: CharacterSet(charactersIn: ",，;；")) {
                let token = raw.replacingOccurrences(of: #"\s+"#, with: "", options: .regularExpression)
                guard let m = Jw64.full(#"([0-9]+)(?:[-~至]([0-9]+))?周?(?:[\(（]([单双])[）\)]|([单双])周?)?"#, token),
                      let first = Int(m[1]), let last = Int(m[2].isEmpty ? m[1] : m[2]), (1...366).contains(first), (first...366).contains(last) else { return [] }
                let parity = (m[3].isEmpty ? m[4] : m[3]) == "单" ? 1 : (m[3].isEmpty ? m[4] : m[3]) == "双" ? 2 : 0
                weeks.append((first, last, parity)); expanded += (first...last).filter { parity == 0 || $0 % 2 == parity % 2 }
            }
            if Set(expanded).count != expanded.count {
                weeks = JwUcasParser.splitWeekRuns(expanded).map { ($0.startWeek, $0.endWeek, $0.type) }
            }
            return weeks.map { JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: node.0, endNode: node.1,
                                       startWeek: $0.0, endWeek: $0.1, type: $0.2, credit: credit) }
        }
        func dayHeader(_ text: String, _ day: Int) -> Bool {
            let t = Jw64.trim(text); guard t.count <= 3, (1...7).contains(day) else { return false }
            let name = Jw64.dayNames[day - 1]
            return [name, "星期" + name, "周" + name, "星期\(day)", "周\(day)"].contains(t) || day == 7 && ["天", "星期天", "周天"].contains(t)
        }
        var primary: [JwCourse] = []
        for table in Jw64.select(doc, "#mytable") {
            let rows = Jw64.rows(table); guard !rows.isEmpty else { continue }
            var grid = Array(repeating: [Int: Element](), count: rows.count)
            for (r, row) in rows.enumerated() {
                var column = 0
                for cell in Jw64.cells(row) {
                    while grid[r][column] != nil { column += 1 }
                    let span = min(max(Int(Jw64.attr(cell, "rowspan")) ?? 1, 1), rows.count - r)
                    let width = min(max(Int(Jw64.attr(cell, "colspan")) ?? 1, 1), 1000)
                    for row in r..<(r + span) { for col in column..<(column + width) { grid[row][col] = cell } }
                    column += width
                }
            }
            var dayColumns: [Int: Int] = [:]
            for row in grid {
                let candidates = row.compactMapValues { cell in (1...7).first { dayHeader(Jw64.text(cell), $0) } }
                if candidates.count >= 2 { dayColumns = candidates; break }
            }
            var visited = Set<ObjectIdentifier>()
            for (r, row) in rows.enumerated() {
                if row.hasClass("H") || !Jw64.select(row, "th").isEmpty || Jw64.children(row).contains(where: { dayHeader(Jw64.text($0), 1) }) { continue }
                if Jw64.children(row).filter({ $0.tagNameNormal() == "td" }).isEmpty { continue }
                for column in grid[r].keys.sorted() {
                    guard let cell = grid[r][column], visited.insert(ObjectIdentifier(cell)).inserted else { continue }
                    let day: Int
                    if !dayColumns.isEmpty { guard let value = dayColumns[column] else { continue }; day = value }
                    else {
                        var gutters = 0
                        for col in grid[r].keys.sorted() {
                            guard let leading = grid[r][col], !leading.hasClass("td"),
                                  ["节次", "时间", "时段", "上午", "下午", "晚上"].contains(Jw64.text(leading)) || Jw64.full(#"第?\d+(?:[-~至]\d+)?节"#, Jw64.text(leading)) != nil else { break }
                            gutters += 1
                        }
                        day = column - gutters + 1
                    }
                    guard (1...7).contains(day) else { continue }
                    var compact = false
                    let children = Jw64.children(cell).filter { $0.tagNameNormal() == "div" }
                    let blocks = children.isEmpty && Jw64.text(cell).range(of: #"\[\s*(?:\d+|傍晚)"#, options: .regularExpression) != nil ? [cell] : children
                    for block in blocks {
                        if block.hasClass("div1") { compact = Jw64.html(block).contains("xkinfo") && Jw64.html(block).contains("&nbsp;"); continue }
                        let html = compact ? Jw64.html(block).replacingOccurrences(of: #"(?i)(?:&nbsp;)+"#, with: "<br>", options: .regularExpression) : Jw64.html(block)
                        let fields = nativeSplit(html, #"(?i)<br\s*/?>"#).map(Jw64.plain).filter { !$0.isEmpty }
                        guard let timing = fields.firstIndex(where: { $0.contains("[") && $0.contains("]") && $0.range(of: #"\[\s*(?:\d+|傍晚)"#, options: .regularExpression) != nil }), timing > 0 else { continue }
                        let detail = fields[timing], before = beforeNative(detail, "["), nodeText = beforeNative(afterNative(detail, "["), "]")
                        let compactMode = compact || timing == 1 && before.contains(" ") && !before.contains(",") && !before.contains("，")
                        let teacher = compactMode && before.contains(" ") ? beforeNative(detail, " ") : fields.dropFirst().prefix(max(0, timing - 1)).joined(separator: " ")
                        let weeks = compactMode && before.contains(" ") ? beforeNative(afterNative(detail, " "), "[") : before
                        primary += emit(fields.first ?? "", teacher, fields.dropFirst(timing + 1).joined(separator: " "), day, nodeText, weeks)
                    }
                }
            }
        }
        if !primary.isEmpty { return primary }; errors.append("chain1 #mytable: no valid weekday cell")
        var secondary: [JwCourse] = []
        for table in Jw64.select(doc, "table") {
            guard let header = Jw64.first(table, "thead tr") else { continue }
            let headers = Jw64.select(header, "th,td").map(Jw64.text)
            guard let nameIndex = headers.firstIndex(of: "课程"), let nodeIndex = headers.firstIndex(where: { $0.contains("节次") }) else { continue }
            let teacherIndex = headers.firstIndex { $0.contains("教师") }, roomIndex = headers.firstIndex { $0.contains("地点") }, weeksIndex = headers.firstIndex { $0.contains("周次") }, parityIndex = headers.firstIndex { $0.contains("单双周") }, creditIndex = headers.firstIndex(of: "学分")
            for row in Jw64.select(table, "tbody tr") {
                let cells = Jw64.children(row)
                func field(_ index: Int?) -> String { index.flatMap { cells.indices.contains($0) ? Jw64.text(cells[$0]) : nil } ?? "" }
                let name = afterNative(field(nameIndex), "]"), timing = field(nodeIndex)
                guard let day = nativeDay(beforeNative(timing, "[")) else { continue }
                let node = beforeNative(afterNative(timing, "["), "]"), weeks = weeksIndex != nil ? field(weeksIndex) : beforeNative(afterNative(timing, "("), "周")
                let parity = field(parityIndex).contains("单") ? "单" : field(parityIndex).contains("双") ? "双" : ""
                let typed = weeks.replacingOccurrences(of: "，", with: ",").components(separatedBy: ",").map { raw in let token = Jw64.trim(raw); return token.contains("单") || token.contains("双") || parity.isEmpty ? token : token + parity }.joined(separator: ",")
                let credit = Float(field(creditIndex)).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? 0
                secondary += emit(name, afterNative(field(teacherIndex), "]"), field(roomIndex), day, node, typed, credit)
            }
        }
        if !secondary.isEmpty { return secondary }; errors.append("chain2 thead: no valid course row")
        var last: [JwCourse] = []
        for table in Jw64.select(doc, "#kbDiv") {
            guard let body = Jw64.select(table, "tbody").last else { continue }
            for (r, row) in Jw64.select(body, "tr").enumerated() {
                for (day, cell) in Jw64.select(row, "td").suffix(7).enumerated() {
                    let text = Jw64.text(cell); guard let opening = text.range(of: "(", options: .backwards) else { continue }
                    let name = Jw64.trim(String(text[..<opening.lowerBound])), detail = beforeNative(String(text[opening.upperBound...]), ")"), fields = nativeSplit(detail, #"\s+"#).filter { !$0.isEmpty }
                    guard !name.isEmpty, let weeks = fields.first else { continue }
                    last += emit(name, "", fields.count > 1 ? fields.last ?? "" : "", day + 1, String(r + 1), weeks)
                }
            }
        }
        if !last.isEmpty { return last }; errors.append("chain3 #kbDiv: no valid timetable cell"); return []
    }
    static func parseKingoSuperHtml(_ source: String) -> [JwCourse] { var errors: [String] = []; return parseKingoSuperHtml(source, errors: &errors) }
}
