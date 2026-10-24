// JwNewZfParser.swift — ← JwNewZfParser.kt
// 正方教务(新版)课表解析器 — T4 修复版。
//
// 适配 zf_new 协议学校。正方新版教务(jwglxt, SpringMVC / Vue)课表:
//   1. 数据可能嵌入在 `<script>` 标签 JSON 中(kbList API 响应直出 / Vue data)
//   2. 或渲染为 HTML 表格(三种实证变体, 见 parseHtmlTable 容器优先级)
//
// T4 修复要点(逐条对齐 Android 真值):
//   - JSON marker 收紧为 "kbList" > "xskbcx_json" > "kbxx"(删臆造的 "tmp_list" 与
//     会命中 URL 子串的 "xskbcx"), 严格 JSON 键匹配(findJsonKeyIndex)
//   - 字段优先级重排: room=cdmc 首位(jasmc 是教学班场地不当教室)、teacher=xm/jsxm、
//     day=xqj 数字 + xqjmc 文本兜底
//   - jc 节次串解析 parseSectionRanges: 支持 "1-2" 范围 / "0102" 补零 / "3-4,6-7" 多段
//   - zcd 周次加固: 剥 { } 第, (单)(单周)(双)(双周) 显式枚举
//   - CF 防御: 元素含 teaxms/jxcdmcs/jcdm2/zcs 任一字段即跳过(青果页面不产脏数据)
//   - 深层包装穿透: {Msg,code,data:[{kbList:[…]}]} 递归下钻 findKbListArray
//   - HTML 五层容器优先级: table1Festival / kbgrid_table_0 / kblist_table /
//     kbcontent / QZ 兜底
//
// 参考:
//   - dIT8Zv/WakeupSchedule_BUPT NewZFParser.kt
//   - 拾光 shiguang_warehouse zhengfang_01.js(kbgrid/kblist 双视图)
//   - zfn_api / FlowCourse(kbList 主流形态与 jc 多形态交叉验证)

import Foundation
import SwiftSoup

