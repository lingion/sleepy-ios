// ScheduleExporter.swift — ← ScheduleExporter.kt
// 课表导出器 — 支持两种格式:
//
// 1. **WakeUp 兼容 JSON** — 可以被原版 WakeUp app 导入(兼容 schema: name/position/type/day/startNode/step/startWeek/endWeek/color)
// 2. **ICS 日历** — 可以导入到系统日历 / Google Calendar / Apple Calendar

import Foundation

enum ScheduleExporter {

    /// startDate 无法按 ISO yyyy-MM-dd 解析 ← Android LocalDate.parse 抛 DateTimeParseException
    enum ExportError: Error {
        case invalidStartDate(String)
    }

    // MARK: - JSON 底层(逐字节对齐 kotlinx Json { prettyPrint = true })

    /// kotlinx buildJsonObject 底层是 LinkedHashMap → 序列化保持插入序。
    /// Swift [String: Any] 不保序, 故用元组数组承载字段(替代原 JSONSerialization 方案)。
    private indirect enum JsonValue {
        case string(String)
        case int(Int)
        case object([(String, JsonValue)])
        case array([JsonValue])
    }

    /// kotlinx prettyPrint 固定格式: 4 空格缩进、`"key": value`(冒号后一个空格)、
    /// 空容器输出 `{}` / `[]`、字符串不转义非 ASCII(Android Issue55OwnTimeRoundTripTest
    /// 断言 `"startTime": "20:50"` 即此格式)。
    private static func prettyJson(_ value: JsonValue, _ level: Int = 0) -> String {
        let pad = String(repeating: " ", count: level * 4)
        let inner = String(repeating: " ", count: (level + 1) * 4)
        switch value {
        case .string(let s):
            return "\"\(escapeJsonString(s))\""
        case .int(let i):
            return String(i)
        case .array(let items):
            if items.isEmpty { return "[]" }
            let body = items.map { inner + prettyJson($0, level + 1) }.joined(separator: ",\n")
            return "[\n\(body)\n\(pad)]"
        case .object(let fields):
            if fields.isEmpty { return "{}" }
            let body = fields.map { inner + "\"\(escapeJsonString($0.0))\": " + prettyJson($0.1, level + 1) }
                .joined(separator: ",\n")
            return "{\n\(body)\n\(pad)}"
        }
    }

    /// kotlinx escapeString 语义: \" \\ \n \r \t \b \f, 其余 <U+0020 → \u00xx(小写十六进制),
    /// 非 ASCII 原样输出(不转义)
    private static func escapeJsonString(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out
    }

