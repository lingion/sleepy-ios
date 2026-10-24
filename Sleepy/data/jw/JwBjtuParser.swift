// JwBjtuParser.swift — ← JwBjtuParser.kt
//
// 北京交通大学教学支撑平台 (AA, aa.bjtu.edu.cn) 课表解析器 — issue #19 适配
// (教务跨仓验证 SOP, 2026-09-09)。
//
// # 协议证据
// BJTU = 自研 Django 系 (CAS SSO + MIS 门户桥 + AA 教学支撑平台)。7 维对比矩阵与
// 24 候选逐仓 verdict 见 docs/bjtu-cross-verify-2026-09-09/ (POSITIVE 12 / INDIRECT 7 /
// NULL_EVIDENCE 2 / NEGATIVE 2 / FETCH_FAILED 1)。与 Sleepy 既有协议族 (正方/强智/金智/
// URP/jwglxt/自建门户 REST) 均不同构, 故独立 TYPE_BJTU。
//
// # 数据路径 (WebView 会话内同源 fetch, 无学期/周次参数 — 服务端按会话决定)
//   GET /course_selection/courseselect/stuschedule/    本学期课表
//   GET /course_selection/courseselecttask/schedule/   选课任务课表 (全学期)
// 证据仓: HFDLYS/BJTUselfService (MIT) + wan300/bjtu_mis_Android (MIT) 双仓独立证实。
// 两段 HTML 以 [DOC_MARKER_PREFIX] 标记拼成一个 source 喂给本 parser, 段间独立解析、
// 取课程数最多者 (并列时 schedule 全学期优先) — 单端点失败不拖垮另一端点。
//
// # 页面形状 (三仓交叉一致)
//   table.table, 表头 th = 星期一..星期日; 数据行首格 = `第N节 <span>[HH:MM-HH:MM]</span>`;
//   课程格 div 块 = code 前缀 `[A-Z]\d+[A-Z]? [NN]` + span 课名 + 内层 div `第01-16周 <i>教师</i>`
//   + span.text-muted 教室 "校区, 楼, 室"; 变体 div.ellipsis[title=完整文本]。
// 节次时间: 页面行首格自带 [HH:MM-HH:MM] (权威, 由 BJTU_FETCH_JS 抽出随 periods 回传);
// 周次文法: 第A-B周 / 第2,4,6周 / 第X周 + (单/双)奇偶后缀。
//
// # 已知上游 bug (禁复制)
// fish2lab/bjtu-cli 的 parseCourseWeeks 先剥 "第/周" 再 regex, 单/双后缀信息丢失 —
// 本 parser 保留原文全文匹配 ([WEEK_NUM_RE] + 奇偶过滤), 不剥前后缀。

import Foundation
import SwiftSoup

