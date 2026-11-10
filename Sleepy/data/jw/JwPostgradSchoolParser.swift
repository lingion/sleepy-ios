import Foundation
import SwiftSoup

/// Declared postgraduate layouts from Android 1.0.64 and its fixed source fixtures.
final class JwPostgradSchoolParser: JwParser, JwParserConfidenceReporting {
    let source: String
    let protocolType: String
    init(_ source: String, protocolType: String) { self.source = source; self.protocolType = protocolType }
    private lazy var document: Document? = {
        let document = try? SwiftSoup.parse(source)
        _ = document?.outputSettings().prettyPrint(pretty: false)
        return document
    }()

    func generateCourseList() throws -> [JwCourse] {
        let courses: [JwCourse]
        switch protocolType {
        case "xjtu_post": courses = xjtu()
        case "uestc_post": courses = uestc()
        case "bfa_post": courses = bfa()
        case "gdbyxy": courses = gdbyxy()
        case "cupl_post": courses = cupl()
        case "ysu_post": courses = ysu()
        case "whu_post": courses = whu()
        case "hrbeu_post": courses = hrbeu()
        case "shtu_post": courses = shtu()
        case "ustc_post": courses = ustc()
        case "xauat_post": courses = xauat()
        case "zju_post": courses = zju()
        case "csv": courses = csv()
        case "shuwei_old": courses = shuweiOld()
        default: courses = []
        }
        var seen = Set<JwCourse>()
        return courses.filter { seen.insert($0).inserted }
    }

