// JwClassicEamsParser.swift — ← JwClassicEamsParser.kt
//
// 经典金智/树维 EAMS (`courseTableForStd!courseTable.action` 系列) 课表解析器。
//
// 适配学校 (2026-09 211 批量收录 B1 档): 电子科技大学 eams.uestc.edu.cn /
// 上海财经大学 eams.sufe.edu.cn / 湖南师范大学 jwglnew.hunnu.edu.cn /
// 南京航空航天大学 aao-eas.nuaa.edu.cn (南航走 courseTableStudent!* 入口,
// 页面内嵌 TaskActivity 结构同款)。
//
// 页面结构 (与强智/正方 HTML 表格完全不同): 课表数据在页面内嵌 JS 块 —
//   var table0 = new CourseTable(2019,84);
//   var unitCount = 12;
//   var actTeachers = [{id:7396,name:"张三",lab:true}];
//   activity = new TaskActivity(教师ID, 教师名, 课号, 课名, roomId, 教室, 周次位图, ...);
//   index = D*unitCount+P;                     // D=0基星期 P=0基节次
//   table0.activities[index][...] = activity;
//   table0.marshalTable(2,1,21);
// HTML 表格 `#manualArrangeCourseTable` 是空壳 (JS 端 fillTable 渲染), DOM 无数据。
//
// 关键规则 (调研 classic-eams.md 多源交叉验证):
//   - 周次位图 01 串, 下标 0 是占位符, 下标 i=1 即第 i 周 (勿 +1);
//     单双周由位图奇偶天然表达, 稀疏周展开成逐周行 (type 按 span 奇偶压缩)
//   - index = D*unitCount+P → day=D+1, node=P+1; unitCount 从页面抠 (禁写死:
//     电子科大/天大/安工程 12, 湖南师大 13, 河南理工 11); 兼容 `index =42;`
//     纯数字形态 (day = i/unitCount, node = i%unitCount, 均 +1)
//   - 教师 [1] 可能是 actTeacherName.join(',') 表达式 → 块起点前 2500 字符内
//     反查最近的 var actTeachers = [...] 抠 name (hpu.js 形态)
//   - 参数切分用带引号/括号深度状态机 (课名可含逗号), 禁 naive split(',')
//   - 异常防护: 教师 = "-1" 跳块 (停课标记); 教室 = "停课" 不输出;
//     上财 2026-08 起第 4 参是 this.courseNameLessonNo 表达式 → 块后反查 var 值
//
// 算法形态参考: shiguang_warehouse (MIT) hunnu.js/uestc.js/hpu.js +
// WakeupSchedule_Kotlin (Apache-2.0) ImportViewModel.kt; 代码自写。

import Foundation

