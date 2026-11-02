// XiaoaiPresetData.swift — ← data/parser/XiaoaiPresetData.kt (v1.0.62 B6)
//
// 小爱课程表 presetData 导出 — 2026-10-10。
//
// 通路: 构造小爱官方前端(H5 /import)同构的 presetData, 经
// `voiceassist://aiweb/?url=<H5>&presetData=<encoded>` URL scheme 唤起小爱 App,
// H5 从 presetData.importData 读 parserRes.courseInfos 进预览页, 用户在小爱里确认导入。
// Sleepy 本地准备数据后交给小爱; 小爱接收后的联网和数据处理由其负责。
//
// presetData 结构(三方独立印证: 小爱官方 umi.js bundle / NEORUAA MIT 实现 / Mercury 实现):
// ```
// { "importData": "<JSON 字符串>" }        ← 外层整体 URL-encode 进 deep link
//   importData = {
//     isV2: true, errorCode: 0, schoolName: "...",
//     parserRes: { courseInfos: [ { name, teacher, position, day,
//                                   weeks: [1,2..], sections: [1,2..] } ] },
//     timerRes:  { totalWeek, startSemester(13位ms), startWithSunday,
//                  showWeekend, forenoon, afternoon, night,
//                  sections: [ { section, startTime, endTime } ] },
//     feedbackId, source, status: "native", id, t: <ms>
//   }
// ```
// weeks/sections 为纯数字数组(NEORUAA/官方 parser 文档一致)。
//
// 字段映射(CourseEntity → courseInfos):
//   courseName→name · teacher→teacher · room→position · day→day
//   inWeek 展开 startWeek..endWeek + type 单双周过滤 → weeks 数组
//   startNode..startNode+step-1 → sections 数组
// timeJson(或绑定 periodTable) node/start/end → timerRes.sections section/startTime/endTime。
//
// 平台映射: kotlinx.serialization buildJsonObject → JSONSerialization
// (键序差异不影响接收端 JSON 解析; sortedKeys 保证输出确定, 深链可复现)。

import Foundation

/// 校验失败 ← Android IllegalArgumentException(require 抛出, 调用方报 export_xiaoai_invalid)
enum XiaoaiPresetDataError: Error {
    case invalid(String)
}

enum XiaoaiPresetData {

    static let XIAOAI_H5_URL = "https://i.ai.mi.com/h5/precache/ai-schedule/"
    private static let SOURCE = "sleepy"

    /// 唤起小爱的完整 deep link。presetData 已做 URL-encode, url 参数同样 encode。
    static func deepLink(_ presetData: String) -> String {
        "voiceassist://aiweb/?source=sleepy&flag=268468224"
            + "&url=\(urlEncode(XIAOAI_H5_URL))"
            + "&presetData=\(urlEncode(presetData))"
    }

