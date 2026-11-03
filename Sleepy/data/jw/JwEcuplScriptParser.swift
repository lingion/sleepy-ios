// JwEcuplScriptParser.swift — ← JwEcuplScriptParser.kt
//
// ECUPL script 子协议解析器 — wakeup-parity-ecupl-super-2026-10-06 SOP v1.11。
//
// OpenWakeUp EcuplParser.kt @ 9c2d0436 证实八参 newActivity 携带教师/课名/教室/
// 起始日期与十进制周次位图; addActivityByTime(activity, day, startMin, endMin)
// 由 CourseTable 把分钟映射回节次。本文件是已观察协议事实的独立实现。
//
// 与 Android 的实现差异(等价翻译, 详见各函数注释):
//   a. java.time.LocalDate.parse(严格 ISO) → 手写 ^[0-9]{4}-[0-9]{2}-[0-9]{2}$
//      正则 + 月/日合法域校验 (DateFormatter 宽松解析会把 2026-02-30 顺延)。
//   b. ChronoUnit.WEEKS.between(a, b) = (b.toEpochDay() - a.toEpochDay()) / 7
//      (Java 整除向零截断) → Howard Hinnant days_from_civil 纯算术 epochDay,
//      不经 Date/Calendar 避免 DST 与时区歧义。
//   c. Kotlin Regex \d 默认 ASCII → 一律 [0-9] 字符类 (PR #22 教训:
//      iOS 26 ICU 的 \d 会吞全角数字)。
//   d. Long 位图 toLongOrNull → Int64(s); 超出 Long 域同样判 nil 跳过。

import Foundation

