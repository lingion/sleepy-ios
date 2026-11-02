// JwThuparser.swift — ← JwThuparser.kt
//
// 清华大学 (THU) 教务解析器 — zhjwxk.cic.tsinghua.edu.cn
//
// 协议指纹 (cross-verify, 4 仓 POSITIVE):
// 1. `<form action="/syxk.vsyxkKcapb.do">` + `name="p_xnxq"` 学期字段
// 2. `<script>` 块内 `function setInitValue() {` + `Event.observe(...)`
// 3. C1 `strHTML += "<a class='mainHref' href='.*?;([0-9A-Z]{8})'...>"` 课程链接
// 4. C1 `strHTML += "<b>title</b>"` 课程名 (复用 WakeUp C1 模板)
// 5. C1 `strHTML1 += \；教师\；课程类型\；周次\；地点\` 4 行连续 (中文分号 \；)
// 6. C1 `getElementById("a{big}_{day}").innerHTML += strHTML` 网格坐标
// + C2 模式 `strHTML = "<a class='blue_red_none' ...>` (单行实验课)
//
// 上游: WakeUp THUParser.java (Apache-2.0), Starrah THUCourseHelper (MIT)
// 4/8 仓 cross-verify POSITIVE; schedule-data.netlify 单源独证 1/8, Sleepy 零依赖。
// 跨语言不变式: regex char-by-char 锁定。

import Foundation

// MARK: - Regex helpers (NSRegularExpression capture-group wrapper)

private struct MatchStr {
    let captures: [Int: String]
    subscript(i: Int) -> String { captures[i] ?? "" }
}

private func firstMatchStr(_ pattern: String, in s: String, group: Int) -> String? {
    let m = firstMatchStr(pattern, in: s)
    let v = m?.captures[group] ?? ""
    return v.isEmpty ? nil : v
}

private func firstMatchStr(_ pattern: String, in s: String) -> MatchStr? {
    let ns = try? NSRegularExpression(pattern: pattern, options: [])
    let range = NSRange(s.startIndex..., in: s)
    guard let m = ns?.firstMatch(in: s, options: [], range: range) else { return nil }
    var out: [Int: String] = [:]
    for i in 0..<m.numberOfRanges {
        let r = m.range(at: i)
        guard r.location != NSNotFound && r.length > 0, let range = Range(r, in: s) else { continue }
        out[i] = String(s[range])
    }
    return out.isEmpty ? nil : MatchStr(captures: out)
}

private func matchStr(_ pattern: String, in s: String, groups: [Int]) -> [String]? {
    guard let m = firstMatchStr(pattern, in: s) else { return nil }
    return groups.map { m.captures[$0] ?? "" }
}

private func matchStr(_ pattern: String, in s: String, group: Int = 0) -> String? {
    let m = firstMatchStr(pattern, in: s)
    let v = m?.captures[group] ?? ""
    return v.isEmpty ? nil : v
}

/// Android `Regex.containsMatchIn` 等价物。
private func regexHasMatch(_ pattern: String, in s: String) -> Bool {
    guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
    let range = NSRange(location: 0, length: (s as NSString).length)
    return re.firstMatch(in: s, options: [], range: range) != nil
}

/// Android `Regex.find(input, startIndex)` 等价物 (UTF-16 偏移)。
private func regexFirstMatchRange(_ pattern: String, in s: String, from location: Int) -> NSRange? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let ns = s as NSString
    guard location < ns.length else { return nil }
    let searchRange = NSRange(location: location, length: ns.length - location)
    return re.firstMatch(in: s, options: [], range: searchRange)?.range
}

/// Android `Regex.matches(input)` 等价物 — 全串匹配。
private func regexMatchesEntire(_ pattern: String, in s: String) -> Bool {
    guard let re = try? NSRegularExpression(pattern: "^(" + pattern + ")$", options: []) else { return false }
    let ns = s as NSString
    guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return false }
    return m.range.location == 0 && m.range.length == ns.length
}

/// Android `Regex.findAll(input).map { it.value }` 等价物。
private func regexAllMatches(_ pattern: String, in s: String) -> [String] {
    guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let ns = s as NSString
    return re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
        .map { ns.substring(with: $0.range) }
}

final class JwThuparser: JwParser, JwParserConfidenceReporting {

    let source: String
    init(_ source: String) { self.source = source }

    // MARK: - Static tables (WakeUp THUParser f9220/f9221)

