// ScheduleParser.swift — ← ScheduleParser.kt @ v1.0.61 (逐函数)
// 课程表文本解析器 — 支持:
//
// 1. **WakeUp 课程表分享 JSON**(来自 WakeUp app 的导出)
//    格式: {"name":"...","startDate":"2024-09-02","courses":[{"name":"高数","teacher":"张三","position":"A101","day":1,"startNode":1,"step":2,"startWeek":1,"endWeek":16,"type":0,"color":"#FF6750A4"}, ...]}
//
// 2. **简化的纯文本格式** (一行一课,制表符或空格分隔):
//    ```
//    高等数学	张三	A101	1	1-2	1-16	0
//    大学英语	李四	B202	2	3-4	1-16	0
//    ```
//    字段: 课程名\t老师\t教室\t星期\t节次(1-2)\t周次(1-16)\t类型(0/1/2)
//
// v7.10.16k 无损收尾: 全路径 nodesPerDay = max(作息声明, 课程到达) — 没时间 ≠ 没有节次。
// v1.0.56 T10/T11: tableInfo 收割同时产出 ParsedPeriodTable; 纯作息 JSON(timeList-only)合法。
// issue#55: WakeUp/ICS/CSV/HTML/文本/JSON 六通路恢复 ownTime 起止。
// issue#28: NEU ICS 教学块模型整表重建(analyzeNeuBlocks)。

import Foundation

enum ScheduleParser {

    struct ParseResult {
        let tableName: String
        let startDate: String
        let courses: [CourseEntity]
        /// ICS 事件里收割出的节次时间表 JSON; 非ICS/收割不到 → 空串(用默认)
        var timeJson: String = ""
        /// timeJson 覆盖的最大节次; 无 → 0
        var nodesPerDay: Int = 0
        /// 防呆: 输入里非空但没解析成功的行(前 40 字符), UI 拿去提示用户 "这几行没进去"
        var droppedLines: [String] = []
        /// 表级提示(T行钳制/节点抬升/chk不符/n=不符/二次表头); 行级问题走 droppedLines (sleepy-v1 §7.3)
        var warnings: [String] = []
        /// sleepy-v1: 总周数由解析端声明(修 P2 "maxWeek 写不读"); 0 = 旧路径未声明
        var maxWeek: Int = 0
        /// sleepy-v1: groupId 已由解析端权威生成, 落库必须绕过 assignGroupIds (§3.4 契约一)
        var groupIdsAuthoritative: Bool = false
        /// issue#40 §6 / v1.0.56 T10: 独立时间节次表。
        /// null = 旧格式/未携带 — 导入流程须为每张课表各建一张(不误共享)。
        var periodTable: ParsedPeriodTable? = nil
    }

    /// P 区块 / tableInfo 收割产物: sourceId = 导出时的 period_tables.id(恢复共享关系的键; 0 = 无既有表可指)
    struct ParsedPeriodTable {
        let sourceId: Int64
        let name: String
        let nodesPerDay: Int
        let timeJson: String
    }

    struct ParseError: LocalizedError {
        let message: String
        init(_ m: String) { message = m }
        var errorDescription: String? { message }
    }

    /// AI 输出隔离标识 — 标识之间的才是课表数据, 标识外(AI 开场白/结尾废话)全部丢弃
    // static let BEGIN_MARKER = "<<<SLEEPY-BEGIN>>>"  // 文档用, 匹配走 markerRegex
    // static let END_MARKER = "<<<SLEEPY-END>>>"

    /// 节次时间表行 — "时间表 1 08:00 09:35" / "第1-2节 08:20-10:00" / "1 08:00~09:35"。
    /// 课程行不含冒号, 所以"带两个 HH:mm 的行"必是时间表行, 无歧义。
    /// 2026-08-26: 作息块有专用标识符后(见 extractTimeBlock), 本正则只负责逐行判定。
    /// 捕获起始和结束节点; "第1-2节 08:20-10:00"(连上两节)展开为每个节点各一条相同时间。
    private static let timeTableRe: NSRegularExpression? = try? NSRegularExpression(
        pattern: "^\\s*(?:时间表|节次|第)?\\s*(\\d{1,2})(?:\\s*[-–]\\s*(\\d{1,2}))?\\s*节?\\s*[\\s:：]*\\s*(\\d{1,2}):(\\d{2})\\s*[-–~～至\\s]+\\s*(\\d{1,2}):(\\d{2})\\s*$")

    /// 自定义时间行(ICS DESCRIPTION 第 4 行) — "20:50-22:00"
    private static let ownTimeLineRe: NSRegularExpression? = try? NSRegularExpression(
        pattern: "(\\d{1,2}:\\d{2})-(\\d{1,2}:\\d{2})")

    // MARK: - 正则小工具(NSString 域, 避免 String/NSRange 混用)