    var confidenceValue: Int {
        let found: Bool
        switch protocolType {
        case "xjtu_post": found = jw1064Elements(document, "#tbl td[id]").contains { jw1064Text($0).contains("课程") }
        case "uestc_post": found = jw1064Elements(document, "#tbl td").contains { jw1064Text($0).filter { $0 == "/" }.count >= 7 }
        case "bfa_post": found = !jw1064Elements(document, "#table .pages-sec-student-scheme-pages-student-timetable-query-timetable-index-tableContent td[_nk]").isEmpty
        case "gdbyxy": found = !jw1064Elements(document, "#pageRpt").isEmpty
        case "cupl_post": found = !jw1064Elements(document, "#tabCT").isEmpty
        case "ysu_post": found = !jw1064Elements(document, "#DataGrid1, #MainWork_DataGrid1").isEmpty
        case "whu_post": found = !jw1064Elements(document, ".table_con").isEmpty
        case "hrbeu_post": found = !jw1064Elements(document, "#StuCul_TimetableQry_TimeTable .WtbodyZlistS").isEmpty
        case "shtu_post": found = !jw1064Elements(document, "#div-table").isEmpty
        case "ustc_post": found = !jw1064Elements(document, "#tablexskbcx-index-table").isEmpty
        case "xauat_post": found = !jw1064Matches(#"td_[1-7]_[0-9]{2}"#, source).isEmpty && source.contains("td.innerHTML")
        case "zju_post": found = source.contains("kcbForm") && jsonArray(source) != nil
        case "csv": found = source.components(separatedBy: .newlines).first.map { $0.contains("课程名称") && $0.contains("开始节数") } ?? false
        case "shuwei_old": found = !jw1064Matches(#"var\s+activity\s*=\s*null;"#, source).isEmpty && source.contains("table0.marshalTable")
        default: found = false
        }
        return found ? 100 : 0
    }
    var matchedFeatureList: [String] { confidenceValue > 0 ? ["postgrad/\(protocolType)"] : [] }

    private func xjtu() -> [JwCourse] {
        var courses: [JwCourse] = []
        for cell in jw1064Elements(document, "#tbl td[id]") {
            let id = Array(jw1064Attribute(cell, "id"))
            guard id.count > 3, let day = Int(String(id[3])), (1...7).contains(day) else { continue }
            for block in blocks(html(cell)) {
                let fields = Array(lines(block).drop(while: { $0.isEmpty }))
                guard fields.count >= 6, fields[0].contains("课程") else { continue }
                courses += slots(afterLabel(fields[0]) + afterLabel(fields[1]), afterLabel(fields[3]), afterLabel(fields[2]), day,
                                 afterLabel(fields[4]), afterLabel(fields[5]))
            }
        }
        return courses
    }

    private func uestc() -> [JwCourse] {
        var courses: [JwCourse] = []
        for row in jw1064Elements(document, "#tbl tr").dropFirst() {
            for (day, cell) in children(row, tags: ["td"]).enumerated() where (1...7).contains(day) {
                let entries = jw1064Text(cell).components(separatedBy: "，")
                for entry in entries {
                    let fields = entry.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "/")
                    guard fields.count >= 8, !fields[1].isEmpty,
                          let nodes = jw1064Matches(#"[（(]([^()（）]+)[）)]"#, fields[6]).first?[1] else { continue }
                    courses += slots(fields[1], fields[7], fields[4], day, nodes.replacingOccurrences(of: "~", with: "-"), fields[5])
                }
            }
        }
        return courses
    }

    private func bfa() -> [JwCourse] {
        var courses: [JwCourse] = []
        for row in jw1064Elements(document, "#table .pages-sec-student-scheme-pages-student-timetable-query-timetable-index-tableContent tr") {
            let cells = children(row, tags: ["td"]).filter { $0.hasAttr("_nk") }
            for (column, cell) in cells.enumerated() {
                let day = column + 1
                let child = cell.children().array()
                guard day <= 7, !jw1064Attribute(cell, "_nk").isEmpty, child.count >= 2 else { continue }
                let fields = child[0].children().array().map { jw1064Text($0) }
                guard fields.count >= 5, let roomWeeks = jw1064Matches(#"^(.*?)\[([^]]+)]\s*$"#, fields[4]).first else { continue }
                let nodeLabel = jw1064Text(child[1])
                let numbers = jw1064Matches(#"[0-9]+"#, nodeLabel).compactMap { jw1064Integer($0[0]) }
                guard let first = numbers.first, let last = numbers.last else { continue }
                let nodeText = nodeLabel.range(of: #"^\s*[0-9]+\s*(?:[-~至到]\s*[0-9]+\s*)?(?:节)?$"#, options: .regularExpression) != nil
                    ? "\(first)-\(last)" : removeSuffix(nodeLabel, "节")
                let weekText = roomWeeks[2], weekRanges = weeks(weekText), nodeRanges = nodes(nodeText)
                var credit: Float = 0
                if weekRanges.count == 1 && nodeRanges.count == 1 {
                    credit = Float(((weekRanges[0].1 - weekRanges[0].0 + 1) * (nodeRanges[0].1 - nodeRanges[0].0 + 1)) / 16)
                }
                courses += slots(fields[1], roomWeeks[1], fields[3], day, nodeText, weekText, credit: credit, note: fields[2])
            }
        }
        return courses
    }

    private func gdbyxy() -> [JwCourse] {
        for fragment in split(source, #"(?i)</?head[^>]*>"#) {
            guard let doc = try? SwiftSoup.parse(fragment), let outer = jw1064Elements(doc, "#pageRpt").first,
                  let table = jw1064Elements(outer, "table").last else { continue }
            var courses: [JwCourse] = []
            for cell in jw1064Elements(table, "td") {
                let fields = lines(html(cell))
                for index in fields.indices {
                    guard let title = jw1064Matches(#"^\[[A-Z][0-9]+](.+)$"#, fields[index]).first,
                          let timing = jw1064Matches(#"^\[(.+)周]([一二三四五六日天])\[(.+)节]([单双]?)$"#, at(fields, index + 2)).first else { continue }
                    let roomPart = at(fields, index + 3)
                    let room = roomPart.isEmpty ? "" : roomPart.contains("_") ? roomPart.components(separatedBy: "_").prefix(2).joined(separator: "-") : roomPart + at(fields, index + 4)
                    courses += slots(title[1], room, at(fields, index + 1), chineseDay(timing[2]), timing[3], timing[1] + timing[4])
                }
            }
            if !courses.isEmpty { return courses }
        }
        return []
    }

    private func cupl() -> [JwCourse] {
        guard let table = jw1064Elements(document, "#tabCT").first, let grid = grid(table) else { return [] }
        let days = headerDays(grid)
        var courses: [JwCourse] = []
        for item in grid where item.row != 0 && item.width == 1 && item.cell.tagName() == "td" {
            let day = days[item.column] ?? item.column
            for block in split(html(item.cell), #"(?i)<b(?:\s[^>]*)?>"#) {
                let fields = lines(block), name = lines(block).first ?? ""
                for (index, line) in fields.enumerated() {
                    guard line.hasPrefix("周次：") || line.range(of: #"^第.+周$"#, options: .regularExpression) != nil else { continue }
                    let campus = at(fields, index + 1).hasPrefix("校区")
                    let room = removePrefix(at(fields, index + (campus ? 2 : 1)), "教室：")
                    let teacher = removePrefix(at(fields, index + (campus ? 3 : 2)), "教师：")
                    courses += slots(name, room, teacher, day, "\(item.row)-\(item.row + item.height - 1)", removePrefix(line, "周次："))
                }
            }
        }
        return courses
    }

    private func ysu() -> [JwCourse] {
        for fragment in split(source, #"(?i)</?head[^>]*>"#) {
            guard let doc = try? SwiftSoup.parse(fragment), let table = jw1064Elements(doc, "#DataGrid1, #MainWork_DataGrid1").first,
                  let grid = grid(table) else { continue }
            let days = headerDays(grid)
            let rows = Set(grid.map(\.row)).sorted().filter { index in
                guard let cell = grid.first(where: { $0.row == index })?.cell, let parent = cell.parent() else { return true }
                return jw1064Attribute(parent, "align").lowercased() != "center"
            }
            let nodeAtRow = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element, $0.offset + 1) })
            var courses: [JwCourse] = []
            for item in grid where item.width == 1 && item.cell.tagName() == "td" && jw1064Attribute(item.cell, "align").lowercased() != "center" {
                guard let node = nodeAtRow[item.row] else { continue }
                let day = days[item.column] ?? item.column
                for block in blocks(html(item.cell)) {
                    let fields = lines(block)
                    for (index, line) in fields.enumerated() {
                        guard let token = jw1064Matches(#"\[([^]]+)周]"#, line).first else { continue }
                        let room = jw1064Matches(#"教室[:：]([^)]*)"#, line).first?[1] ?? ""
                        let teacher = jw1064Matches(#"教师[:：]([^)]*)"#, line).first?[1] ?? ""
                        courses += slots(at(fields, index - 1), room, teacher, day, "\(node)-\(node + item.height - 1)", token[1].replacingOccurrences(of: "单双", with: ""))
                    }
                }
            }
            if !courses.isEmpty { return courses }
        }
        return []
    }

    private func whu() -> [JwCourse] {
        guard let container = jw1064Elements(document, ".table_con").first,
              let table = container.tagName() == "table" ? container : jw1064Elements(container, "table").first else { return [] }
        var courses: [JwCourse] = []
        for item in grid(table) ?? [] where item.width == 1 && item.cell.tagName() == "td" {
            for line in lines(html(item.cell)) {
                guard let match = jw1064Matches(#"^(.+?)\s+([^\s]+周)([^\s]+)节(?:\s+(.*))?$"#, line).first else { continue }
                let extras = match[4].components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                guard extras.count <= 2 else { continue }
                let room = extras.count == 2 ? extras[0].replacingOccurrences(of: "，", with: ",") : ""
                courses += slots(match[1].replacingOccurrences(of: " ", with: ""), room, extras.last ?? "", item.column - 1, match[3], match[2])
            }
        }
        return courses
    }

    private func hrbeu() -> [JwCourse] {
        guard let container = jw1064Elements(document, "#StuCul_TimetableQry_TimeTable .WtbodyZlistS").first else { return [] }
        let englishDays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        var courses: [JwCourse] = []
        for row in jw1064Elements(container, "tr") {
            for (column, cell) in children(row, tags: ["td"]).enumerated() where column != 0 {
                let day = englishDays.firstIndex(of: jw1064Attribute(cell, "field").lowercased()).map { $0 + 1 } ?? column
                let value = html(cell).replacingOccurrences(of: #"\n\s*\n"#, with: "<br><br>", options: .regularExpression)
                for block in blocks(value) {
                    var original = lines(block.replacingOccurrences(of: "\n", with: "<br>"))
                    while original.first?.isEmpty == true { original.removeFirst() }
                    while original.last?.isEmpty == true { original.removeLast() }
                    guard original.count >= 5 else { continue }
                    let fields = original.map(afterLabel)
                    let classLabel = jw1064Matches(#"[0-9]+班"#, fields[1]).first?[0]
                    let name = fields[0] + (classLabel.map { "(\($0))" } ?? "")
                    let note = original.dropFirst(5).joined(separator: ", ")
                    if fields[1].contains("一班多师") {
                        for teaching in fields[3].components(separatedBy: CharacterSet(charactersIn: ";；")) {
                            guard let teacher = jw1064Matches(#"[（(]([^()（）]*)[）)]"#, teaching).first?[1] else { continue }
                            courses += slots(name, fields[4], teacher, day, fields[2], before(before(teaching, "("), "（"), note: note)
                        }
                    } else {
                        let teacher = fields[1].replacingOccurrences(of: #"\s*[0-9]+班"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
                        courses += slots(name, fields[4], teacher, day, fields[2], fields[3], note: note)
                    }
                }
            }
        }
        return courses
    }

    private func shtu() -> [JwCourse] {
        guard let container = jw1064Elements(document, "#div-table").first,
              let table = container.tagName() == "table" ? container : jw1064Elements(container, "table").first else { return [] }
        var courses: [JwCourse] = []
        for item in grid(table) ?? [] where (1...13).contains(item.row) && (1...7).contains(item.column) && item.width == 1 && item.cell.tagName() == "td" {
            let fields = lines(html(item.cell))
            for index in 0..<(fields.count / 4) {
                let offset = index * 4, label = fields[index * 4]
                let name = jw1064Matches(#"^(.+?)(?:\s+[0-9]+班|[（(][0-9]+班[）)])$"#, label).first?[1] ?? label
                let rawWeeks = fields[offset + 3].replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
                let included = before(rawWeeks, "(除")
                var excluded = Set<Int>()
                if rawWeeks.contains("(除") {
                    guard let text = jw1064Matches(#"\(除(.+)\)$"#, rawWeeks).first?[1] else { continue }
                    let ranges = weeks(text)
                    guard !ranges.isEmpty else { continue }
                    excluded = Set(expandedWeeks(ranges))
                }
                for week in expandedWeeks(weeks(included)) where !excluded.contains(week) {
                    courses += slots(name, fields[offset + 2], fields[offset + 1], item.column,
                                     "\(item.row)-\(item.row + item.height - 1)", String(week))
                }
            }
        }
        return courses
    }

    private func ustc() -> [JwCourse] {
        let starts = ["07:50", "08:40", "09:45", "10:35", "11:25", "14:00", "14:50", "15:55", "16:45", "17:35", "19:30", "20:20", "21:10"]
        let periods = starts.compactMap { minute($0) }.map { ($0, $0 + 45) }
        var courses: [JwCourse] = []
        for row in jw1064Elements(document, "#tablexskbcx-index-table tr") {
            let fields = children(row, tags: ["td"]).map { cell in jw1064Elements(cell, "span").first.map { jw1064Text($0) } ?? jw1064Text(cell) }
            guard fields.count >= 9 else { continue }
            let weekGroups = fields[6].components(separatedBy: ";"), arrangements = fields[8].components(separatedBy: ";")
            guard weekGroups.count == arrangements.count else { continue }
            for (index, arrangement) in arrangements.enumerated() {
                guard let match = jw1064Matches(#"^(.*?):\s*([1-7])\(([^()]*)\)\s*$"#, arrangement.trimmingCharacters(in: .whitespacesAndNewlines)).first,
                      let day = Int(match[2]) else { continue }
                let time = match[3].trimmingCharacters(in: .whitespacesAndNewlines)
                let weekText = weekGroups[index].replacingOccurrences(of: #"\(([单双])[^)]*\)"#, with: "($1)", options: .regularExpression)
                guard let clock = jw1064Matches(#"^([0-9]{1,2}:[0-9]{2})[~～-]([0-9]{1,2}:[0-9]{2})$"#, time).first else {
                    courses += slots(fields[5], match[1], fields[7], day, time, weekText, note: fields[1]); continue
                }
                guard let start = minute(clock[1]), let end = minute(clock[2]), end > start,
                      let firstPeriod = periods.first, let lastPeriod = periods.last, start >= firstPeriod.0, end <= lastPeriod.1 else { continue }
                let covered = periods.indices.filter { periods[$0].0 < end && periods[$0].1 > start }
                guard let first = covered.first, let last = covered.last else { continue }
                for (from, to, parity) in weeks(weekText) {
                    courses.append(JwCourse(name: fields[5], room: match[1].trimmingCharacters(in: .whitespacesAndNewlines), teacher: fields[7], day: day,
                                            startNode: first + 1, endNode: last + 1, startWeek: from, endWeek: to, type: parity,
                                            startTime: clockText(start), endTime: clockText(end), note: fields[1]))
                }
            }
        }
        return courses
    }

    private func xauat() -> [JwCourse] {
        guard let script = jw1064Elements(document, "script").first else { return [] }
        let clean = ((try? script.data()) ?? "").components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
        let coordinates = jw1064Matches(#"td_([1-7])_([0-9]{2})"#, clean)
        let assignments = jw1064Matches(#"td\.innerHTML\s*\+=\s*("(?:\\.|[^"\\])*")"#, clean)
        guard coordinates.count == assignments.count else { return [] }
        var courses: [JwCourse] = []
        for (coordinate, assignment) in zip(coordinates, assignments) {
            guard let html = decodeJSString(assignment[1]), !html.isEmpty else { continue }
            let fields = lines(html)
            guard fields.count >= 4, fields[0].hasPrefix("课程:"), let timing = jw1064Matches(#"\(([^)]+)\)"#, fields[3]).first?[1],
                  let week = jw1064Matches(#"第([^周]+)周"#, timing).first?[1], let day = Int(coordinate[1]), let rawNode = Int(coordinate[2]) else { continue }
            let parity = timing.contains("单") ? "单" : timing.contains("双") ? "双" : ""
            let teacher = before(removePrefix(removePrefix(fields[2], "主讲教师："), "教师："), "（")
            let room = after(before(fields[3], "("), "-")
            courses += slots(removePrefix(fields[0], "课程:"), room, teacher, day, String(rawNode - 40), week + parity)
        }
        return courses
    }

    private func zju() -> [JwCourse] {
        guard let pages = jsonArray(source) else { return [] }
        var courses: [JwCourse] = []
        for page in pages {
            guard let html = page as? String, let doc = try? SwiftSoup.parse(html), let form = jw1064Elements(doc, "#kcbForm").first,
                  let parent = form.parent(), let table = jw1064Elements(parent, "table").first else { continue }
            var occupiedUntil = [Int](repeating: 0, count: 7)
            for (rowIndex, row) in jw1064Elements(table, "tr").enumerated() where rowIndex != 0 {
                var column = 0
                for cell in children(row, tags: ["td"]).filter({ ((try? $0.ownText()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                    while column < 7 && occupiedUntil[column] > rowIndex { column += 1 }
                    if column >= 7 { break }
                    let height = cell.hasAttr("rowspan") ? jw1064Integer(jw1064Attribute(cell, "rowspan")) : 1
                    guard let height, let endNode = explicitScheduleEnd(rowIndex, height) else { return courses }
                    occupiedUntil[column] = endNode + 1
                    for anchor in jw1064Elements(cell, "a") {
                        let name = jw1064Text(jw1064Elements(anchor, "strong").first)
                        let tail = blocks(self.html(anchor)).last ?? ""
                        let fields = lines(tail), teacherIndex = lines(tail).count == 4 ? 2 : 3
                        guard fields.count > teacherIndex + 1,
                              let token = jw1064Matches(#"\(([^()]*)周\)"#, after(at(fields, 1), "||")).first?[1] else { continue }
                        let weekText = token.components(separatedBy: CharacterSet(charactersIn: ",，")).map { part -> String in
                            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed == "每" { return "1-20" }
                            if trimmed.hasPrefix("前"), let number = chineseNumber(String(trimmed.dropFirst())) { return "1-\(number)" }
                            return chineseNumber(trimmed).map(String.init) ?? trimmed
                        }.joined(separator: ",")
                        courses += slots(name, fields[teacherIndex + 1], fields[teacherIndex], column + 1, "\(rowIndex)-\(endNode)", weekText)
                    }
                    column += 1
                }
            }
        }
        return courses
    }

    private func csv() -> [JwCourse] {
        let firstLine = source.components(separatedBy: .newlines).first ?? ""
        let separator: Character = firstLine.contains("课程名称;星期") ? ";" : firstLine.contains("课程名称\t星期") ? "\t" : ","
        guard let rows = csvRows(removePrefix(source, "\u{FEFF}"), separator), let header = rows.first,
              header.count >= 7, Array(header.prefix(4)) == ["课程名称", "星期", "开始节数", "结束节数"] else { return [] }
        var courses: [JwCourse] = []
        for row in rows.dropFirst() where row.count >= 7 && !row[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let day = jw1064Integer(row[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? chineseDay(row[1])
            guard (1...7).contains(day), let start = jw1064Integer(row[2].trimmingCharacters(in: .whitespacesAndNewlines)), (1...60).contains(start),
                  let end = jw1064Integer(row[3].trimmingCharacters(in: .whitespacesAndNewlines)), (start...60).contains(end) else { continue }
            for (from, to, parity) in weeks(row[6]) {
                courses.append(JwCourse(name: row[0], room: row[5], teacher: row[4], day: day, startNode: start, endNode: end, startWeek: from, endWeek: to, type: parity))
            }
        }
        return courses
    }

    private func csvRows(_ text: String, _ separator: Character) -> [[String]]? {
        var rows: [[String]] = [], fields: [String] = [], field = "", quoted = false, closed = false
        let chars = Array(text)
        var index = 0
        func finishField() { fields.append(field); field = ""; closed = false }
        func finishRow() { finishField(); rows.append(fields); fields.removeAll() }
        while index < chars.count {
            let character = chars[index]
            if quoted {
                if character == "\"" {
                    if index + 1 < chars.count && chars[index + 1] == "\"" { field.append("\""); index += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(character) }
            } else if character == "\"" {
                if !field.isEmpty || closed { return nil }; quoted = true
            } else if character == separator { finishField() }
            else if character == "\n" || character == "\r" || character == "\r\n" {
                finishRow(); if character == "\r" && index + 1 < chars.count && chars[index + 1] == "\n" { index += 1 }
            } else { if closed { return nil }; field.append(character) }
            index += 1
        }
        if quoted { return nil }
        if !field.isEmpty || !fields.isEmpty || closed { finishRow() }
        return rows
    }

    private func shuweiOld() -> [JwCourse] {
        guard let section = jw1064Matches(#"var\s+activity\s*=\s*null;([\s\S]*?)(?=table0\.marshalTable)"#, source).first?[1] else { return [] }
        let statements = jw1064Matches(#"(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[^;"'])+;"#, section)
        var declaredName = "", name = "", teacher = "", room = "", weekList: [Int] = [], courses: [JwCourse] = []
        for statement in statements {
            let text = statement[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if text.range(of: #"^var\s+courseName\s*="#, options: .regularExpression) != nil { declaredName = jsStrings(text).first ?? "" }
            else if text.range(of: #"^courseName\s*\+="#, options: .regularExpression) != nil { declaredName += jsStrings(text).first ?? "" }
            if text.range(of: #"^var\s+actTeachers\s*="#, options: .regularExpression) != nil {
                let value = removeSuffix(after(text, "=").trimmingCharacters(in: .whitespacesAndNewlines), ";")
                teacher = (jsonArray(value) ?? []).compactMap { $0 as? [String: Any] }.map { jw1064String($0, "name") }.filter { !$0.isEmpty }.joined(separator: ", ")
            }
            if text.range(of: #"new\s+TaskActivity\s*\("#, options: .regularExpression) != nil {
                let args = jsStrings(text)
                guard args.count >= 5 else { name = ""; weekList = []; continue }
                let group = args.count == 11 ? args[8] : at(args, 6)
                name = before(before(declaredName.isEmpty ? args[1] : declaredName, "("), "[")
                if declaredName.isEmpty && !group.isEmpty { name += "(\(removeSuffix(group, "组"))组)" }
                room = args[3]
                let bitmap = Array(args[4])
                weekList = bitmap.allSatisfy { $0 == "0" || $0 == "1" } && bitmap.first != "1"
                    ? bitmap.indices.filter { $0 > 0 && bitmap[$0] == "1" } : []
            }
            guard let coordinate = jw1064Matches(#"^index\s*=\s*([0-9]+)\s*\*\s*unitCount\s*\+\s*([0-9]+)\s*;$"#, text).first,
                  let zeroDay = jw1064Integer(coordinate[1]), let zeroNode = jw1064Integer(coordinate[2]) else { continue }
            for week in weekList { courses += slots(name, room, teacher, zeroDay + 1, String(zeroNode + 1), String(week)) }
            declaredName = ""
        }
        return courses
    }

    private func jsStrings(_ text: String) -> [String] {
        jw1064Matches(#""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#, text).compactMap { decodeJSString($0[0]) }
    }
    private func decodeJSString(_ text: String) -> String? {
        if text.hasPrefix("\""), let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String { return value }
        guard text.hasPrefix("'"), text.hasSuffix("'") else { return nil }
        let contents = String(text.dropFirst().dropLast()).replacingOccurrences(of: "\\'", with: "'").replacingOccurrences(of: "\"", with: "\\\"")
        guard let data = ("\"" + contents + "\"").data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? String
    }
    private func expandedWeeks(_ ranges: [(Int, Int, Int)]) -> [Int] {
        Set(ranges.flatMap { first, last, parity in Array(first...last).filter { parity == 0 || $0 % 2 == parity % 2 } }).sorted()
    }
    private func minute(_ time: String) -> Int? {
        guard let match = jw1064Matches(#"^([0-9]{1,2}):([0-9]{2})$"#, time).first, let hour = Int(match[1]), let minute = Int(match[2]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
    private func clockText(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }
    private func chineseNumber(_ text: String) -> Int? {
        if let number = jw1064Integer(text) { return number }
        let digits: [String: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if text.count == 1 { return text == "十" ? 10 : digits[text] }
        let parts = text.components(separatedBy: "十")
        guard parts.count == 2, let tens = parts[0].isEmpty ? 1 : digits[parts[0]], let ones = parts[1].isEmpty ? 0 : digits[parts[1]] else { return nil }
        return tens * 10 + ones
    }

    private struct GridCell { let cell: Element; let row: Int; let column: Int; let width: Int; let height: Int }
    private func grid(_ table: Element) -> [GridCell]? {
        let rows = jw1064Elements(table, "tr").filter { ((try? $0.parents().array()) ?? []).first(where: { $0.tagName() == "table" }) == table }
        var occupied: [Int: Set<Int>] = [:], result: [GridCell] = []
        for (rowIndex, row) in rows.enumerated() {
            var column = 0
            for cell in children(row, tags: ["td", "th"]) {
                while occupied[rowIndex, default: []].contains(column) { column += 1 }
                func span(_ key: String) -> Int? {
                    if !cell.hasAttr(key) { return 1 }
                    guard let value = jw1064Integer(jw1064Attribute(cell, key).trimmingCharacters(in: .whitespacesAndNewlines)), (1...128).contains(value) else { return nil }
                    return value
                }
                guard let width = span("colspan"), let height = span("rowspan"), column + width <= 128, rowIndex + height <= 128 else { return nil }
                let columns = Set(column..<(column + width))
                guard columns.isDisjoint(with: occupied[rowIndex, default: []]) else { return nil }
                if height > 1 { for covered in (rowIndex + 1)..<(rowIndex + height) { occupied[covered, default: []].formUnion(columns) } }
                result.append(GridCell(cell: cell, row: rowIndex, column: column, width: width, height: height))
                column += width
            }
        }
        return result
    }
    private func headerDays(_ grid: [GridCell]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for item in grid where item.cell.tagName() == "th" || item.cell.parent().map({ jw1064Attribute($0, "align").lowercased() == "center" }) == true {
            let day = chineseDay(jw1064Text(item.cell)); if day > 0 { result[item.column] = day }
        }
        return result
    }
    private func slots(_ name: String, _ room: String, _ teacher: String, _ day: Int, _ nodeText: String, _ weekText: String,
                       credit: Float = 0, note: String = "") -> [JwCourse] {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, (1...7).contains(day) else { return [] }
        return weeks(weekText).flatMap { from, to, parity in nodes(nodeText).map { start, end in
            JwCourse(name: name.trimmingCharacters(in: .whitespacesAndNewlines), room: room.trimmingCharacters(in: .whitespacesAndNewlines),
                     teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines), day: day, startNode: start, endNode: end,
                     startWeek: from, endWeek: to, type: parity, credit: credit, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        } }
    }
    private func weeks(_ text: String) -> [(Int, Int, Int)] {
        schoolWeekRanges(text.replacingOccurrences(of: "、", with: ",").replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "；", with: ",").replacingOccurrences(of: "~", with: "-").replacingOccurrences(of: "～", with: "-"), trailingParityAppliesToAll: true)
    }
    private func nodes(_ text: String) -> [(Int, Int)] {
        schoolNodeRanges(removeSuffix(removePrefix(text.replacingOccurrences(of: "、", with: ",").replacingOccurrences(of: "~", with: "-").replacingOccurrences(of: "～", with: "-").replacingOccurrences(of: "至", with: "-").replacingOccurrences(of: "到", with: "-"), "第"), "节").trimmingCharacters(in: .whitespacesAndNewlines))
    }
    private func lines(_ html: String) -> [String] { split(html, #"(?i)<br\s*/?>"#).map { (try? SwiftSoup.parseBodyFragment($0).text().trimmingCharacters(in: .whitespacesAndNewlines)) ?? "" } }
    private func blocks(_ html: String) -> [String] { split(html, #"(?i)<br\s*/?>\s*<br\s*/?>"#) }
    private func split(_ text: String, _ regex: String) -> [String] { text.replacingOccurrences(of: regex, with: "\u{0}", options: .regularExpression).components(separatedBy: "\u{0}") }
    private func html(_ element: Element) -> String { (try? element.html()) ?? "" }
    private func children(_ element: Element, tags: Set<String>) -> [Element] { element.children().array().filter { tags.contains($0.tagName()) } }
    private func at(_ fields: [String], _ index: Int) -> String { fields.indices.contains(index) ? fields[index] : "" }
    private func removePrefix(_ text: String, _ prefix: String) -> String { text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text }
    private func removeSuffix(_ text: String, _ suffix: String) -> String { text.hasSuffix(suffix) ? String(text.dropLast(suffix.count)) : text }
    private func before(_ text: String, _ delimiter: String) -> String { text.range(of: delimiter).map { String(text[..<$0.lowerBound]) } ?? text }
    private func after(_ text: String, _ delimiter: String) -> String { text.range(of: delimiter).map { String(text[$0.upperBound...]) } ?? "" }
    private func afterLabel(_ text: String) -> String { text.contains("：") ? after(text, "：").trimmingCharacters(in: .whitespacesAndNewlines) : (text.contains(":") ? after(text, ":") : text).trimmingCharacters(in: .whitespacesAndNewlines) }
    private func chineseDay(_ text: String) -> Int { ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7, "七": 7][removePrefix(removePrefix(text.trimmingCharacters(in: .whitespacesAndNewlines), "星期"), "周")] ?? 0 }
    private func jsonArray(_ text: String) -> [Any]? { guard let data = text.data(using: .utf8) else { return nil }; return (try? JSONSerialization.jsonObject(with: data)) as? [Any] }
}
