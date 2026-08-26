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
        /// ICS 事件里收割出的节次时间表 JSON; 非ICS/收割不到 → 空串(用默认)
        var timeJson: String = ""
        /// timeJson 覆盖的最大节次; 无 → 0
        var nodesPerDay: Int = 0
        /// 防呆: 输入里非空但没解析成功的行(前 40 字符), UI 拿去提示用户 "这几行没进去"
        var droppedLines: [String] = []
    }

    /// 解析课表文本。返回 .success / .failure(错误)。 ← Result<ParseResult>
    static func parse(_ text: String, defaultTableId: Int64, defaultColor: String = "#FF6750A4") -> Result<ParseResult, Error> {
        // 防呆: 先统一全角字符(AI 常输出 １－２ / ～), 再提取 AI 标识, 再分派
        let normalized = normalizeFullWidth(text)
        let trimmed = extractMarkedBody(normalized).trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - AI 输出防呆(← extractMarkedBody + normalizeFullWidth)

    /// 提取 <<<SLEEPY-BEGIN>>> 和 <<<SLEEPY-END>>> 之间的内容(纯文本导入的 AI 输出隔离)。
    /// - 容忍标识写歪: 少/多横线、大小写、不同括号、首尾空白
    /// - 只有 BEGIN: 取 BEGIN 之后全部(END 缺失容错)
    /// - 只有 END: 取 END 之前全部
    /// - 都没有: 原样返回(手工输入不带标识, 走原有路径)
    static func extractMarkedBody(_ text: String) -> String {
        func markerRegex(_ kind: String) -> NSRegularExpression? {
            try? NSRegularExpression(pattern: "[<{(]{2,4}\\s*SLEEPY\\s*[-_ ]?\\s*\(kind)\\s*[>})]{2,4}",
                                     options: [.caseInsensitive])
        }
        let ns = text as NSString
        guard let beginRe = markerRegex("begin"), let endRe = markerRegex("end") else { return text }
        let beginM = beginRe.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        let endM = endRe.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))
        let lower = String.Index(encodedOffset: 0)
        switch (beginM, endM) {
        case let (b?, e?) where e.range.location > b.range.location + b.range.length:
            let from = text.index(text.startIndex, offsetBy: b.range.location + b.range.length)
            let to = text.index(text.startIndex, offsetBy: e.range.location)
            return String(text[from..<to])
        case (let b?, _):
            let from = text.index(text.startIndex, offsetBy: b.range.location + b.range.length)
            return String(text[from...])
        case (_, let e?):
            let to = text.index(text.startIndex, offsetBy: e.range.location)
            return String(text[lower..<to])
        default:
            return text
        }
    }

    /// 全角→半角归一: 数字/字母/横线/波浪线/空格。AI 常输出 １－２ 或 1～16, 不归一就静默丢行。
    static func normalizeFullWidth(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(s.unicodeScalars.count)
        for c in s.unicodeScalars {
            switch c {
            case "０"..."９": out.append(UnicodeScalar(c.value - 0xFF10 + 0x30)!)
            case "ａ"..."ｚ": out.append(UnicodeScalar(c.value - 0xFF41 + 0x61)!)
            case "Ａ"..."Ｚ": out.append(UnicodeScalar(c.value - 0xFF21 + 0x41)!)
            case "－", "—", "―", "﹣": out.append("-")
            case "～", "~": out.append("~")
            case "　", "\u{FEFF}": out.append(" ")   // 全角空格 / BOM
            default: out.append(c)
            }
        }
        return String(out)
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

        // 节次时间表: tableInfo.time(Sleepy 导出) / timeList(WakeUp 原生) ← harvestTimeJsonFromTableInfo
        let (timeJson, nodesPerDay) = harvestTimeJsonFromTableInfo(root)
        return ParseResult(tableName: name, startDate: startDate, courses: courses,
                           timeJson: timeJson, nodesPerDay: nodesPerDay)
    }

    /// 从 WakeUp JSON / Sleepy 导出的 tableInfo 里收割节次时间表。
    /// Sleepy 导出: tableInfo.time = 我们的 timeJson 原文, 直接用。
    /// WakeUp 原生: tableInfo.timeList = [{node, startTime, endTime}...] 逐条转。
    private static func harvestTimeJsonFromTableInfo(_ root: [String: Any]) -> (String, Int) {
        guard let tableInfo = root["tableInfo"] as? [String: Any] else { return ("", 0) }
        // Sleepy 自家格式: time 字段就是 timeJson
        if let time = tableInfo["time"] as? String, !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let nodes = TimeTableUtils.parseNodes(time)
            if let last = nodes.last { return (time, last.node) }
        }
        // WakeUp 原生: timeList 数组
        guard let timeList = tableInfo["timeList"] as? [[String: Any]] else { return ("", 0) }
        var nodeTimes: [Int: (Int, Int)] = [:]   // node → (startMin, endMin)
        for el in timeList {
            guard let node = el["node"] as? Int, node >= 1,
                  let st = (el["startTime"] as? String).flatMap(parseHmLenient),
                  let et = (el["endTime"] as? String).flatMap(parseHmLenient),
                  st < et else { continue }
            nodeTimes[node] = (st, et)
        }
        guard !nodeTimes.isEmpty else { return ("", 0) }
        return (buildTimeJson(nodeTimes), nodeTimes.keys.max() ?? 0)
    }

    /// "08:00" / "8:00" / "0800" → 当日分钟数; 非法 nil
    private static func parseHmLenient(_ s: String) -> Int? {
        guard let m = try? NSRegularExpression(pattern: "(\\d{1,2}):?(\\d{2})"),
              let mm = m.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r1 = Range(mm.range(at: 1), in: s), let r2 = Range(mm.range(at: 2), in: s),
              let h = Int(s[r1]), let mi = Int(s[r2]) else { return nil }
        return (0...23).contains(h) && (0...59).contains(mi) ? h * 60 + mi : nil
    }

    /// nodeTimes(node → 分钟对) → timeJson。空 → 空串(调用方用默认)。
    private static func buildTimeJson(_ nodeTimes: [Int: (Int, Int)]) -> String {
        guard !nodeTimes.isEmpty else { return "" }
        var parts: [String] = []
        for n in nodeTimes.keys.sorted() {
            let t = nodeTimes[n]!
            parts.append("{\"node\":\(n),\"start\":\"\(hmString(t.0))\",\"end\":\"\(hmString(t.1))\"}")
        }
        return "[" + parts.joined(separator: ",") + "]"
    }

    /// 分钟数 → "HH:mm"(LocalTime.toString 等价)
    private static func hmString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
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

        // 节次时间表收割(与 parseWakeUpShareText 同一通道)
        let (timeJson, nodesPerDay) = harvestTimeJsonFromTableInfo(root)
        return ParseResult(tableName: name, startDate: startDate, courses: courses,
                           timeJson: timeJson, nodesPerDay: nodesPerDay)
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

    /// 解析 ICS 日历文件 (RFC 5545)。 ← Android 完整语义
    ///
    /// 支持两类来源:
    /// 1. WakeUp 课程表导出 — SUMMARY=课名, DESCRIPTION="第X - Y节\n教室\n教师"(字面 \n 转义),
    ///    每个实际上课时段一条 VEVENT(双周课拆成 N 条 INTERVAL=1 的短事件),
    ///    UNTIL 日期为最后一次发生的日历日(可能比该次晚 6 天,按同星期几对齐回推)。
    /// 2. Sleepy 自家导出 — DESCRIPTION="老师：X", 单双周用 INTERVAL=2 表达。
    ///
    /// 语义:
    /// - 学期锚点 = 最早 DTSTART 所在周的周一 → startDate(周数编号基准)
    /// - 周区间 = [DTSTART 周, UNTIL 对齐星期几后的最后一次发生周]
    /// - 节次优先读 DESCRIPTION "第X - Y节", 无则按 50min/节估算
    /// - 同(课名,星期,节次,教师)的多个 VEVENT 按周序列合并:
    ///   连续拼合→type=0; 全同奇偶且间距2→单/双周; 否则(散周)保持独立行
    /// - 全校作息收割: 节次 → (start,end), 跨 lunch 的多节块只锚定两端
    private static func parseIcs(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        struct Event {
            let name: String, day: Int, startNode: Int, step: Int
            let teacher: String, room: String
            let firstDate: Date, lastDate: Date, interval: Int
        }

        var events: [Event] = []
        // 全校作息收割: 节次 → (startMin, endMin)
        var nodeTimes: [Int: (Int, Int)] = [:]
        for raw in text.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            let endIdx = raw.range(of: "END:VEVENT")?.lowerBound ?? raw.endIndex
            let block = String(raw[raw.startIndex..<endIdx])

            guard let summary = extractIcsField(block, "SUMMARY") else { continue }
            let location = extractIcsField(block, "LOCATION") ?? ""
            let description = extractIcsField(block, "DESCRIPTION") ?? ""
            let descLines = description.components(separatedBy: "\\n")

            // WakeUp: DESCRIPTION="第X - Y节\n教室\n教师", LOCATION="教室 教师" / Sleepy: DESCRIPTION="老师：X"
            let teacher: String
            if descLines.count >= 3 {
                teacher = descLines[2].trimmingCharacters(in: .whitespaces)
            } else if description.hasPrefix("老师：") {
                teacher = String(description.dropFirst("老师：".count)).trimmingCharacters(in: .whitespaces)
            } else if description.hasPrefix("老师:") {
                teacher = String(description.dropFirst("老师:".count)).trimmingCharacters(in: .whitespaces)
            } else {
                teacher = ""
            }
            let room: String
            if descLines.count >= 2, !descLines[1].trimmingCharacters(in: .whitespaces).isEmpty {
                room = descLines[1].trimmingCharacters(in: .whitespaces)
            } else if !location.isEmpty && !teacher.isEmpty && location.hasSuffix(teacher) {
                room = String(location.dropLast(teacher.count)).trimmingCharacters(in: .whitespaces)
            } else {
                room = location
            }

            guard let day = extractIcsDayOfWeek(block) else { continue }
            guard let dtstart = extractIcsDate(block) else { continue }
            // 节次优先读描述 "第X - Y节", 无则按时间估算
            guard let (startNode, step) = extractIcsNode(description) ?? extractIcsTime(block) else { continue }

            // 作息收割: 有节次行 + 有起止钟点才有贡献(Sleepy 自家导出也满足)
            harvestNodeTimes(block, startNode, step, &nodeTimes)

            let rrule = extractIcsField(block, "RRULE") ?? ""
            let interval = rrule.contains("INTERVAL=2") ? 2 : 1
            // UNTIL 是最后一次发生的日历日(可能晚于该次 0-6 天) → 对齐回同星期几
            var untilDate = dtstart
            if let u = try? NSRegularExpression(pattern: "UNTIL=(\\d{8})"),
               let um = u.firstMatch(in: rrule, range: NSRange(rrule.startIndex..., in: rrule)),
               let ur = Range(um.range(at: 1), in: rrule), let ud = parseIcsDate(String(rrule[ur])) {
                untilDate = ud
            }
            let deltaDays = Calendar.isoDaysBetween(dtstart, untilDate)
            let lastOccurrence = Calendar.isoAddDays(dtstart, deltaDays - deltaDays % 7)

            events.append(Event(name: summary, day: day, startNode: startNode, step: step,
                                teacher: teacher, room: room,
                                firstDate: dtstart, lastDate: lastOccurrence, interval: interval))
        }

        if events.isEmpty {
            return ParseResult(tableName: "导入的 ICS 课表", startDate: todayString(), courses: [])
        }

        // 锚点: 最早 DTSTART 所在周的周一 → 周数编号基准
        let anchor = Calendar.isoMondayOfWeek(events.map { $0.firstDate }.min()!)

        // 按 (课名,星期,节次,教师) 聚合各周区间 — room 不进键:
        // WakeUp 会把"每周换教室的同一门课"拆成多条 VEVENT,若 room 进键会把同一时段拆成
        // 两组各自"同奇偶间距2"的散周 → 被误判成两个假单双周(实证: 24sp 管理心理学)。
        // room 变化交给散周 room-run 合并处理。
        struct SlotKey: Hashable { let name: String, day: Int, node: Int, step: Int, teacher: String }
        var groups: [SlotKey: [(Int, Int, String)]] = [:]   // (startW, endW, room)
        var groupOrder: [SlotKey] = []
        var groupInterval: [SlotKey: Int] = [:]
        func weekOf(_ d: Date) -> Int { Calendar.isoDaysBetween(anchor, d) / 7 + 1 }
        for e in events {
            let key = SlotKey(name: e.name, day: e.day, node: e.startNode, step: e.step, teacher: e.teacher)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append((weekOf(e.firstDate), weekOf(e.lastDate), e.room))
            groupInterval[key] = e.interval
        }

        var courses: [CourseEntity] = []
        func emit(_ key: SlotKey, _ startWeek: Int, _ endWeek: Int, _ type: Int, _ room: String) {
            courses.append(CourseEntity(
                groupId: "", tableId: defaultTableId,
                courseName: key.name, teacher: key.teacher, room: room, note: "",
                day: key.day, startNode: key.node, step: key.step,
                startWeek: startWeek, endWeek: endWeek, type: type,
                color: defaultColor, id: 0
            ))
        }

        for key in groupOrder {
            let chunks = groups[key]!.sorted { a, b in
                a.0 != b.0 ? a.0 < b.0 : (a.1 != b.1 ? a.1 < b.1 : a.2 < b.2)
            }
            let interval = groupInterval[key] ?? 1
            let spans = chunks.map { ($0.0, $0.1) }

            func contiguous() -> Bool {
                zip(spans, spans.dropFirst()).allSatisfy { $0.1.0 - $0.0.1 == 1 }
            }
            func allSingleSameParitySpaced2() -> Bool {
                if spans.contains(where: { $0.0 != $0.1 }) { return false }
                let starts = spans.map { $0.0 }
                if Set(starts.map { $0 % 2 }).count != 1 { return false }
                return zip(starts, starts.dropFirst()).allSatisfy { $1 - $0 == 2 }
            }

            if spans.count == 1 {
                emit(key, spans[0].0, spans[0].1, 0, chunks[0].2)
            } else if contiguous() {
                // 1) 逐周连续 → 合并为每周区间(room 取首个 chunk)
                emit(key, spans.first!.0, spans.last!.1, 0, chunks[0].2)
            } else if interval == 2 || allSingleSameParitySpaced2() {
                // 2) 全部单周且同奇偶且间距 2 → 单/双周序列(INTERVAL=2 单条事件同理)
                let startW = spans.first!.0
                emit(key, startW, spans.last!.0, startW % 2 == 1 ? 1 : 2, chunks[0].2)
            } else {
                // 3) 散周: 按教室分段合并连续段,每段一行(换教室课程按实际分段输出)
                var curRoom: String? = nil
                var curStart = 0, curEnd = 0
                for (a, b, r) in chunks {
                    if r == curRoom && a <= curEnd + 1 {
                        curEnd = max(curEnd, b)
                    } else {
                        if curRoom != nil { emit(key, curStart, curEnd, 0, curRoom!) }
                        curRoom = r; curStart = a; curEnd = b
                    }
                }
                if curRoom != nil { emit(key, curStart, curEnd, 0, curRoom!) }
            }
        }

        return ParseResult(
            tableName: "导入的 ICS 课表",
            startDate: Calendar.isoString(anchor),
            courses: courses,
            timeJson: buildTimeJson(nodeTimes),
            nodesPerDay: nodeTimes.isEmpty ? 0 : (nodeTimes.keys.max() ?? 0)
        )
    }

    /// 从单个 VEVENT 收割节次边界: 事件占 [startNode, startNode+step-1] 节,
    /// DTSTART=首节start, DTEND=末节end, 中间节次边界从相邻块推导(块内均匀)。
    /// 冲突时后写覆盖 — 同校作息一致,不同事件只是补充对方缺的节次。
    ///
    /// 跨 lunch/晚上的多节块(如 1-4 @ 08:20-12:00)不能均匀切 — 只锚定两端,
    /// 中间节次交给其他恰好落界的块(如 1-2/3-4)去补,补不上就保持 gap。
    private static func harvestNodeTimes(_ block: String, _ startNode: Int, _ step: Int,
                                         _ out: inout [Int: (Int, Int)]) {
        guard let dtstart = extractIcsField(block, "DTSTART"),
              let dtend = extractIcsField(block, "DTEND"),
              let start = parseIcsTimeOfDay(String(dtstart.components(separatedBy: "T").dropFirst().first?.prefix(6) ?? "")),
              let end = parseIcsTimeOfDay(String(dtend.components(separatedBy: "T").dropFirst().first?.prefix(6) ?? "")),
              start < end else { return }

        let endNode = startNode + step - 1
        if step <= 2 {
            for n in startNode...endNode {
                let s = n == startNode ? start : nil
                let e = n == endNode ? end : nil
                let prev = out[n]
                out[n] = (s ?? prev?.0 ?? start, e ?? prev?.1 ?? end)
            }
        } else {
            let prevFirst = out[startNode]
            let prevLast = out[endNode]
            out[startNode] = (start, prevFirst?.1 ?? end)
            out[endNode] = (prevLast?.0 ?? start, end)
        }
    }

    /// "HHmmss" 前缀 → 当日分钟数; 非法 nil
    private static func parseIcsTimeOfDay(_ s: String) -> Int? {
        guard s.count >= 4,
              let h = Int(s.prefix(2)), let m = Int(s.dropFirst(2).prefix(2)) else { return nil }
        return (0...23).contains(h) && (0...59).contains(m) ? h * 60 + m : nil
    }

    /// "yyyyMMdd" → Date; 非法 nil
    private static func parseIcsDate(_ s: String) -> Date? {
        guard s.count >= 8,
              let y = Int(s.prefix(4)), let mo = Int(s.dropFirst(4).prefix(2)), let d = Int(s.dropFirst(6).prefix(2)) else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        return DateUtils.isoCalendar.date(from: comps)
    }

    /// 从 DTSTART 值提取日期部分(形如 20260831T082000 / 20260831)
    private static func extractIcsDate(_ block: String) -> Date? {
        guard let dtstart = extractIcsField(block, "DTSTART") else { return nil }
        return parseIcsDate(String((dtstart.components(separatedBy: "T").first ?? "").prefix(8)))
    }

    /// 从 DESCRIPTION "第X - Y节" 提取节次; 兼容 Sleepy 自家导出(无此行,返回 nil 走时间估算)
    private static func extractIcsNode(_ description: String) -> (Int, Int)? {
        guard let m = try? NSRegularExpression(pattern: "第\\s*(\\d+)\\s*[-–]\\s*(\\d+)\\s*节"),
              let mm = m.firstMatch(in: description, range: NSRange(description.startIndex..., in: description)),
              let r1 = Range(mm.range(at: 1), in: description), let r2 = Range(mm.range(at: 2), in: description),
              let a = Int(description[r1]), let b = Int(description[r2]),
              a >= 1, b >= a else { return nil }
        return (a, b - a + 1)
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
        // 8:00 = 第 1 节; 节边界按 50min 周期近似(45课+5课间), +10min 防边界抖动
        let startNode = Int((Double(startMin - 480 + 10) / 50)) + 1
        let step = max(Int((Double(duration) / 50).rounded()), 1)
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

    // MARK: - 纯文本

    /// 解析简化的纯文本格式:
    /// 一行一课,字段间用制表符或全角逗号分隔。
    private static func parseSimpleText(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        var courses: [CourseEntity] = []
        var dropped: [String] = []
        var nodeTimes: [Int: (Int, Int)] = [:]
        let lines = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.hasPrefix("#") }

        // 节次时间表行: "时间表 1 08:00 09:35" / "第1节 08:00-09:35" / "1 08:00~09:35" — 先于课程行判断
        // (课程行不含冒号, 所以"带两个 HH:mm 的行"必是时间表行, 无歧义)
        let timeTableRe = try? NSRegularExpression(
            pattern: "^\\s*(?:时间表|节次|第)?\\s*(\\d{1,2})\\s*节?\\s*[\\s:：]*\\s*(\\d{1,2}):(\\d{2})\\s*[-–~～至\\s]+\\s*(\\d{1,2}):(\\d{2})\\s*$")

        for raw in lines {
            let nsRaw = raw as NSString
            if let tt = timeTableRe?.firstMatch(in: raw, range: NSRange(location: 0, length: nsRaw.length)) {
                let g = { (i: Int) -> String? in
                    guard let r = Range(tt.range(at: i), in: raw) else { return nil }
                    return String(raw[r])
                }
                // "时间表 1 …" 节次在第 1 组; "第1节 …" 节次在字面里(也是第 1 组)
                guard let nodeStr = g(1), let node = Int(nodeStr), node >= 1,
                      let sh = g(2).flatMap(Int.init), let sm = g(3).flatMap(Int.init),
                      let eh = g(4).flatMap(Int.init), let em = g(5).flatMap(Int.init) else { continue }
                let st = sh * 60 + sm, et = eh * 60 + em
                if (0...23).contains(sh) && (0...59).contains(sm)
                    && (0...23).contains(eh) && (0...59).contains(em) && st < et {
                    nodeTimes[node] = (st, et)
                }
                continue
            }
            // 剥 Markdown: 管道表格行 + 表头分隔行 + 星号加粗 + 反引号
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let pipeRe = try? NSRegularExpression(pattern: "^\\|?[\\s|:-]+\\|?$"),
               pipeRe.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil { continue }
            if line.hasPrefix("|") || line.hasSuffix("|") {
                line = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .replacingOccurrences(of: "\\s*\\|\\s*", with: "\t", options: .regularExpression)
            }
            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)

            // 支持 tab / 多空格 / 全角逗号 — ← split(Regex("\\s+|，"))
            let parts = splitByWhitespaceOrFullwidthComma(line)
            if parts.count < 6 {
                if !line.isEmpty { dropped.append(String(line.prefix(40))) }
                continue
            }

            let name = parts[0]
            let teacher = parts[1]
            let room = parts[2]
            // 纯数字 0/8 越界也收(钳到 1..7), 其余走 parseDay(周一/Monday)
            guard let day = (Int(parts[3].trimmingCharacters(in: .whitespaces)) ?? parseDay(parts[3]))
                .map({ min(max($0, 1), 7) }) else {
                dropped.append(String(line.prefix(40))); continue
            }
            // 节次列是 start-end 格式 (e.g. "1-2"), 转为 (startNode, step=end-start+1); 反写自动排序
            guard let (nodeStart, nodeEnd) = parseRange(parts[4]).map(sortRange) else {
                dropped.append(String(line.prefix(40))); continue
            }
            let step = max(nodeEnd - nodeStart + 1, 1)
            guard let (startWeek, endWeek) = parseRange(parts[5]).map(sortRange) else {
                dropped.append(String(line.prefix(40))); continue
            }
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
            courses: courses,
            timeJson: buildTimeJson(nodeTimes),
            nodesPerDay: nodeTimes.isEmpty ? 0 : (nodeTimes.keys.max() ?? 0),
            droppedLines: dropped
        )
    }

    /// 区间反写(16-1)自动排序为 (1,16)
    private static func sortRange(_ p: (Int, Int)) -> (Int, Int) {
        p.0 <= p.1 ? p : (p.1, p.0)
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
