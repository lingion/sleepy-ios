// Declared school layouts ported from Android v1.0.64 (77b878fd).
import Foundation
import CoreFoundation
import SwiftSoup

internal enum Jw64 {
    static func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func text(_ o: [String: Any], _ k: String) -> String {
        guard let v = o[k], !(v is NSNull) else { return "" }
        return trim(v as? String ?? String(describing: v))
    }
    static func objects(_ raw: Any?) -> [[String: Any]]? { (raw as? [Any]).map { $0.compactMap { $0 as? [String: Any] } } }
    static func int(_ o: [String: Any], _ k: String) -> Int? { Int(text(o, k)) }
    static func credit(_ o: [String: Any], _ k: String) -> Float { let v = Float(text(o, k)) ?? 0; return v.isFinite && v >= 0 ? v : 0 }
    static func json(_ source: String) -> Any? { source.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) } }
    static func matches(_ pattern: String, _ text: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }
    static func full(_ pattern: String, _ text: String) -> [String]? { matches("^(?:" + pattern + ")$", text).first }
    static func select(_ element: Element?, _ css: String) -> [Element] { guard let element else { return [] }; return (try? element.select(css).array()) ?? [] }
    static func children(_ element: Element) -> [Element] { element.children().array() }
    static func cells(_ row: Element) -> [Element] { children(row).filter { ["td", "th"].contains($0.tagNameNormal()) } }
    static func text(_ e: Element?) -> String { e.map { trim((try? $0.text()) ?? "") } ?? "" }
    static func html(_ e: Element) -> String { (try? e.html()) ?? "" }
    static func attr(_ e: Element, _ name: String) -> String { (try? e.attr(name)) ?? "" }
    static func first(_ e: Element?, _ css: String) -> Element? { select(e, css).first }
    static func doc(_ source: String) -> Document? { try? SwiftSoup.parse(source) }
    static func plain(_ html: String) -> String { text(doc(html)) }
    static func lines(_ e: Element, separator: String = #"(?i)<br\s*/?>"#) -> [String] {
        guard let re = try? NSRegularExpression(pattern: separator) else { return [] }
        let raw = html(e), ns = raw as NSString
        var start = 0, out: [String] = []
        for m in re.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            out.append(plain(ns.substring(with: NSRange(location: start, length: m.range.location - start)))); start = NSMaxRange(m.range)
        }
        out.append(plain(ns.substring(from: start))); return out
    }
    static func ancestor(_ e: Element, css: String) -> Element? {
        var current: Element? = e
        while let node = current {
            if (try? node.select(css).array().contains(where: { $0 === node })) == true { return node }
            current = node.parent()
        }
        return nil
    }
    static func rows(_ table: Element) -> [Element] { select(table, "tr").filter { ancestor($0, css: "table") === table } }
    static func distinct(_ rows: [JwCourse]) -> [JwCourse] { var seen = Set<JwCourse>(); return rows.filter { seen.insert($0).inserted } }
    static func valid(_ c: JwCourse) -> Bool { !trim(c.name).isEmpty && (1...7).contains(c.day) && (1...366).contains(c.startNode) && (c.startNode...366).contains(c.endNode) && (1...366).contains(c.startWeek) && (c.startWeek...366).contains(c.endWeek) && (0...2).contains(c.type) }
    static let dayNames = ["一", "二", "三", "四", "五", "六", "日"]
    static func day(_ raw: String) -> Int { (dayNames.firstIndex(of: raw.replacingOccurrences(of: "天", with: "日").replacingOccurrences(of: "七", with: "日")) ?? -1) + 1 }
    static func prefixJson(_ source: String, assignment: String) -> Any? {
        guard let re = try? NSRegularExpression(pattern: assignment), let match = re.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return nil }
        return prefixJsonValue((source as NSString).substring(from: NSMaxRange(match.range)))
    }
    /// JSONTokener accepts JavaScript object literals and stops after the first complete value.
    static func prefixJsonValue(_ source: String) -> Any? {
        let chars = Array(source)
        var index = 0, start: Int?, stack: [Character] = [], quote: Character?, escaped = false
        var lineComment = false, blockComment = false
        while index < chars.count {
            let char = chars[index], next = index + 1 < chars.count ? chars[index + 1] : nil
            if lineComment { if char == "\n" || char == "\r" { lineComment = false }; index += 1; continue }
            if blockComment { if char == "*", next == "/" { blockComment = false; index += 2 } else { index += 1 }; continue }
            if let active = quote {
                if escaped { escaped = false } else if char == "\\" { escaped = true } else if char == active { quote = nil }
                index += 1; continue
            }
            if char == "/", next == "/" { lineComment = true; index += 2; continue }
            if char == "/", next == "*" { blockComment = true; index += 2; continue }
            if start == nil {
                if char.isWhitespace { index += 1; continue }
                guard char == "[" || char == "{" else { return nil }
                start = index
            }
            if char == "\"" || char == "'" { quote = char }
            else if char == "[" || char == "{" { stack.append(char) }
            else if char == "]" || char == "}" {
                guard let last = stack.popLast(), (last == "[" && char == "]") || (last == "{" && char == "}") else { return nil }
                if stack.isEmpty, let start, let data = String(chars[start...index]).data(using: .utf8) {
                    return try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed])
                }
            }
            index += 1
        }
        return nil
    }

}