    private static func match(_ re: NSRegularExpression?, _ s: String) -> NSTextCheckingResult? {
        guard let re = re else { return nil }
        let ns = s as NSString
        return re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length))
    }

    private static func matches(_ re: NSRegularExpression?, _ s: String) -> Bool {
        return match(re, s) != nil
    }

    private static func group(_ m: NSTextCheckingResult, _ s: String, _ i: Int) -> String? {
        guard i < m.numberOfRanges else { return nil }
        let r = m.range(at: i)
        if r.location == NSNotFound || r.length == 0 { return nil }
        return (s as NSString).substring(with: r)
    }

    // MARK: - 分派

    /// 解析课表文本。返回 .success / .failure(错误)。 ← Result<ParseResult>
    static func parse(_ text: String, defaultTableId: Int64, defaultColor: String = "#FF6750A4") -> Result<ParseResult, Error> {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return .failure(ParseError("空内容")) }
        // 防呆: 先统一全角字符(AI 常输出 １－２ / ～), 再提取标识, 再分派
        let trimmed = extractMarkedBody(normalizeFullWidth(raw))

        // 兼容性:导出端常在 JSON 前加 "【来自Sleepy】\n课程分享:\n\n" 前缀。
        // 如果 trimmed 不以 { 开头但包含 {,剥掉前缀再判别。
        let body: String
        if !trimmed.hasPrefix("{"), let r = trimmed.range(of: "{") {
            body = String(trimmed[r.lowerBound...])
        } else {
            body = trimmed
        }

        return Result {
            // sleepy-v1 原生格式 (§6.2: 分派链最顶 — magic 行首锚定, 与其他 5 路判别子串零交集)
            // 显式拒绝 v2: 用户的 "丢 v2 专有字段" 应有升级决策依据, 不静默尽力导入
            if SleepyNativeFormat.detectVersion(trimmed) > 1 {
                throw ParseError("文件由新版 Sleepy 导出(v\(SleepyNativeFormat.detectVersion(trimmed))),请升级 Sleepy 后导入")
            }
            if SleepyNativeFormat.detectVersion(trimmed) == 1 {
                return try SleepyNativeParser.parse(trimmed, defaultTableId: defaultTableId, defaultColor: defaultColor)
            }
            // Excel "另存为网页" 的 Frameset HTML (issue #6): 顶层只有 <frame> 引用,
            // 真课表在 xxx.files/sheet001.html 附属文件里, OpenDocument 拿不到 → 给出明确指引
            if isExcelFrameset(trimmed) {
                throw ParseError(excelFramesetError(trimmed))
            }
            if body.contains("\"courseDetailJson\"") {
                return try parseWakeUpShareText(body, defaultTableId)
            }
            if body.hasPrefix("{") && (body.contains("\"courses\"") || body.contains("\"tableInfo\"")) {
                return try parseWakeUpJson(body, defaultTableId, defaultColor)
            }
            if body.hasPrefix("BEGIN:VCALENDAR") || body.hasPrefix("BEGIN:VEVENT") {
                return try parseIcs(body, defaultTableId, defaultColor)
            }
            // HTML: 必须以 <!DOCTYPE / <html / <table / <body / <div 开头(先 trim 掉 BOM)
            if startsWithAnyTag(trimmed, tags: ["html", "body", "table", "div", "section", "article"]) {
                return try parseHtml(trimmed, defaultTableId, defaultColor)
            }
            // CSV: 含有 CSV 表头 (课程名/名称/course/name + (教师|老师|teacher 或 星期/周次)),并且至少 1 个换行
            if isLikelyCsv(trimmed) {
                return try parseCsv(trimmed, defaultTableId, defaultColor)
            }
            return try parseSimpleText(trimmed, defaultTableId, defaultColor)
        }
    }

    private static func startsWithAnyTag(_ s: String, tags: [String]) -> Bool {
        // BOM 已在 normalizeFullWidth 里转成空格, 再 trim 一次防 Windows 编辑器带 BOM 的 HTML
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.hasPrefix("<!doctype") || t.hasPrefix("<?xml") { return true }
        return tags.contains { t.hasPrefix("<\($0)") }
    }

    // MARK: - Excel Frameset 识别 (issue #6)

    /// 识别 Excel "另存为网页" 导出的 Frameset HTML (issue #6)。
    /// 判据: <frameset> 存在 且 (Excel Workbook Frameset meta 或 .files/sheet00N.html 引用)。
    /// 只认 frameset 不认 meta: 普通 HTML 页也可能带 Office meta 但内容可解析。
    static func isExcelFrameset(_ html: String) -> Bool {
        let lower = html.lowercased()
        if !lower.contains("<frameset") { return false }
        if lower.contains("excel workbook frameset") { return true }
        let refRe = try? NSRegularExpression(pattern: "\\.files/sheet\\d+\\.html")
        return matches(refRe, lower)
    }

    /// 提取 frameset 里 <link id="shLink"> / <frame src> 指向的 sheet 文件引用; 无 → 空串
    static func excelSheetRef(_ html: String) -> String {
        let linkRe = try? NSRegularExpression(pattern: "<link[^>]*id\\s*=\\s*\"?shLink\"?[^>]*>", options: [.caseInsensitive])
        let frameRe = try? NSRegularExpression(pattern: "<frame[^>]*src\\s*=\\s*\"?([^\">]*)\"?\"?[^>]*>", options: [.caseInsensitive])
        let shLink: String? = match(linkRe, html).map { (html as NSString).substring(with: $0.range) }
            ?? match(frameRe, html).map { (html as NSString).substring(with: $0.range) }
        guard let shLink else { return "" }
        let hrefRe = try? NSRegularExpression(pattern: "href\\s*=\\s*\"?([^\">\\s]+)\"?", options: [.caseInsensitive])
        let srcRe = try? NSRegularExpression(pattern: "src\\s*=\\s*\"?([^\">\\s]+)\"?", options: [.caseInsensitive])
        let m = match(hrefRe, shLink) ?? match(srcRe, shLink)
        guard let m, let v = group(m, shLink, 1) else { return "" }
        return v.trimmingCharacters(in: .whitespaces)
    }

    /// Frameset 识别后的用户指引报错 — 点名 Excel 结构和可行出路, 不用泛泛的"未找到表格"
    private static func excelFramesetError(_ html: String) -> String {
        let ref = excelSheetRef(html)
        let extra = !ref.isEmpty ? "（课表在附属文件 \(ref) 里，本应用无法读取）" : ""
        return "这是 Excel 导出的网页\(extra)，无法直接解析。请在 Excel 中另存为 CSV 文件或普通网页（不要选「单个文件网页/网页-筛选」格式）后重新导入"
    }

    // MARK: - AI 输出防呆(← extractMarkedBody + normalizeFullWidth + TIME 块)

    /// 提取 <<<SLEEPY-BEGIN>>> 和 <<<SLEEPY-END>>> 之间的内容(纯文本导入的 AI 输出隔离)。
    /// - 容忍标识写歪: 少/多横线、大小写、不同括号、首尾空白
    /// - 只有 BEGIN: 取 BEGIN 之后全部(END 缺失容错)
    /// - 只有 END: 取 END 之前全部
    /// - 都没有: 原样返回(手工输入不带标识, 走原有路径)
    /// 邻接标识(END 紧跟 BEGIN)按 Android 规: end.first > begin.last 成立 → 空内容,
    /// 而非落进 BEGIN-only 分支把 END 字面量留在正文里。
    static func extractMarkedBody(_ text: String) -> String {
        // 匹配 <<< / {{ / (( 等 2-4 个任意括号 + SLEEPY[- ]?(BEGIN|END) + 对应右括号, 大小写不敏感
        func markerRegex(_ kind: String) -> NSRegularExpression? {
            try? NSRegularExpression(pattern: "[<{(]{2,4}\\s*SLEEPY\\s*[-_ ]?\\s*\(kind)\\s*[>})]{2,4}",
                                     options: [.caseInsensitive])
        }
        let ns = text as NSString
        let beginM = match(markerRegex("begin"), text)
        let endM = match(markerRegex("end"), text)
        // ← Android: endM.range.first > beginM.range.last ⇔ e.location >= b.location + b.length
        // (begin.last = begin.location + begin.length - 1)。邻接标识(END 紧跟 BEGIN)在
        // 两端同时满足该条件 → 空正文 → trim 后 "" → parse 报「空内容」,
        // 不会落进 BEGIN-only 分支把 '<<<SLEEPY-END>>>' 字面量留在正文里。
        let body: String
        if let b = beginM, let e = endM, e.range.location >= b.range.location + b.range.length {
            let from = b.range.location + b.range.length
            body = ns.substring(with: NSRange(location: from, length: max(0, e.range.location - from)))
        } else if let b = beginM {
            body = ns.substring(from: b.range.location + b.range.length)
        } else if let e = endM {
            body = ns.substring(to: e.range.location)
        } else {
            body = text
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 全角→半角归一: 数字/字母/横线/波浪线/空格。AI 常输出 １－２ 或 1～16, 不归一就静默丢行。
    static func normalizeFullWidth(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(s.unicodeScalars.count)
        for c in s.unicodeScalars {
            switch c {
            case "０"..."９": out.append(UnicodeScalar(c.value - 0xFF10 + 0x30)!)
            case "ａ"..."ｚ": out.append(UnicodeScalar(c.value - 0xFF41 + 0x61)!)
            case "Ａ"..."Ｚ": out.append(UnicodeScalar(c.value - 0xFF21 + 0x41)!)
            case "－", "—", "―", "﹣": out.append("-")
            case "～", "~": out.append("~")
            case "　", "\u{FEFF}": out.append(" ")   // 全角空格 / BOM
            default: out.append(c)
            }
        }
        return String(out)
    }

    /// 作息表专用标识 — <<<SLEEPY-TIME-BEGIN>>> / <<<SLEEPY-TIME-END>>> 之间只放作息行。
    /// 与 BEGIN/END 同规格的宽松匹配: 大小写、2-4 个任意括号、-/_/空格变体。
    /// 注意不能被 markerRegex("begin"/"end") 误吞: SLEEPY 后面跟的是 -TIME-, 主标识正则匹配不上。
    private static func timeMarkerRegex(_ kind: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: "[<{(]{2,4}\\s*SLEEPY\\s*[-_ ]?\\s*TIME\\s*[-_ ]?\\s*\(kind)\\s*[>})]{2,4}",
                                 options: [.caseInsensitive])
    }

    /// 切出作息块。返回 (剩余文本, 作息块文本)。
    /// - 双标识: TIME-BEGIN..TIME-END 之间 = 作息块(严格: 块内垃圾行由调用方计入 dropped)
    /// - 只有 TIME-BEGIN: 从标识后连续吞 timeTableRegex 能吃的行(含空行), 首个不匹配行起归还正文
    ///   — 自愈"AI 忘写 TIME-END"的场景, 课程行不会被吃进作息块
    /// - 没有 TIME 标识: 返回原文 + 空块(走老的裸行兼容路径)
    private static func extractTimeBlock(_ text: String) -> (String, String) {
        guard let bm = match(timeMarkerRegex("begin"), text) else { return (text, "") }
        let ns = text as NSString
        let afterBegin = ns.substring(from: bm.range.location + bm.range.length)
        if let em = match(timeMarkerRegex("end"), afterBegin) {
            let block = (afterBegin as NSString).substring(to: em.range.location)
            let rest = (afterBegin as NSString).substring(from: em.range.location + em.range.length)
            return (rest, block)
        }
        // TIME-END 缺失: 吞连续作息行, 碰到首个非作息行停
        let lines = afterBegin.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let l = lines[i]
            let isBlank = l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isBlank || matches(timeTableRe, l.trimmingCharacters(in: .whitespaces)) {
                i += 1
            } else {
                break
            }
        }
        let rest = lines.dropFirst(i).joined(separator: "\n")
        let block = lines.prefix(i).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n")
        return (rest, block)
    }

    /// "08:00-09:35" / "08:00~09:35" / "08:00 09:35" → (startMin, endMin); 非法 nil
    private static func parseTimeRange(_ s: String) -> (Int, Int)? {
        let re = try? NSRegularExpression(pattern: "(\\d{1,2}):(\\d{2})\\s*[-–~～至\\s]+\\s*(\\d{1,2}):(\\d{2})")
        guard let m = match(re, s),
              let h1 = Int(group(m, s, 1) ?? ""), let mi1 = Int(group(m, s, 2) ?? ""),
              let h2 = Int(group(m, s, 3) ?? ""), let mi2 = Int(group(m, s, 4) ?? ""),
              (0...23).contains(h1), (0...59).contains(mi1),
              (0...23).contains(h2), (0...59).contains(mi2) else { return nil }
        let st = h1 * 60 + mi1, et = h2 * 60 + mi2
        return st < et ? (st, et) : nil
    }

    // MARK: - 判断 CSV

    /// 判断是否为 CSV:
    /// 1) 第一行包含逗号,且第二行也存在
    /// 2) 包含常见表头:课程/课程名/名称/course/name + (教师/老师/teacher 或 周次/星期)
    ///    — 教师列不再硬性要求: 教务导出常无教师列, 靠 课程+星期/周次 就足够定位 CSV
    private static func isLikelyCsv(_ s: String) -> Bool {
        if s.filter({ $0 == "\n" }).count < 1 { return false }
        guard let firstLine = s.split(separator: "\n").first.map(String.init)?.lowercased() else { return false }
        if !firstLine.contains(",") { return false }
        let hasCourse = firstLine.contains("课程") || firstLine.contains("course") || firstLine.contains("name")
        let hasTeacher = firstLine.contains("教师") || firstLine.contains("老师") || firstLine.contains("teacher")
        let hasDay = firstLine.contains("星期") || firstLine.contains("周几") || firstLine.contains("day") || firstLine.contains("周次")
        return hasCourse && (hasTeacher || hasDay)
    }

    // MARK: - v7.10.16k 无损收尾 + tableInfo 收割

    /// v7.10.16k 无损收尾 — 全格式路径统一: 节次数 = max(作息声明, 课程到达)。
    /// 用户 2026-09-03 实测 WakeUp 分享(补实验, startNode=11 step=3 → 13 节)
    /// 没带 tableInfo → 旧代码报 0 → 落库被老表钳成 10 = 丢节次。
    /// 没有时间 ≠ 没有节次; timeJson 原样保留(不伪造)。
    private static func lossless(_ tableName: String, _ startDate: String, _ courses: [CourseEntity],
                                 _ timeJson: String, _ declaredNodes: Int,
                                 // v1.0.56 T10: 混合导入自动建作息表 — 非 nil 时 ParseResult 携带独立作息表,
                                 // 落库端(ImportAsNew)自动建同名作息表并绑定
                                 _ periodTable: ParsedPeriodTable? = nil) -> ParseResult {
        let courseReach = courses.map { $0.startNode + $0.step - 1 }.max() ?? 0
        var result = ParseResult(tableName: tableName, startDate: startDate, courses: courses,
                                 timeJson: timeJson, nodesPerDay: max(declaredNodes, courseReach))
        result.periodTable = periodTable
        return result
    }

    /// 从 WakeUp JSON / Sleepy 导出的 tableInfo 里收割节次时间表。
    /// Sleepy 导出: tableInfo.time = 我们的 timeJson 原文, 直接用。
    /// WakeUp 原生: tableInfo.timeList = [{node, startTime, endTime}...] 逐条转。
    ///
    /// v1.0.56 T10: 收割结果同时产出 ParsedPeriodTable — 混合导入(课程+节次)时
    /// 自动建一张同名作息表并绑定, 不再只填课表兼容列。sourceId=0(无既有表可指)。
    ///
    /// 声明节次数(tableInfo.nodesPerDay): Sleepy 导出必带 — 作息行数可能少于声明
    /// (稀疏 timeJson 只存改动行), 导入不得把声明压掉(v7.10.16k 无损闭环)
    private static func harvestTimeFromTableInfo(_ root: [String: Any], _ tableName: String)
        -> (timeJson: String, nodesPerDay: Int, periodTable: ParsedPeriodTable?) {
        guard let tableInfo = root["tableInfo"] as? [String: Any] else { return ("", 0, nil) }
        let declared = intOrNull(tableInfo["nodesPerDay"]) ?? 0
        // Sleepy 自家格式: time 字段就是 timeJson
        if let time = tableInfo["time"] as? String, !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let nodes = TimeTableUtils.parseNodes(time)
            if let last = nodes.last {
                let nodesPerDay = max(last.node, declared)
                return (time, nodesPerDay,
                        ParsedPeriodTable(sourceId: 0, name: tableName, nodesPerDay: nodesPerDay, timeJson: time))
            }
        }
        // WakeUp 原生: timeList 数组
        guard let timeList = tableInfo["timeList"] as? [[String: Any]] else { return ("", declared, nil) }
        var nodeTimes: [Int: (Int, Int)] = [:]   // node → (startMin, endMin)
        for el in timeList {
            guard let nodeVal = el["node"], nodeVal is NSNumber || nodeVal is String else { continue }
            let node = intOrZero(nodeVal)
            guard node >= 1,
                  let st = contentOrNull(el["startTime"]).flatMap(parseHmLenient),
                  let et = contentOrNull(el["endTime"]).flatMap(parseHmLenient),
                  st < et else { continue }
            nodeTimes[node] = (st, et)
        }
        guard !nodeTimes.isEmpty else { return ("", declared, nil) }
        let builtJson = buildTimeJson(nodeTimes)
        let nodesPerDay = max(nodeTimes.keys.max() ?? 0, declared)
        return (builtJson, nodesPerDay,
                ParsedPeriodTable(sourceId: 0, name: tableName, nodesPerDay: nodesPerDay, timeJson: builtJson))
    }

    /// "08:00" / "8:00" / "0800" → 当日分钟数; 非法 nil
    private static func parseHmLenient(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let re = try? NSRegularExpression(pattern: "(\\d{1,2}):?(\\d{2})")
        guard let m = match(re, s),
              let r1 = group(m, s, 1), let r2 = group(m, s, 2),
              let h = Int(r1), let mi = Int(r2) else { return nil }
        return (0...23).contains(h) && (0...59).contains(mi) ? h * 60 + mi : nil
    }

    /// nodeTimes(node → 分钟对) → timeJson。空 → 空串(调用方用默认)。非连续节次照样输出存在的那些。
    private static func buildTimeJson(_ nodeTimes: [Int: (Int, Int)]) -> String {
        guard !nodeTimes.isEmpty else { return "" }
        var parts: [String] = []
        for n in nodeTimes.keys.sorted() {
            let t = nodeTimes[n]!
            parts.append("{\"node\":\(n),\"start\":\"\(hmString(t.0))\",\"end\":\"\(hmString(t.1))\"}")
        }
        return "[" + parts.joined(separator: ",") + "]"
    }

    /// 分钟数 → "HH:mm"(LocalTime.toString / fmtOwnTime 等价, 两位补零)
    private static func hmString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    // MARK: - WakeUp

    /// Kotlin String.isBlank() 等价
    private static func isBlank(_ s: String) -> Bool {
        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// ← JsonPrimitive.contentOrNull: JSON 字符串原样; 数字回其字面串(content 语义); JsonNull/结构 → nil
    private static func contentOrNull(_ v: Any?) -> String? {
        if v is NSNull || v == nil { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
    }

    /// 解析 WakeUp 分享文本格式:
    /// ```
    /// 【来自WakeUp课程表】
    /// 课程分享:
    ///
    /// {"name":"...","startDate":"...","courseDetailJson":"<URL-encoded JSON>"}
    /// ```
    /// 或简化版:
    /// ```
    /// 课程分享:
    /// {"name":"...","startDate":"...","courses":[...]}
    /// ```
    private static func parseWakeUpShareText(_ text: String, _ defaultTableId: Int64) throws -> ParseResult {
        // 找到 JSON 部分
        guard let jsonStart = text.range(of: "{") else {
            throw ParseError("找不到 JSON")
        }
        let jsonStr = String(text[jsonStart.lowerBound...])

        guard let data = jsonStr.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ParseError("JSON 解析失败")
        }
        let name = root["name"] as? String ?? "导入的课表"
        let startDate = (root["startDate"] as? String)
            ?? ((root["tableInfo"] as? [String: Any])?["startDate"] as? String)
            ?? todayString()

        let courses: [CourseEntity]
        if let courseDetailJsonStr = root["courseDetailJson"] as? String {
            // courseDetailJson 是 URL-encoded JSON 字符串
            // ← java.net.URLDecoder.decode(s, "UTF-8"): 表单编码语义, 先 '+'→空格 再百分号解码。
            //   WakeUp 分享文本(Android URLEncoder / 官方 app 导出)空格一律编码成 '+',
            //   直接 removingPercentEncoding 会留下 '+' → JSON 非法 → 整份分享解析失败。
            let plusNormalized = courseDetailJsonStr.replacingOccurrences(of: "+", with: "%20")
            let decoded = plusNormalized.removingPercentEncoding ?? plusNormalized
            courses = try parseCourseJsonArray(decoded, defaultTableId)
        } else {
            guard let arr = (root["courses"] as? [[String: Any]])
                ?? ((root["tableInfo"] as? [String: Any])?["courses"] as? [[String: Any]]) else {
                throw ParseError("找不到 courses 字段")
            }
            courses = parseCourseJsonArrayRaw(arr, defaultTableId)
        }

        // 节次时间表: Sleepy 自家导出把 timeJson 放在 tableInfo.time — 往返保真
        // v1.0.56 T10: 同时收割独立作息表(混合导入自动建表+绑定)
        let harvested = harvestTimeFromTableInfo(root, name)
        return lossless(name, startDate, courses, harvested.timeJson, harvested.nodesPerDay, harvested.periodTable)
    }

    /// ← JsonPrimitive.intOrNull: 数字或数字串→Int, 否则 nil(键缺失与非法值都 nil)
    private static func intOrNull(_ v: Any?) -> Int? {
        if v == nil || v is NSNull { return nil }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    /// 键存在时的 intOrZero 语义: 非法值 → 0(← JsonPrimitive.intOrZero(): content.toIntOrNull() ?: 0)
    private static func intOrZero(_ v: Any?) -> Int {
        if v == nil || v is NSNull { return 0 }
        return intOrNull(v) ?? 0
    }

    /// 键缺失给默认、键存在但非数字/JsonNull 给 0 — ← obj["k"]?.jsonPrimitive?.intOrZero() ?: def
    /// (def 只在 key 缺失时生效; day="一"/null → 0, 对齐 Android JsonPrimitive.intOrZero())
    private static func intField(_ obj: [String: Any], _ key: String, def: Int) -> Int {
        guard let v = obj[key] else { return def }
        return intOrZero(v)
    }

    private static func parseWakeUpJson(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        guard let data = text.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ParseError("JSON 解析失败")
        }
        let name = root["name"] as? String ?? "导入的课表"
        let startDate = (root["startDate"] as? String) ?? todayString()
        // v1.0.56 T11: 纯作息 JSON(只有 tableInfo.timeList, 无 courses)是合法形态 —
        // 空课程 + periodTable 非空 → 导入端 T9 纯作息路径只建作息表
        let arr: [[String: Any]]
        if let a = root["courses"] as? [[String: Any]] {
            arr = a
        } else if let timeList = (root["tableInfo"] as? [String: Any])?["timeList"] as? [[String: Any]],
                  !timeList.isEmpty {
            arr = []
        } else {
            throw ParseError("找不到 courses 数组")
        }

        let courses: [CourseEntity] = arr.map { obj in
            // issue#55: 与 parseCourseJsonArrayRaw 同规 — 带 startTime/endTime 恢复 ownTime
            let ownStart = contentOrNull(obj["startTime"]) ?? ""
            let ownEnd = contentOrNull(obj["endTime"]) ?? ""
            let ownTime = !isBlank(ownStart) && !isBlank(ownEnd)
            return CourseEntity(
                groupId: "",
                tableId: defaultTableId,
                courseName: (obj["name"] as? String) ?? (obj["courseName"] as? String) ?? "未命名",
                teacher: obj["teacher"] as? String ?? "",
                room: (obj["position"] as? String) ?? (obj["room"] as? String) ?? "",
                note: obj["note"] as? String ?? "",
                day: intField(obj, "day", def: 1),
                startNode: intField(obj, "startNode", def: 1),
                step: intField(obj, "step", def: 1),
                startWeek: intField(obj, "startWeek", def: 1),
                endWeek: intField(obj, "endWeek", def: 16),
                type: intField(obj, "type", def: 0),
                color: (obj["color"] as? String) ?? defaultColor,
                ownTime: ownTime,
                startTime: ownTime ? ownStart : "",
                endTime: ownTime ? ownEnd : ""
            )
        }

        // 节次时间表: tableInfo.time(Sleepy 导出) / timeList(WakeUp 原生)
        // v1.0.56 T10: 同时收割独立作息表(混合导入自动建表+绑定)
        let harvested = harvestTimeFromTableInfo(root, name)
        return lossless(name, startDate, courses, harvested.timeJson, harvested.nodesPerDay, harvested.periodTable)
    }

    private static func parseCourseJsonArray(_ jsonStr: String, _ tableId: Int64) throws -> [CourseEntity] {
        guard let data = jsonStr.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw ParseError("courseDetailJson 解析失败")
        }
        return parseCourseJsonArrayRaw(arr, tableId)
    }

    private static func parseCourseJsonArrayRaw(_ arr: [[String: Any]], _ tableId: Int64) -> [CourseEntity] {
        return arr.map { obj in
            // issue#55: Sleepy 导出的非标准时间课程带 startTime/endTime — 读完恢复 ownTime,
            // 缺字段(原生 WakeUp 分享常态)保持 ownTime=false 兼容
            let ownStart = contentOrNull(obj["startTime"]) ?? ""
            let ownEnd = contentOrNull(obj["endTime"]) ?? ""
            let ownTime = !isBlank(ownStart) && !isBlank(ownEnd)
            return CourseEntity(
                groupId: "",
                tableId: tableId,
                courseName: (obj["name"] as? String) ?? (obj["courseName"] as? String) ?? "未命名",
                teacher: obj["teacher"] as? String ?? "",
                room: obj["position"] as? String ?? "",
                note: "",
                day: intField(obj, "day", def: 1),
                startNode: intField(obj, "startNode", def: 1),
                step: intField(obj, "step", def: 1),
                startWeek: intField(obj, "startWeek", def: 1),
                endWeek: intField(obj, "endWeek", def: 16),
                type: intField(obj, "type", def: 0),
                color: (obj["color"] as? String) ?? "#FF6750A4",
                ownTime: ownTime,
                startTime: ownTime ? ownStart : "",
                endTime: ownTime ? ownEnd : ""
            )
        }
    }

    // MARK: - ICS (RFC 5545)

    /// 解析 ICS 日历文件 (RFC 5545)。 ← Android 完整语义
    ///
    /// 支持两类来源:
    /// 1. WakeUp 课程表导出 — SUMMARY=课名, DESCRIPTION="第X - Y节\n教室\n教师"(字面 \n 转义),
    ///    每个实际上课时段一条 VEVENT(双周课拆成 N 条 INTERVAL=1 的短事件),
    ///    UNTIL 日期为最后一次发生的日历日(可能比该次晚 6 天,按同星期几对齐回推)。
    /// 2. Sleepy 自家导出 — DESCRIPTION 含 "第X - Y节"(v7.10.16k 起) 与末尾 "\nHH:mm-HH:mm"
    ///    ownTime 时间行(issue#55), 单双周用 INTERVAL=2 表达。
    ///
    /// 语义:
    /// - 学期锚点 = 最早 DTSTART 所在周的周一 → startDate(周数编号基准)
    /// - 周区间 = [DTSTART 周, UNTIL 对齐星期几后的最后一次发生周]
    /// - 节次优先读 DESCRIPTION "第X - Y节", 无则按 50min/节估算; NEU 导出走教学块模型(issue#28)
    /// - 同(课名,星期,节次,教师)的多个 VEVENT 按周序列合并:
    ///   连续拼合→type=0; 全同奇偶且间距2→单/双周; 否则(散周)保持独立行
    /// - 全校作息收割: 节次 → (start,end), 跨 lunch 的多节块只锚定两端
    private static func parseIcs(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        struct Event {
            let name: String, day: Int, startNode: Int, step: Int
            let teacher: String, room: String
            let firstDate: Date, lastDate: Date, interval: Int
            let ownStart: String, ownEnd: String
        }

        var events: [Event] = []
        let isNeuIcs = matches(try? NSRegularExpression(
            pattern: "^PRODID:.*NEU_Wisedu2Wakeup",
            options: [.caseInsensitive, .anchorsMatchLines]), text)
        // NEU 导出把真实时间块作为若干逻辑教学时段, 块间午休/晚间间隔不占节次。
        // issue #28: 教学块模型整表重建 — 原子块(起止之间不含其他块起点)给出
        // 节次行, 连排事件映射为跨块节次区间; 不再走逐事件收割。旧法两个缺陷:
        // 同一时刻"最长事件步数"套给该时刻所有事件(08:00-09:40 被拉成 1-4 节),
        // 以及长事件 start 写进共享 endNode.start(第4节 08:00-11:40 时间倒挂)。
        let neuBlocks = isNeuIcs ? analyzeNeuBlocks(text) : []
        // 全校作息收割: 节次 → (startMin, endMin)。每个 VEVENT 直接给出
        // node[首节].start=DTSTART, node[末节].end=DTEND, 中间节次按边界推导。
        var nodeTimes: [Int: (Int, Int)] = [:]
        for raw in text.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            let endIdx = raw.range(of: "END:VEVENT")?.lowerBound ?? raw.endIndex
            let block = String(raw[raw.startIndex..<endIdx])

            guard let summary = extractIcsField(block, "SUMMARY") else { continue }
            let location = extractIcsField(block, "LOCATION") ?? ""
            let description = extractIcsField(block, "DESCRIPTION") ?? ""
            let descLines = description.components(separatedBy: "\\n")

            // WakeUp: DESCRIPTION="第X - Y节\n教室\n教师", LOCATION="教室 教师" / Sleepy: DESCRIPTION="老师：X"
            let teacher: String
            if descLines.count >= 3 {
                teacher = descLines[2].trimmingCharacters(in: .whitespaces)
            } else if description.hasPrefix("老师：") {
                teacher = String(description.dropFirst("老师：".count)).trimmingCharacters(in: .whitespaces)
            } else if description.hasPrefix("老师:") {
                teacher = String(description.dropFirst("老师:".count)).trimmingCharacters(in: .whitespaces)
            } else {
                teacher = ""
            }
            let room: String
            if descLines.count >= 2, !isBlank(descLines[1]) {
                room = descLines[1].trimmingCharacters(in: .whitespaces)
            } else if !location.isEmpty && !teacher.isEmpty && location.hasSuffix(teacher) {
                room = String(location.dropLast(teacher.count)).trimmingCharacters(in: .whitespaces)
            } else {
                room = location
            }

            // issue#55: Sleepy 自家 ICS 在 DESCRIPTION 末尾追加 "\nHH:mm-HH:mm" 时间行
            // (exportIcs ownTimeLine)。读到 → 恢复 ownTime; WakeUp 原生无此行不受影响。
            // 布局: [0]=第X-Y节 [1]=教室 [2]=教师 [3]=HH:mm-HH:mm(ownTime 时)
            let ownTimeLine = descLines.count > 3 ? descLines[3].trimmingCharacters(in: .whitespaces) : ""
            let ownTimeMatch = ownTimeLine.isEmpty ? nil : match(ownTimeLineRe, ownTimeLine)

            guard let day = extractIcsDayOfWeek(block) else { continue }
            guard let dtstart = extractIcsDate(block) else { continue }
            let explicitNode = extractIcsNode(description)
            let neuSpan = (explicitNode == nil && isNeuIcs) ? neuSpanFor(neuBlocks, block) : nil
            let timeSpan = (explicitNode == nil && !isNeuIcs) ? extractIcsTime(block) : nil
            guard let (startNode, step) = explicitNode ?? neuSpan ?? timeSpan else { continue }

            // 作息收割: NEU 走块模型整表重建(buildNeuTimetable), 不逐事件合并;
            // 非 NEU (如 WakeUp 导出带 DESCRIPTION 第X-Y节) 保留逐事件收割。
            if !isNeuIcs { harvestNodeTimes(block, startNode, step, &nodeTimes) }

            let rrule = extractIcsField(block, "RRULE") ?? ""
            let interval = rrule.contains("INTERVAL=2") ? 2 : 1
            // UNTIL 是最后一次发生的日历日(可能晚于该次 0-6 天) → 对齐回同星期几
            var untilDate = dtstart
            if let um = match(try? NSRegularExpression(pattern: "UNTIL=(\\d{8})"), rrule),
               let us = group(um, rrule, 1), let ud = parseIcsDate(us) {
                untilDate = ud
            }
            let deltaDays = Calendar.isoDaysBetween(dtstart, untilDate)
            let lastOccurrence = Calendar.isoAddDays(dtstart, deltaDays - deltaDays % 7)

            let ownStart = ownTimeMatch.flatMap { group($0, ownTimeLine, 1) } ?? ""
            let ownEnd = ownTimeMatch.flatMap { group($0, ownTimeLine, 2) } ?? ""

            events.append(Event(name: summary, day: day, startNode: startNode, step: step,
                                teacher: teacher, room: room,
                                firstDate: dtstart, lastDate: lastOccurrence, interval: interval,
                                ownStart: ownStart, ownEnd: ownEnd))
        }

        if events.isEmpty {
            return ParseResult(tableName: "导入的 ICS 课表", startDate: todayString(), courses: [])
        }

        // 锚点: 最早 DTSTART 所在周的周一 → 周数编号基准
        let anchor = Calendar.isoMondayOfWeek(events.map { $0.firstDate }.min()!)

        // 按 (课名,星期,节次,教师) 聚合各周区间 — room 不进键:
        // WakeUp 会把"每周换教室的同一门课"拆成多条 VEVENT,若 room 进键会把同一时段拆成
        // 两组各自"同奇偶间距2"的散周 → 被误判成两个假单双周(实证: 24sp 管理心理学)。
        // room 变化交给散周 room-run 合并处理。
        struct SlotKey: Hashable { let name: String, day: Int, node: Int, step: Int, teacher: String }
        var groups: [SlotKey: [(Int, Int, String)]] = [:]   // (startW, endW, room)
        var groupOrder: [SlotKey] = []
        var groupInterval: [SlotKey: Int] = [:]
        // issue#55: 同组事件来自同一课程实体, ownTime 时间恒一致 — 取首个非空即可
        var groupOwnTime: [SlotKey: (String, String)] = [:]
        func weekOf(_ d: Date) -> Int { Calendar.isoDaysBetween(anchor, d) / 7 + 1 }
        for e in events {
            let key = SlotKey(name: e.name, day: e.day, node: e.startNode, step: e.step, teacher: e.teacher)
            if groups[key] == nil { groupOrder.append(key) }
            groups[key, default: []].append((weekOf(e.firstDate), weekOf(e.lastDate), e.room))
            groupInterval[key] = e.interval
            if !e.ownStart.isEmpty && !e.ownEnd.isEmpty && groupOwnTime[key] == nil {
                groupOwnTime[key] = (e.ownStart, e.ownEnd)
            }
        }

        var courses: [CourseEntity] = []
        func emit(_ key: SlotKey, _ startWeek: Int, _ endWeek: Int, _ type: Int, _ room: String) {
            let own = groupOwnTime[key]
            courses.append(CourseEntity(
                groupId: "", tableId: defaultTableId,
                courseName: key.name, teacher: key.teacher, room: room, note: "",
                day: key.day, startNode: key.node, step: key.step,
                startWeek: startWeek, endWeek: endWeek, type: type,
                color: defaultColor,
                ownTime: own != nil,
                startTime: own?.0 ?? "",
                endTime: own?.1 ?? "",
                id: 0
            ))
        }

        for key in groupOrder {
            let chunks = groups[key]!.sorted { a, b in
                a.0 != b.0 ? a.0 < b.0 : (a.1 != b.1 ? a.1 < b.1 : a.2 < b.2)
            }
            let interval = groupInterval[key] ?? 1
            let spans = chunks.map { ($0.0, $0.1) }

            func contiguous() -> Bool {
                zip(spans, spans.dropFirst()).allSatisfy { $0.1.0 - $0.0.1 == 1 }
            }
            func allSingleSameParitySpaced2() -> Bool {
                if spans.contains(where: { $0.0 != $0.1 }) { return false }
                let starts = spans.map { $0.0 }
                if Set(starts.map { $0 % 2 }).count != 1 { return false }
                return zip(starts, starts.dropFirst()).allSatisfy { $1 - $0 == 2 }
            }

            if spans.count == 1 {
                emit(key, spans[0].0, spans[0].1, 0, chunks[0].2)
            } else if contiguous() {
                // 1) 逐周连续 → 合并为每周区间(room 取首个 chunk)
                emit(key, spans.first!.0, spans.last!.1, 0, chunks[0].2)
            } else if interval == 2 || allSingleSameParitySpaced2() {
                // 2) 全部单周且同奇偶且间距 2 → 单/双周序列(INTERVAL=2 单条事件同理)
                let startW = spans.first!.0
                emit(key, startW, spans.last!.0, startW % 2 == 1 ? 1 : 2, chunks[0].2)
            } else {
                // 3) 散周: 按教室分段合并连续段,每段一行(换教室课程按实际分段输出)
                var curRoom: String? = nil
                var curStart = 0, curEnd = 0
                for (a, b, r) in chunks {
                    if r == curRoom && a <= curEnd + 1 {
                        curEnd = max(curEnd, b)
                    } else {
                        if curRoom != nil { emit(key, curStart, curEnd, 0, curRoom!) }
                        curRoom = r; curStart = a; curEnd = b
                    }
                }
                if curRoom != nil { emit(key, curStart, curEnd, 0, curRoom!) }
            }
        }

        // NEU: 整表由块模型重建(与事件写入顺序无关); 非 NEU: 逐事件收割结果。
        let timeMap = isNeuIcs ? buildNeuTimetable(neuBlocks) : nodeTimes
        return lossless(
            "导入的 ICS 课表",
            Calendar.isoString(anchor),
            courses,
            buildTimeJson(timeMap),
            timeMap.isEmpty ? 0 : (timeMap.keys.max() ?? 0)
        )
    }

    /// Math.round(double).toInt() 等价 — 半数向上(与 Java 一致, 非 Swift 默认 toNearestOrEven)
    private static func roundHalfUp(_ x: Double) -> Int {
        return Int(floor(x + 0.5))
    }

    /// 从单个 VEVENT 收割节次边界: 事件占 [startNode, startNode+step-1] 节,
    /// DTSTART=首节start, DTEND=末节end, 中间节次边界从相邻块推导(块内均匀)。
    /// 冲突时后写覆盖 — 同校作息一致,不同事件只是补充对方缺的节次。
    ///
    /// 跨 lunch/晚上的多节块(如 1-4 @ 08:20-12:00)不能均匀切 — 只锚定两端,
    /// 中间节次交给其他恰好落界的块(如 1-2/3-4)去补,补不上就保持 gap。
    private static func harvestNodeTimes(_ block: String, _ startNode: Int, _ step: Int,
                                         _ out: inout [Int: (Int, Int)]) {
        guard let dtstart = extractIcsField(block, "DTSTART"),
              let dtend = extractIcsField(block, "DTEND"),
              let start = icsTimeAfterT(dtstart),
              let end = icsTimeAfterT(dtend),
              start < end else { return }

        let endNode = startNode + step - 1
        if step <= 2 {
            for n in startNode...endNode {
                let s = n == startNode ? start : nil
                let e = n == endNode ? end : nil
                let prev = out[n]
                out[n] = (s ?? prev?.0 ?? start, e ?? prev?.1 ?? end)
            }
        } else {
            let prevFirst = out[startNode]
            let prevLast = out[endNode]
            out[startNode] = (start, prevFirst?.1 ?? end)
            out[endNode] = (prevLast?.0 ?? start, end)
        }
    }

    /// DTSTART/DTEND 值 "T" 后取 6 位 "HHmmss" → 当日分钟数
    /// ← Kotlin substringAfter("T"): 无 "T" 时返回整串(与 Android 同规), 再 take(6)
    private static func icsTimeAfterT(_ value: String) -> Int? {
        let tail: Substring
        if let tIdx = value.firstIndex(of: "T") {
            tail = value[value.index(after: tIdx)...]
        } else {
            tail = value[...]
        }
        return parseIcsTimeOfDay(String(tail.prefix(6)))
    }

    /// "HHmmss" 前缀 → 当日分钟数; 非法 nil
    private static func parseIcsTimeOfDay(_ s: String) -> Int? {
        guard s.count >= 4,
              let h = Int(s.prefix(2)), let m = Int(s.dropFirst(2).prefix(2)) else { return nil }
        return (0...23).contains(h) && (0...59).contains(m) ? h * 60 + m : nil
    }

    /// "yyyyMMdd" → Date; 非法 nil
    private static func parseIcsDate(_ s: String) -> Date? {
        guard s.count >= 8,
              let y = Int(s.prefix(4)), let mo = Int(s.dropFirst(4).prefix(2)), let d = Int(s.dropFirst(6).prefix(2)) else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d
        return DateUtils.isoCalendar.date(from: comps)
    }

    /// 从 DTSTART 值提取日期部分(形如 20260831T082000 / 20260831)
    private static func extractIcsDate(_ block: String) -> Date? {
        guard let dtstart = extractIcsField(block, "DTSTART") else { return nil }
        return parseIcsDate(String((dtstart.components(separatedBy: "T").first ?? "").prefix(8)))
    }

    /// 从 DESCRIPTION "第X - Y节" 提取节次; 兼容无此行场景(返回 nil 走时间估算/块模型)
    private static func extractIcsNode(_ description: String) -> (Int, Int)? {
        let re = try? NSRegularExpression(pattern: "第\\s*(\\d+)\\s*[-–]\\s*(\\d+)\\s*节")
        guard let m = match(re, description),
              let aStr = group(m, description, 1), let bStr = group(m, description, 2),
              let a = Int(aStr), let b = Int(bStr),
              a >= 1, b >= a else { return nil }
        return (a, b - a + 1)
    }

    private static func extractIcsField(_ block: String, _ name: String) -> String? {
        // ICS 字段可能折行 (下一行以空格开头) — (?m)^NAME(?:;[^:]*)?:(.*(?:\n .*)*)
        let pattern = "(?m)^\(name)(?:;[^:]*)?:(.*(?:\\n .*)*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = block as NSString
        guard let m = regex.firstMatch(in: block, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: block) else { return nil }
        return block[r]
            .replacingOccurrences(of: "\n ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// NEU 教学块: [start,end] 时钟区间 → [firstNode, firstNode+nodeCount-1] 节次区间
    private struct NeuBlock {
        let start: Int   // 当日分钟
        let end: Int
        let nodeCount: Int
        let firstNode: Int
        var lastNode: Int { firstNode + nodeCount - 1 }
    }

    /// issue #28: NEU ICS 节次重建的块模型。
    ///
    /// 从全部 VEVENT 的 (DTSTART, DTEND) 形态推导教学块: **原子块** = 起止之间
    /// 不含其他事件开始时刻的形态(如 08:00-09:40; 08:00-11:40 中间含 10:00 →
    /// 是跨块连排, 不是块)。块宽按 50min/节(45课+5间)从块自身时长四舍五入,
    /// 节次编号从 1 跨块累加; 块间空档(午休/晚休)不占节次。
    private static func analyzeNeuBlocks(_ text: String) -> [NeuBlock] {
        var shapes: [(Int, Int)] = []
        for raw in text.components(separatedBy: "BEGIN:VEVENT").dropFirst() {
            let endIdx = raw.range(of: "END:VEVENT")?.lowerBound ?? raw.endIndex
            let block = String(raw[raw.startIndex..<endIdx])
            guard let s = extractIcsField(block, "DTSTART").flatMap(icsTimeAfterT),
                  let e = extractIcsField(block, "DTEND").flatMap(icsTimeAfterT),
                  s < e else { continue }
            shapes.append((s, e))
        }
        let startTimes = Array(Set(shapes.map { $0.0 })).sorted()
        var acc = 1
        return startTimes.map { s in
            // 原子块终点 = 该开始时刻所有事件里最早的结束时刻(连排事件的终点属于后面的块)
            let end = shapes.filter { $0.0 == s }.map { $0.1 }.min()!
            let nodeCount = max(roundHalfUp(Double(end - s) / 50.0), 1)
            let blk = NeuBlock(start: s, end: end, nodeCount: nodeCount, firstNode: acc)
            acc += nodeCount
            return blk
        }
    }

    /// 事件 → 节次区间。终点恰好是某块终点 → 精确跨块(块 i 到块 j);
    /// 否则按起点块的每节分钟数折算步数。
    /// 显式 DESCRIPTION 节次在调用方优先, 本函数只处理 NEU 的无描述导出。
    private static func neuSpanFor(_ blocks: [NeuBlock], _ block: String) -> (Int, Int)? {
        guard let dtstart = extractIcsField(block, "DTSTART"),
              let dtend = extractIcsField(block, "DTEND"),
              let start = icsTimeAfterT(dtstart),
              let end = icsTimeAfterT(dtend) else { return nil }
        guard let i = blocks.firstIndex(where: { $0.start == start }) else { return nil }
        let b = blocks[i]
        if let j = blocks.firstIndex(where: { $0.end == end }), j > i {
            return (b.firstNode, blocks[j].lastNode - b.firstNode + 1)
        }
        let perNode = Double(b.end - b.start) / Double(b.nodeCount)
        let step = max(roundHalfUp(Double(end - start) / perNode), 1)
        return (b.firstNode, step)
    }

    /// 块模型 → 节次时间表: 块内均匀插值(块首节 start=块起点, 块末节 end=块终点),
    /// 块间空档不产生行。与事件写入顺序无关。
    private static func buildNeuTimetable(_ blocks: [NeuBlock]) -> [Int: (Int, Int)] {
        var out: [Int: (Int, Int)] = [:]
        for b in blocks {
            let startSec = b.start * 60
            let endSec = b.end * 60
            let perNodeSec = Double(endSec - startSec) / Double(b.nodeCount)
            for k in 0..<b.nodeCount {
                let s = roundHalfUp(Double(startSec) + Double(k) * perNodeSec) / 60
                let e = roundHalfUp(Double(startSec) + Double(k + 1) * perNodeSec) / 60
                out[b.firstNode + k] = (s, e)
            }
        }
        return out
    }

    /// 从 DTSTART/DTEND 提取节次(按 45min课+5min课间≈50min/节估算; DESCRIPTION 无"第X-Y节"时的兜底)
    private static func extractIcsTime(_ block: String) -> (Int, Int)? {
        guard let dtstart = extractIcsField(block, "DTSTART"),
              let dtend = extractIcsField(block, "DTEND"),
              let start = icsTimeAfterT(dtstart),
              let end = icsTimeAfterT(dtend) else { return nil }
        let duration = end - start
        // 8:00 = 第 1 节; 节边界按 50min 周期近似(45课+5课间), +10min 防边界抖动
        let startNode = (start - 480 + 10) / 50 + 1
        let step = max(roundHalfUp(Double(duration) / 50.0), 1)
        return (max(startNode, 1), step)
    }

    /// 从 DTSTART 或 BYDAY 提取星期几。优先从 DTSTART 推算(最可靠)
    private static func extractIcsDayOfWeek(_ block: String) -> Int? {
        // 1) 优先从 DTSTART 的日期推算星期几
        if let dtstart = extractIcsField(block, "DTSTART") {
            let dateStr = String((dtstart.components(separatedBy: "T").first ?? "").prefix(8))  // yyyyMMdd
            if dateStr.count == 8,
               let y = Int(dateStr.prefix(4)), let mo = Int(dateStr.dropFirst(4).prefix(2)), let d = Int(dateStr.dropFirst(6).prefix(2)) {
                var comps = DateComponents()
                comps.year = y; comps.month = mo; comps.day = d
                var cal = Calendar(identifier: .gregorian)
                cal.timeZone = TimeZone(identifier: "UTC")!
                if let date = cal.date(from: comps) {
                    let dow = cal.component(.weekday, from: date)  // 1=Sun..7=Sat
                    let iso = dow == 1 ? 7 : dow - 1               // → 1=Mon..7=Sun
                    if (1...7).contains(iso) { return iso }
                }
            }
        }
        // 2) 退而求其次:找 RRULE.BYDAY
        guard let rrule = extractIcsField(block, "RRULE"),
              let m = rrule.range(of: "BYDAY=([A-Z]{2})", options: .regularExpression),
              let r = rrule[m].range(of: "[A-Z]{2}$", options: .regularExpression) else { return nil }
        switch String(rrule[r]) {
        case "MO": return 1
        case "TU": return 2
        case "WE": return 3
        case "TH": return 4
        case "FR": return 5
        case "SA": return 6
        case "SU": return 7
        default: return nil
        }
    }

    // MARK: - 纯文本

    /// 解析简化的纯文本格式:
    /// 一行一课,字段间用制表符或全角逗号分隔。
    ///
    /// 时间表(2026-08-26): 课前可混排节次时间行 — "时间表 1 08:00 09:35" / "第1节 08:00-09:35",
    /// 截图带时间的场景 AI 直接照抄, 导入即拥有真实作息。课程行不含冒号, 无冲突。
    ///
    /// 防呆(AI 输出不可信, 2026-08-26):
    ///  - Markdown 表格行(| a | b |)和 |---| 分隔行先剥管道再解析
    ///  - 星号加粗 **高数** → 高数
    ///  - 星期列接受 周一/Monday/mon
    ///  - 区间反写 16-1 自动排序
    ///  - day 越界(0/8)钳到 1..7
    ///  - 解析失败的非空行计入 droppedLines, UI 提示用户
    private static func parseSimpleText(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        var courses: [CourseEntity] = []
        var dropped: [String] = []
        var nodeTimes: [Int: (Int, Int)] = [:]

        // 作息块: <<<SLEEPY-TIME-BEGIN>>>..<<<SLEEPY-TIME-END>>> 优先切出。
        // 块内行全部走作息正则, 不匹配的计入 dropped(不静默丢)。
        // 没有标识时兼容老的裸作息行(混排在课程行前面)。
        let (courseText, timeBlock) = extractTimeBlock(text)
        var timeBlockDropped: [String] = []
        for tl in timeBlock.components(separatedBy: "\n") {
            if isBlank(tl) { continue }
            let trimmed = tl.trimmingCharacters(in: .whitespaces)
            guard let tt = match(timeTableRe, trimmed) else {
                timeBlockDropped.append(String(trimmed.prefix(40)))
                continue
            }
            let startNode = Int(group(tt, trimmed, 1) ?? "")
            let endNode = Int(group(tt, trimmed, 2) ?? "") ?? startNode
            let st = clockGroup(tt, trimmed, 3, 4)
            let et = clockGroup(tt, trimmed, 5, 6)
            if let sn = startNode, let en = endNode, en >= sn, let st = st, let et = et, st < et {
                for node in sn...en { nodeTimes[node] = (st, et) }
            } else {
                timeBlockDropped.append(String(trimmed.prefix(40)))
            }
        }

        let lines = courseText.components(separatedBy: "\n")
            .filter { !isBlank($0) && !$0.hasPrefix("#") }

        for raw in lines {
            // 裸作息行兼容: 没写 TIME 标识的输入, "带两个 HH:mm 的行"必是时间表行
            if let tt = match(timeTableRe, raw) {
                guard let startNode = Int(group(tt, raw, 1) ?? "") else { continue }
                let endNode = Int(group(tt, raw, 2) ?? "") ?? startNode
                let st = clockGroup(tt, raw, 3, 4)
                let et = clockGroup(tt, raw, 5, 6)
                if endNode >= startNode, let st = st, let et = et, st < et {
                    for node in startNode...endNode { nodeTimes[node] = (st, et) }
                }
                continue
            }
            // 剥 Markdown: 管道表格行 + 表头分隔行 + 星号加粗 + 反引号
            var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if matches(try? NSRegularExpression(pattern: "^\\|?[\\s|:-]+\\|?$"), line) { continue }  // |---|---| 或整行管道
            if line.hasPrefix("|") || line.hasSuffix("|") {
                line = line.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .replacingOccurrences(of: "\\s*\\|\\s*", with: "\t", options: .regularExpression)
            }
            line = line.replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespaces)

            // 支持 tab / 多空格 / 全角逗号 — ← split(Regex("\\s+|，"))
            let parts = splitByWhitespaceOrFullwidthComma(line)
            if parts.count < 6 {
                if !line.isEmpty { dropped.append(String(line.prefix(40))) }
                continue
            }

            let name = parts[0]
            let teacher = parts[1]
            let room = parts[2]
            // 纯数字 0/8 越界也收(钳到 1..7), 其余走 parseDay(周一/Monday)
            guard let day = (Int(parts[3].trimmingCharacters(in: .whitespaces)) ?? parseDay(parts[3]))
                .map({ min(max($0, 1), 7) }) else {
                dropped.append(String(line.prefix(40))); continue
            }
            // 节次列是 start-end 格式 (e.g. "1-2"), 转为 (startNode, step=end-start+1); 反写自动排序
            guard let (nodeStart, nodeEnd) = parseRange(parts[4]).map(sortRange) else {
                dropped.append(String(line.prefix(40))); continue
            }
            let step = max(nodeEnd - nodeStart + 1, 1)
            guard let (startWeek, endWeek) = parseRange(parts[5]).map(sortRange) else {
                dropped.append(String(line.prefix(40))); continue
            }
            let type = parts.count > 6 ? parseType(parts[6]) : 3
            // issue#55: 类型之后再跟钟点 → 该行是非标准时间课程, 起止为课程私有。
            // 两种写法都认: "20:50 22:00"(两列) / "20:50-22:00"(一列)。
            // 课程行本身不含冒号(作息行在上方已被 timeTableRegex 截走), 无歧义。
            let extra7 = parts.count > 7 ? parts[7] : ""
            let extra8 = parts.count > 8 ? parts[8] : ""
            let ownPair: (Int, Int)?
            if !isBlank(extra8), let p = parseTimeRange("\(extra7)-\(extra8)") {
                ownPair = p
            } else if extra7.contains(":"), let p = parseTimeRange(extra7) {
                ownPair = p
            } else {
                ownPair = nil
            }
            let rowOwnTime = ownPair != nil
            let ownStart = ownPair.map { hmString($0.0) } ?? ""
            let ownEnd = ownPair.map { hmString($0.1) } ?? ""

            courses.append(CourseEntity(
                groupId: "",
                tableId: defaultTableId,
                courseName: name,
                teacher: teacher,
                room: room,
                day: day,
                startNode: nodeStart,
                step: step,
                startWeek: startWeek,
                endWeek: endWeek,
                type: type,
                color: defaultColor,
                ownTime: rowOwnTime,
                startTime: rowOwnTime ? ownStart : "",
                endTime: rowOwnTime ? ownEnd : "",
                id: 0
            ))
        }

        if courses.isEmpty { throw ParseError("未能解析任何课程") }

        // v7.10.16k: 无损收尾走统一 lossless() — 节次数 = max(作息声明, 课程到达)
        var result = lossless(
            "导入的课表",
            todayString(),
            courses,
            buildTimeJson(nodeTimes),
            nodeTimes.isEmpty ? 0 : (nodeTimes.keys.max() ?? 0)
        )
        result.droppedLines = dropped + timeBlockDropped
        return result
    }

    /// 正则组 (h, m) → 当日分钟; 越界 nil(LocalTime.of 非法 runCatching→null 等价)
    private static func clockGroup(_ m: NSTextCheckingResult, _ s: String, _ hi: Int, _ mi: Int) -> Int? {
        guard let hStr = group(m, s, hi), let mStr = group(m, s, mi),
              let h = Int(hStr), let miV = Int(mStr),
              (0...23).contains(h), (0...59).contains(miV) else { return nil }
        return h * 60 + miV
    }

    /// 区间反写(16-1)自动排序为 (1,16)
    private static func sortRange(_ p: (Int, Int)) -> (Int, Int) {
        p.0 <= p.1 ? p : (p.1, p.0)
    }

    /// \s+ 或 全角逗号 切分
    private static func splitByWhitespaceOrFullwidthComma(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in s {
            if ch == "，" || ch == "\t" || ch == " " || ch.isWhitespace && ch != "\u{00a0}" {
                if !cur.isEmpty { out.append(cur); cur = "" }
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    private static func parseRange(_ s: String) -> (Int, Int)? {
        // ← split('-', '~', '至'): Kotlin split 保留空子串 — "1--2" 是 3 段 → null(拒),
        // "2-5-9" 同样 null。Swift 默认 omittingEmptySubsequences:true 会把 "1--2" 当 (1,2) 收编,
        // 与 Android 分叉 → 必须显式保留空段。双段分支 Android 不 trim(" 2"→null),单段分支 trim。
        let parts = s.split(omittingEmptySubsequences: false,
                            whereSeparator: { $0 == "-" || $0 == "~" || $0 == "至" }).map(String.init)
        if parts.count == 1 {
            // 单个数字: e.g. "5" → (5, 5)
            guard let n = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            return (n, n)
        }
        if parts.count != 2 { return nil }
        guard let start = Int(parts[0]), let end = Int(parts[1]) else { return nil }
        return (start, end)
    }

    // MARK: - CSV

    /// 解析 CSV 格式课表。
    /// 自动识别表头,常见列名(中文/英文)都可以:
    ///   课程名 / 课程 / 名称 / course / name
    ///   教师 / 老师 / teacher
    ///   教室 / 位置 / 地点 / room / position
    ///   星期 / 周几 / day
    ///   节次(单列 1-2 格式) / 节点 / node / 节 / class
    ///   开始节数 + 结束节数(两列)  — 教务处常见导出
    ///   开始时间 + 结束时间(两列)  — 收割该节次真实作息(issue#55 时亦为私有起止)
    ///   自定义时间(标记列)         — issue#55 "是/true/yes/1" → 该行 ownTime
    ///   周次 / 周数 / weeks / week — 支持多区间 "2-5,7-9,11-14" / 离散周 "11,13,15" / 单周 "5"
    ///   类型 / type
    ///   备注 / note
    ///
    /// 多区间的周数会被展开成多条 CourseEntity(同一课程名在不同周上可以是不同教师/教室,
    /// 实际是分多行表示的,展开后保持原始行数)
    ///
    /// 支持带引号的字段("" 转义 ")
    private static func parseCsv(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        let rows = parseCsvRows(text)
        if rows.count < 2 { throw ParseError("CSV 至少需要表头 + 1 行数据") }

        let header = rows[0].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        // 查找列索引
        func findCol(_ keys: String...) -> Int? {
            for k in keys {
                if let idx = header.firstIndex(where: { $0.contains(k.lowercased()) }) {
                    return idx
                }
            }
            return nil
        }

        guard let nameIdx = findCol("课程名", "课程", "名称", "course", "name") else {
            throw ParseError("找不到课程名列")
        }
        let teacherIdx = findCol("教师", "老师", "teacher")
        let roomIdx = findCol("教室", "位置", "地点", "room", "position")
        // 时间列(可选): "开始时间"+"结束时间" 成对出现 → 每行收割该节次的真实作息
        // (繁体/日文汉字/西语别名与内置说明文案的表头对齐: 開始時間/hora inicio)
        let timeStartIdx = findCol("开始时间", "上课时间", "開始時間", "start time", "starttime", "hora inicio")
        let timeEndIdx = findCol("结束时间", "下课时间", "結束時間", "end time", "endtime", "hora fin")
        // issue#55: 自定义时间标记列(可选, Sleepy 自家 CSV 才有) — "是/true/yes/1" → 该行 ownTime,
        // 时间列值即课程私有起止而非作息收割源
        // 别名与 6 语说明文案对齐: 简中/繁中/日文汉字/英文 "own time|custom time"
        let ownTimeIdx = findCol(
            "自定义时间", "非标准时间", "自訂時間", "非標準時間", "自定義時間", "own time", "owntime", "custom time"
        )
        guard let dayIdx = findCol("星期", "周几", "day") else {
            throw ParseError("找不到星期列")
        }
        // 节次列三种兼容模式
        let nodeStartIdx = findCol("开始节数", "开始节次", "起节", "节次起", "start node")
        let nodeEndIdx = findCol("结束节数", "结束节次", "止节", "节次止", "end node")
        let nodeIdx = (nodeStartIdx == nil && nodeEndIdx == nil)
            ? findCol("节次", "节点", "上课节次", "node", "节", "class")
            : nil
        guard let weekIdx = findCol("周次", "周数", "weeks", "week") else {
            throw ParseError("找不到周次列")
        }
        let typeIdx = findCol("类型", "type", "周类型")
        let noteIdx = findCol("备注", "note", "remark")

        if nodeStartIdx == nil && nodeEndIdx == nil && nodeIdx == nil {
            throw ParseError("找不到节次列(需要 '节次' 或 '开始节数'+'结束节数')")
        }

        var courses: [CourseEntity] = []
        var nodeTimes: [Int: (Int, Int)] = [:]
        for i in 1..<rows.count {
            let row = rows[i]
            if row.isEmpty || row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }

            func cell(_ idx: Int?) -> String {
                guard let idx = idx, idx < row.count else { return "" }
                return row[idx].trimmingCharacters(in: .whitespaces)
            }

            let name = cell(nameIdx)
            if name.isEmpty { continue }  // ← isBlank

            guard let day = parseDay(cell(dayIdx)) else { continue }

            // 解析节次 (start, end)
            let nodePair: (Int, Int)?
            if let ns = nodeStartIdx, let ne = nodeEndIdx {
                guard let s = Int(cell(ns)), let e = Int(cell(ne)) else { continue }
                nodePair = (s, e)
            } else {
                guard let p = parseRange(cell(nodeIdx)) else { continue }
                nodePair = p
            }
            let (nodeStart, nodeEnd) = nodePair!
            let step = max(nodeEnd - nodeStart + 1, 1)

            // 时间列收割: 该行带真实起止钟点 → 记录首末节的边界作息(中间节交给恰好落界的行补)
            // issue#55: ownTime 行的起止是课程私有时间, 不入公共作息收割
            let ownTimeRow = ownTimeIdx != nil && isYesMarker(cell(ownTimeIdx))
            if !ownTimeRow, let ts = timeStartIdx, let te = timeEndIdx,
               let (st, et) = parseTimeRange(cell(ts) + "-" + cell(te)) {
                let prevStart = nodeTimes[nodeStart]?.0
                let prevEnd = nodeTimes[nodeStart]?.1
                nodeTimes[nodeStart] = (prevStart ?? st, nodeEnd == nodeStart ? et : (prevEnd ?? et))
                if nodeEnd != nodeStart {
                    let pe = nodeTimes[nodeEnd]
                    nodeTimes[nodeEnd] = (pe?.0 ?? st, et)
                }
            }

            // 解析周次——支持多区间 "2-5,7-9,11-14" / 离散 "11,13,15" / 单周 "5" / 区间 "2-16"
            let weekRanges = parseWeekRanges(cell(weekIdx))
            if weekRanges.isEmpty { continue }

            let teacher = cell(teacherIdx)
            let room = cell(roomIdx)
            let note = cell(noteIdx)
            let type = parseType(cell(typeIdx))
            // issue#55: ownTime 行恢复课程私有起止(与导出端 buildCsv 列对齐)
            let ownPair = ownTimeRow ? parseTimeRange(cell(timeStartIdx) + "-" + cell(timeEndIdx)) : nil
            let rowOwnTime = ownPair != nil

            // 每个区间展开为一条 CourseEntity
            for (startWeek, endWeek) in weekRanges {
                courses.append(CourseEntity(
                    groupId: "",
                    tableId: defaultTableId,
                    courseName: name,
                    teacher: teacher,
                    room: room,
                    note: note,
                    day: day,
                    startNode: nodeStart,
                    step: step,
                    startWeek: startWeek,
                    endWeek: endWeek,
                    type: type,
                    color: defaultColor,
                    ownTime: rowOwnTime,
                    startTime: rowOwnTime ? hmString(ownPair!.0) : "",
                    endTime: rowOwnTime ? hmString(ownPair!.1) : "",
                    id: 0
                ))
            }
        }

        if courses.isEmpty { throw ParseError("未能解析任何课程") }

        return lossless(
            "导入的 CSV 课表",
            todayString(),
            courses,
            buildTimeJson(nodeTimes),
            nodeTimes.isEmpty ? 0 : (nodeTimes.keys.max() ?? 0)
        )
    }

    /// issue#55 标记列取值: "是/true/yes/1"(大小写不敏感)→ true
    private static func isYesMarker(_ s: String) -> Bool {
        return s == "是" || s.lowercased() == "true" || s.lowercased() == "yes" || s == "1"
    }

    /// 解析周数字段,支持:
    ///   "5"              → [(5, 5)]
    ///   "2-16"           → [(2, 16)]
    ///   "2-5,7-9,11-14"  → [(2, 5), (7, 9), (11, 14)]
    ///   "11,13,15,17"    → [(11, 11), (13, 13), (15, 15), (17, 17)]
    ///   "2-5,11"         → [(2, 5), (11, 11)]
    private static func parseWeekRanges(_ s: String) -> [(Int, Int)] {
        if s.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        var result: [(Int, Int)] = []
        // ← split(',', '，', ';', '；')
        for part in s.split(whereSeparator: { ",，;；".contains($0) }) {
            let t = String(part).trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            guard let pair = parseRange(t) else { continue }
            result.append(pair)
        }
        return result
    }

    /// 解析 CSV 文本为二维字符串数组,支持引号转义
    private static func parseCsvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var cur: [String] = []
        var sb = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        let n = chars.count
        while i < n {
            let c = chars[i]
            if inQuotes {
                if c == "\"" && i + 1 < n && chars[i + 1] == "\"" {
                    sb.append("\""); i += 2; continue
                }
                if c == "\"" { inQuotes = false; i += 1; continue }
                sb.append(c); i += 1
            } else {
                switch c {
                case "\"":
                    inQuotes = true; i += 1
                case ",":
                    cur.append(sb); sb = ""; i += 1
                case "\n":
                    cur.append(sb); sb = ""; rows.append(cur); cur = []; i += 1
                case "\r":
                    i += 1; continue
                default:
                    sb.append(c); i += 1
                }
            }
        }
        if !sb.isEmpty || !cur.isEmpty {
            cur.append(sb)
            rows.append(cur)
        }
        return rows
    }

    /// 解析 "星期" 列:支持 "周一" "1" "Monday" "mon"
    private static func parseDay(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return nil }
        // 纯数字
        if let v = Int(t), (1...7).contains(v) { return v }
        // 包含 "周"
        if t.contains("周") {
            let map = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7]
            for (k, v) in map where t.contains(k) { return v }
        }
        // 英文
        let enMap = ["mon": 1, "tue": 2, "wed": 3, "thu": 4, "fri": 5, "sat": 6, "sun": 7]
        for (k, v) in enMap where t.hasPrefix(k) { return v }
        return nil
    }

    /// 解析 "类型" 列:0=每周 1=单周 2=双周 3=按周次列实际指定的周
    /// 空串/未知 → 3(不再回退到 0=每周,避免把"周次=6 单次实验"误标成"每周都上")
    /// internal(非 private)供 SleepyTests 直测 — Kotlin 侧用反射访问 private, 语义不变
    static func parseType(_ s: String) -> Int {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        if t.isEmpty { return 3 }
        if t == "0" || t == "每周" || t == "每周都上" { return 0 }
        if t.contains("单") || t == "1" || t == "odd" { return 1 }
        if t.contains("双") || t == "2" || t == "even" { return 2 }
        if t == "3" || t.contains("自定义") || t.contains("按周次") { return 3 }
        // 未知值(包含负数、4+ 等)按"按周次"处理而非"每周",保护用户数据
        return 3
    }

    /// 解析 "节次" 列:支持 "1-2" "第1-2节" "1,2" "1 1"
    private static func parseRangeOrNode(_ s: String) -> (Int, Int)? {
        let t = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "节", with: "")
            .replacingOccurrences(of: "第", with: "")
        // 优先 "1-2" / "1~2" / "1至2"
        if let r = parseRange(t) { return r }
        // 尝试逗号/空格分隔的列表
        let nums = t.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
            .compactMap { Int($0) }.sorted()
        if !nums.isEmpty {
            let start = nums.first!
            let end = nums.last!
            return (start, end - start + 1)
        }
        return nil
    }

    // MARK: - HTML

    /// 解析 HTML 课表。
    /// 处理两种常见格式:
    /// 1) WakeUp HTML 导出:含课程名称+老师+教室+节次+周次的 <table>
    /// 2) 简单 HTML 表格:<table> 包含 <tr><td>...</td></tr>
    ///
    /// 策略:抽取所有 <table>,逐行解析,尝试按列匹配。
    private static func parseHtml(_ text: String, _ defaultTableId: Int64, _ defaultColor: String) throws -> ParseResult {
        // 去掉 HTML 标签得到纯文本,再按 <table> 分段解析
        let tables = extractHtmlTables(text)
        if tables.isEmpty { throw ParseError("HTML 中未找到表格") }

        var courses: [CourseEntity] = []
        for rows in tables {
            if rows.isEmpty { continue }
            // 尝试按"表头识别"方式解析
            courses += parseHtmlTableRows(rows, defaultTableId, defaultColor)
        }

        if courses.isEmpty { throw ParseError("HTML 中未能解析出任何课程") }

        // v7.10.16k: 课程到达节次无损上报(HTML 表头路径本身不携带作息)
        return lossless("导入的 HTML 课表", todayString(), courses, "", 0)
    }

    /// 抽取所有 <table>...</table> 转为 [[String]] (按 <td>/<th>)
    private static func extractHtmlTables(_ html: String) -> [[[String]]] {
        var tables: [[[String]]] = []
        let tableRegex = try! NSRegularExpression(pattern: "(?is)<table[^>]*>(.*?)</table>")
        let trRegex = try! NSRegularExpression(pattern: "(?is)<tr[^>]*>(.*?)</tr>")
        let cellRegex = try! NSRegularExpression(pattern: "(?is)<(td|th)[^>]*>(.*?)</\\1>")
        let tagRegex = try! NSRegularExpression(pattern: "(?is)<[^>]+>")

        let nsHtml = html as NSString
        for tMatch in tableRegex.matches(in: html, range: NSRange(location: 0, length: nsHtml.length)) {
            let tableBody = nsHtml.substring(with: tMatch.range(at: 1))
            let nsBody = tableBody as NSString
            var rows: [[String]] = []
            for trMatch in trRegex.matches(in: tableBody, range: NSRange(location: 0, length: nsBody.length)) {
                let trBody = nsBody.substring(with: trMatch.range(at: 1))
                let nsTr = trBody as NSString
                let cells: [String] = cellRegex.matches(in: trBody, range: NSRange(location: 0, length: nsTr.length)).map { m in
                    let raw = nsTr.substring(with: m.range(at: 2))
                    // 解码 HTML 实体
                    return tagRegex.stringByReplacingMatches(
                        in: raw, range: NSRange(location: 0, length: (raw as NSString).length),
                        withTemplate: ""
                    )
                    .replacingOccurrences(of: "&nbsp;", with: " ")
                    .replacingOccurrences(of: "&amp;", with: "&")
                    .replacingOccurrences(of: "&lt;", with: "<")
                    .replacingOccurrences(of: "&gt;", with: ">")
                    .replacingOccurrences(of: "&quot;", with: "\"")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if !cells.isEmpty { rows.append(cells) }
            }
            if !rows.isEmpty { tables.append(rows) }
        }
        return tables
    }

    /// 解析一个表格的所有行。
    /// 先尝试识别表头行(含 "课程"/"教师"/"星期"/"节次" 等关键字),
    /// 找到的话按列解析;找不到就把每行作为非结构化文本走 parseSimpleText 逻辑。
    private static func parseHtmlTableRows(_ rows: [[String]], _ defaultTableId: Int64, _ defaultColor: String) -> [CourseEntity] {
        // 找表头行
        let headerIdx = rows.firstIndex { row in
            let t = row.joined(separator: " ").lowercased()
            return t.contains("课程") || t.contains("course") || t.contains("name")
        } ?? -1
        if headerIdx < 0 {
            // 退化:按文本行处理 — Android 直调 parseSimpleText(不走完整分派,
            // 防展平后的 cell 以 '{' 或 'BEGIN:VCALENDAR' 开头被误路由进 JSON/ICS 解析器)
            let text = rows.flatMap { $0 }.joined(separator: "\n")
            if let r = try? parseSimpleText(text, defaultTableId, defaultColor) {
                return r.courses
            }
            return []
        }
        let header = rows[headerIdx].map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func findCol(_ keys: String...) -> Int? {
            for k in keys {
                if let idx = header.firstIndex(where: { $0.contains(k.lowercased()) }) {
                    return idx
                }
            }
            return nil
        }
        guard let nameIdx = findCol("课程", "course", "name") else { return [] }
        let teacherIdx = findCol("教师", "老师", "teacher")
        let roomIdx = findCol("教室", "位置", "room", "position", "地点")
        let dayIdx = findCol("星期", "周几", "day")
        let nodeStartIdx = findCol("开始节数", "开始节次", "起节", "节次起", "start node")
        let nodeEndIdx = findCol("结束节数", "结束节次", "止节", "节次止", "end node")
        let nodeIdx = (nodeStartIdx == nil && nodeEndIdx == nil)
            ? findCol("节次", "节点", "node", "上课节次")
            : nil
        let weekIdx = findCol("周次", "周数", "weeks", "week")
        let typeIdx = findCol("类型", "type")
        let noteIdx = findCol("备注", "note")
        // issue#55: Sleepy 自家 HTML 才有的列 — 自定义时间标记 + 起止时间
        let ownTimeIdx = findCol(
            "自定义时间", "非标准时间", "自訂時間", "非標準時間", "自定義時間", "own time", "owntime", "custom time"
        )
        let timeStartIdx = findCol("开始时间", "上课时间", "開始時間", "start time", "starttime", "hora inicio")
        let timeEndIdx = findCol("结束时间", "下课时间", "結束時間", "end time", "endtime", "hora fin")

        if nodeStartIdx == nil && nodeEndIdx == nil && nodeIdx == nil {
            return []
        }
        guard let weekIdx = weekIdx else {
            return []
        }

        var courses: [CourseEntity] = []
        for i in (headerIdx + 1)..<rows.count {
            let row = rows[i]
            if row.isEmpty || row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            func cell(_ idx: Int?) -> String {
                guard let idx = idx, idx < row.count else { return "" }
                return row[idx].trimmingCharacters(in: .whitespaces)
            }

            let name = cell(nameIdx)
            if name.isEmpty { continue }

            guard let day = parseDay(cell(dayIdx)) else { continue }
            // 节点:开始/结束两列 或 单列 range
            let nodePair: (Int, Int)?
            if let ns = nodeStartIdx, let ne = nodeEndIdx {
                guard let s = Int(cell(ns)), let e = Int(cell(ne)) else { continue }
                nodePair = (s, e)
            } else {
                guard let p = parseRange(cell(nodeIdx)) else { continue }
                nodePair = p
            }
            let (nodeStart, nodeEnd) = nodePair!
            let step = max(nodeEnd - nodeStart + 1, 1)
            let weekRanges = parseWeekRanges(cell(weekIdx))
            if weekRanges.isEmpty { continue }
            let type = parseType(cell(typeIdx))

            let teacher = cell(teacherIdx)
            let room = cell(roomIdx)
            let note = cell(noteIdx)
            // issue#55: ownTime 行恢复课程私有起止(钟点归一两位补零, 与 sleepy-v1 同规)
            let ownPair = (ownTimeIdx != nil && isYesMarker(cell(ownTimeIdx)))
                ? parseTimeRange(cell(timeStartIdx) + "-" + cell(timeEndIdx))
                : nil
            let rowOwnTime = ownPair != nil
            for (startWeek, endWeek) in weekRanges {
                courses.append(CourseEntity(
                    groupId: "",
                    tableId: defaultTableId,
                    courseName: name,
                    teacher: teacher,
                    room: room,
                    note: note,
                    day: day,
                    startNode: nodeStart,
                    step: step,
                    startWeek: startWeek,
                    endWeek: endWeek,
                    type: type,
                    color: defaultColor,
                    ownTime: rowOwnTime,
                    startTime: rowOwnTime ? hmString(ownPair!.0) : "",
                    endTime: rowOwnTime ? hmString(ownPair!.1) : "",
                    id: 0
                ))
            }
        }
        return courses
    }

    // MARK: - helpers

    /// LocalDate.now().toString()
    private static func todayString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