    /// 生成完整 presetData 字符串(外层 {importData:"..."} 未 encode 形态, 供 deepLink/测试用)。
    /// periodTable 优先; nil 时回落 table.timeJson 兼容列。
    static func build(
        table: TimeTableEntity,
        courses: [CourseEntity],
        periodTable: PeriodTableEntity? = nil,
        nowMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> String {
        let timeJson = periodTable?.timeJson ?? table.timeJson
        let timerSections = parseTimerSections(timeJson)
        try validate(table: table, courses: courses, timeJson: timeJson, sections: timerSections)

        let importData: [String: Any] = [
            "isV2": true,
            "errorCode": 0,
            "schoolName": table.name,
            "parserRes": ["courseInfos": buildCourseInfos(courses: courses, timeJson: timeJson)],
            "timerRes": try buildTimerRes(table: table, sections: timerSections),
            "feedbackId": "sleepy_\(nowMillis)",
            "source": SOURCE,
            "status": "native",
            "id": "sleepy",
            "t": String(nowMillis),
        ]
        return jsonString(["importData": jsonString(importData)])
    }

    /// Reject unsupported input before XiaoAI silently drops weeks or renumbers periods.
    private static func validate(
        table: TimeTableEntity,
        courses: [CourseEntity],
        timeJson: String,
        sections: [(node: Int, start: String, end: String)]
    ) throws {
        func reject(_ reason: String) -> XiaoaiPresetDataError { .invalid(reason) }
        guard (1...30).contains(table.maxWeek) else { throw reject("maxWeek \(table.maxWeek) 超出 [1,30]") }
        guard !courses.isEmpty, !sections.isEmpty else { throw reject("courses/sections 为空") }
        let ordered = sections.sorted { $0.node < $1.node }
        for (index, s) in ordered.enumerated() {
            guard s.node == index + 1 else { throw reject("节次序号不连续: \(s.node) @\(index)") }
            let sm = clockMinutes(s.start)
            let em = clockMinutes(s.end)
            guard sm >= 0, em > sm else { throw reject("非法节次时间: \(s.start)-\(s.end)") }
            if index > 0 { guard sm >= clockMinutes(ordered[index - 1].end) else { throw reject("节次时间回退: \(s.start)") } }
        }
        let counts = inferSessionCounts(sections)
        guard (1...10).contains(counts.morning), (0...10).contains(counts.afternoon), (0...10).contains(counts.night)
            else { throw reject("上午/下午/晚间节数越界: \(counts)") }
        for course in courses {
            guard (1...7).contains(course.day) else { throw reject("day 越界: \(course.day)") }
            guard (1...30).contains(course.startWeek), course.endWeek >= course.startWeek, (1...30).contains(course.endWeek)
                else { throw reject("周次越界: \(course.startWeek)-\(course.endWeek)") }
            guard !expandWeeks(course).isEmpty else { throw reject("单双周过滤后无周次") }
            let normalized = course.normalizeNode(timeJson: canonical(timeJson))
            guard (1...sections.count).contains(normalized.startNode), (1...sections.count).contains(normalized.step)
                else { throw reject("节次落位越界: \(normalized.startNode)+\(normalized.step)") }
            guard normalized.startNode + normalized.step - 1 <= sections.count else { throw reject("节次落位越界") }
        }
    }

    /// CourseEntity 列表 → courseInfos 数组。空列表返回空数组(由调用方拦空表)。
    /// timeJson 用于 issue#55 ownTime 课程按节次表归一化 sections 落位。
    static func buildCourseInfos(courses: [CourseEntity], timeJson: String) -> [[String: Any]] {
        let canonicalTimeJson = canonical(timeJson)
        return courses.map { c in
            let normalized = c.normalizeNode(timeJson: canonicalTimeJson)
            return [
                "name": c.courseName,
                "teacher": c.teacher,
                "position": c.room,
                "day": c.day,
                "weeks": expandWeeks(c),
                "sections": Array(normalized.startNode...(normalized.startNode + normalized.step - 1)),
            ]
        }
    }

    /// startWeek..endWeek 按 type(0每周/1单周/2双周/3按列) 展开为显式周次数组。
    static func expandWeeks(_ c: CourseEntity) -> [Int] {
        // Android (startWeek..endWeek) 起点大于终点时抛异常; validate 已挡,
        // 此处防御性返回空(不崩溃), 语义等价于"无有效周次"。
        guard c.startWeek <= c.endWeek else { return [] }
        return (c.startWeek...c.endWeek).filter { c.inWeek($0) }
    }

    private static func canonical(_ timeJson: String) -> String {
        jsonString(parseTimerSections(timeJson).map { ["node": $0.node, "start": $0.start, "end": $0.end] })
    }

    /// timeJson → timerRes.sections [{section,startTime,endTime}]。
    /// 兼容两种键形(真实 DB 并存, 模拟器实测抓到):
    ///   规范形 {node,start,end}(TimeTableUtils.buildTimeJsonFromRows 写入)
    ///   历史形 {nodeStart,startTime,endTime}(创建向导/旧版写入)
    /// 任一条目缺键/坏值 → 整体返回空(← Android runCatching.getOrDefault(emptyList()))。
    static func parseTimerSections(_ timeJson: String) -> [(node: Int, start: String, end: String)] {
        if timeJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        guard let data = timeJson.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        var out: [(node: Int, start: String, end: String)] = []
        out.reserveCapacity(arr.count)
        for (index, o) in arr.enumerated() {
            let nodeValue = o["node"] ?? o["nodeStart"]
            let node: Int
            if let nv = nodeValue {
                // ← Android nodeValue.toString().toIntOrNull(): 转不成整数整体失败
                guard let n = Int(stringifyScalar(nv)) else { return [] }
                node = n
            } else {
                node = index + 1  // ← 隐式顺序节点
            }
            guard let start = (o["start"] ?? o["startTime"]) as? String,
                  let end = (o["end"] ?? o["endTime"]) as? String else { return [] }
            out.append((node, start, end))
        }
        return out
    }

    /// JsonPrimitive.toString 等价: NSNumber(1) → "1", String → 原文(不带引号)
    private static func stringifyScalar(_ v: Any) -> String {
        if let n = v as? NSNumber {
            // Bool 也走 NSNumber; 节次号不会是 bool, objCType 'c' 时按 0/1 输出即可
            return n.stringValue
        }
        return String(describing: v)
    }

    private static func buildTimerRes(
        table: TimeTableEntity,
        sections: [(node: Int, start: String, end: String)]
    ) throws -> [String: Any] {
        let counts = inferSessionCounts(sections)
        return [
            "totalWeek": table.maxWeek,
            "startSemester": try startSemesterMillis(table.startDate),
            "startWithSunday": false,
            "showWeekend": true,
            "forenoon": counts.morning,
            "afternoon": counts.afternoon,
            "night": counts.night,
            "sections": sections.sorted { $0.node < $1.node }.map {
                ["section": $0.node, "startTime": $0.start, "endTime": $0.end]
            },
        ]
    }

    /// 按 startTime 推断上午/下午/晚间节数 (小爱 timerRes 三段统计):
    /// <13:00 上午 · [13:00,18:00) 下午 · >=18:00 晚间，与接收端保持一致。
    static func inferSessionCounts(_ sections: [(node: Int, start: String, end: String)]) -> (morning: Int, afternoon: Int, night: Int) {
        var morning = Set<Int>()
        var afternoon = Set<Int>()
        var night = Set<Int>()
        for s in sections {
            let minutes = clockMinutes(s.start)
            if minutes < 13 * 60 {  // ← Android minutes < 0 归上午(负值即非法, 同落上午桶)
                morning.insert(s.node)
            } else if minutes < 18 * 60 {
                afternoon.insert(s.node)
            } else {
                night.insert(s.node)
            }
        }
        return (morning.count, afternoon.count, night.count)
    }

    /// "HH:mm" → 分钟数; 非法(非 [0-9]{2}:[0-9]{2} 或越界) → -1
    static func clockMinutes(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              hhmm.allSatisfy({ $0.isNumber || $0 == ":" }),
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return -1 }
        return h * 60 + m
    }

    /// startDate("yyyy-MM-dd") → 当日 00:00 UTC+8 的 13 位毫秒时间戳字符串。
    static func startSemesterMillis(_ startDate: String) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)  // ← ZoneOffset.ofHours(8)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: startDate) else {
            throw XiaoaiPresetDataError.invalid("startDate 非法: \(startDate)")
        }
        return String(Int64(date.timeIntervalSince1970 * 1000))
    }

    // MARK: - JSON / URL 编码工具

    private static func jsonString(_ obj: [[String: Any]]) -> String {
        guard !obj.isEmpty, let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    private static func jsonString(_ obj: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// ← java.net.URLEncoder.encode(value, "UTF-8"): 保留 A-Za-z0-9 与 .-*_,
    /// 空格→+, 其余(含中文)逐 UTF-8 字节 %XX。CharacterSet.alphanumerics 含非 ASCII
    /// 字母, 不能直接用 — 显式枚举 ASCII 白名单。
    private static func urlEncode(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.-*_ ")
        let raw = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return raw.replacingOccurrences(of: " ", with: "+")
    }
}
