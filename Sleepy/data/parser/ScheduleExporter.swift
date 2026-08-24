// ScheduleExporter.swift — ← ScheduleExporter.kt
// 课表导出器 — 支持两种格式:
//
// 1. **WakeUp 兼容 JSON** — 可以被原版 WakeUp app 导入(兼容 schema: name/position/type/day/startNode/step/startWeek/endWeek/color)
// 2. **ICS 日历** — 可以导入到系统日历 / Google Calendar / Apple Calendar

import Foundation

enum ScheduleExporter {

    /// 导出 WakeUp 兼容 JSON ← exportWakeUpJson (prettyPrint)
    static func exportWakeUpJson(_ table: TimeTableEntity, _ courses: [CourseEntity]) -> String {
        var courseArr: [[String: Any]] = []
        for c in courses {
            courseArr.append([
                "name": c.courseName,
                "teacher": c.teacher,
                "position": c.room,
                "day": c.day,
                "startNode": c.startNode,
                "step": c.step,
                "startWeek": c.startWeek,
                "endWeek": c.endWeek,
                "type": c.type,
                "color": c.color
            ])
        }

        let obj: [String: Any] = [
            "name": table.name,
            "startDate": table.startDate,
            "tableInfo": [
                "name": table.name,
                "startDate": table.startDate,
                "maxWeek": table.maxWeek,
                "nodesPerDay": table.nodesPerDay,
                "time": table.timeJson
            ] as [String: Any],
            "courses": courseArr
        ]

        return prettyJson(obj)
    }

    /// 导出 WakeUp 分享文本格式 (URL 编码的 JSON 字符串) ← exportWakeUpShareText
    static func exportWakeUpShareText(_ table: TimeTableEntity, _ courses: [CourseEntity]) -> String {
        var courseArr: [[String: Any]] = []
        for c in courses {
            courseArr.append([
                "name": c.courseName,
                "teacher": c.teacher,
                "position": c.room,
                "day": c.day,
                "startNode": c.startNode,
                "step": c.step,
                "startWeek": c.startWeek,
                "endWeek": c.endWeek,
                "type": c.type,
                "color": c.color
            ])
        }
        // ← URLEncoder.encode(json, "UTF-8"): 表单编码(空格→+),非 componentEncoding(空格→%20)
        let courseDetailJson = compactJson(courseArr)
        let encoded = formURLEncode(courseDetailJson)

        let root: [String: Any] = [
            "name": table.name,
            "startDate": table.startDate,
            "courseDetailJson": encoded
        ]

        return "【来自Sleepy】\n课程分享:\n\n" + compactJson(root)
    }

    /// 导出 ICS 日历 ← exportIcs
    static func exportIcs(_ table: TimeTableEntity, _ courses: [CourseEntity]) -> String {
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
        guard let parsedStart = isoDate(table.startDate) else { return lines.joined(separator: "\n") + "\n" }
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
            let startTime: String
            let endTime: String
            if c.ownTime && !c.startTime.isEmpty && !c.endTime.isEmpty {
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
            if !c.room.isEmpty { lines.append("LOCATION:\(escapeIcs(c.room))") }
            if !c.teacher.isEmpty { lines.append("DESCRIPTION:老师:\(escapeIcs(c.teacher))") }
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

    // MARK: - JSON 底层(替代 kotlinx.serialization prettyPrint/compact)

    /// kotlinx Json { prettyPrint = true } 风格:缩进多行(键序保持插入序)
    private static func prettyJson(_ obj: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// compact(无缩进,键序保持)
    private static func compactJson(_ obj: Any) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// java.net.URLEncoder.encode 表单语义: 空格→+,保留 .-*_,其余百分号编码(UTF-8)
    private static func formURLEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: ".-*_")
        return s.addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? s
    }

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

    private static func isoDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }

    /// LocalDate.with(DayOfWeek.MONDAY): 本周的周一(ISO 周)
    private static func mondayOfWeek(_ d: Date, _ cal: Calendar) -> Date {
        let weekday = cal.component(.weekday, from: d)   // 1=Sun..7=Sat
        let iso = weekday == 1 ? 7 : weekday - 1          // 1=Mon..7=Sun
        return cal.date(byAdding: .day, value: -(iso - 1), to: d)!
    }
}