final class JwEcuplScriptParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    // MARK: - 协议指纹 R5/R6/R7 char-by-char 锁定

    /// R5 — CourseTable 起始日 + 时间矩阵 (参数间允许空白/换行, WakeUp smali
    /// 调用常跨多行; DOT_MATCHES_ALL → .dotMatchesLineSeparators)。
    static let reCourseTable = try! NSRegularExpression(
        pattern: "new CourseTable\\(\\s*'([-0-9]+?)'\\s*,\\s*\\[([0-9\\[\\],\\s]+)]\\s*\\)",
        options: [.dotMatchesLineSeparators])
    /// R6 — 时间矩阵 [start_min, end_min]。
    static let reTimePair = try! NSRegularExpression(
        pattern: "\\[([0-9]+)\\s*,\\s*([0-9]+)]")
    /// 五参 legacy fixture 标记; 非已验证的排课来源。
    static let reNewActivity5 = try! NSRegularExpression(
        pattern: "newActivity\\(\\s*\"[^\"]*\"\\s*,\\s*\"[^\"]*\"\\s*,\\s*\"[^\"]*\"\\s*,\\s*\"[01-]+\"\\s*,\\s*[0-9]+\\s*\\)")
    /// 八参 newActivity: g1=教师 g2=课名 g3=教室 g4=起始日 g5=周次位图。
    static let reNewActivity8 = try! NSRegularExpression(
        pattern: "newActivity\\(\\s*\"([^\"]*)\"\\s*,\\s*\"([^\"]*)\"\\s*,\\s*\"([^\"]*)\"\\s*,\\s*\"([^\"]*)\"\\s*,\\s*\"([^\"]*)\"\\s*,\\s*\"([^\"]*)\"\\s*,\\s*\"([0-9-]+)\"\\s*,\\s*([0-9]+)\\s*\\)\\s*;?")
    /// Kotlin `RE_NEW_ACTIVITY = RE_NEW_ACTIVITY_8` 别名。
    static let reNewActivity = JwEcuplScriptParser.reNewActivity8

    /// addActivityByTime(activity, day, startMin, endMin); day 为单个数字。
    private static let reSlot = try! NSRegularExpression(
        pattern: "addActivityByTime\\(\\s*activity\\s*,\\s*([0-9])\\s*,\\s*([0-9]+)\\s*,\\s*([0-9]+)\\s*\\);")
    /// `<script language="JavaScript">` 块体抽取 (IGNORE_CASE)。
    private static let reScript = try! NSRegularExpression(
        pattern: "<script[^>]*language\\s*=\\s*\"?JavaScript\"?[^>]*>([\\s\\S]*?)</script>",
        options: [.caseInsensitive])
    /// newActivity 段起点。
    private static let reActivityStart = try! NSRegularExpression(
        pattern: "newActivity\\s*\\(")
    /// 课名尾部 "(123)" 序号剥离。
    private static let reTrailingIndex = try! NSRegularExpression(
        pattern: "\\([0-9]+\\)$")

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        var out: [JwCourse] = []
        let src = source

        // 协议族验证
        guard let table = Self.firstMatch(Self.reCourseTable, src) else { return out }
        guard let semester = Self.parseIsoDate(table.group(1) ?? "") else { return out }
        let matrix = table.group(2) ?? ""
        var periods: [(Int, Int)?] = []
        for m in Self.allMatches(Self.reTimePair, matrix) {
            let ns = matrix as NSString
            let start = Int(ns.substring(with: m.range(at: 1)))
            let end = Int(ns.substring(with: m.range(at: 2)))
            if let s = start, let e = end, s < e, e <= 1440 {
                periods.append((s, e))
            } else {
                periods.append(nil)
            }
        }
        if periods.isEmpty || periods.contains(where: { $0 == nil }) { return out }

        // 含 CourseTable 调用的 JavaScript script 块 (通知页路径)
        let tableValue = table.group(0) ?? ""
        let script = Self.allMatches(Self.reScript, src)
            .map { (src as NSString).substring(with: $0.range(at: 1)) }
            .first { $0.contains(tableValue) }
        guard let script = script else { return out }

        // 逐 newActivity 段: 段 = 本起点到下一起点 (末段到 script 结尾)
        let scriptNs = script as NSString
        let starts = Self.allMatches(Self.reActivityStart, script).map { $0.range.location }
        for (i, start) in starts.enumerated() {
            let end = i + 1 < starts.count ? starts[i + 1] : scriptNs.length
            let segment = scriptNs.substring(with: NSRange(location: start, length: end - start))
            // Kotlin `activity.find(segment)` + `m.range.first != 0 continue`:
            // 八参调用必须是段首 (五参 legacy 标记不产课)
            guard let m = Self.firstMatch(Self.reNewActivity8, segment), m.range.location == 0 else { continue }
            guard let date = Self.parseIsoDate(m.group(4) ?? "") else { continue }
            guard let bitmap = Int64(m.group(5) ?? "") else { continue }
            // ChronoUnit.WEEKS.between(semester, date): epochDay 差 / 7 (向零截断)
            let offset = (Self.epochDay(date) - Self.epochDay(semester)) / 7
            var weeks: [Int] = []
            for bit in 0..<64 where (bitmap & (Int64(1) << bit)) != 0 {
                weeks.append(bit + offset + 1)
            }
            if weeks.isEmpty || weeks.contains(where: { !(1...64).contains($0) }) { continue }
            let name = Self.replaceMatches(Self.reTrailingIndex, m.group(2) ?? "", with: "")
                .trimmingCharacters(in: .whitespaces)
            let teacher = (m.group(1) ?? "").trimmingCharacters(in: .whitespaces)
            let room = (m.group(3) ?? "").trimmingCharacters(in: .whitespaces)
            if name.isEmpty { continue }

            // 段内 newActivity 匹配结束之后的 addActivityByTime 调用串
            let afterMatch = (segment as NSString).substring(from: m.range.upperBound)
            for slot in Self.allMatches(Self.reSlot, afterMatch) {
                let slotNs = afterMatch as NSString
                let day = Int(slotNs.substring(with: slot.range(at: 1))) ?? 0
                guard let startMinute = Int(slotNs.substring(with: slot.range(at: 2))),
                      let endMinute = Int(slotNs.substring(with: slot.range(at: 3))) else { continue }
                // Kotlin indexOfFirst(...)+1: 未命中时 -1+1=0 → startNode<=0 跳过
                let startNode = (periods.firstIndex { $0?.0 == startMinute }.map { $0 + 1 }) ?? 0
                let endNode = (periods.firstIndex { $0?.1 == endMinute }.map { $0 + 1 }) ?? 0
                if !(1...7).contains(day) || startNode <= 0 || endNode < startNode { continue }
                for range in Self.compactWeeks(weeks) {
                    out.append(JwCourse(
                        name: name, room: room, teacher: teacher,
                        day: day, startNode: startNode, endNode: endNode,
                        startWeek: range.0, endWeek: range.1, type: range.2))
                }
            }
        }
        return out
    }

    // MARK: - 测试辅助 (← internal fun parseWeekBitmap)

    /// '0'/'1' 位图串 (1..30 位) → 单一连续段; 形态不符或多段返回 nil。
    func parseWeekBitmap(_ bitmap: String) -> (Int, Int, Int)? {
        let bits = bitmap.trimmingCharacters(in: .whitespaces)
        guard Self.matchesEntire("^([01]{1,30})$", bits) else { return nil }
        let weeks = bits.enumerated().compactMap { i, c -> Int? in c == "1" ? i + 1 : nil }
        let runs = Self.compactWeeks(weeks)
        return runs.count == 1 ? runs[0] : nil
    }

    // MARK: - 周次段归并 (← private fun compactWeeks)

    /// 连续/单双周步长归并; type: 0=每周 1=单周 2=双周。
    static func compactWeeks(_ weeks: [Int]) -> [(Int, Int, Int)] {
        var pending = Set(weeks)
        var result: [(Int, Int, Int)] = []
        while !pending.isEmpty {
            guard let first = pending.min() else { break }
            let step = pending.contains(first + 1) ? 1 : (pending.contains(first + 2) ? 2 : 1)
            var last = first
            while pending.contains(last + step) { last += step }
            var week = first
            while week <= last {
                pending.remove(week)
                week += step
            }
            result.append((first, last, step == 2 ? (first % 2 == 1 ? 1 : 2) : 0))
        }
        return result
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        var hits = 0
        if Self.firstMatch(Self.reCourseTable, source) != nil { hits += 1 }
        if !Self.allMatches(Self.reTimePair, source).isEmpty { hits += 1 }
        if Self.firstMatch(Self.reNewActivity, source) != nil
            && source.contains("addActivityByTime(") { hits += 1 }
        if source.contains("<script") && source.contains("language=\"JavaScript\"") { hits += 1 }
        switch hits {
        case 4...: return 95
        case 3: return 80
        case 2: return 50
        case 1: return 20
        default: return 0
        }
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if Self.firstMatch(Self.reCourseTable, source) != nil {
            out.append("ecupl-script:r5-newCourseTable")
        }
        let timePairs = Self.allMatches(Self.reTimePair, source).count
        if timePairs >= 1 { out.append("ecupl-script:r6-timePairs(\(timePairs))") }
        if Self.firstMatch(Self.reNewActivity, source) != nil {
            out.append("ecupl-script:r7-newActivity")
        }
        if source.contains("<script") && source.contains("language=\"JavaScript\"") {
            out.append("ecupl-script:script-language-javascript")
        }
        if out.isEmpty { out.append("guard:no-ecupl-script-markers") }
        return out
    }

    // MARK: - 正则/日期辅助

    /// 单次匹配快照: group index → 捕获文本 + 整条匹配 NSRange。
    /// (Kotlin `m.range.first`/`m.range.last` 语义由 range.location/upperBound 承担)
    struct MatchHit {
        let range: NSRange
        let captured: [Int: String]

        func group(_ i: Int) -> String? { captured[i] }
    }

    /// internal: JwEcuplSuperParser.hasNewActivity 复用 (Kotlin companion 同语义)。
    static func firstMatch(_ re: NSRegularExpression, _ s: String) -> MatchHit? {
        let ns = s as NSString
        guard let m = re.firstMatch(
            in: s, options: [],
            range: NSRange(location: 0, length: ns.length)) else { return nil }
        var captured: [Int: String] = [:]
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            guard r.location != NSNotFound, r.length > 0 else { continue }
            captured[i] = ns.substring(with: r)
        }
        return MatchHit(range: m.range, captured: captured)
    }

    private static func allMatches(_ re: NSRegularExpression, _ s: String) -> [NSTextCheckingResult] {
        let ns = s as NSString
        return re.matches(
            in: s, options: [],
            range: NSRange(location: 0, length: ns.length))
    }

    private static func replaceMatches(_ re: NSRegularExpression, _ s: String, with t: String) -> String {
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        return re.stringByReplacingMatches(in: s, options: [], range: full, withTemplate: t)
    }

    private static func matchesEntire(_ pattern: String, _ s: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return false }
        return m.range.location == 0 && m.range.length == ns.length
    }

    /// Java LocalDate.parse 严格语义: ^yyyy-MM-dd$ + 月/日合法域 (含闰年)。
    static func parseIsoDate(_ s: String) -> (year: Int, month: Int, day: Int)? {
        guard let re = try? NSRegularExpression(pattern: "^([0-9]{4})-([0-9]{2})-([0-9]{2})$") else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)),
              m.range.location == 0, m.range.length == ns.length else { return nil }
        guard let y = Int(ns.substring(with: m.range(at: 1))),
              let mo = Int(ns.substring(with: m.range(at: 2))),
              let d = Int(ns.substring(with: m.range(at: 3))) else { return nil }
        guard (1...12).contains(mo) else { return nil }
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let daysInMonth = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][mo - 1]
        guard (1...daysInMonth).contains(d) else { return nil }
        return (y, mo, d)
    }

    /// Howard Hinnant days_from_civil — 纯算术 proleptic Gregorian epochDay,
    /// 语义同 java.time.LocalDate.toEpochDay (无时区/DST 歧义)。
    static func epochDay(_ date: (year: Int, month: Int, day: Int)) -> Int {
        var y = date.year
        if date.month <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (date.month + 9) % 12
        let doy = (153 * mp + 2) / 5 + date.day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }
}