internal class Jw1064SchoolParser: JwParser, JwParserConfidenceReporting {
    let source: String
    let kind: String
    init(_ source: String, kind: String) { self.source = source; self.kind = kind }
    var confidenceValue: Int { diagnosticResult.confidence }
    var matchedFeatureList: [String] { diagnosticResult.features }
    /// JSONObject.optString and JsonPrimitive.content preserve scalar types and whitespace.
    private func sourceText(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let text = value as? String { return text }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            if ["f", "d"].contains(String(cString: number.objCType)) { return String(number.doubleValue) }
            return number.stringValue
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    private func sourceField(_ row: [String: Any], _ key: String, trim: Bool = true) -> String {
        let text = sourceText(row[key]); return trim ? Jw64.trim(text) : text
    }
    private func stringField(_ row: [String: Any], _ key: String, trim: Bool = true) -> String {
        let text = row[key] as? String ?? ""; return trim ? Jw64.trim(text) : text
    }
    private func primitiveField(_ row: [String: Any], _ key: String) -> String {
        guard row[key] is String || row[key] is NSNumber else { return "" }
        return sourceText(row[key])
    }
    private func sourceInteger(_ value: Any?, trim: Bool = false, allowPlus: Bool = true) -> Int? {
        let input: Any?
        if let text = value as? String {
            let text = trim ? Jw64.trim(text) : text
            if !allowPlus, Jw64.full("-?[0-9]+", text) == nil { return nil }
            input = text
        } else { input = value }
        return jw1064Integer(input)
    }
    private func sourceCredit(_ row: [String: Any], _ key: String) -> Float {
        let value = Float(sourceField(row, key)) ?? 0
        return value.isFinite && value >= 0 ? value : 0
    }
    /// Android diagnostics use source anchors, including recognized empty schedules.
    private lazy var diagnosticResult: (confidence: Int, features: [String]) = {
        func report(_ matched: Bool, _ features: [String], confidence: Int = 100) -> (Int, [String]) {
            matched ? (confidence, features) : (0, [])
        }
        let document = Jw64.doc(source)
        switch kind {
        case "gdbh": return report(source.contains("\"cname\"") && source.contains("\"seq\""), ["GDBH/data/seq"])
        case "jlu_post": return report(source.contains("\"xsjxrwcx\"") && source.contains("\"PKSJDD\""), ["datas/xsjxrwcx/rows/PKSJDD"])
        case "kingosoft": return report(!Jw64.matches(#""week[1-7]"\s*:"#, source).isEmpty && source.contains("\"jcxx\""), ["kingosoft-week-array", "jcxx"])
        case "stum": return report(source.drop(while: \.isWhitespace).hasPrefix("[") && source.contains("\"week\""), ["declared-stum-week-pages"], confidence: 90)
        case "fdu": let features = fduFeatures; return report(!features.isEmpty, features)
        case "shcc": return report(!Jw64.matches(#"\bvar\s+ypData\s*="#, source).isEmpty, ["ypData"])
        case "ruc": return report(rucData != nil, ["ruc-course", "schoolHours"])
        case "hbmzu": return report(Jw64.first(document, ".list_table.tac") != nil, ["list_table/tac"])
        case "hust": return report(Jw64.first(document, ".main-page-block") != nil, ["main-page-block/search-details-body"])
        case "sdu": return report(Jw64.first(document, "#ysjddDataTableId") != nil, ["ysjddDataTableId"])
        case "nua": return report(!Jw64.select(document, "table").isEmpty, ["declared-nua-last-table"], confidence: 80)
        case "gdei": return report(Jw64.first(document, "tbody") != nil, ["declared-gdei-tbody"], confidence: 80)
        case "gliet": return report(Jw64.select(document, "table[role=presentation]").contains { Jw64.text($0).contains("第1、2节") }, ["GLIET/presentation-grid"])
        case "nyist": return report(Jw64.first(document, ".course-content .course-item-list") != nil, ["NYIST/course-content"])
        case "jxau": return report(Jw64.first(document, "#KebiaoTable1") != nil, ["JXAU/KebiaoTable1"])
        case "seig": return report(Jw64.select(document, "table").contains { table in ["星期一", "星期二", "星期三"].allSatisfy { Jw64.text(table).contains($0) } }, ["declared-seig-grid"])
        case "ztvtit": return report(!Jw64.select(document, "table.scheduleTable").isEmpty, ["scheduleTable", "week-lesson"])
        case "zptc": return report(Jw64.select(document, "#kb").contains { !Jw64.select($0, ".pbtd").isEmpty }, ["ZPTC/kb-pbtd-header"])
        case "cdut": return report(Jw64.first(document, ".tab1") != nil, ["CDUT/weekly-tab1"])
        case "ctgu": return report(Jw64.first(document, "#ctl00_MainContentPlaceHolder_GridScore") != nil, ["CTGU/GridScore"])
        case "dhu":
            let table = Jw64.first(document, "table")
            let periods = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十"]
            let matched = table.map { Jw64.rows($0).contains { row in
                guard let first = Jw64.children(row).first else { return false }
                let text = Jw64.text(first)
                return periods.contains(Jw64.trim(text.hasSuffix("节") ? String(text.dropLast()) : text))
            } } ?? false
            return report(matched, ["DHU/chinese-period-grid"], confidence: 80)
        case "gzhuyjs": return report(Jw64.first(document, "table.tab_0") != nil, ["GZHU-post/tab_0"])
        // These five Android parsers inherit the base diagnostics, even with valid courses.
        case "buaa", "chaoxing_share", "sues", "login_xbellsoft", "hit": return (0, [])
        default: return (0, [])
        }
    }()
    func generateCourseList() throws -> [JwCourse] {
        let output: [JwCourse]
        switch kind {
        case "buaa": output = buaa()
        case "chaoxing_share": output = chaoxingShare()
        case "gdbh": output = gdbh()
        case "jlu_post": output = jluPost()
        case "kingosoft": output = kingosoft()
        case "stum": output = stum()
        case "sues": output = sues()
        case "login_xbellsoft": output = xbellsoft()
        case "fdu": output = fdu()
        case "shcc": output = shcc()
        case "ruc": output = ruc()
        case "hbmzu": output = hbmzu()
        case "hust": output = hust()
        case "sdu": output = sdu()
        case "nua": output = nua()
        case "gdei": output = gdei()
        case "gliet": output = gliet()
        case "nyist": output = nyist()
        case "jxau": output = jxau()
        case "seig": output = seig()
        case "ztvtit": output = ztvtit()
        case "zptc": output = zptc()
        case "hit": output = hit()
        case "cdut": output = cdut()
        case "ctgu": output = ctgu()
        case "dhu": output = dhu()
        case "gzhuyjs": output = gzhuyjs()
        default: output = []
        }
        return Jw64.distinct(output)
    }

    private func buaa() -> [JwCourse] {
        guard let root = Jw64.json(source) as? [String: Any], let rows = Jw64.objects((root["datas"] as? [String: Any])?["arrangedList"]) else { return [] }
        var out: [JwCourse] = []
        for row in rows {
            let name = sourceField(row, "courseName"), startTime = sourceField(row, "beginTime"), endTime = sourceField(row, "endTime")
            guard !name.isEmpty, let day = sourceInteger(row["dayOfWeek"], trim: true), (1...7).contains(day), let first = sourceInteger(row["beginSection"], trim: true), let last = sourceInteger(row["endSection"], trim: true), first > 0, last >= first,
                  (startTime.isEmpty && endTime.isEmpty) || JwCourse.isValidTimeRange(startTime, endTime), let details = Jw64.objects(row["cellDetail"]) else { continue }
            let title = row["titleDetail"] as? [Any] ?? [], note = title.count > 8 ? Jw64.trim(sourceText(title[8])) : ""
            for detail in details {
                let text = sourceField(detail, "text"); var segments: [(String, String, String)] = []
                if !Jw64.matches(#"^.+\[[0-9].*周(?:\([单双]\))*]"#, text).isEmpty {
                    let matches = Jw64.matches(#"([^\[\]]+)\[([^]]+)]"#, text)
                    let remainder = text.replacingOccurrences(of: #"([^\[\]]+)\[([^]]+)]"#, with: "", options: .regularExpression)
                    if Jw64.trim(remainder).isEmpty { segments = matches.map { (Jw64.trim($0[1]), "", $0[2]) } }
                } else if !Jw64.matches(#"^[0-9].*周"#, text).isEmpty, let re = try? NSRegularExpression(pattern: #"[0-9]周(?:\([单双]\))?"#), let m = re.matches(in: text, range: NSRange(text.startIndex..., in: text)).last {
                    let ns = text as NSString, end = NSMaxRange(m.range)
                    let rest = ns.substring(from: end).split(whereSeparator: \.isWhitespace).map(String.init)
                    if let teacher = rest.first { segments = [(String(teacher.split(separator: "[").first ?? ""), rest.count > 1 ? rest[1] : "", ns.substring(to: end))] }
                }
                for (teacher, room, weeks) in segments { for (from, to, parity) in schoolWeekRanges(weeks) where (from...to).contains(where: { parity == 0 || $0 % 2 == parity % 2 }) {
                    out.append(JwCourse(name: name, room: room.isEmpty ? sourceField(row, "placeName") : room, teacher: teacher, day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: parity, startTime: startTime, endTime: endTime, credit: sourceCredit(row, "credit"), note: note))
                } }
            }
        }
        return out
    }
    private func chaoxingShare() -> [JwCourse] {
        guard let rows = Jw64.objects(Jw64.json(source)) else { return [] }; var out: [JwCourse] = []
        for row in rows {
            let name = primitiveField(row, "name")
            guard !Jw64.trim(name).isEmpty, let day = sourceInteger(row["dayOfWeek"]), (1...7).contains(day), let start = sourceInteger(row["beginNumber"]), let length = sourceInteger(row["length"]), start > 0, length > 0, start <= Int(Int32.max) - length + 1 else { continue }
            let tokens = primitiveField(row, "weeks").components(separatedBy: ","), weeks = tokens.compactMap { sourceInteger($0, trim: true) }
            guard weeks.count == tokens.count, weeks.allSatisfy({ (1...366).contains($0) }) else { continue }
            for run in JwUcasParser.splitWeekRuns(weeks) { out.append(JwCourse(name: name, room: primitiveField(row, "location") + primitiveField(row, "onlineLocation"), teacher: primitiveField(row, "teacherName"), day: day, startNode: start, endNode: start + length - 1, startWeek: run.startWeek, endWeek: run.endWeek, type: run.type)) }
        }
        return mergeCourseWeeks(out)
    }
    private func gdbh() -> [JwCourse] {
        guard let rows = Jw64.objects((Jw64.json(source) as? [String: Any])?["data"]) else { return [] }
        return rows.compactMap { row in
            let name = stringField(row, "cname")
            guard !name.isEmpty, let day = sourceInteger(row["week"]), (1...7).contains(day), let pair = sourceInteger(row["seq"]), (1...6).contains(pair), let from = sourceInteger(row["startweek"]), let to = sourceInteger(row["endweek"]), (1...366).contains(from), (from...366).contains(to) else { return nil }
            return JwCourse(name: name, room: stringField(row, "croomno"), teacher: stringField(row, "name"), day: day, startNode: pair * 2 - 1, endNode: pair * 2, startWeek: from, endWeek: to, credit: sourceCredit(row, "xf"))
        }
    }
    private func jluPost() -> [JwCourse] {
        guard let datas = (Jw64.json(source) as? [String: Any])?["datas"] as? [String: Any], let rows = Jw64.objects((datas["xsjxrwcx"] as? [String: Any])?["rows"]) else { return [] }; var out: [JwCourse] = []
        for row in rows where !stringField(row, "KCMC").isEmpty {
            for text in stringField(row, "PKSJDD", trim: false).components(separatedBy: CharacterSet(charactersIn: ";；")) {
                guard let m = Jw64.full(#"\[?(.+?)\]?\s*星期([一二三四五六日七])\s*\[?([^\[\]]+)节\](.*)"#, Jw64.trim(text)) else { continue }
                for (first, last) in schoolNodeRanges(m[3]) { for (from, to, type) in schoolWeekRanges(Jw64.trim(m[1])) { out.append(JwCourse(name: stringField(row, "KCMC"), room: Jw64.trim(m[4]), teacher: stringField(row, "RKJS"), day: Jw64.day(m[2]), startNode: first, endNode: last, startWeek: from, endWeek: to, type: type)) } }
            }
        }; return out
    }
    private func kingosoft() -> [JwCourse] {
        guard let buckets = Jw64.json(source) as? [Any] else { return [] }; var out: [JwCourse] = []
        for (index, raw) in buckets.enumerated() { guard let bucket = raw as? [String: Any] else { continue }
            for day in 1...7 { for row in Jw64.objects(bucket["week\(day)"]) ?? [] {
                let name = sourceField(row, "kcmc"); guard !name.isEmpty, let m = Jw64.full(#"([0-9]+)(?:\s*-\s*([0-9]+))?"#, sourceField(row, "jcxx")), let first = sourceInteger(m[1]), let last = sourceInteger(m[2].isEmpty ? m[1] : m[2]), first > 0, last >= first else { continue }
                out.append(JwCourse(name: name, room: sourceField(row, "skdd"), teacher: sourceField(row, "rkjs"), day: day, startNode: first, endNode: last, startWeek: index + 1, endWeek: index + 1, credit: sourceCredit(row, "xf")))
            } }
        }; return mergeCourseWeeks(out)
    }
    private func stum() -> [JwCourse] {
        guard let pages = Jw64.objects(Jw64.json(source)) else { return [] }; var out: [JwCourse] = []
        let days = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
        for page in pages { guard let data = page["data"] as? [String: Any], let week = sourceInteger(data["week"]), (1...366).contains(week) else { continue }
            for row in Jw64.objects(data["data"]) ?? [] {
                let raw = sourceField(row, "name", trim: false), node = ["A":11,"B":12,"C":13][raw] ?? sourceInteger(row["name"]) ?? 0
                guard (1...366).contains(node) else { continue }
                let start = sourceField(row, "start_time", trim: false), end = sourceField(row, "end_time", trim: false), valid = JwCourse.isValidTimeRange(start, end)
                for (index, day) in days.enumerated() { guard let encoded = row[day] as? String, let items = Jw64.objects(Jw64.json(encoded)) else { continue }
                    for item in items where !stringField(item, "f2").isEmpty { out.append(JwCourse(name: stringField(item, "f2"), room: stringField(item, "f4"), teacher: stringField(item, "f3"), day: index + 1, startNode: node, endNode: node, startWeek: week, endWeek: week, startTime: valid ? start : "", endTime: valid ? end : "")) }
                }
            }
        }; return out
    }
    private func sues() -> [JwCourse] {
        guard let root = Jw64.json(source) as? [String: Any] else { return [] }
        var tables = Jw64.objects(root["studentTableVms"]) ?? []; if let one = root["studentTableVm"] as? [String: Any] { tables.append(one) }
        var out: [JwCourse] = []
        for table in tables { for row in Jw64.objects(table["activities"]) ?? [] {
            let rawWeeks = row["weekIndexes"] as? [Any] ?? [], weeks = rawWeeks.compactMap { sourceInteger($0) }
            guard !weeks.isEmpty, weeks.count == rawWeeks.count, weeks.allSatisfy({ $0 > 0 }), let day = sourceInteger(row["weekday"]), let first = sourceInteger(row["startUnit"]), let last = sourceInteger(row["endUnit"]) else { continue }
            let room = sourceField(row, "room"), start = JwSuesParser.adjustedTime(room: room, node: first, end: false, fallback: sourceField(row, "startTime", trim: false)), end = JwSuesParser.adjustedTime(room: room, node: last, end: true, fallback: sourceField(row, "endTime", trim: false)), valid = JwCourse.isValidTimeRange(start, end)
            for week in Set(weeks).sorted() { let c = JwCourse(name: sourceField(row, "courseName", trim: false), room: room, teacher: (row["teachers"] as? [Any] ?? []).compactMap { $0 as? String }.joined(separator: ","), day: day, startNode: first, endNode: last, startWeek: week, endWeek: week, startTime: valid ? start : "", endTime: valid ? end : "", credit: sourceCredit(row, "credits"), note: sourceField(row, "lessonCode", trim: false) + sourceField(row, "lessonRemark", trim: false)); if Jw64.valid(c) { out.append(c) } }
        } }; return out
    }
    private func xbellsoft() -> [JwCourse] {
        guard let rows = Jw64.objects(Jw64.json(source)) else { return [] }; var out: [JwCourse] = []
        for row in rows {
            let name = stringField(row, "kcmc", trim: false)
            guard !Jw64.trim(name).isEmpty, let day = sourceInteger(row["xqj"], trim: true, allowPlus: false), (1...7).contains(day), let node = sourceInteger(row["djj"], trim: true, allowPlus: false), (1...366).contains(node), let code = sourceInteger(row["dsz"], trim: true, allowPlus: false) else { continue }
            let parity = code == 1 ? 1 : code == 2 ? 0 : 2
            let tokens = stringField(row, "qmz", trim: false).components(separatedBy: CharacterSet(charactersIn: ";；")).filter { !Jw64.trim($0).isEmpty }
            var ranges: [(Int, Int)] = []
            for token in tokens { guard let m = Jw64.full(#"\s*([0-9]+)(?:\s*-\s*([0-9]+))?\s*"#, token), let first = Int(m[1]), let last = Int(m[2].isEmpty ? m[1] : m[2]), (1...366).contains(first), (first...366).contains(last) else { ranges = []; break }; ranges.append((first, last)) }
            for (from, to) in ranges where (from...to).contains(where: { parity == 0 || $0 % 2 == parity % 2 }) { out.append(JwCourse(name: name, room: stringField(row, "skdd", trim: false), teacher: stringField(row, "jsxm", trim: false), day: day, startNode: node, endNode: node, startWeek: from, endWeek: to, type: parity)) }
        }
        let groups = Dictionary(grouping: Jw64.distinct(out)) { c in
            JwCourse(name: c.name, room: c.room, teacher: c.teacher, day: c.day,
                     startNode: c.startNode, endNode: c.endNode, startWeek: 1, endWeek: 1,
                     type: 0, startTime: c.startTime, endTime: c.endTime, credit: c.credit, note: c.note)
        }
        return groups.values.flatMap { group -> [JwCourse] in let weeks = group.flatMap { c in (c.startWeek...c.endWeek).filter { c.type == 0 || $0 % 2 == c.type % 2 } }; return weeks.count == Set(weeks).count ? group : mergeCourseWeeks(group) }
    }
    private func fduInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !["f", "d", "B", "c"].contains(String(cString: number.objCType)),
              let result = Int(exactly: number.int64Value), (Int(Int32.min)...Int(Int32.max)).contains(result) else { return nil }
        return result
    }
    private var fduFeatures: [String] {
        if let root = Jw64.json(source) as? [String: Any] {
            if root["results"] == nil, let table = (root["studentTableVms"] as? [Any])?.first as? [String: Any], table["activities"] is [Any] { return ["fdu-undergraduate-print-data"] }
            if root["studentTableVms"] == nil, let rows = Jw64.objects(root["results"]), rows.contains(where: { row in ["KCMC", "ZCBH", "XQ", "KSJCDM"].allSatisfy(row.keys.contains) }) { return ["fdu-postgraduate-results"] }
            return []
        }
        guard !["{", "[", "\""].contains(String(Jw64.trim(source).prefix(1))) else { return [] }
        return Jw64.select(Jw64.doc(source), "table.table.table-hover").isEmpty ? [] : ["declared-fdu-list"]
    }
    private func fdu() -> [JwCourse] {
        if let root = Jw64.json(source) as? [String: Any] {
            var out: [JwCourse] = []
            func optional(_ row: [String: Any], _ key: String) -> String? { guard let value = row[key], !(value is NSNull) else { return "" }; return (value as? String).map(Jw64.trim) }
            if root["results"] == nil, let table = (root["studentTableVms"] as? [Any])?.first as? [String: Any], let rows = Jw64.objects(table["activities"]) {
                for row in rows {
                    guard let name = row["courseName"] as? String, !Jw64.trim(name).isEmpty, let day = fduInteger(row["weekday"]), (1...7).contains(day), let first = fduInteger(row["startUnit"]), let last = fduInteger(row["endUnit"]), (1...366).contains(first), (first...366).contains(last), let rawWeeks = row["weekIndexes"] as? [Any], let room = optional(row, "room") else { continue }
                    let weeks = rawWeeks.compactMap(fduInteger); guard weeks.count == rawWeeks.count, weeks.allSatisfy({ (1...366).contains($0) }) else { continue }
                    var teacher = ""; if let value = row["teachers"], !(value is NSNull) { guard let names = value as? [String] else { continue }; teacher = names.map(Jw64.trim).filter { !$0.isEmpty }.joined(separator: "/") }
                    for week in Set(weeks.map { day == 7 ? $0 - 1 : $0 }).sorted() where week >= 1 { out.append(JwCourse(name: Jw64.trim(name), room: room, teacher: teacher, day: day, startNode: first, endNode: last, startWeek: week, endWeek: week)) }
                }
            } else if root["studentTableVms"] == nil, let rows = Jw64.objects(root["results"]) {
                for row in rows {
                    guard let name = row["KCMC"] as? String, !Jw64.trim(name).isEmpty, let day = fduInteger(row["XQ"]), (1...7).contains(day), let node = fduInteger(row["KSJCDM"]), (1...366).contains(node), let bitmap = row["ZCBH"] as? String, (1...366).contains(bitmap.count), bitmap.allSatisfy({ $0 == "0" || $0 == "1" }), let teacher = optional(row, "JSXM"), let room = optional(row, "JASMC") else { continue }
                    for (index, bit) in bitmap.enumerated() where bit == "1" { out.append(JwCourse(name: Jw64.trim(name), room: room, teacher: teacher, day: day, startNode: node, endNode: node, startWeek: index + 1, endWeek: index + 1)) }
                }
            }; return out
        }
        if ["{", "[", "\""].contains(String(Jw64.trim(source).prefix(1))) { return [] }
        var out: [JwCourse] = []
        for table in Jw64.select(Jw64.doc(source), "table.table.table-hover") { var name = ""
            for row in Jw64.children(Jw64.first(table, "tbody") ?? table) where row.tagNameNormal() == "tr" {
                let cells = Jw64.cells(row).filter { $0.tagNameNormal() == "td" }
                if cells.count == 6 { name = Jw64.text(cells[1]) } else if cells.count != 4 { name = ""; continue }
                guard !name.isEmpty else { continue }; let fields = Array(cells.suffix(4))
                guard let m = Jw64.full(#"星期\s*([一二三四五六日天])\s*[：:]?\s*第\s*([0-9,，\s-]+)\s*节"#, Jw64.text(fields[1])) else { continue }
                for (first, last) in schoolNodeRanges(m[2]) { for (from, to, type) in schoolWeekRanges(Jw64.text(fields[2])) { out.append(JwCourse(name: name, room: Jw64.text(fields[0]), day: Jw64.day(m[1]), startNode: first, endNode: last, startWeek: from, endWeek: to, type: type)) } }
            }
        }; return out
    }
    private func shcc() -> [JwCourse] {
        guard let rows = Jw64.objects(Jw64.prefixJson(source, assignment: #"\bvar\s+ypData\s*="#)) else { return [] }; var out: [JwCourse] = []
        for row in rows {
            let name = stringField(row, "kcS"), teacherWeeks = stringField(row, "js").replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
            guard !name.isEmpty, let day = sourceInteger(row["xqj"]), (1...7).contains(day), let first = sourceInteger(row["djj"]), let length = sourceInteger(row["skcd"]), let last = explicitScheduleEnd(first, length), let m = Jw64.full(#"([^()]*)\((.*)\)"#, teacherWeeks) else { continue }
            for (from, to, type) in schoolWeekRanges(m[2]) { out.append(JwCourse(name: name, room: stringField(row, "jsmc"), teacher: Jw64.trim(m[1]), day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: type)) }
        }; return out
    }
    private lazy var rucData: [String: Any]? = {
        func table(_ value: Any?) -> [String: Any]? {
            guard let object = value as? [String: Any], object["schoolHours"] is [Any], object["course"] is [Any] else { return nil }
            return object
        }
        var root: [String: Any]?
        if Jw64.trim(source).hasPrefix("{") { root = table(Jw64.prefixJsonValue(source)) }
        else {
            for script in Jw64.select(Jw64.doc(source), "script") where root == nil {
                let text = Jw64.html(script), ns = Jw64.html(script) as NSString
                guard let expression = try? NSRegularExpression(pattern: #"\bvar\s+data\s*=\s*"#) else { continue }
                for match in expression.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let value = table(Jw64.prefixJsonValue(ns.substring(from: NSMaxRange(match.range)))) { root = value; break }
                }
            }
        }
        return root
    }()
    private func ruc() -> [JwCourse] {
        guard let root = rucData, let hours = root["schoolHours"] as? [Any], let rows = Jw64.objects(root["course"]) else { return [] }
        let clocks: [(String, String)?] = hours.map { value in let raw = value as? String ?? ""; let p = raw.components(separatedBy: "~").map { String(repeating: "0", count: max(0, 5 - Jw64.trim($0).count)) + Jw64.trim($0) }; return p.count == 2 && JwCourse.isValidTimeRange(p[0], p[1]) ? (p[0], p[1]) : nil }
        var out: [JwCourse] = []
        for row in rows { let name = sourceField(row, "title")
            guard !name.isEmpty, let day = sourceInteger(row["week"], trim: true), (1...7).contains(day), let first = sourceInteger(row["start"], trim: true), let length = sourceInteger(row["quittingTime"], trim: true), let last = explicitScheduleEnd(first, length) else { continue }
            let complete = last <= clocks.count && (first...last).allSatisfy { clocks[$0 - 1] != nil }
            let firstTime = complete ? clocks[first - 1]!.0 : "", lastTime = complete ? clocks[last - 1]!.1 : ""
            let valid = complete && JwCourse.isValidTimeRange(firstTime, lastTime)
            func after(_ text: String, _ marker: String) -> String {
                Jw64.trim(text.range(of: marker).map { String(text[$0.upperBound...]) } ?? text)
            }
            let room = after(sourceField(row, "place", trim: false), "地点："), teacher = after(sourceField(row, "teacher", trim: false), "教师：")
            for (from, to, type) in schoolWeekRanges(sourceField(row, "weekly", trim: false), trailingParityAppliesToAll: true) { out.append(JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: type, startTime: valid ? firstTime : "", endTime: valid ? lastTime : "")) }
        }; return out
    }
    private func hbmzu() -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), ".list_table.tac") else { return [] }; var out: [JwCourse] = []
        for (index, row) in Jw64.rows(table).enumerated() { guard let nodes = explicitSchedulePair(index + 1) else { continue }
            for (column, cell) in Jw64.cells(row).filter({ $0.tagNameNormal() == "td" }).enumerated() where column < 7 {
                for item in Jw64.select(cell, "p") { let fields = Jw64.select(item, "span"); guard fields.count >= 4, !Jw64.text(fields[0]).isEmpty else { continue }
                    for (from, to, type) in schoolWeekRanges(Jw64.text(fields[1])) { out.append(JwCourse(name: Jw64.text(fields[0]), room: Jw64.text(fields[2]), teacher: Jw64.text(fields[3]), day: column + 1, startNode: nodes.lowerBound, endNode: nodes.upperBound, startWeek: from, endWeek: to, type: type)) }
                }
            }
        }; return out
    }
    private func hust() -> [JwCourse] {
        guard let root = Jw64.first(Jw64.doc(source), ".main-page-block") else { return [] }; var out: [JwCourse] = []
        for block in Jw64.children(root) { let paragraphs = Jw64.select(block, "p"); guard paragraphs.count >= 3, !Jw64.text(paragraphs[0]).isEmpty else { continue }
            let name = Jw64.text(paragraphs[0]), note = "开课对象：" + Jw64.text(paragraphs[2])
            for body in Jw64.select(block, ".search-details-body") { for detail in Jw64.children(body) { let boxes = Jw64.select(detail, ".text-box"); guard boxes.count >= 3 else { continue }
                func field(_ i: Int, _ label: String) -> String? { let text = Jw64.text(boxes[i]).replacingOccurrences(of: "：", with: ":"); return text.hasPrefix(label + ":") ? Jw64.trim(String(text.dropFirst(label.count + 1))) : nil }
                guard let time = field(0, "时间"), let teacher = field(1, "教师"), let room = field(2, "教室") else { continue }
                let p = time.split(whereSeparator: \.isWhitespace).map(String.init); guard p.count == 3, p[2].hasSuffix("节"), p[1].hasPrefix("星期"), (1...7).contains(Jw64.day(String(p[1].dropFirst(2)))) else { continue }
                for (first, last) in schoolNodeRanges(String(p[2].dropLast())) { for (from, to, type) in schoolWeekRanges(p[0]) { out.append(JwCourse(name: name, room: room, teacher: teacher, day: Jw64.day(String(p[1].dropFirst(2))), startNode: first, endNode: last, startWeek: from, endWeek: to, type: type, note: note)) } }
            } }
        }; return out
    }
    private func sdu() -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "#ysjddDataTableId") else { return [] }; var out: [JwCourse] = []
        for row in Jw64.rows(table).dropFirst() { let cells = Jw64.cells(row).filter { $0.tagNameNormal() == "td" }; guard cells.count >= 12, !Jw64.text(cells[2]).isEmpty, let day = Int(Jw64.text(cells[9])), (1...7).contains(day), let node = Int(Jw64.text(cells[10])), (1...366).contains(node) else { continue }
            for (from, to, type) in schoolWeekRanges(Jw64.text(cells[8])) { out.append(JwCourse(name: Jw64.text(cells[2]), room: Jw64.text(cells.last), teacher: Jw64.text(cells[7]), day: day, startNode: node, endNode: node, startWeek: from, endWeek: to, type: type)) }
        }; return out
    }
    private func nua() -> [JwCourse] {
        guard let table = Jw64.select(Jw64.doc(source), "table").last else { return [] }; var out: [JwCourse] = []
        for row in Jw64.rows(table).dropFirst() { let cells = Jw64.cells(row).filter { $0.tagNameNormal() == "td" }; guard cells.count >= 5, !Jw64.text(cells[0]).isEmpty else { continue }
            let parts = Jw64.text(cells[3]).split(whereSeparator: \.isWhitespace).map(String.init); guard parts.count >= 2 else { continue }
            for part in parts.dropFirst() { guard let m = Jw64.full(#"周([一二三四五六日天])(.+)"#, part) else { continue }
                let tokens = m[2].components(separatedBy: CharacterSet(charactersIn: ",，")), values = tokens.compactMap { token -> Int? in if token == "中午" { return 5 }; guard let n = Int(token), (1...29).contains(n) else { return nil }; return n >= 5 ? n + 1 : n }
                guard values.count == tokens.count else { continue }
                for (first, last) in schoolNodeRanges(values.map(String.init).joined(separator: ",")) { for (from, to, type) in schoolWeekRanges(parts[0]) { out.append(JwCourse(name: Jw64.text(cells[0]), room: Jw64.text(cells[4]), teacher: Jw64.text(cells[1]), day: Jw64.day(m[1]), startNode: first, endNode: last, startWeek: from, endWeek: to, type: type)) } }
            }
        }; return out
    }
    private func gdei() -> [JwCourse] {
        guard let body = Jw64.first(Jw64.doc(source), "tbody") else { return [] }; var out: [JwCourse] = []
        func periods(_ text: String, row: Bool = false) -> [(Int, Int)] { guard let m = Jw64.full(row ? #"第(.+?)节(?:[（(][^()（）]*[）)])?"# : #"第(.+?)节"#, Jw64.trim(text)) else { return [] }; return schoolNodeRanges(m[1]) }
        for row in Jw64.children(body) where row.tagNameNormal() == "tr" { let cells = Jw64.cells(row).filter { $0.tagNameNormal() == "td" }; guard cells.count >= 2 else { continue }; let defaults = periods(Jw64.text(cells[0]), row: true)
            for (day, cell) in cells.enumerated() where (1...7).contains(day) { for course in Jw64.children(cell) { let fields = Jw64.children(course); guard fields.count >= 5, !Jw64.text(fields[0]).isEmpty else { continue }; let time = Jw64.select(fields[1], "span"); guard !time.isEmpty else { continue }
                let nodes = time.count > 1 ? periods(Jw64.text(time[1])) : defaults, weekText = Jw64.text(time[0]).replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "；", with: ","), room = Jw64.trim(Jw64.text(fields[3]).replacingOccurrences(of: #"\([^()]*\)$"#, with: "", options: .regularExpression))
                for (first, last) in nodes { for (from, to, type) in schoolWeekRanges(weekText) { out.append(JwCourse(name: Jw64.text(fields[0]), room: room, teacher: Jw64.text(fields[4]), day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: type)) } }
            } }
        }; return out
    }
    private func gliet() -> [JwCourse] {
        let tables = Jw64.select(Jw64.doc(source), "table[role=presentation]").filter { Jw64.text($0).contains("第1、2节") }; var out: [JwCourse] = []
        for table in tables { for (index, row) in Jw64.rows(table).enumerated() { guard let pair = explicitSchedulePair(index + 1) else { continue }; let first = pair.lowerBound, last = first > 10 ? first : first + 1
            for (day, cell) in Jw64.cells(row).filter({ $0.tagNameNormal() == "td" }).enumerated() where (1...7).contains(day) {
                for block in Jw64.select(cell, "div").filter({ block in var p = block.parent(); while let node = p, node !== cell { if node.tagNameNormal() == "div" { return false }; p = node.parent() }; return true }) {
                    let lines = Jw64.lines(block), starts = lines.indices.filter { lines[$0].hasPrefix("课号:") }
                    for (position, begin) in starts.enumerated() { let end = position + 1 < starts.count ? starts[position + 1] : lines.count; let fields = Array(lines[begin..<end]); guard fields.count > 1, !fields[1].isEmpty else { continue }; let teacher = Jw64.trim(fields[0].replacingOccurrences(of: #"^课号:[0-9]+"#, with: "", options: .regularExpression))
                        for line in fields.dropFirst(2) { guard let m = Jw64.full(#"\(([^()]*)\)(.*)"#, line) else { continue }; for (from, to, parity) in schoolWeekRanges(m[1]) { out.append(JwCourse(name: fields[1], room: Jw64.trim(m[2]), teacher: teacher, day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: parity)) } }
                    }
                }
            }
        } }; return out
    }
    private func nyist() -> [JwCourse] {
        var out: [JwCourse] = []
        for group in Jw64.select(Jw64.doc(source), ".course-content") { let name = Jw64.text(Jw64.first(group, ".name")); guard !name.isEmpty else { continue }
            for item in Jw64.select(group, ".course-item-list") { let text = Jw64.text(Jw64.first(item, "div.time > p.content")); guard let m = Jw64.full(#"(.+?)\s+(周[一二三四五六日])\s+([0-9,，\-]+)节\s+([0-9]{2}:[0-9]{2})\s*[~～-]\s*([0-9]{2}:[0-9]{2})"#, text), JwCourse.isValidTimeRange(m[4], m[5]) else { continue }
                var weeks: [(Int, Int, Int)] = [], valid = true
                for token in Jw64.trim(m[1]).split(whereSeparator: \.isWhitespace) { guard let w = Jw64.full(#"第\[([0-9]+(?:-[0-9]+)?)\]周(\([单双]\))?"#, String(token)) else { valid = false; break }; let ranges = schoolWeekRanges(w[1] + w[2]); if ranges.isEmpty { valid = false }; weeks += ranges }
                guard valid else { continue }
                for (first, last) in schoolNodeRanges(m[3]) { for (from, to, type) in weeks { out.append(JwCourse(name: name, room: Jw64.text(Jw64.first(item, "div.address > p.content")), teacher: Jw64.text(Jw64.first(item, "div.teacher > p.content")), day: Jw64.day(String(m[2].dropFirst())), startNode: first, endNode: last, startWeek: from, endWeek: to, type: type, startTime: m[4], endTime: m[5])) } }
            }
        }; return mergeCourseWeeks(out)
    }
    private func jxau() -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "#KebiaoTable1") else { return [] }; let rows = Array(Jw64.rows(table).dropFirst(2).prefix(7)); var out: [JwCourse] = []
        guard !rows.contains(where: { row in Jw64.children(row).contains { cell in ["rowspan", "colspan"].contains { cell.hasAttr($0) && Int(Jw64.attr(cell, $0)) != 1 } } }) else { return [] }
        for row in rows { let label = Jw64.text(Jw64.first(row, ".left1")).replacingOccurrences(of: "星期", with: ""), day = Jw64.day(label); guard (1...7).contains(day) else { continue }; var node = 1
            for (index, cell) in Jw64.cells(row).filter({ $0.tagNameNormal() == "td" }).dropFirst().enumerated() { if index == 4 || index == 6 { continue }; if node >= 366 { break }
                for lesson in Jw64.select(cell, "dl") { let name = Jw64.text(Jw64.first(lesson, "a")), details = Jw64.select(lesson, "dd"); guard !name.isEmpty, details.count >= 2 else { continue }; let raw = Jw64.text(details[1]).replacingOccurrences(of: "(周)", with: "").replacingOccurrences(of: "（周）", with: "")
                    for (from, to, parity) in schoolWeekRanges(raw, trailingParityAppliesToAll: true) { out.append(JwCourse(name: name, room: Jw64.text(Jw64.first(lesson, "b")), teacher: Jw64.text(details[0]), day: day, startNode: node, endNode: node + 1, startWeek: from, endWeek: to, type: parity)) }
                }; node += 2
            }
        }; return mergeCourseWeeks(out)
    }
    private func seig() -> [JwCourse] {
        let tables = Jw64.select(Jw64.doc(source), "table").filter { t in ["星期一", "星期二", "星期三"].allSatisfy { Jw64.text(t).contains($0) } }; var out: [JwCourse] = []
        for table in tables {
            if Jw64.select(table, "td, th").contains(where: { c in ["rowspan", "colspan"].contains { c.hasAttr($0) && Jw64.attr(c, $0) != "1" } }) { continue }
            for (index, row) in Jw64.rows(table).dropFirst().enumerated() { guard let nodes = explicitSchedulePair(index + 1) else { continue }
                for (day, cell) in Jw64.cells(row).filter({ $0.tagNameNormal() == "td" }).enumerated() where (1...7).contains(day) { let text = Jw64.text(cell); guard let opening = text.lastIndex(of: "("), opening > text.startIndex, text.hasSuffix(")") else { continue }; let name = Jw64.trim(String(text[..<opening])), fields = text[text.index(after: opening)..<text.index(before: text.endIndex)].split(whereSeparator: \.isWhitespace).map(String.init)
                    guard !name.isEmpty, fields.count >= 4, let room = Jw64.full(#"\[(.*)]"#, fields.last!)?[1] else { continue }
                    let tokens = fields.dropFirst(2).dropLast(), weeks = tokens.compactMap { Jw64.full(#"([0-9]+)周?"#, $0).flatMap { Int($0[1]) } }; guard weeks.count == tokens.count, weeks.allSatisfy({ (1...366).contains($0) }) else { continue }
                    for run in JwUcasParser.splitWeekRuns(weeks) { out.append(JwCourse(name: name, room: room, teacher: fields[1], day: day, startNode: nodes.lowerBound, endNode: nodes.upperBound, startWeek: run.startWeek, endWeek: run.endWeek, type: run.type)) }
                }
            }
        }; return out
    }
    private func ztvtit() -> [JwCourse] {
        var out: [JwCourse] = []; let names = ["", "mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        for table in Jw64.select(Jw64.doc(source), "table.scheduleTable") { for info in Jw64.select(table, ".courseInfo") {
            guard let owner = Jw64.ancestor(info, css: "[week]"), let day = names.firstIndex(of: Jw64.attr(owner, "week")), (1...7).contains(day), let nodeEl = Jw64.first(owner, "[lesson]"), let node = Int(Jw64.attr(nodeEl, "lesson")), (1...366).contains(node) else { continue }
            let name = Jw64.select(info, "span:not([class])").map(Jw64.text).joined(separator: " "); guard !name.isEmpty else { continue }
            for (from, to, type) in schoolWeekRanges(Jw64.text(Jw64.first(info, ".WeekDetail"))) { out.append(JwCourse(name: name, room: Jw64.text(Jw64.first(info, ".place")), teacher: Jw64.text(Jw64.first(info, ".teacher")), day: day, startNode: node, endNode: node, startWeek: from, endWeek: to, type: type)) }
        } }; return out
    }
    private func zptc() -> [JwCourse] {
        var out: [JwCourse] = []; let names = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        for table in Jw64.select(Jw64.doc(source), "#kb") { guard let header = Jw64.select(table, "tr").first(where: { Jw64.ancestor($0, css: "#kb") === table }) else { continue }; let headings = Jw64.children(header)
            for block in Jw64.select(table, ".pbtd") where Jw64.ancestor(block, css: "#kb") === table && !Jw64.select(block, ".pbtd").contains(where: { $0 !== block }) {
                guard let m = Jw64.full(#"[^x]*x([0-9]+)_[^\s]+"#, Jw64.attr(block, "id")), let column = Int(m[1]), column < headings.count, headings[column].tagNameNormal() == "th", let day = names.firstIndex(of: Jw64.text(headings[column])), (1...7).contains(day) else { continue }
                let rawFields = Jw64.text(block).split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false).map { Jw64.trim(String($0)) }; guard rawFields.count == 3, !rawFields[0].isEmpty, let parity = ["每周":0,"单周":1,"双周":2][rawFields[1]] else { continue }; let details = rawFields[2]
                guard let n = Jw64.full(#"第\s*([0-9]+)\s*-\s*([0-9]+)\s*节?"#, Jw64.trim(String(details.prefix { $0 != "[" && $0 != "【" }))), let first = Int(n[1]), let last = Int(n[2]), (1...29).contains(first), last == first + 1 else { continue }
                let brackets = Jw64.matches(#"\[([^\[\]]*)]"#, details), meta = Jw64.matches(#"【([^【】]*)】"#, details); guard brackets.count > 1, meta.count == 2 else { continue }; let weeks = schoolWeekRanges(brackets[1][1]); guard !weeks.contains(where: { $0.2 != 0 && $0.2 != parity }) else { continue }
                for (from, to, _) in weeks { out.append(JwCourse(name: rawFields[0], room: Jw64.trim(meta[1][1]), teacher: Jw64.trim(meta[0][1]), day: day, startNode: first, endNode: last, startWeek: from, endWeek: to, type: parity)) }
            }
        }; return mergeCourseWeeks(out)
    }
    private func hit() -> [JwCourse] {
        let fragments = source.replacingOccurrences(of: #"(?i)</?head[^>]*>"#, with: "\u{001e}", options: .regularExpression).components(separatedBy: "\u{001e}")
        for fragment in fragments { let doc = Jw64.doc(fragment); guard let table = Jw64.first(doc, ".xfyq_con") ?? Jw64.first(doc, "#xszp") else { continue }; var out: [JwCourse] = []
            for row in Jw64.select(table, "tr") { let cells = Jw64.select(row, "td"), nodeColumn = cells.count == 8 ? 0 : cells.count == 9 ? 1 : -1; guard nodeColumn >= 0, let nodeText = Jw64.matches(#"第([0-9,，\-]+)节"#, Jw64.text(cells[nodeColumn])).first?[1] else { continue }; let rowNodes = schoolNodeRanges(nodeText)
                for (index, cell) in cells.dropFirst(nodeColumn + 1).enumerated() where index < 7 {
                    let lines = Jw64.lines(cell, separator: #"(?i)<br\s*/?>|◇"#).filter { !$0.isEmpty }, starts = lines.indices.filter { lines[$0].contains("[") && lines[$0].contains("]") && lines[$0].contains("周") }; var name = ""
                    for (position, begin) in starts.enumerated() { let preceding = begin > 0 ? lines[begin - 1] : ""; if !preceding.isEmpty && !(preceding.contains("[") && preceding.contains("]") && preceding.contains("周")) { name = preceding }; guard !name.isEmpty else { continue }
                        let next = position + 1 < starts.count ? starts[position + 1] : lines.count, end = next < lines.count && next > begin + 1 ? next - 1 : next, raw = lines[begin..<end].joined(), explicit = Jw64.matches(#"第([0-9,，\-]+)节"#, raw).first?[1], nodes = explicit.map(schoolNodeRanges) ?? rowNodes
                        for m in Jw64.matches(#"([^，\[\]]*)\[([0-9,，\-单双周()]+)](?:([单双])?周)?([^，]*)"#, raw) { var room = Jw64.trim(m[4].components(separatedBy: "第")[0]); if room.hasPrefix("[") && room.hasSuffix("]") { room = String(room.dropFirst().dropLast()) }
                            for (first, last) in nodes { for (from, to, parity) in schoolWeekRanges(m[2] + m[3]) where (from...to).contains(where: { parity == 0 || $0 % 2 == parity % 2 }) { out.append(JwCourse(name: name, room: room, teacher: Jw64.trim(m[1]), day: index + 1, startNode: first, endNode: last, startWeek: from, endWeek: to, type: parity)) } }
                        }
                    }
                }
            }
            if !out.isEmpty { return out.filter(Jw64.valid) }
        }; return []
    }
    private func cdut() -> [JwCourse] {
        let doc = Jw64.doc(source); guard let table = Jw64.first(doc, ".tab1") else { return [] }
        let rows = Jw64.select(table, "tr").filter { Jw64.ancestor($0, css: ".tab1") === table }
        func span(_ c: Element, _ attr: String) -> Int? { guard c.hasAttr(attr) else { return 1 }; let raw = Jw64.trim(Jw64.attr(c, attr)); guard Jw64.full("[0-9]+", raw) != nil, let n = Int(raw), (1...84).contains(n) else { return nil }; return n }
        guard !rows.contains(where: { Jw64.children($0).contains { span($0, "rowspan") != 1 } }) else { return [] }
        struct Meta: Equatable { let name: String; let teacher: String; let credit: Float }
        var meta: [String: Meta] = [:], conflicts = Set<String>()
        if let mt = Jw64.first(doc, ".tab2") { for cell in Jw64.select(mt, "td") where Jw64.ancestor(cell, css: ".tab2") === mt {
            guard let title = Jw64.first(cell, "b"), let header = Jw64.matches(#"\(([^()]+)\)\s*(.*?)\(ID"#, Jw64.text(title)).first, !Jw64.trim(header[2]).isEmpty else { continue }
            let credit = Float(Jw64.matches(#"学分\[([^]]*)]"#, Jw64.text(cell)).first?[1] ?? "") ?? 0, validCredit: Float = credit.isFinite && credit >= 0 ? credit : 0
            let html = Jw64.html(cell), details = html.range(of: "</b>").map { String(html[$0.upperBound...]) } ?? ""
            for detail in details.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\u{001e}", options: .regularExpression).components(separatedBy: "\u{001e}") {
                let text = Jw64.plain(detail)
                guard let match = Jw64.matches(#"-\s*([^()]+)\("#, text).first else { continue }
                let group = Jw64.trim(match[1])
                guard let first = group.first, let last = group.last else { continue }
                let code = Jw64.trim(header[1]) + String(first) + String(last), value = Meta(name: Jw64.trim(header[2]), teacher: Jw64.trim(Jw64.matches(#"师\[([^]]*)]"#, text).first?[1] ?? ""), credit: validCredit)
                if conflicts.contains(code) { continue }; if let old = meta[code], old != value { meta[code] = nil; conflicts.insert(code) } else { meta[code] = value }
            }
        } }
        var out: [JwCourse] = []
        for row in rows { let cells = Jw64.cells(row); guard let label = cells.first, label.hasClass("td1"), span(label, "colspan") == 1, let m = Jw64.full(#"(?:第\s*)?([0-9]+)\s*周?"#, Jw64.text(label)), let week = Int(m[1]), (1...366).contains(week) else { continue }; var column = 0, one: [JwCourse] = [], invalid = false
            for cell in cells.dropFirst() { guard let width = span(cell, "colspan"), width <= 84 - column else { invalid = true; break }; let start = column; column += width; let code = Jw64.trim((try? cell.ownText()) ?? ""); if code.isEmpty { continue }; guard start / 12 == (column - 1) / 12 else { invalid = true; break }; let a = start % 12, b = (column - 1) % 12; if (a...b).contains(5) { continue }; let info = meta[code]
                one.append(JwCourse(name: info?.name ?? code, room: Jw64.text(Jw64.first(cell, ".roomcss")), teacher: info?.teacher ?? "", day: start / 12 + 1, startNode: a < 5 ? a + 1 : a, endNode: b < 5 ? b + 1 : b, startWeek: week, endWeek: week, credit: info?.credit ?? 0))
            }; if !invalid { out += one }
        }; return mergeCourseWeeks(out)
    }
    private func ctgu() -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "#ctl00_MainContentPlaceHolder_GridScore"), let header = Jw64.rows(table).first else { return [] }; let rows = Jw64.rows(table)
        let labels = ["周一","周二","周三","周四","周五","周六","周日","星期一","星期二","星期三","星期四","星期五","星期六","星期日"]
        guard Jw64.children(header).contains(where: { $0.tagNameNormal() == "th" }) || Jw64.children(header).dropFirst().contains(where: { labels.contains(Jw64.text($0)) }) else { return [] }
        guard !rows.dropFirst().contains(where: { Jw64.children($0).contains { c in c.tagNameNormal() != "td" || ["rowspan","colspan"].contains { c.hasAttr($0) && Int(Jw64.trim(Jw64.attr(c,$0))) != 1 } } }) else { return [] }
        func blocks(_ e: Element) -> [Element]? { let children = Jw64.children(e); if !Jw64.select(e,"div").contains(where: { $0 !== e }) { return [e] }; guard Jw64.trim((try? e.ownText()) ?? "").isEmpty, children.allSatisfy({ $0.tagNameNormal() == "div" }) else { return nil }; var out:[Element] = []; for child in children { guard let sub = blocks(child) else { return nil }; out += sub }; return out }
        func parity(_ s: String) -> Int? { ["":0,"每周":0,"全周":0,"单":1,"单周":1,"双":2,"双周":2][s] }
        func records(_ fields: [String]) -> [[String]]? { guard fields.count >= 5 else { return nil }; var starts = [0]; if fields.count >= 10 { for index in 5...(fields.count - 5) { if fields[index].isEmpty { continue }; let week = fields[index + 2], like = (week.hasPrefix("第") && week.hasSuffix("周")) || !schoolWeekRanges(week).isEmpty || Jw64.full(#"-?\d[\d.,，、;；\-~～\s]*周?"#,week) != nil; if !like { if !fields[index + 3].isEmpty && parity(fields[index+3]) != nil { return nil }; continue }; guard index - starts.last! >= 5, !fields[index-1].isEmpty else { return nil }; starts.append(index) } }; starts.append(fields.count); return zip(starts, starts.dropFirst()).map { Array(fields[$0.0..<$0.1]) } }
        var out:[JwCourse] = []
        for (index,row) in rows.enumerated() where (1...15).contains(index) { let start = index * 2 - 1
            for (day,cell) in Jw64.children(row).filter({ $0.tagNameNormal() == "td" }).enumerated() where (1...7).contains(day) && !Jw64.text(cell).isEmpty {
                guard let pieces = blocks(cell) else { continue }; for block in pieces { let fields = Jw64.lines(block,separator:#"(?i)<br\s*/?>|&nbsp;|\u00a0"#); guard let groups = records(fields) else { continue }; for record in groups { let name = Jw64.trim(record[0].components(separatedBy:"(")[0]); guard !name.isEmpty, let type = parity(record[3]) else { continue }; let weeks = schoolWeekRanges(record[2]); guard !weeks.contains(where: { $0.2 != 0 && $0.2 != type }) else { continue }; for (from,to,_) in weeks { out.append(JwCourse(name:name,room:record[1],teacher:record.last!,day:day,startNode:start,endNode:start+1,startWeek:from,endWeek:to,type:type)) } } }
            }
        }; return mergeCourseWeeks(out)
    }
    private func dhu() -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source), "table"), let rows = legacyDhuEcjtuRows(table) else { return [] }
        let numerals = ["一","二","三","四","五","六","七","八","九","十","十一","十二","十三","十四","十五","十六","十七","十八","十九","二十"]; var out:[JwCourse] = []
        for row in rows { guard let label = row.first(where: { $0.column == 0 }) else { continue }; let raw = Jw64.text(label.element); let labelText = Jw64.trim(raw.hasSuffix("节") ? String(raw.dropLast()) : raw); guard let period = numerals.firstIndex(of:labelText) else { continue }; let first = period+1
            for cell in row where (1...7).contains(cell.column) && cell.columnSpan == 1 { guard let last = explicitScheduleEnd(first,cell.rowSpan) else { continue }; let fields = Jw64.text(cell.element).split(whereSeparator: \.isWhitespace).map(String.init)
                for index in stride(from:0,to:fields.count,by:4) { guard !fields[index].isEmpty, index+1<fields.count else { continue }; for (from,to,type) in schoolWeekRanges(fields[index+1]) { out.append(JwCourse(name:fields[index],room:index+3<fields.count ? fields[index+3]:"",teacher:index+2<fields.count ? fields[index+2]:"",day:cell.column,startNode:first,endNode:last,startWeek:from,endWeek:to,type:type)) } }
            }
        }; return mergeCourseWeeks(out)
    }
    private func gzhuyjs() -> [JwCourse] {
        guard let table = Jw64.first(Jw64.doc(source),"table.tab_0"), let body = Jw64.children(table).first(where: { $0.tagNameNormal() == "tbody" }) else { return [] }; let rows = Jw64.children(body).filter { $0.tagNameNormal() == "tr" }; var occupied:[Int:Set<Int>] = [:], out:[JwCourse] = []
        func span(_ e:Element,_ a:String)->Int? { if !e.hasAttr(a){return 1}; let raw=Jw64.trim(Jw64.attr(e,a)); guard Jw64.full("[0-9]+",raw) != nil, let n=Int(raw),(1...128).contains(n) else{return nil};return n }
        func parse(_ block:Element,_ day:Int)->[JwCourse] {let fields=Jw64.lines(block);guard fields.count>=6,!fields[0].isEmpty,let m=Jw64.full(#"(.+?周(?:[（(][单双]周?[）)])?)\s*(.+?)\s*小节"#,fields[4]) else{return []};var result:[JwCourse]=[];for(from,to,type)in schoolWeekRanges(m[1]){for(first,last)in schoolNodeRanges(Jw64.trim(m[2]).replacingOccurrences(of:"到",with:"-")){result.append(JwCourse(name:fields[0],room:fields[5],teacher:fields[3],day:day,startNode:first,endNode:last,startWeek:from,endWeek:to,type:type))}};return result}
        for(index,row)in rows.enumerated(){var column=0;for cell in Jw64.cells(row){while occupied[index,default:[]].contains(column){column+=1};guard let width=span(cell,"colspan"),let height=span(cell,"rowspan"),column<=128-width,height<=128-index else{return []};let columns=column..<(column+width);guard !columns.contains(where:{occupied[index,default:[]].contains($0)}) else{return []};if height>1{for r in (index+1)..<(index+height){occupied[r,default:[]].formUnion(columns)}}
                if (4...6).contains(index),(1...7).contains(column),width==1,cell.tagNameNormal()=="td"{let candidates=Jw64.select(cell,"div").compactMap{block->(Element,[JwCourse])? in let records=parse(block,column);return records.isEmpty ? nil:(block,records)};for(block,records)in candidates{if !candidates.contains(where:{other,_ in other !== block && Jw64.ancestorIs(other,block)}){out+=records}}};column+=width
            }};return mergeCourseWeeks(out)
    }
}

internal struct DhuEcjtuCell { let element: Element; let column: Int; let rowSpan: Int; let columnSpan: Int }
internal func legacyDhuEcjtuRows(_ table: Element) -> [[DhuEcjtuCell]]? {
    var occupied = Array(repeating:-1,count:8), output:[[DhuEcjtuCell]]=[]
    for(index,row)in Jw64.rows(table).enumerated(){var column=0,cells:[DhuEcjtuCell]=[]
        for element in Jw64.cells(row){while column<8 && occupied[column]>=index{column+=1}
            func span(_ a:String,_ limit:Int)->Int?{if !element.hasAttr(a){return 1};let raw=Jw64.trim(Jw64.attr(element,a));guard Jw64.full("[0-9]+",raw) != nil,let n=Int(raw),(1...limit).contains(n) else{return nil};return n}
            guard let width=span("colspan",8),let height=span("rowspan",366),column+width<=8,!(column..<(column+width)).contains(where:{occupied[$0]>=index}) else{return nil}
            cells.append(DhuEcjtuCell(element:element,column:column,rowSpan:height,columnSpan:width));for p in column..<(column+width){occupied[p]=index+height-1};column+=width
        };if occupied.allSatisfy({$0>=index}){output.append(cells)}
    };return output
}

extension Jw64 {
    static func ancestorIs(_ element:Element,_ target:Element)->Bool {var current=element.parent();while let node=current{if node===target{return true};current=node.parent()};return false}
}

final class JwSuesParser: Jw1064SchoolParser {
    init(_ source:String){super.init(source,kind:"sues")}
    static var periods:[(Int,String,String)] {JwSourcePeriods.rows("08:15-08:55 08:55-09:35 09:55-10:40 10:40-11:35 11:35-12:20 13:20-14:00 14:00-14:40 15:00-15:40 15:40-16:20 16:35-17:15 17:15-17:55 18:10-18:50 18:50-19:30 19:35-20:15 20:20-21:00")}
    static func adjustedTime(room:String,node:Int,end:Bool,fallback:String)->String {
        let early=Jw64.full(#"([AF][0-9]{3}|J301)多"#,room) != nil,late=Jw64.full(#"([DE][0-9]{3}|J303)(多|\(中外教室）)"#,room) != nil
        let pair:(String,String)?
        switch node{case 3:pair=late ? ("10:15","10:55"):("09:55","10:35");case 4:pair=late ? ("10:55","11:35"):early ? ("10:40","11:20"):("10:35","11:15");case 5:pair=late ? ("11:40","12:20"):("11:20","12:00");default:pair=nil}
        if let pair{return end ? pair.1:pair.0};guard let m=Jw64.full(#"([0-9]{1,2}):([0-9]{2})"#,Jw64.trim(fallback)),let h=Int(m[1]),let minute=Int(m[2]),(0...23).contains(h),(0...59).contains(minute) else{return ""};return String(format:"%02d:%02d",h,minute)
    }
}
final class JwBuaaParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"buaa")} }
final class JwCdutParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"cdut")} }
final class JwChaoxingShareParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"chaoxing_share")} }
final class JwCtguParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"ctgu")} }
final class JwDhuParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"dhu")} }
final class JwFduParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"fdu")} }
final class JwGdbhParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"gdbh")} }
final class JwGdeiParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"gdei")} }
final class JwGlietParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"gliet")} }
final class JwGzhuyjsParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"gzhuyjs")} }
final class JwHbmzuParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"hbmzu")} }
final class JwHitParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"hit")} }
final class JwHustParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"hust")} }
final class JwJluPostParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"jlu_post")} }
final class JwJxauParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"jxau")} }
final class JwKingosoftParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"kingosoft")} }
final class JwNuaParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"nua")} }
final class JwNyistParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"nyist")} }
final class JwRucParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"ruc")} }
final class JwSduParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"sdu")} }
final class JwSeigParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"seig")} }
final class JwShccParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"shcc")} }
final class JwStumParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"stum")} }
final class JwXbellsoftParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"login_xbellsoft")} }
final class JwZptcParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"zptc")} }
final class JwZtvtitParser: Jw1064SchoolParser { init(_ source:String){super.init(source,kind:"ztvtit")} }