final class JwNewZfParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        // 1. 尝试从页面提取嵌入的 JSON
        let embedded = parseEmbeddedJson()
        if !embedded.isEmpty { return embedded }

        // 2. HTML 表格解析
        return parseHtmlTable()
    }

    // ─── JSON 提取 ────────────────────────────────────────────

    /// 标记关键字(按上游 NewZFParser.kt / 拾光 zhengfang_01.js / FlowCourse / zfn_api /
    /// GZUS-PRO / SHUFEZJ / NBUT / HUEL / QUT 调研结论排序):
    ///   - "kbList": 主流, FlowCourse 嗅探条件原文 text.indexOf('kbList') !== -1
    ///   - "xskbcx_json": SHUFEZJ 注释提及, 极少版本
    ///   - "kbxx": v1.0.29 兼容(老 fixture 使用), 保留但降级到最后; CF 防御靠字段 guard
    ///
    /// 已剔除(调研确认无佐证或是 bug 源):
    ///   - "tmp_list": 无任何上游/适配器实证, 属臆造
    ///   - "xskbcx": 作 marker 会命中 URL 子串如 /kbcx/xskbcx_cxXsgrkb.html, 产生假 JSON
    private static let jsonMarkers = ["\"kbList\"", "\"xskbcx_json\"", "\"kbxx\""]

    private func parseEmbeddedJson() -> [JwCourse] {
        let chars = Array(source)
        for marker in Self.jsonMarkers {
            guard let idx = Self.findJsonKeyIndex(chars, marker),
                  let jsonStr = Self.extractBalanced(chars, idx) else { continue }
            let courses = parseCourseJsonArray(jsonStr)
            if !courses.isEmpty { return courses }
        }
        // T8 补充: JS 变量赋值形态 `var kbList = [...]` / `var kbxx=[...]`(无引号键名)
        for name in ["kbList", "xskbcx_json", "kbxx"] {
            guard let idx = Self.findJsonVarIndex(chars, name),
                  let jsonStr = Self.extractBalanced(chars, idx) else { continue }
            let courses = parseCourseJsonArray(jsonStr)
            if !courses.isEmpty { return courses }
        }

        // 尝试纯 JSON 页面(API 响应被 WebView 直接渲染, 或移动端深层包装)
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            let courses = parseCourseJsonArray(trimmed)
            if !courses.isEmpty { return courses }
        }

        return []
    }

    /// 严格 JSON 键搜索: 找到 marker 后, 要求后续非空字符为 JSON 开始符({ 或 [)。
    /// 命中位置返回 JSON 开始符的下标, 以便 extractBalanced 从该处起算。
    ///
    /// 反例(应跳过):
    ///   ".../kbcx/xskbcx_cxXsgrkb.html..."  // URL 子串, xskbcx 后面是 '_', 非空白+{
    ///   "var foo = \"xskbcx_json_other\""   // 标识符前缀, xskbcx_json 后面是 '_'
    private static func findJsonKeyIndex(_ s: [Character], _ quotedKey: String) -> Int? {
        let quoted = Array(quotedKey)
        let n = s.count
        let m = quoted.count
        var from = 0
        while true {
            guard let idx = indexOf(s, quoted, from: from) else { return nil }
            let after = idx + m
            if after >= n { return nil }
            // 跳过空白
            var p = after
            while p < n, s[p].isWhitespace { p += 1 }
            // JSON 键形态 "kbList": [ 允许单个冒号
            if p < n, s[p] == ":" {
                p += 1
                while p < n, s[p].isWhitespace { p += 1 }
            }
            if p >= n { from = idx + 1; continue }
            switch s[p] {
            case "{", "[": return p
            default: from = idx + 1; continue
            }
        }
    }

    /// T8: JS 变量赋值形态的严格搜索 — `var kbList = [...]`。
    /// marker 后必须跳过空白与单个 '=', 后续非空字符为 { 或 [。
    private static func findJsonVarIndex(_ s: [Character], _ name: String) -> Int? {
        let marker = Array("var " + name)
        let n = s.count
        let m = marker.count
        var from = 0
        while true {
            guard let idx = indexOf(s, marker, from: from) else { return nil }
            var p = idx + m
            while p < n, s[p].isWhitespace { p += 1 }
            if p < n, s[p] == "=" {
                p += 1
                while p < n, s[p].isWhitespace { p += 1 }
                if p < n, s[p] == "{" || s[p] == "[" { return p }
            }
            from = idx + 1
        }
    }

    /// 在字符数组 s 中从 from 起查找子序列 pat 的起始下标(← Kotlin String.indexOf)
    private static func indexOf(_ s: [Character], _ pat: [Character], from: Int) -> Int? {
        let n = s.count
        let m = pat.count
        if m == 0 { return from <= n ? max(from, 0) : nil }
        if from < 0 || n - from < m { return nil }
        var i = from
        outer: while i + m <= n {
            for j in 0..<m where s[i + j] != pat[j] {
                i += 1
                continue outer
            }
            return i
        }
        return nil
    }

    /// 从 start 位置提取配对的 JSON 数组/对象(括号匹配)
    private static func extractBalanced(_ s: [Character], _ start: Int) -> String? {
        let n = s.count
        if start >= n { return nil }
        let open = s[start]
        let close: Character
        switch open {
        case "[": close = "]"
        case "{": close = "}"
        default: return nil
        }
        var depth = 0
        var inStr = false
        var esc = false
        for i in start..<n {
            let c = s[i]
            if esc { esc = false; continue }
            if c == "\\" { esc = true; continue }
            if c == "\"" { inStr = !inStr; continue }
            if inStr { continue }
            switch c {
            case open: depth += 1
            case close:
                depth -= 1
                if depth == 0 { return String(s[start...i]) }
            default: break
            }
        }
        return nil
    }

    private func parseCourseJsonArray(_ jsonStr: String) -> [JwCourse] {
        var result: [JwCourse] = []
        guard let data = jsonStr.data(using: .utf8) else { return result }
        do {
            // 可能是数组直接开始, 也可能包在对象里
            let obj = try JSONSerialization.jsonObject(with: data)
            let arr: [Any]
            if let a = obj as? [Any] {
                arr = a
            } else if let o = obj as? [String: Any] {
                guard let found = Self.findKbListArray(o) else { return result }
                arr = found
            } else {
                return result
            }

            for case let o as [String: Any] in arr {
                // ── CF(青果) 字段白名单防御 ──────────────────────
                // CF 的 kbxx 元素字段: kcmc/teaxms/jxcdmcs/xq/jcdm2/zcs,
                // 与 zf_new 别名不重合; 检测任一 CF 独有字段 → 整条跳过
                if o["teaxms"] != nil || o["jxcdmcs"] != nil || o["jcdm2"] != nil || o["zcs"] != nil { continue }

                // ── 课程名(必填) ────────────────────────────────
                let name = Self.firstStr(o, "kcmc", "kcm", "kc_mc", "courseName", "rlkcmc", "jxbmc")
                if name.isEmpty { continue }

                // ── 教师(主流=xm, jsxm=变体) ────────────────────
                let teacher = Self.firstStr(o, "xm", "jsxm", "teacher", "attendClassTeacher", "skjs")

                // ── 教室(主流=cdmc; jasmc 是教学班场地, 不当教室) ──
                let room = Self.firstStr(o, "cdmc", "classroomName", "jxcd", "jsmc", "jxlh", "jasdm")

                // ── 星期(优先数字 xqj, 文本 xqjmc 兜底) ──────────
                guard let day = Self.firstInt(o, "xqj", "kcxq", "xq", "classDay", "skxq")
                    ?? Self.xqjmcToInt(o) else { continue }

                // ── 节次(字符串, 支持范围/补零/多段) ──────────────
                let jcStr = Self.firstStr(o, "jcs", "jc", "classSessions", "ksjcsd", "ksjc")
                if jcStr.isEmpty { continue }  // 缺节次串 → 不产课程

                // ── 周次 ───────────────────────────────────────
                let zcStr = Self.firstStr(o, "zcd", "kkzc", "zc", "classWeek", "skzc")
                let ranges = Self.parseWeekStr(zcStr)

                // ── 节次展开: '1-2' → [(1,2)]; '3-4,6-7' → [(3,4),(6,7)]; '0102' → [(1,2)] ──
                for node in Self.parseSectionRanges(jcStr) {
                    for r in ranges {
                        result.append(JwCourse(
                            name: name,
                            room: room,
                            teacher: teacher,
                            day: min(max(day, 1), 7),
                            startNode: max(node.0, 1),
                            endNode: max(node.1, node.0),
                            startWeek: r.0,
                            endWeek: r.1,
                            type: r.2
                        ))
                    }
                }
            }
        } catch {
            // JSON 解析失败, 静默(tryAllParsers 候选链兜底)
        }
        return result
    }

    /// 递归查找 JSON 对象树中名为 kbList / kbxx / tmp_list 的数组。
    ///
    /// 移动端标准版真实形态 (FlowCourse 抓包):
    ///   {"Msg":"success","code":"1","data":[{"date":[...],"kbList":[...]}]}
    /// kbList 在 data[0] 对象里, 必须递归下钻。
    ///
    /// ← Android findKbListArray(obj, depth)。Swift 侧 optJSONArray 的
    /// "键存在但不是数组 → null" 语义 = `as? [Any]`(非数组自然失败)。
    private static func findKbListArray(_ obj: [String: Any], depth: Int = 0) -> [Any]? {
        if depth > 4 { return nil }  // 防御: 最多下钻 4 层
        for key in ["kbList", "kbxx", "tmp_list"] {
            if let v = obj[key] as? [Any] { return v }
        }
        for (_, value) in obj {
            if let v = value as? [String: Any] {
                if let inner = findKbListArray(v, depth: depth + 1) { return inner }
                continue
            }
            if let arr = value as? [Any] {
                for case let inner as [String: Any] in arr {
                    if let found = findKbListArray(inner, depth: depth + 1) { return found }
                }
            }
        }
        return nil
    }

    /// 节次字符串 → [(startNode, endNode)]
    ///
    /// 三种输入形态(zfn_api/FlowCourse/NBUT/SHUFEZJ 四源交叉确认):
    ///   1. 范围串: "1-2" / "6-7" / "5" — 按 '-' split
    ///   2. 两位补零: "0102" / "0304" — 偶数长度纯数字串, 每 2 位一节
    ///   3. 多段逗号: "3-4,6-7" — 每段独立, 拆多条课程
    private static func parseSectionRanges(_ s0: String) -> [(Int, Int)] {
        // 惠州学院 HZU (2026-10-04 采集包): jc 字段带「节」后缀 ("8-9节"/"10-12节"),
        // 部分老版本教务直接把 jc 喂进来 (jcs 缺失时 firstStr 落到 jc)。先剥后缀再分段,
        // 否则 "2节".toIntOrNull() = null → 整条范围串静默丢弃 → 0 课 → 误报「解析结果为空」。
        let s = s0.replacingOccurrences(of: "节", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return [] }
        var out: [(Int, Int)] = []
        for seg0 in splitMulti(s, separators: [",", "，", ";", "；"]) {
            let t = seg0.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            // 形态 1: 含 '-' 的范围串
            if t.contains("-") {
                // ← Kotlin split("-", limit=2): 只切第一段
                let pair = t.components(separatedBy: "-")
                let aStr = (pair.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let bStr = pair.count > 1
                    ? (pair[1...].joined(separator: "-")).trimmingCharacters(in: .whitespacesAndNewlines)
                    : ""
                if let a = Int(aStr), let b = Int(bStr), (1...16).contains(a), (1...16).contains(b) {
                    out.append((a, b))
                }
                continue
            }
            // 纯数字
            let digits = String(t.filter { $0 >= "0" && $0 <= "9" })  // ← Kotlin isDigit(): ASCII 0-9
            if digits.isEmpty { continue }
            // 形态 2: 偶数长度补零串 ("0102" → 01,02)
            if digits.count >= 2 && digits.count % 2 == 0 && digits.hasPrefix("0") {
                var ok = true
                var nums: [Int] = []
                let dc = Array(digits)
                var pos = 0
                while pos + 1 < dc.count {
                    let v = Int(String(dc[pos...(pos + 1)]))
                    if v == nil || !(1...16).contains(v!) { ok = false; break }
                    nums.append(v!)
                    pos += 2
                }
                if ok && nums.count >= 2 {
                    // 相邻两位一组: 0102 → (1,2), 01121314 → (1,2),(13,14)
                    var k = 0
                    while k + 1 < nums.count {
                        out.append((nums[k], nums[k + 1]))
                        k += 2
                    }
                } else if ok && nums.count == 1 {
                    out.append((nums[0], nums[0]))
                }
                continue
            }
            // 形态 1 变体: 纯数字单节 "5"
            if let v = Int(digits), (1...16).contains(v) { out.append((v, v)) }
        }
        return out
    }

    /// xqjmc 星期文本 → 1..7, 无法识别返回 nil。
    /// 兼容 "星期一"/"周一"/"星期日"/"周日"/"周天"
    private static func xqjmcToInt(_ o: [String: Any]) -> Int? {
        let s = optString(o, "xqjmc").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        let zh: [Character] = ["一", "二", "三", "四", "五", "六", "日", "天"]
        for c in s {
            if let idx = zh.firstIndex(of: c) {
                // '日'/'天' 在下标 6/7 → 都是 7 (周日)
                return idx >= 6 ? 7 : idx + 1
            }
        }
        return nil
    }

    private static func firstStr(_ o: [String: Any], _ keys: String...) -> String {
        for k in keys {
            let v = optString(o, k).trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return v }
        }
        return ""
    }

    private static func firstInt(_ o: [String: Any], _ keys: String...) -> Int? {
        for k in keys {
            let v = optString(o, k).trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty { return Int(v) }
        }
        return nil
    }

    /// ← org.json JSONObject.optString(key, ""): 任意标量转字符串, 缺键回 ""。
    /// org.json 的 JSONObject.get 对非字符串值做 String.valueOf, JSONSerialization 则给
    /// NSNumber/NSNull; 这里统一折算, 保持 firstStr/firstInt 的"键存在且非空"语义。
    private static func optString(_ o: [String: Any], _ key: String) -> String {
        guard let v = o[key] else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            // JSON true/false → CFBoolean(kCFBooleanNumber), NSNumber 桥接整数 0/1 时
            // `v is Bool` 对 0 与任意非 2 小整数也为 true(实测: JSONSerialization 缓存 0/1/
            // true/false 同一 __NSCFNumber 类, `is Bool` 靠数值判等), 会把 "0"/"1" 错报成
            // "false"/"true" → firstInt 得 nil → 整行丢课。按 CF 类型判别, 只有真布尔走文本。
            if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
            return n.stringValue
        }
        if v is NSNull { return "" }
        return String(describing: v)
    }

    /// ← Kotlin String.split(vararg delimiters): 全保留空段
    private static func splitMulti(_ s: String, separators: [String]) -> [String] {
        var pieces = [s]
        for sep in separators {
            var next: [String] = []
            for p in pieces { next.append(contentsOf: p.components(separatedBy: sep)) }
            pieces = next
        }
        return pieces
    }

    /// 周次字符串 → (start, end, type) 范围列表(T4 加固: 剥 { } 第, 单双周显式枚举)
    private static func parseWeekStr(_ s0: String) -> [(Int, Int, Int)] {
        // 1. 先剥离花括号与 '第' 字 (SHUFEZJ: '{第1-16周}')
        let s = s0.replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "第", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return [(1, 16, 0)] }
        var result: [(Int, Int, Int)] = []

        // 2. bitmap 模式: 11111111111100000(每位 = 第 N 周)
        if s.count >= 10 && s.allSatisfy({ $0 == "0" || $0 == "1" }) {
            let weeks = s.enumerated().compactMap { $0.element == "1" ? $0.offset + 1 : nil }
            return bitsToRanges(weeks)
        }

        // 3. 范围/列表模式: "1-16" / "1-16周" / "1-16周(单)" / "1,3,5,7" / "1-8,11-16周(双)"
        for part0 in splitMulti(s, separators: [",", "，", ";", "；"]) {
            let part = part0.trimmingCharacters(in: .whitespacesAndNewlines)
            if part.isEmpty { continue }
            // 单双周后缀显式枚举 (防误判 '单元'/'双方' 等词)
            let type: Int
            if part.contains("(单)") || part.contains("(单周)") || part.hasSuffix("单") || part.hasSuffix("单周") {
                type = 1
            } else if part.contains("(双)") || part.contains("(双周)") || part.hasSuffix("双") || part.hasSuffix("双周") {
                type = 2
            } else {
                type = 0
            }
            let cleaned = part
                .replacingOccurrences(of: "周", with: "")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "（", with: "")
                .replacingOccurrences(of: "）", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.contains("-") {
                let pair = cleaned.components(separatedBy: "-")
                let startStr = (pair.first ?? "").filter { $0 >= "0" && $0 <= "9" }
                let endStr = pair.count > 1
                    ? pair[1...].joined(separator: "-").filter { $0 >= "0" && $0 <= "9" }
                    : ""
                let start = startStr.isEmpty ? nil : Int(startStr)
                let end = endStr.isEmpty ? nil : Int(endStr)
                if let start, let end { result.append((start, end, type)) }
            } else {
                let digits = cleaned.filter { $0 >= "0" && $0 <= "9" }
                guard !digits.isEmpty, let v = Int(digits) else { continue }
                result.append((v, v, type))
            }
        }
        return result.isEmpty ? [(1, 16, 0)] : result
    }

    private static func bitsToRanges(_ weeks: [Int]) -> [(Int, Int, Int)] {
        if weeks.isEmpty { return [] }
        var result: [(Int, Int, Int)] = []
        var i = 0
        while i < weeks.count {
            let start = weeks[i]
            var end = start
            if i + 1 < weeks.count && weeks[i + 1] - start == 2 {
                // 单/双周模式
                end = weeks[i + 1]
                var k = i + 1
                while k + 1 < weeks.count && weeks[k + 1] - weeks[k] == 2 { k += 1; end = weeks[k] }
                let type = start % 2 == 1 ? 1 : 2
                result.append((start, end, type))
                i = k + 1
            } else if i + 1 < weeks.count && weeks[i + 1] - start == 1 {
                // 连续周
                end = weeks[i + 1]
                var k = i + 1
                while k + 1 < weeks.count && weeks[k + 1] - weeks[k] == 1 { k += 1; end = weeks[k] }
                result.append((start, end, 0))
                i = k + 1
            } else {
                result.append((start, end, 0))
                i += 1
            }
        }
        return result
    }

    // ─── HTML 表格解析(兜底) ─────────────────────────────────

    /// 移植自 JwOldZfParser 的 (N-M节) 模式, table1/kbgrid 变体共用
    private static let nodePattern = try! NSRegularExpression(pattern: "\\(\\d{1,2}[-]*\\d*节")

    /// 新正方 HTML 渲染后的课表解析。容器优先级:
    ///   1. #table1 + td.festival + div.title + p[title=...] (上游 NewZFParser.kt)
    ///   2. #kbgrid_table_0 + td.td_wrap + .timetable_con.text-left (shiguang 网格)
    ///   3. #kblist_table tbody + td:first-child 节次 + td[1] .title (shiguang 列表)
    ///   4. #kbtable/#kbgrid/.kbcapi-table/[id*=kb] (现有强智/kbgrid 兜底)
    ///   5. parseHtmlTableFromQz 兜底(空列表返回)
    private func parseHtmlTable() -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(source) else { return parseHtmlTableFromQz() }

        // ── 1. 上游 NewZFParser.kt 期望结构 ──
        if let table1 = (try? doc.getElementById("table1")) ?? nil,
           !((try? table1.select("td.festival")) ?? Elements()).isEmpty() {
            let result = parseTable1FestivalView(table1)
            if !result.isEmpty { return result }
        }

        // ── 2. shiguang 网格视图 ──
        if let gridTable = (try? doc.getElementById("kbgrid_table_0")) ?? nil {
            let result = parseKbgridTable0(gridTable)
            if !result.isEmpty { return result }
        }

        // ── 3. shiguang 列表视图 ──
        if let listTable = (try? doc.getElementById("kblist_table")) ?? nil {
            let result = parseKblistTable(listTable)
            if !result.isEmpty { return result }
        }

        // ── 4. 现有强智 / kbgrid 兜底(维持原状) ──
        let container: Element? = {
            if let el = (try? doc.getElementById("kbtable")) ?? nil { return el }
            if let el = (try? doc.getElementById("kbgrid")) ?? nil { return el }
            if let el = (try? doc.select("table.el-table__body"))?.first() { return el }
            if let el = (try? doc.select(".kbcapi-table"))?.first() { return el }
            if let el = (try? doc.select("[id*=kb]"))?.first() { return el }
            return nil
        }()
        if let container {
            let result = parseKbcontentContainer(container)
            if !result.isEmpty { return result }
        }

        // ── 5. parseHtmlTableFromQz 兜底(空列表返回, 不抛异常) ──
        return parseHtmlTableFromQz()
    }

    /// 上游 NewZFParser.kt (dIT8Zv/WakeupSchedule_BUPT) 移植实现。
    /// 适配 table#table1 + td.festival + div.title + p[title=教师/上课地点/节/周]
    private func parseTable1FestivalView(_ table: Element) -> [JwCourse] {
        var result: [JwCourse] = []
        let trs = ((try? table.getElementsByTag("tr")) ?? Elements()).array()
        for tr in trs {
            // 行头: 节次数字 (class="festival")
            let nodeStr = ((try? tr.getElementsByClass("festival").text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if nodeStr.isEmpty { continue }
            guard let rowNode = Int(nodeStr) else { continue }

            let tds = ((try? tr.getElementsByTag("td")) ?? Elements()).array()
            for td in tds {
                // 跳过无 id 的 td(表头星期单元格)
                let tdId = (try? td.attr("id")) ?? ""
                if tdId.isEmpty { continue }
                // td.id 首字符 → 星期 (id 格式: "日-节" 如 "2-1")
                guard let first = tdId.first, let day = Int(String(first)), (1...7).contains(day) else { continue }

                let divs = ((try? td.getElementsByTag("div")) ?? Elements()).array()
                for div in divs {
                    // 跳过空白 div
                    let courseText = ((try? div.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    if courseText.count <= 1 { continue }
                    // 课程名(div.title)
                    let courseName = ((try? div.getElementsByClass("title").text()) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if courseName.isEmpty { continue }

                    // p[title=教师/上课地点/节/周]
                    var teacher = ""
                    var room = ""
                    var timeStr = ""
                    let pList = ((try? div.getElementsByTag("p")) ?? Elements()).array()
                    for p in pList {
                        switch (try? p.attr("title")) ?? "" {
                        case "教师": teacher = ((try? p.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        case "上课地点": room = ((try? p.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        case "节/周", "周/节": timeStr = ((try? p.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        default: break
                        }
                    }
                    if timeStr.isEmpty { continue }

                    // 节/周文本解析: "(N-M节)X-Y周(单),A-B周(双)"
                    guard let nodeInfo = Self.firstMatch(Self.nodePattern, in: timeStr) else { continue }
                    // ← Kotlin substring(1).removeSuffix("节").split("-")
                    let nodes = String(nodeInfo.dropFirst())
                        .replacingOccurrences(of: "节", with: "")
                        .components(separatedBy: "-")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    // ← Kotlin `?: continue`: 首段非法数字时整条跳过
                    guard var startNode = Int(nodes.first ?? "") else { continue }
                    let endNode = nodes.count > 1 ? (Int(nodes[1]) ?? startNode) : startNode
                    // (N-M节) 优先, 行头 rowNode 仅作缺省
                    if startNode <= 0 { startNode = rowNode }

                    // 周次段
                    let weekList = Self.replace(Self.nodePattern, in: timeStr, with: "").components(separatedBy: ",")
                    for weekPart in weekList {
                        let trimmed = weekPart.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty { continue }
                        for r in Self.parseWeekStr(trimmed) {
                            result.append(JwCourse(
                                name: courseName,
                                room: room,
                                teacher: teacher,
                                day: day,
                                startNode: startNode,
                                endNode: endNode,
                                startWeek: r.0,
                                endWeek: r.1,
                                type: r.2
                            ))
                        }
                    }
                }
            }
        }
        return result
    }

    /// shiguang_warehouse resources/zhengfang_jiaowu/zhengfang_01.js parserTbale 移植。
    /// 适配 #kbgrid_table_0 + td.td_wrap + .timetable_con.text-left
    private func parseKbgridTable0(_ table: Element) -> [JwCourse] {
        var result: [JwCourse] = []
        let trs = ((try? table.getElementsByTag("tr")) ?? Elements()).array()
        for tr in trs {
            let tds = ((try? tr.getElementsByTag("td")) ?? Elements()).array()
            for td in tds {
                let tdId = (try? td.attr("id")) ?? ""
                if tdId.isEmpty { continue }
                // ← Kotlin tdId.split("-").getOrNull(0)?.toIntOrNull()
                let head = tdId.components(separatedBy: "-").first ?? ""
                guard let day = Int(head.trimmingCharacters(in: .whitespacesAndNewlines)), (1...7).contains(day) else { continue }

                let timetableCons = ((try? td.getElementsByClass("timetable_con")) ?? Elements()).array()
                for tc in timetableCons {
                    let name = ((try? (try? tc.getElementsByClass("title"))?.first()?.text()) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if name.isEmpty { continue }

                    // p[0] = 节/周; p[1] = 地点; p[2] = 教师
                    let pList = ((try? tc.getElementsByTag("p")) ?? Elements()).array()
                    if pList.count < 3 { continue }  // 缺字段直接跳过(对齐 grid_missing_fields 边界)
                    let infoStr = ((try? pList[0].text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let position = ((try? pList[1].text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let teacher = ((try? pList[2].text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

                    // 节次解析: infoStr 必须含 "(N-M节)"
                    guard let nodeMatch = Self.firstMatch(Self.nodePattern, in: infoStr) else { continue }
                    let nodes = String(nodeMatch.dropFirst())
                        .replacingOccurrences(of: "节", with: "")
                        .components(separatedBy: "-")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard let startNode = Int(nodes.first ?? "") else { continue }
                    let endNode = nodes.count > 1 ? (Int(nodes[1]) ?? startNode) : startNode

                    // 周次段: 剥 (N-M节) 后按逗号拆
                    let weekStr = Self.replace(Self.nodePattern, in: infoStr, with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let ranges = Self.parseWeekStr(weekStr)
                    if ranges.isEmpty { continue }

                    for r in ranges {
                        result.append(JwCourse(
                            name: name,
                            room: position,
                            teacher: teacher,
                            day: day,
                            startNode: startNode,
                            endNode: endNode,
                            startWeek: r.0,
                            endWeek: r.1,
                            type: r.2
                        ))
                    }
                }
            }
        }
        return result
    }

    /// shiguang_warehouse zhengfang_01.js parserList 移植。
    /// 适配 #kblist_table tbody 按星期分组 + td[0] 节次 + td[1] .title + 3 个带前缀的 font
    ///
    /// 注意: tbody[0] 是视图控制, tbody[1..7]=周一..周日 (index 0 跳过)。
    private func parseKblistTable(_ table: Element) -> [JwCourse] {
        var result: [JwCourse] = []
        let tbodies = ((try? table.getElementsByTag("tbody")) ?? Elements()).array()
        for (index, tbody) in tbodies.enumerated() {
            if index == 0 { continue }
            if index > 7 { break }  // 防御越界
            let day = index  // 1=周一, 2=周二, ..., 7=周日

            let trs = ((try? tbody.getElementsByTag("tr")) ?? Elements()).array()
            for tr in trs {
                let tds = ((try? tr.getElementsByTag("td")) ?? Elements()).array()
                if tds.count < 2 { continue }  // 表头行 th-only 无 td, 跳过
                let sectionStr = ((try? tds[0].text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if sectionStr.isEmpty { continue }
                // 解析节次: "1-2" / "5-6" → (start, end)
                // ← Kotlin sectionStr.split("-", limit = 2): 只切第一个 '-'
                let nodes: [String]
                if let dash = sectionStr.firstIndex(of: "-") {
                    nodes = [String(sectionStr[..<dash]),
                             String(sectionStr[sectionStr.index(after: dash)...])]
                } else {
                    nodes = [sectionStr]
                }
                guard let startNode = Int(nodes[0].trimmingCharacters(in: .whitespacesAndNewlines)) else { continue }
                let endNode = nodes.count > 1
                    ? (Int(nodes[1].trimmingCharacters(in: .whitespacesAndNewlines)) ?? startNode)
                    : startNode

                // td[1] 内 .title div
                let name = ((try? (try? tds[1].getElementsByClass("title"))?.first()?.text()) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { continue }

                // 整块文本 + 前缀正则剥字段
                //   周数：1-16周 / 上课地点：教学楼A101 / 教师　：张老师 (U+3000 全角空格)
                let allText = (try? tds[1].text()) ?? ""
                let weekStr = Self.regexGroup(Self.weekLabelRegex, in: allText, group: 1) ?? ""
                let room = Self.regexGroup(Self.roomLabelRegex, in: allText, group: 1) ?? ""
                let teacher = Self.regexGroup(Self.teacherLabelRegex, in: allText, group: 1) ?? ""

                if weekStr.isEmpty { continue }
                let ranges = Self.parseWeekStr(weekStr)
                if ranges.isEmpty { continue }

                for r in ranges {
                    result.append(JwCourse(
                        name: name,
                        room: room.trimmingCharacters(in: .whitespacesAndNewlines),
                        teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
                        day: day,
                        startNode: startNode,
                        endNode: endNode,
                        startWeek: r.0,
                        endWeek: r.1,
                        type: r.2
                    ))
                }
            }
        }
        return result
    }

    // ← Kotlin Regex("""周数\s*[：:]\s*(.+?)(?=上课地点|教师|$)""") 等三条。
    // NSRegularExpression 不支持后向断言里的中文 alternation? 支持; 但 $ 在 NS 中
    // 默认匹配行尾(无 MULTILINE 时即串尾), 语义与 Kotlin Regex 一致。
    // `\s` 不覆盖 U+3000 全角空格 → Kotlin 用 [\s　] 显式补, 这里保持同款。
    private static let weekLabelRegex = try! NSRegularExpression(pattern: "周数\\s*[：:]\\s*(.+?)(?=上课地点|教师|\\z)", options: [])
    private static let roomLabelRegex = try! NSRegularExpression(pattern: "上课地点\\s*[：:]\\s*(.+?)(?=教师|\\z)", options: [])
    private static let teacherLabelRegex = try! NSRegularExpression(pattern: "教师[\\s\u{3000}]*[：:]\\s*(.+?)\\z", options: [])

    /// 取第 1 个匹配的 group(1), trim 后返回; 无匹配返回 ""(← Kotlin orEmpty + trim 语义)
    private static func regexGroup(_ re: NSRegularExpression, in text: String, group: Int) -> String? {
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard group < m.numberOfRanges, m.range(at: group).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: group)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// NODE_PATTERN 首匹配整段(← Kotlin Regex.find(...)?.value)
    private static func firstMatch(_ re: NSRegularExpression, in text: String) -> String? {
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)) else { return nil }
        return ns.substring(with: m.range)
    }

    /// NODE_PATTERN.replace(text, "") (← Kotlin Regex.replace)
    private static func replace(_ re: NSRegularExpression, in text: String, with replacement: String) -> String {
        let ns = text as NSString
        return re.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length), withTemplate: replacement)
    }

    /// 现有强智 kbcontent 容器解析(原 parseHtmlTable 内循环提取为命名函数)。
    private func parseKbcontentContainer(_ container: Element) -> [JwCourse] {
        var result: [JwCourse] = []
        let trs = ((try? container.getElementsByTag("tr")) ?? Elements()).array()
        var nodeCount = 0
        for tr in trs {
            let tds = ((try? tr.getElementsByTag("td")) ?? Elements()).array()
            if tds.isEmpty { continue }
            let firstCellText = ((try? tds.first?.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // ← tds.none { it.getElementsByClass("kbcontent").isNotEmpty() }
            let hasKbcontent = tds.contains { td in
                !(((try? td.getElementsByClass("kbcontent")) ?? Elements()).isEmpty())
            }
            let isSectionHeader = firstCellText.contains("节") && !hasKbcontent
            if isSectionHeader { continue }
            nodeCount += 1
            var day = 0
            for td in tds {
                day += 1
                let cells = ((try? td.getElementsByClass("kbcontent")) ?? Elements()).array()
                if cells.isEmpty { continue }
                for cell in cells {
                    let html = (try? cell.html()) ?? ""
                    if html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    // 同格多门课用 "-----" 分隔(与 QZ 一致)
                    for part in html.components(separatedBy: "-----") {
                        result += parseCell(part.trimmingCharacters(in: .whitespacesAndNewlines), day: day, nodeCount: nodeCount)
                    }
                }
            }
        }
        return result
    }

    private func parseCell(_ html: String, day: Int, nodeCount: Int) -> [JwCourse] {
        // ← Jsoup.parse(html) + try/catch: 解析失败时降级用原文本, 不崩
        let cellDoc = try? SwiftSoup.parse(html)
        let before = html.components(separatedBy: "<font").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name: String
        // ← Jsoup.parse(html) + try/catch: runCatching{ text().trim() }.getOrNull() ?: before
        let parsedText: String? = (try? SwiftSoup.parse(before)).flatMap { try? $0.text() }
        if let parsed = parsedText?.trimmingCharacters(in: .whitespacesAndNewlines) {
            name = parsed
        } else {
            name = before
        }
        if name.isEmpty { return [] }

        func titleText(_ title: String) -> String {
            guard let cellDoc else { return "" }
            return ((try? cellDoc.getElementsByAttributeValue("title", title).text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let teacher = titleText("老师")
        let room = titleText("教室")
        let weekRaw: String = {
            guard let cellDoc else { return "" }
            return (try? cellDoc.getElementsByAttributeValue("title", "周次(节次)").text()) ?? ""
        }()
        // ← Jsoup 端 .text().substringBefore("(周)") — text() 已把 NBSP 折叠为普通空格
        let weekStr = weekRaw.components(separatedBy: "(周)").first ?? weekRaw

        let ranges = Self.parseWeekStr(weekStr)
        let node = nodeCount * 2 - 1

        // 展开全部周次段(之前只取 ranges.first(), 会丢失 "1-11周(单),13-16周" 的后半段)
        return ranges.map { r in
            JwCourse(
                name: name,
                room: room,
                teacher: teacher,
                day: day,
                startNode: node,
                endNode: node + 1,
                startWeek: r.0,
                endWeek: r.1,
                type: r.2
            )
        }
    }

    /// 完全 fallback 到 QZ 解析逻辑
    /// (T8: QZ 缺表抛 JwParseError, 兜底处吸收为空列表)
    private func parseHtmlTableFromQz() -> [JwCourse] {
        (try? JwQzParser(source).generateCourseList()) ?? []
    }

    // MARK: - T8 置信度

    /// zftal-ui- / "kbList" = 100; kblist_table = 80; kbtable/kbgrid = 70; CF 页 = 0..49
    var confidenceValue: Int {
        let lower = source.lowercased()
        if lower.contains("zftal-ui-") || lower.contains("\"kblist\"") { return 100 }
        if lower.contains("kblist_table") { return 80 }
        if lower.contains("kbtable") || lower.contains("kbgrid") { return 70 }
        return 0
    }

    var matchedFeatureList: [String] {
        let lower = source.lowercased()
        var out: [String] = []
        if lower.contains("\"kblist\"") { out.append("kbList") }
        if lower.contains("kbgrid_table_0") { out.append("kbgrid_table_0") }
        if lower.contains("kblist_table") { out.append("kblist_table") }
        return out
    }
}
