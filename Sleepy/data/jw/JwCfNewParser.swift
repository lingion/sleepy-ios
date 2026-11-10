// JwCfNewParser.swift — ← JwCfNewParser.kt
//
// 新青果 NTSS (FullCalendar 形态) 课表 JSON 解析器 (type=cf_new)。
//
// 适配学校:江西中医药大学 (jiaowu.jxutcm.edu.cn, 2026-09 采集包实锤)。
//
// source 是抓取侧 (CF_NEW_FETCH_JS) 组装的组合 JSON 信封 —
//   {
//     "sleepyCfNtss": true, "xnxqdm":"202601", "startDate":"2026-09-07",
//     "weeks": [{"week": 1, "rows": [{...}]}, ...],
//     "periods": [{"node": 1, "start": "08:30", "end": "09:10"}, ...]
//   }
//
// rows 为 POST /new/student/xsgrkb/getCalendarWeekDatas 原始行(JS 只透传不解码,跨语言 invariant)。
// 字段语义(2026-09-16 真实响应实锚):
//   kcmc=课名  teaxms=教师  jxcdmc=教学场地  xq=星期(1-7)
//   ps/pe=起止节(零填充且可为空串,空串时以行内 qssj/jssj 对 periods 节次时间反推节点)
//   zc=单周次("2",与所在请求周一致 — 全学期周次归属由逐周请求的 week 决定;
//        兼容旧假设的全学期串形态:zc 展开多于 1 个周次时以其为准)
//   kcbh=课号  jxbmc=教学班  bapjxcd='1'=排课不用场地(jxcdmc 空)
//
// 抓取侧优先单请求全量(zc 空时服务端回整学期,bucket week=0):同一门课在其 occurring
// 的每周各有一行,本 parser 按唯一键 (kcbh|kcmc|teaxms|jxcd|xq|ps|pe|jxbmc) 聚合
// 合并周次集合,周次归属优先取行自身 zc(两种形态下都正确),缺失才回退所在请求周;
// 复用 JwChengFangParser.weekIntList2WeekBeanList 折叠为 (start, end, type) 三元组。

import Foundation