    /// Kotlin String.isNotBlank() 对应: 纯空白视同缺失(非标准时间两路 JSON + ICS 共用同一闸)
    private static func isNotBlank(_ s: String) -> Bool {
        !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 导出 WakeUp 兼容 JSON ← exportWakeUpJson (prettyPrint)
    static func exportWakeUpJson(_ table: TimeTableEntity, _ courses: [CourseEntity]) -> String {
        let obj: JsonValue = .object([
            ("name", .string(table.name)),
            ("startDate", .string(table.startDate)),
            ("tableInfo", .object([
                ("name", .string(table.name)),
                ("startDate", .string(table.startDate)),
                ("maxWeek", .int(table.maxWeek)),
                ("nodesPerDay", .int(table.nodesPerDay)),
                ("time", .string(table.timeJson))
            ])),
            ("courses", courseArray(courses))
        ])
        return prettyJson(obj)
    }

    /// 导出 WakeUp 分享文本格式 (URL 编码的 JSON 字符串) ← exportWakeUpShareText
    static func exportWakeUpShareText(_ table: TimeTableEntity, _ courses: [CourseEntity]) -> String {
        // ← Android: courseDetailJson 与 root 都经 prettyPrint=true 的 Json 实例序列化;
        //   URLEncoder.encode(json, "UTF-8") 表单编码(空格→+), 非 componentEncoding(空格→%20)
        let courseDetailJson = prettyJson(courseArray(courses))
        let encoded = formURLEncode(courseDetailJson)

        let root: JsonValue = .object([
            ("name", .string(table.name)),
            ("startDate", .string(table.startDate)),
            ("courseDetailJson", .string(encoded))
        ])

        // ← Android 实字节: 课程分享 后跟全角冒号 U+FF1A(EF BC 9A), 非 ASCII ':'
        return "【来自Sleepy】\n课程分享：\n\n" + prettyJson(root)
    }

    private static func courseArray(_ courses: [CourseEntity]) -> JsonValue {
        var items: [JsonValue] = []
        for c in courses {
            var fields: [(String, JsonValue)] = [
                ("name", .string(c.courseName)),
                ("teacher", .string(c.teacher)),
                ("position", .string(c.room)),
                ("day", .int(c.day)),
                ("startNode", .int(c.startNode)),
                ("step", .int(c.step)),
                ("startWeek", .int(c.startWeek)),
                ("endWeek", .int(c.endWeek)),
                ("type", .int(c.type)),
                ("color", .string(c.color))
            ]
            // issue#55: 非标准时间课程往返保真 — startTime/endTime 为该卡覆盖值,
            // 丢了导入端会退化成按节次定位(用户实测 20:50-22:00 变 11-12 节)
            if c.ownTime && isNotBlank(c.startTime) && isNotBlank(c.endTime) {
                fields.append(("startTime", .string(c.startTime)))
                fields.append(("endTime", .string(c.endTime)))
            }
            items.append(.object(fields))
        }
        return .array(items)
    }

    /// 导出 ICS 日历 ← exportIcs (既有调用点签名不变)
    /// ← Android `LocalDate.parse` 对非法 startDate 抛异常; 旧实现静默返回缺
    /// `END:VCALENDAR` 的 header-only 残缺日历(非法 ICS)。这里改为拒绝输出:
    /// 非法日期返回空串, 需要错误传播的新调用点走 exportIcsOrThrow。
    static func exportIcs(_ table: TimeTableEntity, _ courses: [CourseEntity]) -> String {
        return (try? exportIcsOrThrow(table, courses)) ?? ""
    }

    /// ← exportIcs 真身: startDate 无法按 ISO yyyy-MM-dd 解析时抛 ExportError.invalidStartDate
    static func exportIcsOrThrow(_ table: TimeTableEntity, _ courses: [CourseEntity]) throws -> String {
        var lines: [String] = []
        lines.append("BEGIN:VCALENDAR")
        lines.append("VERSION:2.0")
        lines.append("PRODID:-//Sleepy//课程表//ZH")
        lines.append("CALSCALE:GREGORIAN")
        lines.append("METHOD:PUBLISH")
        lines.append("X-WR-CALNAME:\(table.name)")

        // 学期起始日规范化为周一(应用约定 day=1 对应周一;导入数据可能非周一,直接 plusDays(day-1) 会整体偏移)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone.current
        // ← LocalDate.parse 严格 ISO: 形状(4-2-2)与日历语义双重校验
        guard isIsoDateShape(table.startDate), let parsedStart = isoDate(table.startDate) else {
            throw ExportError.invalidStartDate(table.startDate)
        }
        let start = mondayOfWeek(parsedStart, cal)
        let nodeStartTimes = parseNodeTimes(table.timeJson)

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = cal.timeZone
        df.dateFormat = "yyyyMMdd"

        for c in courses {
            // 单双周(type=1 单周/2 双周)按起止周奇偶选第一个实际发生周
            let firstWeek: Int
            switch c.type {
            case 1: firstWeek = c.startWeek % 2 == 1 ? c.startWeek : c.startWeek + 1
            case 2: firstWeek = c.startWeek % 2 == 0 ? c.startWeek : c.startWeek + 1
            default: firstWeek = c.startWeek
            }
            // 起止周奇偶不符导致无实际发生周时跳过,避免生成错误事件
            if firstWeek > c.endWeek { continue }

            // ← start.plusWeeks(firstWeek-1).plusDays(day-1)
            let startDate = cal.date(byAdding: .day, value: (firstWeek - 1) * 7 + (c.day - 1), to: start)!
            let endDate = cal.date(byAdding: .day, value: (c.endWeek - 1) * 7 + (c.day - 1), to: start)!

            // ownTime 课程用自身自定义时间,否则按节次反查
            // ← Android isNotBlank(): 纯空白视同缺失, 与 JSON 导出两路同一闸
            let startTime: String
            let endTime: String
            if c.ownTime && isNotBlank(c.startTime) && isNotBlank(c.endTime) {
                startTime = compactTime(c.startTime)
                endTime = compactTime(c.endTime)
            } else {
                let sIdx = c.startNode - 1
                let eIdx = c.startNode + c.step - 2
                startTime = (sIdx >= 0 && sIdx < nodeStartTimes.count) ? nodeStartTimes[sIdx].0 : "080000"
                endTime = (eIdx >= 0 && eIdx < nodeStartTimes.count) ? nodeStartTimes[eIdx].1 : "090000"
            }

            let dtStart = "\(df.string(from: startDate))T\(startTime)"
            let dtEnd = "\(df.string(from: startDate))T\(endTime)"

            let byDay: String?
            switch c.day {
            case 1: byDay = "MO"
            case 2: byDay = "TU"
            case 3: byDay = "WE"
            case 4: byDay = "TH"
            case 5: byDay = "FR"
            case 6: byDay = "SA"
            case 7: byDay = "SU"
            default: byDay = nil
            }

            // 单双周加 INTERVAL=2 表示隔周重复
            let interval = (c.type == 1 || c.type == 2) ? ";INTERVAL=2" : ""
            let until = ";UNTIL=\(df.string(from: endDate))T235959Z"

            lines.append("BEGIN:VEVENT")
            // ← UID:${c.id}-${c.courseName.hashCode()}@sleepy (hashCode 用稳定 djb2 代理,Kotlin hashCode 不跨语言)
            lines.append("UID:\(c.id)-\(stableHash(c.courseName))@sleepy")
            // ← ZonedDateTime.now(UTC) 形如 2026-08-24T09:30:00.123Z[TZID 无],剔非数字保留 15 位+"Z"
            let stamp = utcStampCompact()
            lines.append("DTSTAMP:\(stamp)Z")
            lines.append("DTSTART:\(dtStart)")
            lines.append("DTEND:\(dtEnd)")
            if let byDay = byDay {
                lines.append("RRULE:FREQ=WEEKLY;BYDAY=\(byDay)\(interval)\(until)")
            } else {
                lines.append("RRULE:FREQ=WEEKLY\(interval)\(until)")
            }
            lines.append("SUMMARY:\(escapeIcs(c.courseName))")
            if isNotBlank(c.room) { lines.append("LOCATION:\(escapeIcs(c.room))") }
            // v7.10.16k 无损闭环: DESCRIPTION 写"第X-Y节"(字面 \n 转义换行, 与 WakeUp 格式一致:
            // 第X - Y节\n教室\n教师)。旧版只写"老师：X", 导入端读不到节次,
            // 只能按钟点估算 → 11-13节被估成第1节。
            // issue#55: ownTime 卡再追加 "\nHH:mm-HH:mm" 行(导入端 descLines[3] 恢复 ownTime)。
            let ownTimeLine = (c.ownTime && isNotBlank(c.startTime) && isNotBlank(c.endTime))
                ? "\\n\(c.startTime)-\(c.endTime)" : ""
            lines.append("DESCRIPTION:第\(c.startNode) - \(c.startNode + c.step - 1)节" +
                (isNotBlank(c.room) ? "\\n\(escapeIcs(c.room))" : "") +
                (isNotBlank(c.teacher) ? "\\n\(escapeIcs(c.teacher))" : "") + ownTimeLine)
            lines.append("END:VEVENT")
        }
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\n") + "\n"  // ← appendLine 每行带 \n
    }

    private static func escapeIcs(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// 将 "HH:mm" 自定义时间压缩为 ICS 的 "HHmmss" 格式(补足秒)
    private static func compactTime(_ hhmm: String) -> String {
        let t = hhmm.replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
        if t.count == 4 { return t + "00" }
        return t
    }

    private static func parseNodeTimes(_ jsonStr: String) -> [(String, String)] {
        guard let data = jsonStr.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return arr.map { o in
            let start = ((o["start"] as? String) ?? "00:00").replacingOccurrences(of: ":", with: "")
            let end = ((o["end"] as? String) ?? "00:00").replacingOccurrences(of: ":", with: "")
            let startCompact = start.count == 4 ? start + "00" : start
            let endCompact = end.count == 4 ? end + "00" : end
            return (startCompact, endCompact)
        }
    }

    // MARK: - URL 编码

    /// java.net.URLEncoder.encode 表单语义: 保留 a-zA-Z0-9 与 .-*_,
    /// 空格→+, 其余(含非 ASCII)按 UTF-8 字节百分号编码(大写十六进制)。
    /// 注意: allowed 集必须 ASCII 限定 — CharacterSet.alphanumerics 含 Unicode 字母,
    /// 会把中文原样留下 → 与 Android 的 %XX 字节串分叉。
    private static func formURLEncode(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-*_")
        return s.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? s
    }

    // MARK: - 日期/杂项

    /// Kotlin String.hashCode() 不跨语言稳定 → djb2 替代(UID 只需唯一性,不需与 Android 相同)
    private static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 5381
        for b in s.utf8 {
            h = (h &* 33) &+ UInt64(b)
        }
        return h
    }

    /// UTC now → "20260824T093000" 形(15 字符,与 Kotlin take(15) 同长)
    private static func utcStampCompact() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        return f.string(from: Date())
    }

    /// ISO 形状校验 ← LocalDate.parse 要求严格 4-2-2 数字位(yyyy-M-d 拒绝)
    private static func isIsoDateShape(_ s: String) -> Bool {
        s.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil
    }

    private static func isoDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false   // ← "2026-02-30" 等语义非法日期拒绝(LocalDate.parse 抛异常)
        return f.date(from: s)
    }

    /// LocalDate.with(DayOfWeek.MONDAY): 本周的周一(ISO 周)
    private static func mondayOfWeek(_ d: Date, _ cal: Calendar) -> Date {
        let weekday = cal.component(.weekday, from: d)   // 1=Sun..7=Sat
        let iso = weekday == 1 ? 7 : weekday - 1          // 1=Mon..7=Sun
        return cal.date(byAdding: .day, value: -(iso - 1), to: d)!
    }
}