    /// big(0-6) → startNode。0 占位; 1→1; 2→3(连3节); 3→6; 4→8; 5→10; 6→12(连3节)
    static let START_NODE_MAP: [Int] = [0, 1, 3, 6, 8, 10, 12]
    /// big(0-6) → endNode
    static let END_NODE_MAP: [Int] =   [0, 2, 5, 7, 9, 11, 14]
    /// 清华 14 节作息 (4/8 仓共识), index 1-14
    static let THU_TIME_SLOTS: [(String, String)] = [
        ("08:00","08:45"),("08:50","09:35"),("09:50","10:35"),("10:40","11:25"),
        ("11:30","12:15"),("13:30","14:15"),("14:20","15:05"),("15:20","16:05"),
        ("16:10","16:55"),("17:05","17:50"),("17:55","18:40"),("19:20","20:05"),
        ("20:10","20:55"),("21:00","21:45"),
    ]

    // ---- regex constants ----
    // v1.0.62 口径: \d → [0-9] 字符类 (Kotlin Regex \d 默认 ASCII, iOS 26 ICU
    // 的 \d 会吞全角数字, PR #22 教训)。
    static let RE_C1_LINK = #"strHTML \+= "<a class='mainHref' href='.*?;([0-9A-Z]{8})'.*?>"#
    static let RE_C1_TITLE = ##"strHTML \+= "<b>(.*)</b>""##
    static let RE_C1_DATA = ##"strHTML1 \+= ?"；(.*)""##
    static let RE_C1_WEEKBIG = #"getElementById\('a([0-9])_([0-9])'\).innerHTML \+= strHTML"#
    static let RE_C2_BLUE_RED_NONE = ##"strHTML = "<a class='blue_red_none' href='.*?p_id=([0-9A-Z]+)'.*?><b><font color='blue'>(.*?)</font></b></a><font color='blue'>(.*?)</font>";"##
    static let RE_SEMESTER = ##"name="p_xnxq" value="([0-9\-]+?)"##
    static let RE_SET_INIT_VALUE = #"function setInitValue\(\)"#
    static let RE_EVENT_OBSERVE = #"Event\.observe"#
    /// 数字串 — 周次数字解析 (Kotlin RE_NUMBER = \d+ → [0-9]+)。
    static let RE_NUMBER = #"[0-9]+"#

    // ---- state machine ----
    private enum ParseState {
        case idle, gotLink, gotTitle, gotTeacher, gotType, gotWeeks, gotLocation
        // v1.0.62: 已识别 C2, 等待 grid 坐标 (C2 不再即时 emit)
        case gotC2
    }
    private static let defaultWeekCount: Int = 16
    private static let xkTypeList = ["必修", "限选", "任选"]

    /// v1.0.62: 元数据缺项/形态不支持而跳过的课程数 (诊断特征用)。
    /// Kotlin `internal var skippedCourseCount: Int = 0; private set`。
    private(set) var skippedCourseCount: Int = 0

    private struct PendingCourse {
        var courseId: String = ""
        var name: String = ""
        var teacher: String = ""
        var type: String = ""
        var weekText: String = ""
        var location: String = ""
        var isC2: Bool = false  // v1.0.62: C2 与 C1 共用 pending 管线
        var big: Int = 0
        var day: Int = 0
        func copy(big: Int = 0, day: Int = 0) -> PendingCourse {
            var c = self
            c.big = big
            c.day = day
            return c
        }
    }

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        skippedCourseCount = 0
        var out: [JwCourse] = []
        if !source.contains("function setInitValue") || !source.contains("Event.observe") {
            return []
        }
        // Android: RE_SET_INIT_VALUE.find(source) ?: return emptyList() — 需完整 "function setInitValue()"
        guard let startRange = regexFirstMatchRange(Self.RE_SET_INIT_VALUE, in: source, from: 0) else {
            return []
        }
        let startIdx = startRange.location
        // Android: RE_EVENT_OBSERVE.find(source, startIdx) ?: source.length — observe 缺失时解析至源文末尾
        let nsSource = source as NSString
        let endIdx = regexFirstMatchRange(Self.RE_EVENT_OBSERVE, in: source, from: startIdx)?.location ?? nsSource.length
        let jsBlock = nsSource.substring(with: NSRange(location: startIdx, length: max(0, endIdx - startIdx)))
        let lines = jsBlock.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var state = ParseState.idle
        var pending = PendingCourse()
        var foundCourses: [String: PendingCourse] = [:]