final class JwCfNewParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    private struct Acc {
        let course: JwCourse
        var weeks: [Int]
    }

    func generateCourseList() throws -> [JwCourse] {
        let html = JwCfNewHtmlParser(source)
        if html.confidenceValue > 0 { return html.generateCourseList() }
        guard let data = source.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if root["requestedWeeks"] != nil { try validateCapture(root) }
        guard let buckets = root["weeks"] as? [[String: Any]] else { return [] }
        var startByTime: [String: Set<Int>] = [:], endByTime: [String: Set<Int>] = [:]
        func remember(_ time: String, _ node: Int?, _ starts: Bool) {
            guard let node, node > 0, !time.isEmpty else { return }
            if starts { startByTime[time, default: []].insert(node) }
            else { endByTime[time, default: []].insert(node) }
        }
        for period in root["periods"] as? [[String: Any]] ?? [] {
            let start = normTime(jw1064String(period, "start")), end = normTime(jw1064String(period, "end"))
            if JwCourse.isValidTimeRange(start, end) {
                remember(start, jw1064Integer(period["node"]), true)
                remember(end, jw1064Integer(period["node"]), false)
            }
        }
        var flatRows: [([String: Any], Int)] = []
        for bucket in buckets {
            for row in bucket["rows"] as? [[String: Any]] ?? [] {
                flatRows.append((row, jw1064Integer(bucket["week"]) ?? 0))
                guard let day = jw1064Integer(jw1064String(row, "xq")), (1...7).contains(day),
                      let first = jw1064Integer(jw1064String(row, "ps")), let last = jw1064Integer(jw1064String(row, "pe")), first > 0, last >= first else { continue }
                let start = normTime(jw1064String(row, "qssj")), end = normTime(jw1064String(row, "jssj"))
                if JwCourse.isValidTimeRange(start, end) { remember(start, first, true); remember(end, last, false) }
            }
        }
        var order: [String] = [], groups: [String: Acc] = [:]
        for (row, bucketWeek) in flatRows {
            let name = jw1064String(row, "kcmc"), teacher = jw1064String(row, "teaxms")
            var room = jw1064String(row, "jxcdmc")
            if room.isEmpty && jw1064String(row, "bapjxcd") == "1" { room = "不用场地" }
            guard !name.isEmpty, let day = jw1064Integer(jw1064String(row, "xq")), (1...7).contains(day) else { continue }
            let rawStart = jw1064String(row, "qssj"), rawEnd = jw1064String(row, "jssj")
            let start = normTime(rawStart), end = normTime(rawEnd)
            if !rawStart.isEmpty && start.isEmpty || !rawEnd.isEmpty && end.isEmpty { continue }
            if !start.isEmpty && !end.isEmpty && !JwCourse.isValidTimeRange(start, end) { continue }
            let ps = jw1064String(row, "ps"), pe = jw1064String(row, "pe")
            let first = ps.isEmpty ? (startByTime[start]?.count == 1 ? startByTime[start]?.first : nil) : jw1064Integer(ps)
            let last = pe.isEmpty ? (endByTime[end]?.count == 1 ? endByTime[end]?.first : nil) : jw1064Integer(pe)
            guard let first, let last, first > 0, last >= first else { continue }
            let hasTime = JwCourse.isValidTimeRange(start, end)
            let zc = jw1064String(row, "zc")
            let weeks = zc.isEmpty ? ((1...366).contains(bucketWeek) ? [bucketWeek] : []) : strictWeeks(zc)
            guard !weeks.isEmpty else { continue }
            let course = JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: first, endNode: last,
                                  startWeek: 1, endWeek: 1, startTime: hasTime ? start : "", endTime: hasTime ? end : "")
            let key = [jw1064String(row, "kcbh"), name, teacher, room, String(day), String(first), String(last), jw1064String(row, "jxbmc"), course.startTime, course.endTime].joined(separator: "|")
            if groups[key] == nil { order.append(key); groups[key] = Acc(course: course, weeks: []) }
            groups[key]!.weeks.append(contentsOf: weeks)
        }
        return order.flatMap { key -> [JwCourse] in
            guard let group = groups[key] else { return [] }
            return JwChengFangParser.weekIntList2WeekBeanList(Array(Set(group.weeks)).sorted()).map { jw1064Weeks(group.course, $0.0, $0.1, $0.2) }
        }
    }

    private func normTime(_ text: String) -> String {
        guard let m = jw1064Matches(#"^([0-9]{1,2}):([0-9]{1,2})(?::([0-9]{2}))?$"#, text.trimmingCharacters(in: .whitespacesAndNewlines)).first,
              let hour = Int(m[1]), let minute = Int(m[2]), (0...23).contains(hour), (0...59).contains(minute),
              m[3].isEmpty || (0...59).contains(Int(m[3]) ?? -1) else { return "" }
        return String(format: "%02d:%02d", hour, minute)
    }
    private func strictWeeks(_ text: String) -> [Int] {
        var weeks = Set<Int>()
        for token in text.components(separatedBy: ",") {
            guard let m = jw1064Matches(#"^([0-9]+)(?:\s*[-~—]\s*([0-9]+))?$"#, token.trimmingCharacters(in: .whitespacesAndNewlines)).first,
                  let first = jw1064Integer(m[1]), let last = jw1064Integer(m[2].isEmpty ? m[1] : m[2]), first > 0, last >= first, last <= 366 else { return [] }
            weeks.formUnion(first...last)
        }
        return weeks.sorted()
    }
    private func validateCapture(_ root: [String: Any]) throws {
        func number(_ value: Any) -> Int? {
            guard !(value is String), let n = jw1064Integer(value), (1...366).contains(n) else { return nil }; return n
        }
        guard let requested = root["requestedWeeks"] as? [Any], !requested.isEmpty else { throw JwParseError(message: "Missing requested weeks") }
        let expected = requested.compactMap(number)
        guard expected.count == requested.count, Set(expected).count == expected.count else { throw JwParseError(message: "Invalid requested weeks") }
        guard let buckets = root["weeks"] as? [[String: Any]], buckets.count == expected.count else { throw JwParseError(message: "Incomplete week capture") }
        guard buckets.allSatisfy({ $0["rows"] is [Any] }) else { throw JwParseError(message: "Invalid week bucket") }
        let actual = buckets.compactMap { $0["week"].flatMap(number) }
        guard actual.count == buckets.count, Set(actual).count == actual.count, Set(actual) == Set(expected) else { throw JwParseError(message: "Mismatched week capture") }
    }

    static func parseWeekList(_ zcs: String) -> [Int] {
        let rangeRe = try! NSRegularExpression(pattern: "^(\\d+)\\s*[-~—]\\s*(\\d+)$", options: [])
        var result: [Int] = []
        for tok in zcs.split(separator: ",") {
            let t = tok.trimmingCharacters(in: .whitespaces)
            let nsRange = NSRange(t.startIndex..., in: t)
            if let m = rangeRe.firstMatch(in: t, options: [], range: nsRange) {
                let ns = t as NSString
                guard let a = Int(ns.substring(with: m.range(at: 1))),
                      let b = Int(ns.substring(with: m.range(at: 2))) else { continue }
                if a <= b { result.append(contentsOf: a...b) }
            } else if let n = Int(t) {
                result.append(n)
            }
        }
        return result.filter { $0 >= 1 }
    }

    // MARK: - T9

    var confidenceValue: Int {
        if JwCfNewHtmlParser(source).confidenceValue > 0 { return 100 }
        if !source.contains("sleepyCfNtss") { return 0 }
        let hasFields = source.contains("kcmc") && source.contains("\"zc\"")
        return hasFields ? 100 : 70
    }

    var matchedFeatureList: [String] {
        let htmlFeatures = JwCfNewHtmlParser(source).matchedFeatureList
        if !htmlFeatures.isEmpty { return htmlFeatures }
        if !source.contains("sleepyCfNtss") { return [] }
        var out: [String] = ["sleepyCfNtss"]
        if source.contains("weeks") { out.append("weeks") }
        if source.contains("kcmc") { out.append("字段=kcmc") }
        if source.contains("teaxms") { out.append("字段=teaxms") }
        if source.contains("jxcdmc") { out.append("字段=jxcdmc") }
        if source.contains("\"ps\"") && source.contains("\"pe\"") { out.append("字段=ps/pe") }
        return out
    }
}