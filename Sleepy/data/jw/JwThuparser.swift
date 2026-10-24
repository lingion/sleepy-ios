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
    static let RE_C1_LINK = #"strHTML \+= "<a class='mainHref' href='.*?;([0-9A-Z]{8})'.*?>"#
    static let RE_C1_TITLE = ##"strHTML \+= "<b>(.*)</b>""##
    static let RE_C1_DATA = ##"strHTML1 \+= ?"；(.*)""##
    static let RE_C1_WEEKBIG = #"getElementById\('a(\d)_(\d)'\).innerHTML \+= strHTML"#
    static let RE_C2_BLUE_RED_NONE = ##"strHTML = "<a class='blue_red_none' href='.*?p_id=([0-9A-Z]+)'.*?><b><font color='blue'>(.*?)</font></b></a><font color='blue'>(.*?)</font>";"##
    static let RE_SEMESTER = ##"name="p_xnxq" value="([\d\-]+?)"##
    static let RE_SET_INIT_VALUE = #"function setInitValue\(\)"#
    static let RE_EVENT_OBSERVE = #"Event\.observe"#

    // ---- state machine ----
    private enum ParseState {
        case idle, gotLink, gotTitle, gotTeacher, gotType, gotWeeks, gotLocation
    }
    private static let defaultWeekCount: Int = 16
    private static let xkTypeList = ["必修", "限选", "任选"]

    private struct PendingCourse {
        var courseId: String = ""
        var name: String = ""
        var teacher: String = ""
        var type: String = ""
        var weekText: String = ""
        var location: String = ""
        var big: Int = 0
        var day: Int = 0
        func copy(big: Int = 0, day: Int = 0) -> PendingCourse {
            PendingCourse(courseId: courseId, name: name, teacher: teacher,
                          type: type, weekText: weekText, location: location,
                          big: big, day: day)
        }
    }

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
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
        var out: [JwCourse] = []

        for trimmed in lines {
            switch state {
            case .idle:
                if let c2 = matchC2(trimmed) {
                    out += parseBlueRedNone(name: c2.name, detStr: c2.detail)
                    continue
                }
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
                    if Self.xkTypeList.contains(str) { pending.type = str; state = .gotType }
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
                    let big = Int(m[0]) ?? 0
                    let day = Int(m[1]) ?? 0
                    pending.big = big; pending.day = day
                    out += emitCourse(pending)
                    foundCourses[pending.courseId] = pending.copy(big: 0, day: 0)
                    state = .idle; pending = PendingCourse()
                }
            }
        }
        return out
    }

    // MARK: - Emit
    private func emitCourse(_ p: PendingCourse) -> [JwCourse] {
        // Android: p.name.isBlank() — 纯空白名也算空
        guard !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              (1...6).contains(p.big), (1...7).contains(p.day) else { return [emptyCourse(p.name)] }
        let startNode = Self.START_NODE_MAP[p.big]
        let endNode = Self.END_NODE_MAP[p.big]
        if startNode == 0 || endNode == 0 { return [emptyCourse(p.name)] }
        let (sw, ew, type) = Self.parseWeekText(p.weekText)
        let adj = JwParity.adjustedRange(sw, ew, parity: type)
        return [JwCourse(
            name: p.name,
            room: p.location.trimmingCharacters(in: .whitespaces),
            teacher: p.teacher.trimmingCharacters(in: .whitespaces),
            day: p.day, startNode: startNode, endNode: endNode,
            startWeek: adj.start, endWeek: adj.end, type: type
        )]
    }
    private func emptyCourse(_ name: String) -> JwCourse {
        JwCourse(name: name, room: "", teacher: "", day: 0, startNode: 0, endNode: 0, startWeek: 0, endWeek: 0, type: 0)
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
    /// C2 (blue_red_none) — 跨周实验课/辅修。
    /// name = `<font color=blue>` 第1段 课程名; detail = 第2段 blue font (周次/地点).
    private func parseBlueRedNone(name: String, detStr: String) -> [JwCourse] {
        // Android: detStr.trim() 同时去掉换行
        return [JwCourse(name: name, room: detStr.trimmingCharacters(in: .whitespacesAndNewlines), teacher: "",
            day: 0, startNode: 0, endNode: 0,
            startWeek: 1, endWeek: Self.defaultWeekCount, type: 0)
        ]
    }

    // MARK: - Week text parsing
    /// "全周"→(1,16,0); "前八周"→(1,8,0); "后八周"→(9,16,0); "单周"→(1,16,1); "双周"→(2,16,2)
    /// "第X-Y周（单/双）" / "第X-Y周(单/双)"; "第X-Y周"; "第X周"
    internal static func parseWeekText(_ text: String) -> (startWeek: Int, endWeek: Int, parity: Int) {
        // Android: text.trim().trimStart('；',';') — 只去前导分号, 保留尾部分号
        let spaceTrimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = String(spaceTrimmed.drop { $0 == "\u{FF1B}" || $0 == ";" })
        if t == "全周" { return (1, Self.defaultWeekCount, 0) }
        if t == "前八周" { return (1, 8, 0) }
        if t == "后八周" { return (9, Self.defaultWeekCount, 0) }
        if t == "单周" { return (1, Self.defaultWeekCount, 1) }
        if t == "双周" { return (2, Self.defaultWeekCount, 2) }
        // Android 走 t.matches(...) 全串匹配 → iOS 用 ^…$ 锚定;
        // 全角（单/双）与半角(单/双) 分别匹配, 混用括号不匹配 (与 Android 两分支语义一致)
        let parityFullRe = #"^第(\d+)-(\d+)周（(单|双)）$"#
        let parityHalfRe = #"^第(\d+)-(\d+)周\((单|双)\)$"#
        if let m = matchStr(parityFullRe, in: t, groups: [1, 2, 3]) ?? matchStr(parityHalfRe, in: t, groups: [1, 2, 3]) {
            let sw = Int(m[0]) ?? 1, ew = Int(m[1]) ?? sw
            let p = m[2] == "单" ? 1 : 2
            return (sw, ew, p)
        }
        let rangeRe = #"^第(\d+)-(\d+)周$"#
        if let m = matchStr(rangeRe, in: t, groups: [1, 2]) {
            let sw = Int(m[0]) ?? 1, ew = Int(m[1]) ?? sw
            return (sw, ew, 0)
        }
        let singleRe = #"^第(\d+)周$"#
        if let m = matchStr(singleRe, in: t, groups: [1]) {
            let sw = Int(m[0]) ?? 1
            return (sw, sw, 0)
        }
        return (1, Self.defaultWeekCount, 0)
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        JwThuparser.confidenceValueFor(source: source)
    }
    var matchedFeatureList: [String] {
        JwThuparser.matchedFeaturesFor(source: source)
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
    /// Android matchedFeatures(): 7 项特征检查 (含 thu:login-or-sso-marker),
    /// 仅当特征列表为空时追加 guard 项 (不对 login-only 页面短路)。
    static func matchedFeaturesFor(source: String) -> [String] {
        var feats: [String] = []
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