        for trimmed in lines {
            // v1.0.62: 上游在元数据缺项时会直接进入网格坐标;
            // 不能把下一门课的字段吞进当前记录 → 截断当前 pending 并计数。
            if state != .idle && (regexHasMatch(Self.RE_C1_LINK, in: trimmed)
                || regexHasMatch(Self.RE_C2_BLUE_RED_NONE, in: trimmed)) {
                skippedCourseCount += 1
                state = .idle
                pending = PendingCourse()
            }
            // v1.0.62: GOT_TITLE/GOT_TEACHER/GOT_TYPE/GOT_WEEKS 阶段网格坐标可提前到达
            // (缺类型/缺周次/缺地点) — 直接 emit, 不再等 GOT_LOCATION。
            if [ParseState.gotTitle, .gotTeacher, .gotType, .gotWeeks].contains(state) {
                if let m = matchStr(Self.RE_C1_WEEKBIG, in: trimmed, groups: [1, 2]) {
                    pending.big = Int(m[0]) ?? 0
                    pending.day = Int(m[1]) ?? 0
                    if let course = emitCourse(pending) {
                        out.append(course)
                    } else {
                        skippedCourseCount += 1
                    }
                    foundCourses[pending.courseId] = pending.copy(big: 0, day: 0)
                    state = .idle
                    pending = PendingCourse()
                    continue
                }
            }
            switch state {
            case .idle:
                // 优先 C2 (单行 blue_red_none 模式, 跨周实验课/辅修)
                // v1.0.62: C2 不再即时 emit — 进 pending 管线等 grid 坐标,
                // 无可用排课信息时由 emitCourse 返回 nil 并计数。
                if let c2 = matchC2(trimmed) {
                    pending = PendingCourse(name: c2.name, location: c2.detail, isC2: true)
                    state = .gotC2
                    continue
                }
                // 否则试 C1 链接
                if let link = matchStr(Self.RE_C1_LINK, in: trimmed, group: 1) {
                    let courseId = link.trimmingCharacters(in: .whitespaces)
                    pending = foundCourses[courseId]?.copy(big: 0, day: 0) ?? PendingCourse(courseId: courseId)
                    state = .gotLink
                }
            case .gotLink:
                if let name = matchStr(Self.RE_C1_TITLE, in: trimmed, group: 1) {
                    pending.name = name
                    foundCourses[pending.courseId] = pending
                    state = .gotTitle
                }
            case .gotTitle:
                if let teacher = matchStr(Self.RE_C1_DATA, in: trimmed, group: 1) {
                    pending.teacher = teacher
                    state = .gotTeacher
                }
            case .gotTeacher:
                if let str = matchStr(Self.RE_C1_DATA, in: trimmed, group: 1) {
                    if Self.xkTypeList.contains(str) {
                        pending.type = str
                        state = .gotType
                    } else {
                        // v1.0.62: 课程属性是可选字段; 缺省时本行就是周次, 不可丢弃。
                        pending.weekText = str
                        state = .gotWeeks
                    }
                }
            case .gotType:
                if let weekText = matchStr(Self.RE_C1_DATA, in: trimmed, group: 1) {
                    pending.weekText = weekText; state = .gotWeeks
                }
            case .gotWeeks:
                if let location = matchStr(Self.RE_C1_DATA, in: trimmed, group: 1) {
                    pending.location = location; state = .gotLocation
                }
            case .gotLocation:
                if let m = matchStr(Self.RE_C1_WEEKBIG, in: trimmed, groups: [1, 2]) {
                    pending.big = Int(m[0]) ?? 0
                    pending.day = Int(m[1]) ?? 0
                    if let course = emitCourse(pending) {
                        out.append(course)
                    } else {
                        skippedCourseCount += 1
                    }
                    // 保留课程 (跨段复用), 重置 big/day
                    foundCourses[pending.courseId] = pending.copy(big: 0, day: 0)
                    state = .idle; pending = PendingCourse()
                }
            case .gotC2:
                if let m = matchStr(Self.RE_C1_WEEKBIG, in: trimmed, groups: [1, 2]) {
                    pending.big = Int(m[0]) ?? 0
                    pending.day = Int(m[1]) ?? 0
                    if let course = emitCourse(pending) {
                        out.append(course)
                    } else {
                        skippedCourseCount += 1
                    }
                    state = .idle
                    pending = PendingCourse()
                }
            }
        }
        // v1.0.62: 收尾仍挂在中间态的残课计一次 skipped
        if state != .idle { skippedCourseCount += 1 }
        return out
    }

    // MARK: - Emit
    /// v1.0.62: emit 失败返回 nil (调用方计 skipped), 不再伪造占位课。
    private func emitCourse(_ p: PendingCourse) -> JwCourse? {
        // Android: p.name.isBlank() — 纯空白名也算空
        guard !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...6).contains(p.big), (1...7).contains(p.day) else { return nil }
        let startNode = Self.START_NODE_MAP[p.big]
        let endNode = Self.END_NODE_MAP[p.big]
        if p.isC2 {
            // v1.0.62: C2 详情可含任意周集合/小时区间;
            // 当前模型不能无损表达时不伪造全周。
            guard p.location.contains("("), p.location.contains(")") else { return nil }
            // substringAfter('(') → substringBeforeLast(')')
            guard let openRange = p.location.range(of: "(") else { return nil }
            let afterOpen = String(p.location[openRange.upperBound...])
            let details: String
            if let lastRange = afterOpen.range(of: ")", options: .backwards) {
                details = String(afterOpen[afterOpen.startIndex..<lastRange.lowerBound])
            } else {
                details = afterOpen
            }
            let parts = details.components(separatedBy: "；")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let weekText = parts.first(where: { $0.contains("周") }) else { return nil }
            if parts.contains(where: { $0.contains("时间：") }) { return nil }
            guard let range = Self.parseKnownWeekText(weekText) else { return nil }
            let room = parts.prefix { !$0.contains("周") }.joined(separator: "；")
            let (sw, ew, type) = range
            let adj = JwParity.adjustedRange(sw, ew, parity: type)
            if adj.start > ew { return nil }
            return JwCourse(
                name: p.name, room: room, teacher: "",
                day: p.day, startNode: startNode, endNode: endNode,
                startWeek: adj.start, endWeek: adj.end, type: type)
        }
        guard let range = Self.parseKnownWeekText(p.weekText) else { return nil }
        let (sw, ew, type) = range
        let adj = JwParity.adjustedRange(sw, ew, parity: type)
        if adj.start > ew { return nil }
        return JwCourse(
            name: p.name,
            room: p.location.trimmingCharacters(in: .whitespaces),
            teacher: p.teacher.trimmingCharacters(in: .whitespaces),
            day: p.day, startNode: startNode, endNode: endNode,
            startWeek: adj.start, endWeek: adj.end, type: type)
    }

    // MARK: - C2 (blue_red_none)
    private struct C2Match {
        let id: String
        let name: String
        let detail: String
    }
    private func matchC2(_ line: String) -> C2Match? {
        guard let m = firstMatchStr(Self.RE_C2_BLUE_RED_NONE, in: line) else { return nil }
        return C2Match(id: m[1], name: m[2], detail: m[3])
    }

    // MARK: - Week text parsing
    /// v1.0.62: 解析已知周次文字; 未知或越界返回 nil, 不伪造全周:
    ///  "全周"→(1,16,0); "前八周"→(1,8,0); "后八周"→(9,16,0);
    ///  "单周"→(1,16,1); "双周"→(2,16,2);
    ///  "X-Y周"→(X,Y,0); "第X-Y周"→(X,Y,0); "第X-Y周(单/双)"→(X,Y,1/2); "第X周"→(X,X,0)
    static func parseKnownWeekText(_ text: String) -> (startWeek: Int, endWeek: Int, parity: Int)? {
        // Android: text.trim().trimStart('；',';') — 只去前导分号, 保留尾部分号
        let spaceTrimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = String(spaceTrimmed.drop { $0 == "\u{FF1B}" || $0 == ";" })
        var parsed: (Int, Int, Int)?
        if t == "全周" {
            parsed = (1, Self.defaultWeekCount, 0)
        } else if t == "前八周" {
            parsed = (1, 8, 0)
        } else if t == "后八周" {
            parsed = (9, Self.defaultWeekCount, 0)
        } else if t == "单周" {
            parsed = (1, Self.defaultWeekCount, 1)
        } else if t == "双周" {
            parsed = (2, Self.defaultWeekCount, 2)
        } else if regexMatchesEntire(#"[0-9]+-[0-9]+周"#, in: t)
            || regexMatchesEntire(#"第[0-9]+-[0-9]+周（单）"#, in: t)
            || regexMatchesEntire(#"第[0-9]+-[0-9]+周\(单\)"#, in: t)
            || regexMatchesEntire(#"第[0-9]+-[0-9]+周（双）"#, in: t)
            || regexMatchesEntire(#"第[0-9]+-[0-9]+周\(双\)"#, in: t)
            || regexMatchesEntire(#"第[0-9]+-[0-9]+周"#, in: t) {
            // RE_NUMBER.findAll 取全部数字; Kotlin `?: return null` → 整体 nil
            let nums = regexAllMatches(Self.RE_NUMBER, in: t).compactMap { Int($0) }
            guard nums.count >= 2 else { return nil }
            let parity: Int
            if regexMatchesEntire(#"第[0-9]+-[0-9]+周（单）"#, in: t) || regexMatchesEntire(#"第[0-9]+-[0-9]+周\(单\)"#, in: t) {
                parity = 1
            } else if regexMatchesEntire(#"第[0-9]+-[0-9]+周（双）"#, in: t) || regexMatchesEntire(#"第[0-9]+-[0-9]+周\(双\)"#, in: t) {
                parity = 2
            } else {
                parity = 0
            }
            parsed = (nums[0], nums[1], parity)
        } else if regexMatchesEntire(#"第[0-9]+周"#, in: t) {
            guard let n = regexAllMatches(Self.RE_NUMBER, in: t).first.flatMap({ Int($0) }) else { return nil }
            parsed = (n, n, 0)
        }
        guard let (sw, ew, parity) = parsed,
              (1...30).contains(sw), (sw...30).contains(ew) else { return nil }
        return (sw, ew, parity)
    }

    /// 兼容 shim: v1.0.61 静态 parseWeekText 签名 (既有单测仍在调用)。
    /// v1.0.62 起解析路径走 parseKnownWeekText (nil=跳过不伪造);
    /// shim 仅把"未知文字"回落到旧默认 (1,16,0), 已知文字行为不变。
    internal static func parseWeekText(_ text: String) -> (startWeek: Int, endWeek: Int, parity: Int) {
        parseKnownWeekText(text) ?? (1, Self.defaultWeekCount, 0)
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        JwThuparser.confidenceValueFor(source: source)
    }
    var matchedFeatureList: [String] {
        JwThuparser.matchedFeaturesFor(source: source, skippedCount: skippedCourseCount)
    }

    // MARK: - Static confidence (协议指纹 6 件套)
    /// Android confidence(): 6 个 regex containsMatchIn 计 hits,
    /// hits>=6→95, 5→80, 4→70, 3→50, 2→30, 1→10, else 0 (阶梯映射, 与 Registry 打分对齐)。
    static func confidenceValueFor(source: String) -> Int {
        var hits = 0
        if regexHasMatch(RE_SEMESTER, in: source) { hits += 1 }
        if regexHasMatch(RE_SET_INIT_VALUE, in: source) { hits += 1 }
        if regexHasMatch(RE_C1_LINK, in: source) { hits += 1 }
        if regexHasMatch(RE_C1_TITLE, in: source) { hits += 1 }
        if regexHasMatch(RE_C1_WEEKBIG, in: source) { hits += 1 }
        if regexHasMatch(RE_C1_DATA, in: source) { hits += 1 }
        if hits >= 6 { return 95 }
        if hits >= 5 { return 80 }
        if hits >= 4 { return 70 }
        if hits >= 3 { return 50 }
        if hits >= 2 { return 30 }
        if hits >= 1 { return 10 }
        return 0
    }
    /// Android matchedFeatures(): 8 项特征检查 (v1.0.62 首位 thu:skipped-unsupported=N),
    /// 仅当特征列表为空时追加 guard 项 (不对 login-only 页面短路)。
    static func matchedFeaturesFor(source: String, skippedCount: Int = 0) -> [String] {
        var feats: [String] = []
        if skippedCount > 0 { feats.append("thu:skipped-unsupported=\(skippedCount)") }
        if source.contains("zhjwxk") || source.contains("cic.tsinghua") {
            feats.append("thu:login-or-sso-marker")
        }
        if regexHasMatch(RE_SEMESTER, in: source) { feats.append("thu:p_xnxq-form") }
        if regexHasMatch(RE_SET_INIT_VALUE, in: source) { feats.append("thu:setInitValue-block") }
        if regexHasMatch(RE_C1_LINK, in: source) { feats.append("thu:strHTML-course-link") }
        if regexHasMatch(RE_C1_WEEKBIG, in: source) { feats.append("thu:aN_M-innerHTML") }
        if Self.xkTypeList.contains(where: { source.contains($0) }) { feats.append("thu:xktype-必修/限选/任选") }
        if regexHasMatch(RE_C1_DATA, in: source) { feats.append("thu:week-text-grammar") }
        if feats.isEmpty { feats.append("guard:login-only-no-setInitValue") }
        return feats
    }
}