final class JwBjtuParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    /// JwCourse.type 契约: 0=每周 1=单周 2=双周
    static let TYPE_DEFAULT = 0
    static let TYPE_ODD = 1
    static let TYPE_EVEN = 2

    /// 组合源分段标记: `<mark>label</mark>-->HTML`, label ∈ {stuschedule, schedule}
    static let DOC_MARKER_PREFIX = "<!--sleepy-bjtu-doc:"

    /// AA 课表数据端点 (相对 aa.bjtu.edu.cn, WebView 同源 fetch)
    static let PATH_STUSCHEDULE = "/course_selection/courseselect/stuschedule/"
    static let PATH_SCHEDULE = "/course_selection/courseselecttask/schedule/"

    /// host 锚点 (schools.json url 与 WebView 落地页校验用)
    static let HOST_SUFFIX = "bjtu.edu.cn"

    /// 跨语言 invariant 源码常量 (SOP 铁律 3): JwWebViewLoginScreen 的 BJTU_FETCH_JS
    /// 里 `new RegExp('...')` 的 JS 字符串字面量必须与这里逐字符相等,
    /// JwBjtuParserTest 断言锁死。Kotlin 侧 `\\s` 在文件源码里就是反斜杠+s 两个字符,
    /// JS 字符串字面量 '第\\s*(\\d+)\\s*节' 解析后正是同一 regex 文本。
    static let PERIOD_LABEL_RE_SRC = "第\\s*(\\d+)\\s*节"
    static let PERIOD_TIME_RE_SRC = "(\\d{1,2}:\\d{2})\\s*[-–—~至]\\s*(\\d{1,2}:\\d{2})"

    private static let PERIOD_LABEL_RE = PERIOD_LABEL_RE_SRC
    private static let PERIOD_TIME_RE = PERIOD_TIME_RE_SRC

    /// 周次文法 (矩阵 D4 canonical, wan300 仓实锚): 完整形态必以 第 开头、以 周 收口,
    /// 枚举分隔符 ,，、 与范围分隔符 -~—–－至到 都在形态内部; 可带 (单/双) 奇偶后缀。
    /// 锚定形态是刻意的: 教室 "3-302" 这类裸数字段禁被当成周次, 教师姓氏 "单"
    /// 禁被当成奇偶过滤 — 只在形态匹配区内取数。
    private static let WEEK_FORM_RE =
        #"第[\d,，、\s\-~—–－至到]+?周(?:\s*[（(]\s*(单|双)\s*[）)])?"#

    /// 形态内的数字/范围 token (仅在 WEEK_FORM_RE 命中区内使用)
    private static let WEEK_NUM_RE = #"(\d{1,2})(?:\s*[-~—–－至到]\s*(\d{1,2}))?"#

    /// 异族协议负锚点: 命中即非 BJTU 页面 (防 fallback 裁决在正方/强智/jwglxt 页误抢)
    private static let FOREIGN_ANCHOR_RE = #"jwglxt|xskbcx|zftal|default2\.aspx|xs_main|jqGrid"#

    /// 登录/失效页锚点 (矩阵 D7): AA 自登录路径或 Django csrf 表单
    private static let LOGIN_PAGE_RE = #"/client/login/|csrfmiddlewaretoken"#

    /// 表头星期锚点: 课表页必有, 登录页必无 — 双向判别用
    private static let DAY_ANCHOR = "星期一"

    /// 表头 星期X → 1..7 (日/天 都算第 7)
    private static let DAY_HEADER_NAMES: [(String, Int)] = [
        ("一", 1), ("二", 2), ("三", 3), ("四", 4), ("五", 5), ("六", 6), ("日", 7), ("天", 7),
    ]

    /// 周次上限 (防病态大数展开; AA 学期最长 25 周)
    private static let MAX_WEEK = 30

    /// 可表示周次段: startWeek..endWeek + type (每周/单周/双周)
    struct WeekRun: Hashable {
        let startWeek: Int
        let endWeek: Int
        let type: Int
    }

    /// 课程格块解析中间态 (合并前)
    private struct BlockInfo {
        let name: String
        let day: Int
        let node: Int
        let weeksText: String
        let teacher: String
        let room: String
    }

    // MARK: - 组合源切段

    /// 组合源切段: 无标记 → 整体一段 ("plain"); 有标记 → 逐段 (label, body)。
    /// 标记内 label 截到 "-->", body 到下一个标记或文末。
    static func sections(_ source: String) -> [(String, String)] {
        if !source.contains(DOC_MARKER_PREFIX) { return [("plain", source)] }
        var out: [(String, String)] = []
        var idx = source.range(of: DOC_MARKER_PREFIX)
        while let r = idx {
            let labelStart = r.upperBound
            guard let arrow = source.range(of: "-->", range: labelStart..<source.endIndex) else { break }
            let label = String(source[labelStart..<arrow.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let bodyStart = arrow.upperBound
            let next = source.range(of: DOC_MARKER_PREFIX, range: bodyStart..<source.endIndex)
            let bodyEnd = next?.lowerBound ?? source.endIndex
            out.append((label, String(source[bodyStart..<bodyEnd])))
            idx = next
        }
        return out
    }

    // MARK: - 周次解析

    /// 周次文本 → 可表示周次段列表 (逐形态展开)。
    ///   "第1-16周(单)"   → [1..15 单周]
    ///   "第1-16周（双）"  → [2..16 双周]
    ///   "第01-16周"      → [1..16 每周]
    ///   "第2,4,6周"      → [2..6 双周] (步长 2 连续 → 奇偶段, UCAS splitWeekRuns 同构)
    ///   "第1-4,6-10周"   → [1..4 每周] + [6..10 每周] (缺口断段)
    ///   "第1-8周 第9-16周" → 两形态 → 两段
    /// 奇偶后缀只在形态收口括号内识别 — 教室数字 ("3-302") 与教师姓氏 ("单")
    /// 不在形态区内, 不受影响。
    /// 返回空 = 文本无可表示周次 (调用方跳过该块, 禁编造 1-16 占位)。
    static func parseWeekRuns(_ text: String) -> [WeekRun] {
        var out: [WeekRun] = []
        for form in matches(text, WEEK_FORM_RE) {
            let formText = form.0
            var nums: [(Int, Int?)] = []
            for m in matches(formText, WEEK_NUM_RE) {
                guard let a = Int(m.1) else { continue }
                let b = m.2.isEmpty ? nil : Int(m.2)
                nums.append((a, b))
            }
            if nums.isEmpty { continue }
            let parity: Int
            switch form.1 {
            case "单": parity = 1
            case "双": parity = 0
            default: parity = -1
            }
            var weeks = Set<Int>()
            for (a, b) in nums {
                // 逆序区间 (如 第16-2周) 对齐 Kotlin a..(b ?: a) 的空区间语义: 跳过, 不产周次。
                // Swift 的 a...hi 在 a > hi 时触发 ClosedRange 前置条件 trap, 必须先挡。
                let hi = b ?? a
                if a > hi { continue }
                for w in a...hi where (1...MAX_WEEK).contains(w) { weeks.insert(w) }
            }
            let filtered = parity >= 0 ? weeks.filter { $0 % 2 == parity } : Array(weeks)
            if filtered.isEmpty { continue }
            // 步长切段 (UCAS splitWeekRuns 同构): 步长 1 连续 = 每周段,
            // 步长 2 连续 = 单/双周段, 缺口/步长切换处断段
            var runStart = 0
            var prev = 0
            var step = 0
            for w in filtered.sorted() {
                if runStart == 0 {
                    runStart = w; prev = w; step = 0
                } else if w == prev + 1 && step != 2 {
                    prev = w; step = 1
                } else if w == prev + 2 && step != 1 {
                    prev = w; step = 2
                } else {
                    out.append(mkRun(runStart, prev, step))
                    runStart = w; prev = w; step = 0
                }
            }
            out.append(mkRun(runStart, prev, step))
        }
        // 去重 (ellipsis 块 title 与内层 div 会给出同一 第A-B周 形态两遍)
        var seen = Set<WeekRun>()
        var distinct: [WeekRun] = []
        for r in out where !seen.contains(r) {
            seen.insert(r)
            distinct.append(r)
        }
        return distinct
    }

    /// 步长 → JwCourse.type: 步长 2 连续段按段首奇偶定单/双, 其余每周
    private static func mkRun(_ startWeek: Int, _ endWeek: Int, _ step: Int) -> WeekRun {
        WeekRun(
            startWeek: startWeek,
            endWeek: endWeek,
            type: step == 2
                ? (startWeek % 2 == 1 ? TYPE_ODD : TYPE_EVEN)
                : TYPE_DEFAULT)
    }

    /// 表头文本 星期X/礼拜X/周X → 1..7; 其余 0
    static func dayOfWeek(_ text: String) -> Int {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t.count > 4 { return 0 }
        for (suffix, day) in DAY_HEADER_NAMES {
            if t == "星期\(suffix)" || t == "礼拜\(suffix)" || t == "周\(suffix)" { return day }
        }
        return 0
    }

    /// 静态表锚点 (无标记路径的 confidence 来源): 星期表头 + 节次行首 + 周次文法齐备,
    /// 且无异族协议锚点。
    static func hasTableAnchors(_ s: String) -> Bool {
        s.contains(DAY_ANCHOR)
            && s.range(of: PERIOD_LABEL_RE, options: .regularExpression) != nil
            && s.contains("周")
            && s.range(of: FOREIGN_ANCHOR_RE, options: .regularExpression) == nil
    }

    /// 登录/失效页判别 (矩阵 D7): 命中登录锚点 且 无课表表头锚点。
    /// 后半条防误杀 — AA 真课表页内嵌 Django 表单时也会带 csrfmiddlewaretoken。
    static func isLoginLike(_ body: String) -> Bool {
        body.range(of: LOGIN_PAGE_RE, options: .regularExpression) != nil && !body.contains(DAY_ANCHOR)
    }

    // MARK: - 主入口

    func generateCourseList() throws -> [JwCourse] {
        // 异族协议守卫: 正方/强智/jwglxt 形态页面不是 AA 课表, 防误抢 (含 declaredType 强制分发误用)。
        if !source.contains(Self.DOC_MARKER_PREFIX)
            && source.range(of: Self.FOREIGN_ANCHOR_RE, options: .regularExpression) != nil {
            return []
        }
        // 段间独立解析: 每段 (label, courses), 登录页段跳过; 取课程数最多者,
        // 并列时段优先级 schedule(全学期)=2 > stuschedule(本学期)=1 > 其他=0。
        struct Candidate {
            let label: String
            let courses: [JwCourse]
        }
        var candidates: [Candidate] = []
        for (label, body) in Self.sections(source) {
            if Self.isLoginLike(body) { continue }
            guard let courses = parseTable(body) else { continue }
            if courses.isEmpty { continue }
            candidates.append(Candidate(label: label, courses: courses))
        }
        return candidates.max { a, b in
            if a.courses.count != b.courses.count { return a.courses.count < b.courses.count }
            return sectionPriority(a.label) < sectionPriority(b.label)
        }?.courses ?? []
    }

    /// 段优先级: schedule(全学期)=2 > stuschedule(本学期)=1 > 其他=0
    private func sectionPriority(_ label: String) -> Int {
        switch label {
        case "schedule": return 2
        case "stuschedule": return 1
        default: return 0
        }
    }

    // MARK: - 表格解析

    /// 解析一段课表 HTML。定位表头行 (≥5 个星期格) → 逐数据行 (行首格 第N节) →
    /// 逐课程格块 → 分组 (名|周次文本|教室|星期) 合并相邻节次 → 段×周次段展开。
    /// 返回 nil = 找不到表头 (非课表页)。
    private func parseTable(_ html: String) -> [JwCourse]? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        var dayStartCol = -1
        let allTrs = ((try? doc.select("tr")) ?? Elements()).array()
        for tr in allTrs {
            let cells = tableCells(tr)
            var firstDayCol: Int? = nil
            for (i, c) in cells.enumerated() {
                if Self.dayOfWeek(((try? c.text()) ?? "")) > 0 { firstDayCol = i; break }
            }
            if let f = firstDayCol, cells.count - f >= 5 {
                dayStartCol = f
                break
            }
        }
        if dayStartCol < 0 { return nil }

        var infos: [BlockInfo] = []
        for tr in allTrs {
            let cells = tableCells(tr)
            if cells.isEmpty { continue }
            let firstText = ((try? cells[0].text()) ?? "")
            guard let node = Self.firstPeriodLabel(firstText) else { continue }
            let upper = min(dayStartCol + 7, cells.count)
            guard dayStartCol < upper else { continue }
            for col in dayStartCol..<upper {
                let day = col - dayStartCol + 1
                for block in cellBlocks(cells[col]) {
                    let name = courseNameOf(block)
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    // part = 一个授课班次 (一个周次 div), 教师与周次段一一对应;
                    // ellipsis 块的 title 属性即完整文本, 单 part, 不与内层 div 重复展开。
                    for (weeksText, teacher) in partsOf(block) {
                        infos.append(BlockInfo(
                            name: name,
                            day: day,
                            node: node,
                            weeksText: weeksText,
                            teacher: teacher,
                            room: roomOf(block)))
                    }
                }
            }
        }

        var courses: [JwCourse] = []
        var groups: [String: [BlockInfo]] = [:]
        var groupOrder: [String] = []
        for b in infos {
            let key = "\(b.name)|\(b.weeksText)|\(b.room)|\(b.day)"
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append(b)
        }
        for key in groupOrder {
            let members = groups[key]!
            let first = members[0]
            let runs = Self.parseWeekRuns(first.weeksText)
            if runs.isEmpty { continue }
            // 同组相邻节次合并 (10,11 → 10-11); 缺口 >1 断段
            var segments: [(Int, Int)] = []
            let nodes = members.map { $0.node }
            var seenNodes = Set<Int>()
            for n in nodes where !seenNodes.contains(n) {
                seenNodes.insert(n)
            }
            for n in seenNodes.sorted() {
                if let last = segments.last, n == last.1 + 1 {
                    segments[segments.count - 1] = (last.0, n)
                } else {
                    segments.append((n, n))
                }
            }
            for seg in segments {
                for run in runs {
                    courses.append(JwCourse(
                        name: first.name,
                        room: first.room,
                        teacher: first.teacher,
                        day: first.day,
                        startNode: seg.0,
                        endNode: seg.1,
                        startWeek: run.startWeek,
                        endWeek: run.endWeek,
                        type: run.type))
                }
            }
        }
        return courses
    }

    /// "第N节" → N (首个匹配)
    private static func firstPeriodLabel(_ text: String) -> Int? {
        guard let r = text.range(of: PERIOD_LABEL_RE, options: .regularExpression) else { return nil }
        let m = String(text[r])
        guard let digitRange = m.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(String(m[digitRange]))
    }

    /// 行内单元格序列 (th/td, 保序)
    private func tableCells(_ tr: Element) -> [Element] {
        ((try? tr.children()) ?? Elements()).array().filter { el in
            let tag = (try? el.tagName()) ?? ""
            return tag == "th" || tag == "td"
        }
    }

    /// 课程格 → 课程块列表: 直接子 div 且非空 (真实形态一课一块);
    /// 无子 div 时整格当一个块 (宽容形态)。
    private func cellBlocks(_ cell: Element) -> [Element] {
        let divs = ((try? cell.select("> div")) ?? Elements()).array().filter {
            !((try? $0.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return divs.isEmpty ? [cell] : divs
    }

    /// 课名: 第一个非 text-muted 的 span; 兜底 code 前缀 `]` 之后文本
    private func courseNameOf(_ block: Element) -> String {
        let spans = ((try? block.select("span")) ?? Elements()).array()
        for span in spans {
            let cls = (try? span.hasClass("text-muted")) ?? false
            let text = ((try? span.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cls && !text.isEmpty { return text }
        }
        let text = ((try? block.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let bracket = text.firstIndex(of: "]"), bracket < text.index(before: text.endIndex) {
            return String(text[text.index(after: bracket)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// 课程块 → (周次文本, 教师) part 列表, part = 一个授课班次 (一个周次 div)。
    /// - ellipsis 块: title 属性即完整文本 → 单 part (title, 块内全部 i), 不与内层 div 重复。
    /// - 普通块: 每个含 周 的内层 div 一个 part, 教师取该 div 内的 i 标签。
    /// 返回空 = 无可解析周次 (调用方跳过, 禁编造)。
    private func partsOf(_ block: Element) -> [(String, String)] {
        let title = (try? block.attr("title")) ?? ""
        if title.contains("周") {
            return [(title, teacherOf(block))]
        }
        var parts: [(String, String)] = []
        // 只取直接子 div (jsoup 的 select("div") 会把 block 自身也算进结果, 会让每课翻倍)
        for d in ((try? block.children()) ?? Elements()).array() {
            guard (try? d.tagName()) ?? "" == "div" else { continue }
            let t = (try? d.text()) ?? ""
            if t.contains("周") {
                var teachers: [String] = []
                for i in ((try? d.select("i")) ?? Elements()).array() {
                    let v = ((try? i.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { teachers.append(v) }
                }
                // distinct 保序
                var seen = Set<String>()
                let distinct = teachers.filter { seen.insert($0).inserted }
                parts.append((t, distinct.joined(separator: ",")))
            }
        }
        // distinctBy { it.first }
        var seenKeys = Set<String>()
        return parts.filter { seenKeys.insert($0.0).inserted }
    }

    /// 教师: 块内全部 i 标签 (ellipsis/title 路径用)
    private func teacherOf(_ block: Element) -> String {
        var teachers: [String] = []
        for i in ((try? block.select("i")) ?? Elements()).array() {
            let v = ((try? i.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { teachers.append(v) }
        }
        var seen = Set<String>()
        return teachers.filter { seen.insert($0).inserted }.joined(separator: ",")
    }

    /// 教室: span.text-muted ("校区, 楼, 室" 形态)
    private func roomOf(_ block: Element) -> String {
        for span in ((try? block.select("span.text-muted")) ?? Elements()).array() {
            let v = ((try? span.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        return ""
    }

    // MARK: - 正则辅助

    /// 全部匹配, 返回 [(全文, 组1, 组2)]
    private static func matches(_ text: String, _ pattern: String) -> [(String, String, String)] {
        let re = try! NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        var out: [(String, String, String)] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let full = ns.substring(with: m.range)
            let g1 = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ""
            let g2 = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
            out.append((full, g1, g2))
        }
        return out
    }

    // MARK: - T8 置信度

    var confidenceValue: Int {
        if source.contains(Self.DOC_MARKER_PREFIX) { return 95 }
        if Self.hasTableAnchors(source) { return 92 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains(Self.DOC_MARKER_PREFIX) { out.append("bjtu:combined-doc") }
        for (label, _) in Self.sections(source) {
            if label == "stuschedule" { out.append("path:stuschedule") }
            if label == "schedule" { out.append("path:schedule") }
        }
        if source.contains(Self.DAY_ANCHOR) { out.append("th:星期一") }
        if source.range(of: Self.PERIOD_LABEL_RE, options: .regularExpression) != nil { out.append("cell:第N节") }
        if source.range(of: Self.PERIOD_TIME_RE, options: .regularExpression) != nil { out.append("cell:[HH:MM-HH:MM]") }
        if source.range(of: Self.LOGIN_PAGE_RE, options: .regularExpression) != nil { out.append("guard:login-page") }
        if !source.contains(Self.DOC_MARKER_PREFIX)
            && source.range(of: Self.FOREIGN_ANCHOR_RE, options: .regularExpression) != nil {
            out.append("guard:foreign-anchor")
        }
        return out
    }
}