final class JwClassicEamsParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    /// 一条 TaskActivity 记录 (块级, 尚未按 index/位图展开)
    private struct Task {
        let teacher: String
        let name: String
        let room: String
        let weeks: [Int]
        let blockStart: Int     // 块在 source 中的起点 (actTeachers 反查窗口, 字符偏移)
        let nameExpr: String?   // 第 4 参为表达式时记原式 (courseNameLessonNo)
    }

    func generateCourseList() throws -> [JwCourse] {
        if source.contains("newActivity(") && source.contains("addActivityByTime(") {
            return timeActivities()
        }
        guard let unitCount = unitCountFromPage() else { return [] }
        var out: [JwCourse] = []

        for (task, indexPairs) in blocks(unitCount) {
            if task.teacher == "-1" || task.teacher.trimmingCharacters(in: .whitespaces).isEmpty { continue } // 停课/异常排课标记 (WakeupSchedule 经验)
            if task.room == "停课" { continue }          // 电子科大: 停课教室扣整条
            let resolvedName = resolveCourseName(task)
            if resolvedName.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            // (day, startNode, endNode) 连堂合并 + 每周展开 → 与强智位图语义对齐
            let (day, startNode, endNode) = mergeConsecutiveNodes(indexPairs)
            for week in task.weeks {
                out.append(JwCourse(
                    name: resolvedName,
                    room: task.room,
                    teacher: task.teacher,
                    day: day,
                    startNode: startNode,
                    endNode: endNode,
                    startWeek: week,
                    endWeek: week,
                    type: 0))
            }
        }
        return out
    }

    /// 一条 addActivityByTime 形态的时间活动 (块级, 尚未按周展开)
    private struct TimeActivity {
        let teacher: String
        let name: String
        let room: String
        let weeks: [Int]
    }

    /// 时间形态活动: 页面用 newActivity(...) + addActivityByTime(activity, D, startMin, endMin)
    /// 而非 index 段 → 直接按 link 的分钟区间映射节次。
    private func timeActivities() -> [JwCourse] {
        let ns = source as NSString
        let linkRe = try! NSRegularExpression(pattern: #"addActivityByTime\(activity\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)"#)
        let links = linkRe.matches(in: source, range: NSRange(location: 0, length: ns.length))
        var out: [JwCourse] = []
        for link in links {
            let activityStart = ns.range(of: "newActivity(", options: .backwards, range: NSRange(location: 0, length: link.range.location)).location
            if activityStart == NSNotFound { continue }
            let argStart = activityStart + ("newActivity(" as NSString).length
            let (args, _) = splitArgs(ns, argStart)
            if args.count < 8 { continue }
            let activity = TimeActivity(
                teacher: unquote(args[1]),
                name: unquote(args[3]),
                room: unquote(args[5]),
                weeks: bitmapToWeeks(args[7].trimmingCharacters(in: .whitespaces)))
            guard let day = Int(ns.substring(with: link.range(at: 1))) else { continue }
            guard let startMin = Int(ns.substring(with: link.range(at: 2))),
                  let endMin = Int(ns.substring(with: link.range(at: 3))) else { continue }
            let start = timeToNode(startMin)
            let end = timeToNode(endMin)
            for week in activity.weeks {
                out.append(JwCourse(
                    name: activity.name,
                    room: activity.room,
                    teacher: activity.teacher,
                    day: day,
                    startNode: start,
                    endNode: end,
                    startWeek: week,
                    endWeek: week,
                    type: 0))
            }
        }
        return out
    }

    /// 分钟时刻 → 节次起点/终点 (addActivityByTime 形态, 阈值逐条对齐 Android)
    private func timeToNode(_ minutes: Int) -> Int {
        switch minutes {
        case ...900: return 1
        case ...1010: return 3
        case ...1170: return 5
        case ...1330: return 7
        case ...1450: return 9
        case ...1615: return 11
        default: return 13
        }
    }

    /// 页面 var unitCount = N; — 拿不到返回 nil (硬失败, 别猜默认值)
    private func unitCountFromPage() -> Int? {
        guard let m = source.range(of: #"\bvar\s+unitCount\s*=\s*(\d+)\s*;"#, options: .regularExpression) else { return nil }
        let matched = String(source[m])
        guard let digitRange = matched.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(String(matched[digitRange]))
    }

    /// 切出每课块并解析 TaskActivity 参数 + 后随 index 赋值。
    private func blocks(_ unitCount: Int) -> [(Task, [(Int, Int)])] {
        var result: [(Task, [(Int, Int)])] = []
        let ns = source as NSString
        let actRe = try! NSRegularExpression(pattern: #"new\s+TaskActivity\("#)
        let matches = actRe.matches(in: source, range: NSRange(location: 0, length: ns.length))

        for (i, m) in matches.enumerated() {
            let argStart = m.range.upperBound
            let (args, _) = splitArgs(ns, argStart)
            if args.count < 7 { continue }

            // 教师: 老版 args[1] 是字面姓名串; 新版 args[0]/args[1] 是 actTeacher*.join 表达式,
            // 块前 2500 字符反查 var actTeachers (hpu.js 形态)。表达式判据: 含 join( 且非引号串。
            let nameArgRaw = args[1].trimmingCharacters(in: .whitespaces)
            let teacher: String
            if nameArgRaw.hasPrefix("\"") || nameArgRaw.hasPrefix("'") {
                teacher = unquote(nameArgRaw)
            } else if nameArgRaw.contains("join(") {
                teacher = resolveTeachersFromActTeachers(m.range.location)
            } else {
                teacher = unquote(nameArgRaw)
            }
            let nameArg = args[3]
            let room = unquote(args[5])
            let bitmap = unquote(args[6])
            let weeks = bitmapToWeeks(bitmap)
            if weeks.isEmpty { continue }

            let task = Task(
                teacher: teacher.trimmingCharacters(in: .whitespaces),
                name: nameArg.hasPrefix("\"") ? unquote(nameArg) : "",
                room: room.trimmingCharacters(in: .whitespaces),
                weeks: weeks,
                blockStart: m.range.location,
                nameExpr: nameArg.hasPrefix("\"") ? nil : nameArg.trimmingCharacters(in: .whitespaces))

            // 本块的 index 段: TaskActivity(...) 之后到下一个块声明 (或 marshalTable) 之间
            let blockEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : ns.length
            let tailRange = NSRange(location: argStart, length: max(0, blockEnd - argStart))
            let tail = ns.substring(with: tailRange)
            var indexPairs: [(Int, Int)] = []
            // 兼容: index =D*unitCount+P; / index=D*12+P; / index =42; 三种形态
            let idxRe = try! NSRegularExpression(pattern: #"index\s*=\s*(?:(\d+)\s*\*\s*(?:unitCount|\d+)\s*\+\s*(\d+)|(\d+))\s*;"#)
            let tailNS = tail as NSString
            for im in idxRe.matches(in: tail, range: NSRange(location: 0, length: tailNS.length)) {
                let d = im.range(at: 1).location != NSNotFound ? tailNS.substring(with: im.range(at: 1)) : ""
                let p = im.range(at: 2).location != NSNotFound ? tailNS.substring(with: im.range(at: 2)) : ""
                if !d.isEmpty && !p.isEmpty {
                    if let dv = Int(d), let pv = Int(p) { indexPairs.append((dv, pv)) }
                } else {
                    let linear = im.range(at: 3).location != NSNotFound ? tailNS.substring(with: im.range(at: 3)) : ""
                    if let lv = Int(linear) { indexPairs.append((lv / unitCount, lv % unitCount)) }
                }
            }
            if !indexPairs.isEmpty { result.append((task, indexPairs)) }
        }
        return result
    }

    /// 带引号/括号深度状态的参数切分 (hunnu.js splitArgs 形态)。
    /// 返回 (参数列表, 闭括号位置)。参数内逗号 (引号中/括号内) 不切分。
    /// 全程 NSString UTF-16 偏移 (与调用方的 NSRegularExpression range 同基, 对齐 Kotlin String 索引)。
    private func splitArgs(_ src: NSString, _ start: Int) -> ([String], Int) {
        var args: [String] = []
        var cur = ""
        var inQuote = false
        var depth = 0
        var i = start
        var closed = -1
        let limit = src.length
        while i < limit {
            let c = src.character(at: i)
            if c == 0x22 /* " */ && !isEscaped(src, i) {
                inQuote.toggle(); cur += String(decoding: [c], as: UTF16.self)
            } else if c == 0x28 /* ( */ && !inQuote {
                depth += 1; cur += String(decoding: [c], as: UTF16.self)
            } else if c == 0x29 /* ) */ && !inQuote {
                if depth == 0 { closed = i; break }
                depth -= 1; cur += String(decoding: [c], as: UTF16.self)
            } else if c == 0x2C /* , */ && !inQuote && depth == 0 {
                args.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""
            } else if c >= 0xD800 && c <= 0xDBFF && i + 1 < limit {
                // 代理对: 高低位一起解码, 保持字符完整
                cur += String(decoding: [c, src.character(at: i + 1)], as: UTF16.self)
                i += 1
            } else {
                cur += String(decoding: [c], as: UTF16.self)
            }
            i += 1
        }
        if !cur.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !args.isEmpty {
            args.append(cur.trimmingCharacters(in: .whitespaces))
        }
        return (args, closed)
    }

    private func isEscaped(_ src: NSString, _ i: Int) -> Bool {
        var back = 0
        var j = i - 1
        while j >= 0 && src.character(at: j) == 0x5C /* \ */ { back += 1; j -= 1 }
        return back % 2 == 1
    }

    /// 块起点前 2500 字符内最近的 var actTeachers = [{id:..,name:".."},..] → 逗号连名
    private func resolveTeachersFromActTeachers(_ blockStart: Int) -> String {
        let segStart = max(blockStart - 2500, 0)
        let ns = source as NSString
        let segStartBounded = min(segStart, ns.length)
        let seg = ns.substring(with: NSRange(location: segStartBounded, length: max(0, blockStart - segStartBounded)))
        let arrRe = try! NSRegularExpression(pattern: #"var\s+actTeachers\s*=\s*\[([^\]]*)\]\s*;"#)
        let segNS = seg as NSString
        let allArr = arrRe.matches(in: seg, range: NSRange(location: 0, length: segNS.length))
        guard let lastArr = allArr.last, lastArr.range(at: 1).location != NSNotFound else { return "" }
        let names = segNS.substring(with: lastArr.range(at: 1))  // [ ] 内内容
        var out: [String] = []
        let nameRe = try! NSRegularExpression(pattern: #"name\s*:\s*"([^"]*)""#)
        let nns = names as NSString
        for m in nameRe.matches(in: names, range: NSRange(location: 0, length: nns.length)) {
            if m.range(at: 1).location != NSNotFound {
                let v = nns.substring(with: m.range(at: 1))
                if !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(v) }
            }
        }
        return out.joined(separator: "/")
    }

    /// 上财形态: 第 4 参 = this.courseNameLessonNo → 块后反查 var courseNameLessonNo = "..";
    private func resolveCourseName(_ task: Task) -> String {
        // verbatim: 课程名整体入库, 不做任何清洗/剥离
        // 历史误伤: cleanCourseName("大学物理Ⅱ(D1200440.18)") → "大学物理Ⅱ" 丢了课程编码
        if !task.name.trimmingCharacters(in: .whitespaces).isEmpty { return task.name }
        guard let expr = task.nameExpr else { return "" }
        if !expr.contains("courseNameLessonNo") { return "" }
        let re = try! NSRegularExpression(pattern: #"var\s+courseNameLessonNo\s*=\s*"([^"]*)"\s*;"#)
        let ns = source as NSString
        guard let m = re.firstMatch(in: source, range: NSRange(location: 0, length: ns.length)),
              m.range(at: 1).location != NSNotFound else { return "" }
        return ns.substring(with: m.range(at: 1))
    }

    /// 位图 → 周列表。下标 0 占位, 下标 i=1 即第 i 周 (勿 +1, 四源同证)。
    /// 超长位图 (53/54 位) 天然兼容。
    private func bitmapToWeeks(_ bitmap: String) -> [Int] {
        if bitmap.count > 20 && bitmap.contains(where: { $0 == "8" || $0 == "9" }) {
            // 数值形态长位图: 十进制数 → Long 位掩码, 位 i-1 置位即第 i 周
            if let value = Int64(bitmap) {
                return (1...63).filter { value & (Int64(1) << (UInt64($0) - 1)) != 0 }
            }
            return []
        }
        return bitmap.enumerated().compactMap { i, ch in (i >= 1 && ch == "1") ? i : nil }
    }

    /// index 对 (0基) → (day, startNode, endNode): 排序后连续节次合并成连堂
    private func mergeConsecutiveNodes(_ pairs: [(Int, Int)]) -> (Int, Int, Int) {
        let sorted = pairs.sorted { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            return a.1 < b.1
        }
        let day = sorted.first!.0 + 1
        let nodes = Array(Set(sorted.map { $0.1 + 1 })).sorted()
        // 连续段取首尾 (跨天 index 不该出现在同一块; 出现时取最小段保守处理)
        var start = nodes[0]
        var end = nodes[0]
        for n in nodes.dropFirst() {
            if n == end + 1 { end = n } else { break }
        }
        return (day, start, end)
    }

    private func unquote(_ arg: String) -> String {
        let t = arg.trimmingCharacters(in: .whitespaces)
        let chars = Array(t)
        if chars.count >= 2 && ((chars.first == "\"" && chars.last == "\"") || (chars.first == "'" && chars.last == "'")) {
            return String(chars[1..<(chars.count - 1)])
        }
        return t
    }

    /// 三锚齐中 95 (manualArrangeCourseTable + TaskActivity + unitCount); 仅 TaskActivity 50..79
    var confidenceValue: Int {
        let hasUnitCount = source.range(of: #"\bvar\s+unitCount\s*=\s*\d+\s*;"#, options: .regularExpression) != nil
        if source.contains("manualArrangeCourseTable") && source.contains("new TaskActivity(") && hasUnitCount { return 95 }
        if source.contains("manualArrangeCourseTable") && source.contains("new TaskActivity(") { return 90 }
        if source.contains("new TaskActivity(") {
            return hasUnitCount ? 70 : 55
        }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("manualArrangeCourseTable") { out.append("table#manualArrangeCourseTable") }
        if source.contains("new TaskActivity(") { out.append("new TaskActivity(...)") }
        if source.range(of: #"\bvar\s+unitCount\s*=\s*\d+\s*;"#, options: .regularExpression) != nil { out.append("var unitCount = N") }
        if source.contains("marshalTable") { out.append("table0.marshalTable") }
        if source.contains("courseTableForStd") { out.append("courseTableForStd") }
        return out
    }
}
