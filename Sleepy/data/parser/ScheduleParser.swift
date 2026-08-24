// ScheduleParser.swift — ← ScheduleParser.kt (738 行,逐函数)
// 课程表文本解析器 — 支持:
//
// 1. **WakeUp 课程表分享 JSON**(来自 WakeUp app 的导出)
//    格式: {"name":"...","startDate":"2024-09-02","courses":[{"name":"高数","teacher":"张三","position":"A101","day":1,"startNode":1,"step":2,"startWeek":1,"endWeek":16,"type":0,"color":"#FF6750A4"}, ...]}
//
// 2. **简化的纯文本格式** (一行一课,制表符或空格分隔):
//    ```
//    高等数学	张三	A101	1	1-2	1-16	0
//    大学英语	李四	B202	2	3-4	1-16	0
//    ```
//    字段: 课程名\t老师\t教室\t星期\t节次(1-2)\t周次(1-16)\t类型(0/1/2)

import Foundation

enum ScheduleParser {

    struct ParseResult {
        let tableName: String
        let startDate: String
        let courses: [CourseEntity]
    }

    /// 解析课表文本。返回 .success / .failure(错误)。 ← Result<ParseResult>
    static func parse(_ text: String, defaultTableId: Int64, defaultColor: String = "#FF6750A4") -> Result<ParseResult, Error> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .failure(ParseError("空内容")) }

        // 兼容性:导出端常在 JSON 前加 "【来自Sleepy】\n课程分享:\n\n" 前缀。
        // 如果 trimmed 不以 { 开头但包含 {,剥掉前缀再判别。
        let body: String
        if !trimmed.hasPrefix("{"), let r = trimmed.range(of: "{") {
            body = String(trimmed[r.lowerBound...])
        } else {
            body = trimmed
        }

        return Result {
            if body.contains("\"courseDetailJson\"") {
                return try parseWakeUpShareText(body, defaultTableId)
            }
            if body.hasPrefix("{") && (body.contains("\"courses\"") || body.contains("\"tableInfo\"")) {
                return try parseWakeUpJson(body, defaultTableId, defaultColor)
            }
            if body.hasPrefix("BEGIN:VCALENDAR") || body.hasPrefix("BEGIN:VEVENT") {
                return try parseIcs(body, defaultTableId, defaultColor)
            }
            // HTML: 必须以 <!DOCTYPE / <html / <table / <body / <div 开头(先 trim 掉 BOM)
            if startsWithAnyTag(trimmed, tags: ["html", "body", "table", "div", "section", "article"]) {
                return try parseHtml(trimmed, defaultTableId, defaultColor)
            }
            // CSV: 含有 CSV 表头 (课程名/名称/course/name + 教师/teacher 等),并且至少 1 个换行
            if isLikelyCsv(trimmed) {
                return try parseCsv(trimmed, defaultTableId, defaultColor)
            }
            return try parseSimpleText(trimmed, defaultTableId, defaultColor)
        }
    }

    struct ParseError: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }

    private static func startsWithAnyTag(_ s: String, tags: [String]) -> Bool {
        let t = s.lowercased()
        if t.hasPrefix("<!doctype") || t.hasPrefix("<?xml") { return true }
        return tags.contains { t.hasPrefix("<\($0)") }
    }

    /// 判断是否为 CSV:
    /// 1) 第一行包含逗号,且第二行也存在
    /// 2) 包含常见表头:课程/课程名/名称/course/name + 教师/老师/teacher
    private static func isLikelyCsv(_ s: String) -> Bool {
        if s.filter({ $0 == "\n" }).count < 1 { return false }
        guard let firstLine = s.split(separator: "\n").first.map(String.init)?.lowercased() else { return false }
        if !firstLine.contains(",") { return false }
        let hasCourse = firstLine.contains("课程") || firstLine.contains("course") || firstLine.contains("name")
        let hasTeacher = firstLine.contains("教师") || firstLine.contains("老师") || firstLine.contains("teacher")
        let hasDay = firstLine.contains("星期") || firstLine.contains("周几") || firstLine.contains("day") || firstLine.contains("周次")
        return hasCourse && hasTeacher && hasDay
    }

    // MARK: - WakeUp

    /// 解析 WakeUp 分享文本格式:
    /// ```
    /// 【来自WakeUp课程表】
    /// 课程分享:
    ///
    /// {"name":"...","startDate":"...","courseDetailJson":"<URL-encoded JSON>"}
    /// ```
    /// 或简化版:
    /// ```
    /// 课程分享:
    /// {"name":"...","startDate":"...","courses":[...]}
    /// ```
    private static func parseWakeUpShareText(_ text: String, _ defaultTableId: Int64) throws -> ParseResult {
        // 找到 JSON 部分
        guard let jsonStart = text.range(of: "{") else {
            throw ParseError("找不到 JSON")
        }
        let jsonStr = String(text[jsonStart.lowerBound...])

        guard let data = jsonStr.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ParseError("JSON 解析失败")
        }
        let name = root["name"] as? String ?? "导入的课表"
        let startDate = (root["startDate"] as? String)
            ?? ((root["tableInfo"] as? [String: Any])?["startDate"] as? String)
            ?? todayString()

        let courses: [CourseEntity]
        if let courseDetailJsonStr = root["courseDetailJson"] as? String {
            // courseDetailJson 是 URL-encoded JSON 字符串
            let decoded = courseDetailJsonStr.removingPercentEncoding ?? courseDetailJsonStr
            courses = try parseCourseJsonArray(decoded, defaultTableId)
        } else {
            guard let arr = (root["courses"] as? [[String: Any]])
                ?? ((root["tableInfo"] as? [String: Any])?["courses"] as? [[String: Any]]) else {
                throw ParseError("找不到 courses 字段")
            }
            courses = parseCourseJsonArrayRaw(arr, defaultTableId)
        }

        return ParseResult(tableName: name, startDate: startDate, courses: courses)
    }

    private static func parseWakeUpJson(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        guard let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ParseError("JSON 解析失败")
        }
        let name = root["name"] as? String ?? "导入的课表"
        let startDate = (root["startDate"] as? String) ?? todayString()
        guard let arr = root["courses"] as? [[String: Any]] else {
            throw ParseError("找不到 courses 数组")
        }

        let courses: [CourseEntity] = arr.map { obj in
            CourseEntity(
                groupId: "",
                tableId: defaultTableId,
                courseName: (obj["name"] as? String) ?? (obj["courseName"] as? String) ?? "未命名",
                teacher: obj["teacher"] as? String ?? "",
                room: (obj["position"] as? String) ?? (obj["room"] as? String) ?? "",
                note: obj["note"] as? String ?? "",
                day: intOrZero(obj["day"], 1),
                startNode: intOrZero(obj["startNode"], 1),
                step: intOrZero(obj["step"], 1),
                startWeek: intOrZero(obj["startWeek"], 1),
                endWeek: intOrZero(obj["endWeek"], 16),
                type: intOrZero(obj["type"], 0),
                color: (obj["color"] as? String) ?? defaultColor,
                id: 0
            )
        }

        return ParseResult(tableName: name, startDate: startDate, courses: courses)
    }

    private static func parseCourseJsonArray(_ jsonStr: String, _ tableId: Int64) throws -> [CourseEntity] {
        guard let data = jsonStr.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw ParseError("courseDetailJson 解析失败")
        }
        return parseCourseJsonArrayRaw(arr, tableId)
    }

    private static func parseCourseJsonArrayRaw(_ arr: [[String: Any]], _ tableId: Int64) -> [CourseEntity] {
        return arr.map { obj in
            CourseEntity(
                groupId: "",
                tableId: tableId,
                courseName: (obj["name"] as? String) ?? (obj["courseName"] as? String) ?? "未命名",
                teacher: obj["teacher"] as? String ?? "",
                room: obj["position"] as? String ?? "",
                note: "",
                day: intOrZero(obj["day"], 1),
                startNode: intOrZero(obj["startNode"], 1),
                step: intOrZero(obj["step"], 1),
                startWeek: intOrZero(obj["startWeek"], 1),
                endWeek: intOrZero(obj["endWeek"], 16),
                type: intOrZero(obj["type"], 0),
                color: (obj["color"] as? String) ?? "#FF6750A4",
                id: 0
            )
        }
    }

    // MARK: - ICS (RFC 5545)

    /// 解析 ICS 日历文件。
    /// 简化版:每个 VEVENT 视为一节课,按 RRULE 展开成单双周处理。
    private static func parseIcs(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        var courses: [CourseEntity] = []
        let events = text.components(separatedBy: "BEGIN:VEVENT").dropFirst()
        for event in events {
            let end = event.range(of: "END:VEVENT")?.lowerBound ?? event.endIndex
            let block = String(event[event.startIndex..<end])

            guard let summary = extractIcsField(block, "SUMMARY") else { continue }
            let location = extractIcsField(block, "LOCATION") ?? ""
            let description = extractIcsField(block, "DESCRIPTION") ?? ""

            guard let (startNode, step) = extractIcsTime(block) else { continue }
            guard let day = extractIcsDayOfWeek(block) else { continue }
            let (startWeek, endWeek, type) = extractIcsWeeks(block) ?? (1, 16, 0)

            let teacher = !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? description : ""
            courses.append(CourseEntity(
                groupId: "",
                tableId: defaultTableId,
                courseName: summary,
                teacher: teacher,
                room: location,
                note: "",
                day: day,
                startNode: startNode,
                step: step,
                startWeek: startWeek,
                endWeek: endWeek,
                type: type,
                color: defaultColor,
                id: 0
            ))
        }

        return ParseResult(
            tableName: "导入的 ICS 课表",
            startDate: todayString(),
            courses: courses
        )
    }

    private static func extractIcsField(_ block: String, _ name: String) -> String? {
        // ICS 字段可能折行 (下一行以空格开头) — (?m)^NAME(?:;[^:]*)?:(.*(?:\n .*)*)
        let pattern = "(?m)^\(name)(?:;[^:]*)?:(.*(?:\\n .*)*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = block as NSString
        guard let m = regex.firstMatch(in: block, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: block) else { return nil }
        return block[r]
            .replacingOccurrences(of: "\n ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 从 DTSTART/DTEND 提取节次(按 ~55min/节粗略估算;ICS 不含节次表,仅近似)
    private static func extractIcsTime(_ block: String) -> (Int, Int)? {
        guard let dtstart = extractIcsField(block, "DTSTART"),
              let dtend = extractIcsField(block, "DTEND") else { return nil }
        // 解析 HHmmss
        // ← substringAfter("T").take(6)
        let s = dtstart.components(separatedBy: "T").dropFirst().first ?? ""
        let e = dtend.components(separatedBy: "T").dropFirst().first ?? ""
        guard s.count >= 6, e.count >= 6,
              let sh = Int(s.prefix(2)), let sm = Int(s.dropFirst(2).prefix(2)),
              let eh = Int(e.prefix(2)), let em = Int(e.dropFirst(2).prefix(2)) else { return nil }
        let startMin = sh * 60 + sm
        let endMin = eh * 60 + em
        let duration = endMin - startMin
        // 8:00 = 第 1 节,每节约 55 分钟(含课间)近似映射
        let startNode = (startMin - 480) / 55 + 1
        let step = max(duration / 55, 1)
        return (max(startNode, 1), step)
    }

    /// 从 DTSTART 或 BYDAY 提取星期几。优先从 DTSTART 推算(最可靠)
    private static func extractIcsDayOfWeek(_ block: String) -> Int? {
        // 1) 优先从 DTSTART 的日期推算星期几
        if let dtstart = extractIcsField(block, "DTSTART") {
            let dateStr = String((dtstart.components(separatedBy: "T").first ?? "").prefix(8))  // yyyyMMdd
            if dateStr.count == 8,
               let y = Int(dateStr.prefix(4)), let mo = Int(dateStr.dropFirst(4).prefix(2)), let d = Int(dateStr.dropFirst(6).prefix(2)) {
                var comps = DateComponents()
                comps.year = y; comps.month = mo; comps.day = d
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "UTC")!
                if let date = cal.date(from: comps) {
                    let dow = cal.component(.weekday, from: date)  // 1=Sun..7=Sat
                    let iso = dow == 1 ? 7 : dow - 1               // → 1=Mon..7=Sun
                    if (1...7).contains(iso) { return iso }
                }
            }
        }
        // 2) 退而求其次:找 RRULE.BYDAY
        guard let rrule = extractIcsField(block, "RRULE"),
              let m = rrule.range(of: "BYDAY=([A-Z]{2})", options: .regularExpression),
              let r = rrule[m].range(of: "[A-Z]{2}$", options: .regularExpression) else { return nil }
        switch String(rrule[r]) {
        case "MO": return 1
        case "TU": return 2
        case "WE": return 3
        case "TH": return 4
        case "FR": return 5
        case "SA": return 6
        case "SU": return 7
        default: return nil
        }
    }

    private static func extractIcsWeeks(_ block: String) -> (Int, Int, Int)? {
        // 仅做最简支持:使用 UNTIL/COUNT 推导范围,type 默认为每周
        return (1, 16, 0)
    }

    // MARK: - 纯文本

    /// 解析简化的纯文本格式:
    /// 一行一课,字段间用制表符或全角逗号分隔。
    private static func parseSimpleText(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        var courses: [CourseEntity] = []
        let lines = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasPrefix("#") }

        for line in lines {
            // 支持 tab / 多空格 / 全角逗号 — ← split(Regex("\\s+|，"))
            let parts = splitByWhitespaceOrFullwidthComma(line.trimmingCharacters(in: .whitespacesAndNewlines))
            if parts.count < 6 { continue }

            let name = parts[0]
            let teacher = parts[1]
            let room = parts[2]
            guard let day = Int(parts[3]) else { continue }
            // 节次列是 start-end 格式 (e.g. "1-2"), 转为 (startNode, step=end-start+1)
            guard let (nodeStart, nodeEnd) = parseRange(parts[4]) else { continue }
            let step = max(nodeEnd - nodeStart + 1, 1)
            guard let (startWeek, endWeek) = parseRange(parts[5]) else { continue }
            let type = parts.count > 6 ? (Int(parts[6]) ?? 0) : 0

            courses.append(CourseEntity(
                groupId: "",
                tableId: defaultTableId,
                courseName: name,
                teacher: teacher,
                room: room,
                day: day,
                startNode: nodeStart,
                step: step,
                startWeek: startWeek,
                endWeek: endWeek,
                type: type,
                color: defaultColor,
                id: 0
            ))
        }

        if courses.isEmpty { throw ParseError("未能解析任何课程") }

        return ParseResult(
            tableName: "导入的课表",
            startDate: todayString(),
            courses: courses
        )
    }

    /// \s+ 或 全角逗号 切分
    private static func splitByWhitespaceOrFullwidthComma(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in s {
            if ch == "，" || ch == "\t" || ch == " " || ch.isWhitespace && ch != "\u{00a0}" {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private static func parseRange(_ s: String) -> (Int, Int)? {
        // ← split('-', '~', '至')
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "~" || $0 == "至" }).map(String.init)
        if parts.count == 1 {
            // 单个数字: e.g. "5" → (5, 5)
            guard let n = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            return (n, n)
        }
        if parts.count != 2 { return nil }
        guard let start = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let end = Int(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return (start, end)
    }

    // MARK: - CSV

    /// 解析 CSV 格式课表。
    /// 自动识别表头,常见列名(中文/英文)都可以:
    ///   课程名 / 课程 / 名称 / course / name
    ///   教师 / 老师 / teacher
    ///   教室 / 位置 / 地点 / room / position
    ///   星期 / 周几 / day
    ///   节次(单列 1-2 格式) / 节点 / node / 节 / class
    ///   开始节数 + 结束节数(两列)  — 教务处常见导出
    ///   周次 / 周数 / weeks / week — 支持多区间 "2-5,7-9,11-14" / 离散周 "11,13,15" / 单周 "5"
    ///   类型 / type
    ///   备注 / note
    ///
    /// 多区间的周数会被展开成多条 CourseEntity(同一课程名在不同周上可以是不同教师/教室,
    /// 实际是分多行表示的,展开后保持原始行数)
    ///
    /// 支持带引号的字段("" 转义 ")
    private static func parseCsv(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        let rows = parseCsvRows(text)
        if rows.count < 2 { throw ParseError("CSV 至少需要表头 + 1 行数据") }

        let header = rows[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        // 查找列索引
        func findCol(_ keys: String...) -> Int? {
            for k in keys {
                if let idx = header.firstIndex(where: { $0.contains(k.lowercased()) }) {
                    return idx
                }
            }
            return nil
        }

        guard let nameIdx = findCol("课程名", "课程", "名称", "course", "name") else {
            throw ParseError("找不到课程名列")
        }
        let teacherIdx = findCol("教师", "老师", "teacher")
        let roomIdx = findCol("教室", "位置", "地点", "room", "position")
        guard let dayIdx = findCol("星期", "周几", "day") else {
            throw ParseError("找不到星期列")
        }
        // 节次列三种兼容模式
        let nodeStartIdx = findCol("开始节数", "开始节次", "起节", "节次起", "start node")
        let nodeEndIdx = findCol("结束节数", "结束节次", "止节", "节次止", "end node")
        let nodeIdx = (nodeStartIdx == nil && nodeEndIdx == nil)
            ? findCol("节次", "节点", "上课节次", "node", "节", "class")
            : nil
        guard let weekIdx = findCol("周次", "周数", "weeks", "week") else {
            throw ParseError("找不到周次列")
        }
        let typeIdx = findCol("类型", "type", "周类型")
        let noteIdx = findCol("备注", "note", "remark")

        if nodeStartIdx == nil && nodeEndIdx == nil && nodeIdx == nil {
            throw ParseError("找不到节次列(需要 '节次' 或 '开始节数'+'结束节数')")
        }

        var courses: [CourseEntity] = []
        for i in 1..<rows.count {
            let row = rows[i]
            if row.isEmpty || row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }

            func cell(_ idx: Int?) -> String {
                guard let idx = idx, idx < row.count else { return "" }
                return row[idx].trimmingCharacters(in: .whitespaces)
            }

            let name = cell(nameIdx)
            if name.isEmpty { continue }  // ← isBlank

            guard let day = parseDay(cell(dayIdx)) else { continue }

            // 解析节次 (start, end)
            let nodePair: (Int, Int)?
            if let ns = nodeStartIdx, let ne = nodeEndIdx {
                guard let s = Int(cell(ns)), let e = Int(cell(ne)) else { continue }
                nodePair = (s, e)
            } else {
                guard let p = parseRange(cell(nodeIdx)) else { continue }
                nodePair = p
            }
            let (nodeStart, nodeEnd) = nodePair!
            let step = max(nodeEnd - nodeStart + 1, 1)

            // 解析周次——支持多区间 "2-5,7-9,11-14" / 离散 "11,13,15" / 单周 "5" / 区间 "2-16"
            let weekRanges = parseWeekRanges(cell(weekIdx))
            if weekRanges.isEmpty { continue }

            let teacher = cell(teacherIdx)
            let room = cell(roomIdx)
            let note = cell(noteIdx)
            let type = parseType(cell(typeIdx))

            // 每个区间展开为一条 CourseEntity
            for (startWeek, endWeek) in weekRanges {
                courses.append(CourseEntity(
                    groupId: "",
                    tableId: defaultTableId,
                    courseName: name,
                    teacher: teacher,
                    room: room,
                    note: note,
                    day: day,
                    startNode: nodeStart,
                    step: step,
                    startWeek: startWeek,
                    endWeek: endWeek,
                    type: type,
                    color: defaultColor,
                    id: 0
                ))
            }
        }

        if courses.isEmpty { throw ParseError("未能解析任何课程") }

        return ParseResult(
            tableName: "导入的 CSV 课表",
            startDate: todayString(),
            courses: courses
        )
    }

    /// 解析周数字段,支持:
    ///   "5"              → [(5, 5)]
    ///   "2-16"           → [(2, 16)]
    ///   "2-5,7-9,11-14"  → [(2, 5), (7, 9), (11, 14)]
    ///   "11,13,15,17"    → [(11, 11), (13, 13), (15, 15), (17, 17)]
    ///   "2-5,11"         → [(2, 5), (11, 11)]
    private static func parseWeekRanges(_ s: String) -> [(Int, Int)] {
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var result: [(Int, Int)] = []
        // ← split(',', '，', ';', '；')
        for part in s.split(whereSeparator: { ",，;；".contains($0) }) {
            let t = String(part).trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            guard let pair = parseRange(t) else { continue }
            result.append(pair)
        }
        return result
    }

    /// 解析 CSV 文本为二维字符串数组,支持引号转义
    private static func parseCsvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var cur: [String] = []
        var sb = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        let n = chars.count
        while i < n {
            let c = chars[i]
            if inQuotes {
                if c == "\"" && i + 1 < n && chars[i + 1] == "\"" {
                    sb.append("\""); i += 2; continue
                }
                if c == "\"" { inQuotes = false; i += 1; continue }
                sb.append(c); i += 1
            } else {
                switch c {
                case "\"":
                    inQuotes = true; i += 1
                case ",":
                    cur.append(sb); sb = ""; i += 1
                case "\n":
                    cur.append(sb); sb = ""; rows.append(cur); cur = []; i += 1
                case "\r":
                    i += 1; continue
                default:
                    sb.append(c); i += 1
                }
            }
        }
        if !sb.isEmpty || !cur.isEmpty {
            cur.append(sb)
            rows.append(cur)
        }
        return rows
    }

    /// 解析 "星期" 列:支持 "周一" "1" "Monday" "mon"
    private static func parseDay(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return nil }
        // 纯数字
        if let v = Int(t), (1...7).contains(v) { return v }
        // 包含 "周"
        if t.contains("周") {
            let map = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7]
            for (k, v) in map where t.contains(k) { return v }
        }
        // 英文
        let enMap = ["mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7]
        for (k, v) in enMap where t.hasPrefix(k) { return v }
        return nil
    }

    /// 解析 "类型" 列:0=每周 1=单周 2=双周
    private static func parseType(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return 0 }
        if t.contains("单") || t == "1" || t == "odd" { return 1 }
        if t.contains("双") || t == "2" || t == "even" { return 2 }
        return 0
    }

    /// 解析 "节次" 列:支持 "1-2" "第1-2节" "1,2" "1 1"
    private static func parseRangeOrNode(_ s: String) -> (Int, Int)? {
        let t = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "节", with: "")
            .replacingOccurrences(of: "第", with: "")
        // 优先 "1-2" / "1~2" / "1至2"
        if let r = parseRange(t) { return r }
        // 尝试逗号/空格分隔的列表
        let nums = t.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Int($0) }.sorted()
        if !nums.isEmpty {
            let start = nums.first!
            let end = nums.last!
            return (start, end - start + 1)
        }
        return nil
    }

    // MARK: - HTML

    /// 解析 HTML 课表。
    /// 处理两种常见格式:
    /// 1) WakeUp HTML 导出:含课程名称+老师+教室+节次+周次的 <table>
    /// 2) 简单 HTML 表格:<table> 包含 <tr><td>...</td></tr>
    ///
    /// 策略:抽取所有 <table>,逐行解析,尝试按列匹配。
    private static func parseHtml(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        // 去掉 HTML 标签得到纯文本,再按 <table> 分段解析
        let tables = extractHtmlTables(text)
        if tables.isEmpty { throw ParseError("HTML 中未找到表格") }

        var courses: [CourseEntity] = []
        for rows in tables {
            if rows.isEmpty { continue }
            // 尝试按"表头识别"方式解析
            courses += parseHtmlTableRows(rows, defaultTableId, defaultColor)
        }

        if courses.isEmpty { throw ParseError("HTML 中未能解析出任何课程") }

        return ParseResult(
            tableName: "导入的 HTML 课表",
            startDate: todayString(),
            courses: courses
        )
    }

    /// 抽取所有 <table>...</table> 转为 [[String]] (按 <td>/<th>)
    private static func extractHtmlTables(_ html: String) -> [[[String]]] {
        var tables: [[[String]]] = []
        let tableRegex = try! NSRegularExpression(pattern: "(?is)<table[^>]*>(.*?)</table>")
        let trRegex = try! NSRegularExpression(pattern: "(?is)<tr[^>]*>(.*?)</tr>")
        let cellRegex = try! NSRegularExpression(pattern: "(?is)<(td|th)[^>]*>(.*?)</\\1>")
        let tagRegex = try! NSRegularExpression(pattern: "(?is)<[^>]+>")

        let nsHtml = html as NSString
        for tMatch in tableRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length)) {
            let tableBody = nsHtml.substring(with: tMatch.range(at: 1))
            let nsBody = tableBody as NSString
            var rows: [[String]] = []
            for trMatch in trRegex.matches(in: tableBody, range: NSRange(location: 0, length: nsBody.length)) {
                let trBody = nsBody.substring(with: trMatch.range(at: 1))
                let nsTr = trBody as NSString
                let cells: [String] = cellRegex.matches(in: trBody, range: NSRange(location: 0, length: nsTr.length)).map { m in
                    let raw = nsTr.substring(with: m.range(at: 2))
                    // 解码 HTML 实体
                    return tagRegex.stringByReplacingMatches(
                        in: raw, range: NSRange(location: 0, length: raw.count),
                        withTemplate: ""
                    )
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !cells.isEmpty { rows.append(cells) }
            }
            if !rows.isEmpty { tables.append(rows) }
        }
        return tables
    }

    /// 解析一个表格的所有行。
    /// 先尝试识别表头行(含 "课程"/"教师"/"星期"/"节次" 等关键字),
    /// 找到的话按列解析;找不到就把每行作为非结构化文本走 parseSimpleText 逻辑。
    private static func parseHtmlTableRows(_ rows: [[String]], _ defaultTableId: Int64, _ defaultColor: String) -> [CourseEntity] {
        // 找表头行
        let headerIdx = rows.firstIndex { row in
            let t = row.joined(separator: " ").lowercased()
            return t.contains("课程") || t.contains("course") || t.contains("name")
        } ?? -1
        if headerIdx < 0 {
            // 退化:按文本行处理
            let text = rows.flatMap { $0 }.joined(separator: "\n")
            if case .success(let r) = parse(text, defaultTableId: defaultTableId, defaultColor: defaultColor) {
                return r.courses
            }
            return []
        }
        let header = rows[headerIdx].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func findCol(_ keys: String...) -> Int? {
            for k in keys {
                if let idx = header.firstIndex(where: { $0.contains(k.lowercased()) }) {
                    return idx
                }
            }
            return nil
        }
        guard let nameIdx = findCol("课程", "course", "name") else { return [] }
        let teacherIdx = findCol("教师", "老师", "teacher")
        let roomIdx = findCol("教室", "位置", "room", "position", "地点")
        let dayIdx = findCol("星期", "周几", "day")
        let nodeStartIdx = findCol("开始节数", "开始节次", "起节", "节次起", "start node")
        let nodeEndIdx = findCol("结束节数", "结束节次", "止节", "节次止", "end node")
        let nodeIdx = (nodeStartIdx == nil && nodeEndIdx == nil)
            ? findCol("节次", "节点", "node", "上课节次")
            : nil
        let weekIdx = findCol("周次", "周数", "weeks", "week")
        let typeIdx = findCol("类型", "type")
        let noteIdx = findCol("备注", "note")

        if nodeStartIdx == nil && nodeEndIdx == nil && nodeIdx == nil {
            return []
        }
        guard let weekIdx = weekIdx else {
            return []
        }

        var courses: [CourseEntity] = []
        for i in (headerIdx + 1)..<rows.count {
            let row = rows[i]
            if row.isEmpty || row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            func cell(_ idx: Int?) -> String {
                guard let idx = idx, idx < row.count else { return "" }
                return row[idx].trimmingCharacters(in: .whitespaces)
            }

            let name = cell(nameIdx)
            if name.isEmpty { continue }

            guard let day = parseDay(cell(dayIdx)) else { continue }
            // 节点:开始/结束两列 或 单列 range
            let nodePair: (Int, Int)?
            if let ns = nodeStartIdx, let ne = nodeEndIdx {
                guard let s = Int(cell(ns)), let e = Int(cell(ne)) else { continue }
                nodePair = (s, e)
            } else {
                guard let p = parseRange(cell(nodeIdx)) else { continue }
                nodePair = p
            }
            let (nodeStart, nodeEnd) = nodePair!
            let step = max(nodeEnd - nodeStart + 1, 1)
            let weekRanges = parseWeekRanges(cell(weekIdx))
            if weekRanges.isEmpty { continue }
            let type = parseType(cell(typeIdx))

            let teacher = cell(teacherIdx)
            let room = cell(roomIdx)
            let note = cell(noteIdx)
            for (startWeek, endWeek) in weekRanges {
                courses.append(CourseEntity(
                    groupId: "",
                    tableId: defaultTableId,
                    courseName: name,
                    teacher: teacher,
                    room: room,
                    note: note,
                    day: day,
                    startNode: nodeStart,
                    step: step,
                    startWeek: startWeek,
                    endWeek: endWeek,
                    type: type,
                    color: defaultColor,
                    id: 0
                ))
            }
        }
        return courses
    }

    // MARK: - helpers

    /// ← JsonPrimitive.intOrZero(): 数字或数字串→Int,否则 0
    private static func intOrZero(_ v: Any?, _ def: Int) -> Int {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String, let i = Int(s) { return i }
        return def
    }

    /// LocalDate.now().toString()
    private static func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
