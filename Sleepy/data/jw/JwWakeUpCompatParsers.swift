// JwWakeUpCompatParsers.swift — ← JwWakeUpCompatParsers.kt
//
// WakeUp 协议族兼容解析器(kingo_new / jz / south_soft / login_chaoxing / shuwei_json /
// suda_post / cumtb / xju_post)。
//
// 8 个 concrete parser(JwKingoParser / JwJzParser / JwSouthSoftParser / JwChaoxingLegacyParser /
// JwShuweiParser / JwSudaParser / JwCumtbParser / JwXjuParser)都基于抽象基类
// WakeUpMarkerParser, 派发到 WakeUpCompat 的具体子解析器并暴露 markers 锚点。
//
// 主要复用 WakeUpCompat.parse(source, markers) 入口:链式尝试多个子解析器, 第一个产出
// 非空课程列表的胜出; 否则 jsonHint=false 时再回退 parseDelimited(纯文本 CSV)。
//
// 设计思路与 JwWakeUpCompatParsers.kt 1:1 对应, 包含 parseKingoInfo 私有死代码(原 Kotlin
// 标记 private, 无调用点 — 仅保留以备跨语言 diff 审计)。

import Foundation
import SwiftSoup

// MARK: - WakeUpCompat 子解析器集合(逐层回退, 第一个非空结果胜出)

enum WakeUpCompat {

    // 入口: JSON 课表 → JZ 兼容 JSON → JzSuper(2026-10) → JzHtml → marked table → plain CSV
    static func parse(_ source: String, markers: Set<String>, jsonHint: Bool = false) -> [JwCourse] {
        if let root = parseJson(source) {
            let r = parseJsonCourses(root)
            if !r.isEmpty { return r }
            let jz = parseJzJson(root)
            if !jz.isEmpty { return jz }
        }
        let jzSuper = parseJzSuper(source)
        if !jzSuper.isEmpty { return jzSuper }
        let jzHtml = parseJzNativeChain(source)
        if !jzHtml.isEmpty { return jzHtml }
        let marked = parseMarkedTable(source, markers: markers)
        if !marked.isEmpty { return marked }
        return []
    }

    /// JZHandCourseInfoItem JSON: xqj=day, djj=起始节, qmz="1-8;10-16", dsz==1→单 / dsz!=2→双 / else 每周 (WakeUp 反转语义).
    static func parseJzJson(_ root: Any) -> [JwCourse] {
        guard root is [Any], let data = try? JSONSerialization.data(withJSONObject: root), let json = String(data: data, encoding: .utf8) else { return [] }
        return (try? JwXbellsoftParser(json).generateCourseList()) ?? []
    }

    /// KingoInfo JSON: 顶层数组, 行 week1..week7 → day=列号, 值=[{jcxx:"a-b", kcmc, skdd, rkjs, xf}], week=row 索引.
    /// 死代码: 私有未暴露给 WakeUpCompat.parse 调用, 仅在 WakeUpCompat 内部可见 — 1:1 Kotlin 复制以保
    /// 跨语言 diff 审计一致(Kotlin 侧仅一处 `private fun parseKingoInfo(root: Any)` 声明)。
    fileprivate static func parseKingoInfo(_ root: Any) -> [JwCourse] {
        let rows = jsonRows(root)
        if rows.isEmpty { return [] }
        var out: [JwCourse] = []
        for (r, row) in rows.enumerated() {
            for d in 1...7 {
                let key = "week\(d)"
                guard let cells = optArray(row[key]) else { continue }
                for case let cell as [String: Any] in cells {
                    let name = optString(cell["kcmc"])
                    let jcxx = optString(cell["jcxx"])
                    let bounds = jcxx.components(separatedBy: "-")
                    guard let start = Int(bounds.first?.trimmingCharacters(in: .whitespaces) ?? "") else { continue }
                    if name.trimmingCharacters(in: .whitespaces).isEmpty || start < 1 { continue }
                    let end = bounds.count > 1 ? (Int(bounds[1].trimmingCharacters(in: .whitespaces)) ?? start) : start
                    out.append(JwCourse(name: name,
                        room: optString(cell["skdd"]),
                        teacher: optString(cell["rkjs"]),
                        day: d, startNode: start, endNode: end,
                        startWeek: r, endWeek: r))
                }
            }
        }
        return out
    }
}
// MARK: - chaoxing / cumtb / south_soft 子解析器

extension WakeUpCompat {

    static func parseChaoxing(_ source: String) -> [JwCourse] {
        guard let parsed = parseJson(source) else { return [] }
        let root = parsed as? [String: Any] ?? [:]
        // Kotlin: root.optJSONObject("data")?.optJSONArray("kckbData") ?: root.optJSONArray("kckbData")
        let rowsNode = (parsed as? [Any]) ?? optArray((root["data"] as? [String: Any])?["kckbData"]) ?? optArray(root["kckbData"])
        guard let rowsNode else { return [] }
        // Kotlin 逐行 optJSONObject(i) ?: continue
        let rows = rowsNode.compactMap { $0 as? [String: Any] }
        if rows.isEmpty { return [] }
        var out: [JwCourse] = []
        for row in rows {
            let name = stripMarkup(optString(row["kcmc"]))
            // Kotlin: row.optString("xq").toIntOrNull() — optString 把数字 3 强转 "3", 混合类型不丢行
            guard let day = Int(optString(row["xq"])) else { continue }
            let node = intField(row["djc"]) ?? 0
            if name.isEmpty || day < 1 || day > 7 || node < 1 { continue }
            let type = Int(optString(row["zctype"])) ?? 0
            let zcRaw = optString(row["zc"])
            let room = stripMarkup(optString(row["croommc"]))
            let teacher = stripMarkup(optString(row["tmc"]))
            for token in zcRaw.components(separatedBy: ",") {
                let nums = extractInts(token.components(separatedBy: CharacterSet(charactersIn: "(（")).first ?? "")
                if nums.isEmpty { continue }
                let first = nums[0]
                let second = nums.count > 1 ? nums[1] : first
                out.append(JwCourse(name: name, room: room, teacher: teacher,
                    day: day, startNode: node, endNode: node,
                    startWeek: first, endWeek: second, type: type))
            }
        }
        return out
    }

    static func parseCumtb(_ source: String) -> [JwCourse] {
        guard let root = Jw64.json(source) as? [String: Any], let payload = root["result"] as? [String: Any], let schedules = payload["scheduleList"] as? [Any] else { return [] }
        var names: [Int: String] = [:]
        for case let lesson as [String: Any] in (payload["lessonList"] as? [Any] ?? []) { if let id = jw1064Integer(lesson["id"]) { names[id] = Jw64.text(lesson, "courseName") } }
        return schedules.compactMap { raw in
            guard let row = raw as? [String: Any], let id = jw1064Integer(row["lessonId"]), let day = jw1064Integer(row["weekday"]), (1...7).contains(day),
                  let week = jw1064Integer(row["weekIndex"]), week > 0, let start = jw1064Integer(row["startTime"]), let end = jw1064Integer(row["endTime"]) else { return nil }
            let clockStart = String(format: "%02d:%02d", start / 100, start % 100), clockEnd = String(format: "%02d:%02d", end / 100, end % 100)
            guard JwCourse.isValidTimeRange(clockStart, clockEnd) else { return nil }
            let node = timeToNode(start); guard node > 0 else { return nil }
            let name = names[id].flatMap { $0.isEmpty ? nil : $0 } ?? "未知"
            return JwCourse(name: name, room: (row["room"] as? [String: Any]).map { Jw64.text($0, "nameZh") } ?? "", teacher: Jw64.text(row, "personName"),
                day: day, startNode: node, endNode: node + durationToNodes(start, end) - 1, startWeek: week, endWeek: week, startTime: clockStart, endTime: clockEnd)
        }
    }


    static func parseSouthSoftLegacy(_ source: String) -> [JwCourse] {
        guard let parsed = parseJson(source) else { return [] }
        // Kotlin: root is JSONArray -> root; root is JSONObject ->
        //   root.optJSONArray("value") ?: root.optJSONArray("data") ?: return emptyList()
        let rows: [[String: Any]]
        if optArray(parsed) != nil {
            rows = jsonRows(parsed)
        } else if let obj = parsed as? [String: Any] {
            // 注意: Kotlin 中 value/data 均缺失(或非数组)→ 直接 emptyList; 存在但全是坏元素 → 空行集
            guard let node = optArray(obj["value"]) ?? optArray(obj["data"]) else { return [] }
            rows = node.compactMap { $0 as? [String: Any] }
        } else {
            return []
        }
        var out: [JwCourse] = []
        let keyRe = try! NSRegularExpression(pattern: "xq(\\d+)_jc\\d+", options: [])
        for row in rows {
            let keyRaw = optString(row["KEY"])
            if keyRaw == "bz" { continue }
            let nsKey = keyRaw as NSString
            let keyRange = NSRange(keyRaw.startIndex..., in: keyRaw)
            guard let m = keyRe.firstMatch(in: keyRaw, options: [], range: keyRange),
                  let day = Int(nsKey.substring(with: m.range(at: 1))) else { continue }
            let sksj = optString(row["SKSJ"])
            let bracketRe = try! NSRegularExpression(pattern: "\\[(.*?)\\]", options: [])
            let sksjNs = sksj as NSString
            let sksjRange = NSRange(sksj.startIndex..., in: sksj)
            let fields = bracketRe.matches(in: sksj, options: [], range: sksjRange).map { sksjNs.substring(with: $0.range(at: 1)).trimmingCharacters(in: .whitespaces) }
            if fields.count < 5 { continue }
            let nodes = fields[4].replacingOccurrences(of: "第", with: "").replacingOccurrences(of: "节", with: "").components(separatedBy: "-")
            guard let start = Int(nodes.first ?? "") else { continue }
            let end = nodes.count > 1 ? (Int(nodes[1]) ?? start) : start
            for token in fields[1].components(separatedBy: ",") {
                let weeks = extractInts(token)
                if weeks.isEmpty { continue }
                let first = weeks[0]
                let second = weeks.count > 1 ? weeks[1] : first
                let type: Int
                if token.contains("单") { type = 1 }
                else if token.contains("双") { type = 2 }
                else { type = 0 }
                let kcwzsm = optString(row["KCWZSM"])
                out.append(JwCourse(
                    name: kcwzsm.isEmpty ? fields[0] : kcwzsm,
                    room: fields[4], teacher: fields[2],
                    day: day, startNode: start, endNode: end,
                    startWeek: first, endWeek: second, type: type))
            }
        }
        return out
    }
}

// MARK: - parseKingoTaskActivity (Kingosoft courseTable JS)

extension WakeUpCompat {

    /// Kingo TaskActivity JS grid: "activity = new TaskActivity(name,teacher,room,weeksBinary)";
    /// index=a*unitCount+b → day=a+1, node=b+1; '1'@p → week p+1, 连续段合并成组,
    /// 全奇→单周/全偶→双周.
    static func parseKingoTaskActivity(_ source: String) -> [JwCourse] { (try? JwClassicEamsParser(source).generateCourseList()) ?? [] }

}

// MARK: - parseXju / extractXjuCourses / parseXjuWeeksWithBrackets

extension WakeUpCompat {

    /// XJU dgData: 兼容两种表头形态。
    ///  - 形态 A: th="节次|周X" 无时间列, 节次=阿拉伯数字, 单元格 "｛名(周次)[教师:X,地点:Y]｝"
    ///  - 形态 B (真实 Gwork 学期课表信息查询, 2026-09-17 用户报修): th="时间|节次|周X",
    ///    时间列 rowspan=4, 节次=中文数字"一"..."十二", 课程名在花括号**外**,
    ///    单元格 "名｛周次[教师:X,地点:Y]｝", 课程行用 rowspan 跨节次合并.
    ///  通用通路: 还原 (col, row) 网格, rowspan 残留补齐, 映射 (day, node).
    static func parseXju(_ source: String) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        // Kotlin: selectFirst("#ctl00_contentParent_dgData") ?: selectFirst("#contentParent_dgData")
        // — 真实 Gwork 形态 B 页面表 id 无 ctl00_ 前缀(2026-09-17 报修案例), 缺回退 = 0 课
        guard let table = (try? doc.select("#ctl00_contentParent_dgData"))?.first()
                ?? (try? doc.select("#contentParent_dgData"))?.first() else { return [] }
        let rows = (try? table.select("tr")) ?? Elements()
        if rows.isEmpty() { return [] }
        guard let firstRow = rows.first(),
              let ths = try? firstRow.select("th"), ths.size() > 0 else { return [] }
        let dayRe = try! NSRegularExpression(pattern: "星期[一二三四五六日天]", options: [])
        let firstDayIdx = ths.array().firstIndex { (try? dayRe.firstMatch(in: $0.text(), options: [], range: NSRange($0.text().startIndex..., in: $0.text()))) != nil } ?? -1
        if firstDayIdx < 0 { return [] }
        let firstDayLabel = (try? ths.get(firstDayIdx).text()) ?? ""
        let dayOfFirstCol: Int = {
            if firstDayLabel.contains("星期一") { return 1 }
            if firstDayLabel.contains("星期二") { return 2 }
            if firstDayLabel.contains("星期三") { return 3 }
            if firstDayLabel.contains("星期四") { return 4 }
            if firstDayLabel.contains("星期五") { return 5 }
            if firstDayLabel.contains("星期六") { return 6 }
            return 7
        }()

        let cnMap: [String: Int] = ["一":1,"二":2,"三":3,"四":4,"五":5,"六":6,"七":7,"八":8,"九":9,"十":10,"十一":11,"十二":12]
        let rangeRe = try! NSRegularExpression(pattern: "第(\\d+)\\s*[-–~]\\s*\\d+节", options: [])

        func nodeLabelToInt(_ raw: String) -> Int? {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if let n = Int(trimmed), (1...20).contains(n) { return n }
            if let v = cnMap[trimmed] { return v }
            let r = NSRange(trimmed.startIndex..., in: trimmed)
            if let m = rangeRe.firstMatch(in: trimmed, options: [], range: r) {
                let ns = trimmed as NSString
                if let n = Int(ns.substring(with: m.range(at: 1))), (1...20).contains(n) { return n }
            }
            return nil
        }

        let dataRows = rows.array().dropFirst()

        var rowToNode = Array(repeating: 0, count: dataRows.count)
        var lastNode = 0
        for (rowIdx, row) in dataRows.enumerated() {
            var thisNode = 0
            let tds = (try? row.select("td")) ?? Elements()
            for td in tds.array() {
                let align = (try? td.attr("align")) ?? ""
                if align.lowercased() == "center" {
                    if let n = nodeLabelToInt((try? td.text()) ?? "") {
                        thisNode = n
                        break
                    }
                }
            }
            if thisNode == 0 { thisNode = lastNode } else { lastNode = thisNode }
            rowToNode[rowIdx] = thisNode
        }

        var cellText: [String: String] = [:]
        var colExpire: [Int: Int] = [:]
        for (rowIdx, row) in dataRows.enumerated() {
            let occupiedNow = Set(colExpire.filter { ($0.value) >= rowIdx }.keys)
            var col = 0
            let tds = (try? row.select("td")) ?? Elements()
            for td in tds.array() {
                guard let cs = td.hasAttr("colspan") ? Int((try? td.attr("colspan")) ?? "") : 1,
                      let rs = td.hasAttr("rowspan") ? Int((try? td.attr("rowspan")) ?? "") : 1,
                      (1...ths.size()).contains(cs), (1...(dataRows.count - rowIdx)).contains(rs) else { return [] }
                while occupiedNow.contains(col) { col += 1 }
                if col + cs > ths.size() {
                    if wakeText(td).isEmpty && cs == 1 && rs == 1 { continue }; return []
                }
                let align = (try? td.attr("align")) ?? ""
                let isCenter = align.lowercased() == "center"
                let rawText = (try? td.text()) ?? ""
                let raw = rawText.replacingOccurrences(of: " ", with: " ")
                    .replacingOccurrences(of: "{", with: "｛")
                    .replacingOccurrences(of: "}", with: "｝")
                    .trimmingCharacters(in: .whitespaces)
                for i in 0..<cs {
                    let c = col + i
                    if !isCenter && !raw.isEmpty {
                        cellText["\(c),\(rowIdx)"] = raw
                        for k in 1..<rs {
                            cellText["\(c),\(rowIdx + k)"] = raw
                        }
                    }
                    if rs > 1 { colExpire[c] = rowIdx + rs - 1 }
                }
                col += cs
            }
        }

        let thArr = ths.array()
        let firstDayCol = thArr.firstIndex { (try? dayRe.firstMatch(in: $0.text(), options: [], range: NSRange($0.text().startIndex..., in: $0.text()))) != nil } ?? firstDayIdx
        var grid: [String: String] = [:]
        for (key, raw) in cellText {
            if raw.isEmpty { continue }
            let parts = key.components(separatedBy: ",")
            guard parts.count == 2,
                  let col = Int(parts[0]),
                  let rowIdx = Int(parts[1]) else { continue }
            let node = rowToNode[rowIdx]
            guard (1...20).contains(node) else { continue }
            if col < firstDayCol { continue }
            let dayColIdx = col - firstDayCol
            guard (0...6).contains(dayColIdx) else { continue }
            let day = ((dayOfFirstCol - 1 + dayColIdx) % 7) + 1
            grid["\(day),\(node)"] = raw
        }
        if grid.isEmpty { return [] }

        var out: [JwCourse] = []
        var emitted: Set<String> = []
        for node in 1...20 {
            for day in 1...7 {
                let key = "\(day),\(node)"
                if emitted.contains(key) { continue }
                guard let raw = grid[key], !raw.isEmpty else { continue }
                var endNode = node
                while endNode + 1 <= 20 && grid["\(day),\(endNode + 1)"] == raw {
                    endNode += 1
                }
                for k in node...endNode { emitted.insert("\(day),\(k)") }
                out.append(contentsOf: extractXjuCourses(raw, day: day, startNode: node, endNode: endNode))
            }
        }
        return out
    }

    /// 把单格文本切成 JwCourse 列表。优先匹配形态 B「名｛周次[教师:…,地点:…],…｝」,
    /// 回退形态 A「｛名(周次)[教师:…,地点:…]｝」(旧 fixture).
    fileprivate static func extractXjuCourses(_ cellText: String, day: Int, startNode: Int, endNode: Int) -> [JwCourse] {
        var out: [JwCourse] = []
        if cellText.isEmpty { return out }
        let blocks = cellText.components(separatedBy: "；").map { $0.trimmingCharacters(in: .whitespaces) }
        let altBlocks = blocks.flatMap { b -> [String] in
            if !b.contains(";") { return [b] }
            return b.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        for block in altBlocks {
            if block.isEmpty { continue }
            if block.contains("｛") {
                let braceRe = try! NSRegularExpression(pattern: "｛([^｝]+)｝", options: [])
                let blockNs = block as NSString
                let blockRange = NSRange(block.startIndex..., in: block)
                let matches = braceRe.matches(in: block, options: [], range: blockRange)
                if !matches.isEmpty {
                    let firstInner = blockNs.substring(with: matches[0].range(at: 1))
                    let cutAt = block.index(block.startIndex, offsetBy: matches[0].range.location)
                    let namePrefix = block.substring(with: block.startIndex..<cutAt).trimmingCharacters(in: .whitespaces)
                    let isLegacy = namePrefix.isEmpty && firstInner.contains("(") && firstInner.contains("[")
                    if isLegacy {
                        let name = firstInner.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? firstInner
                        let weeksSection = innerParen(firstInner) ?? ""
                        let bracket = innerBracket(firstInner) ?? ""
                        let teacher = bracketTeacher(bracket)
                        let room = bracketRoom(bracket)
                        for entry in weeksSection.components(separatedBy: CharacterSet(charactersIn: "、，,")) {
                            for (from, to, type) in parseWeekTokens(entry) {
                                out.append(JwCourse(name: name, room: room, teacher: teacher,
                                    day: day, startNode: startNode, endNode: endNode,
                                    startWeek: from, endWeek: to, type: type))
                            }
                        }
                        continue
                    }
                    let name = namePrefix
                    for m in matches {
                        let inner = blockNs.substring(with: m.range(at: 1))
                        for (from, to, teacher, room, parity) in parseXjuWeeksWithBrackets(inner) {
                            out.append(JwCourse(name: name, room: room, teacher: teacher,
                                day: day, startNode: startNode, endNode: endNode,
                                startWeek: from, endWeek: to, type: parity))
                        }
                    }
                    continue
                }
            }
            if block.hasPrefix("｛") && block.hasSuffix("｝") {
                let inner = block.trimmingCharacters(in: CharacterSet(charactersIn: "｛｝"))
                let name = inner.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? inner
                guard let weeksSection = innerParen(inner) else { continue }
                let bracket = innerBracket(inner) ?? ""
                let teacher = bracketTeacher(bracket)
                let room = bracketRoom(bracket)
                for entry in weeksSection.components(separatedBy: CharacterSet(charactersIn: "、，,")) {
                    for (from, to, type) in parseWeekTokens(entry) {
                        out.append(JwCourse(name: name, room: room, teacher: teacher,
                            day: day, startNode: startNode, endNode: endNode,
                            startWeek: from, endWeek: to, type: type))
                    }
                }
            }
        }
        return out
    }

    private static func innerParen(_ s: String) -> String? {
        let re = try! NSRegularExpression(pattern: "\\(([^)]*)\\)", options: [])
        let r = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, options: [], range: r) else { return nil }
        return (s as NSString).substring(with: m.range(at: 1))
    }
    private static func innerBracket(_ s: String) -> String? {
        let re = try! NSRegularExpression(pattern: "\\[([^\\]]*)\\]", options: [])
        let r = NSRange(s.startIndex..., in: s)
        guard let m = re.firstMatch(in: s, options: [], range: r) else { return nil }
        return (s as NSString).substring(with: m.range(at: 1))
    }
    private static func bracketTeacher(_ bracket: String) -> String {
        let re = try! NSRegularExpression(pattern: "教师[:：]([^,，\\]]*)", options: [])
        let r = NSRange(bracket.startIndex..., in: bracket)
        guard let m = re.firstMatch(in: bracket, options: [], range: r) else { return "" }
        return (bracket as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }
    private static func bracketRoom(_ bracket: String) -> String {
        let re = try! NSRegularExpression(pattern: "地点[:：]([^,，\\]]*)", options: [])
        let r = NSRange(bracket.startIndex..., in: bracket)
        guard let m = re.firstMatch(in: bracket, options: [], range: r) else { return "" }
        return (bracket as NSString).substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
    }

    /// 形态 B 块内解析: "12-19周[教师:孙冬璞,地点:待定]"
    fileprivate static func parseXjuWeeksWithBrackets(_ inner: String) -> [(Int, Int, String, String, Int)] {
        guard let re = try? NSRegularExpression(pattern: #"([^\[\]]+)\[([^\[\]]*)\]"#) else { return [] }
        let ns = inner as NSString, matches = re.matches(in: inner, range: NSRange(location: 0, length: ns.length))
        guard let last = matches.last, Jw64.trim(ns.substring(from: NSMaxRange(last.range))).isEmpty else { return [] }
        var out: [(Int, Int, String, String, Int)] = []
        for match in matches {
            let weeks = Jw64.trim(Jw64.trim(ns.substring(with: match.range(at: 1))).trimmingCharacters(in: CharacterSet(charactersIn: "、，,")))
            let bracket = ns.substring(with: match.range(at: 2))
            for (from, to, parity) in schoolWeekRanges(weeks, trailingParityAppliesToAll: true) {
                out.append((from, to, bracketTeacher(bracket), bracketRoom(bracket), parity))
            }
        }
        return out
    }

    static func parseSudaLegacy(_ source: String) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        // Kotlin: selectFirst("#DataGrid1") ?: selectFirst("#MainWork_DataGrid1")
        // — 原版本 单测(171/195)喂 <table id="MainWork_DataGrid1">, 缺回退这些页面 iOS 返回 []
        guard let table = (try? doc.select("#DataGrid1"))?.first()
                ?? (try? doc.select("#MainWork_DataGrid1"))?.first() else { return [] }
        var out: [JwCourse] = []
        for row in (try? table.select("tr")) ?? Elements() {
            let tds = (try? row.select("td")) ?? Elements()
            if tds.array().contains(where: { (try? $0.text().contains("星期")) ?? false }) { continue }
            var node = 1
            for (col, td) in tds.array().enumerated() {
                let align = (try? td.attr("align")) ?? ""
                if align.lowercased() == "center" {
                    let text = (try? td.text()) ?? ""
                    let digitRe = try! NSRegularExpression(pattern: "\\d+", options: [])
                    let r = NSRange(text.startIndex..., in: text)
                    if let m = digitRe.firstMatch(in: text, options: [], range: r),
                       let n = Int((text as NSString).substring(with: m.range)) {
                        node = n
                    }
                    continue
                }
                let day = col + 1
                let text = (try? td.text()) ?? ""
                if text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                let html = (try? td.html()) ?? ""
                // SwiftSoup 输出 "<br />"(Jsoup 输出 "<br>"), 字面量分隔切不开 → 整格塌成一行
                let lines = splitByRegex(html, #"<br\s*/?>"#).map { s -> String in
                    let d = (try? SwiftSoup.parse(s)) ?? Document("")
                    return (try? d.text())?.trimmingCharacters(in: .whitespaces) ?? s
                }.filter { !$0.isEmpty }
                var name = ""
                var teacher = ""
                var room = ""
                var weeks: [(Int, Int, Int)] = []
                let weekRe = try! NSRegularExpression(pattern: "第\\s*(\\d+)\\s*(-\\s*(\\d+))?\\s*周\\s*(单|双)?", options: [])
                for line in lines {
                    if line.hasPrefix("课程:") || line.hasPrefix("课程：") {
                        name = dropPrefixColon(line).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("(") && !line.contains("辅讲教师") {
                        teacher = line.trimmingCharacters(in: CharacterSet(charactersIn: "()")).trimmingCharacters(in: .whitespaces)
                    } else if line.hasPrefix("主讲教师:") || line.hasPrefix("主讲教师：") {
                        teacher = dropPrefixColon(line).trimmingCharacters(in: .whitespaces)
                    } else if line.range(of: "第\\s*\\d+.*周", options: .regularExpression) != nil {
                        let r = NSRange(line.startIndex..., in: line)
                        let ms = weekRe.matches(in: line, options: [], range: r)
                        let ns = line as NSString
                        for m in ms {
                            // 可选组(第X周无尾数/无单双时)range = {NSNotFound, 0}, substring 直接抛 NSRangeException。
                            // Kotlin groupValues[n] 非参与组返回 "" → 用 optGroup 等价。
                            let toStr = optGroup(ns, m, 3)
                            let typeStr = optGroup(ns, m, 4)
                            let from = Int(optGroup(ns, m, 1)) ?? 1
                            let to = Int(toStr) ?? from
                            let type: Int
                            switch typeStr {
                            case "单": type = 1
                            case "双": type = 2
                            default: type = 0
                            }
                            weeks.append((from, to, type))
                        }
                    } else {
                        if name.isEmpty { name = line } else { room = line }
                    }
                }
                if name.isEmpty { name = lines.first ?? "" }
                if weeks.isEmpty { weeks.append((1, 20, 0)) }
                // WakeUp dex L00e9 rowspan: 纵向合并单元格占多节 — endNode = node + rowspan - 1
                let rs = Int((try? td.attr("rowspan")) ?? "") ?? 1
                let endNode = node + max(rs - 1, 0)
                for (from, to, type) in weeks {
                    out.append(JwCourse(name: name, room: room, teacher: teacher,
                        day: day, startNode: node, endNode: endNode,
                        startWeek: from, endWeek: to, type: type))
                }
            }
        }
        return out
    }

    private static func dropPrefixColon(_ s: String) -> String {
        if let idx = s.firstIndex(where: { $0 == ":" || $0 == "：" }) {
            let after = s.index(after: idx)
            return String(s[after...])
        }
        return s
    }

    /// Kotlin `MatchResult.groupValues[n]` 等价: 非参与捕获组(.location == NSNotFound)返回 "",
    /// 绝不对 {NSNotFound, 0} 调 NSString.substring(with:) 抛 NSRangeException。
    fileprivate static func optGroup(_ ns: NSString, _ m: NSTextCheckingResult, _ g: Int) -> String {
        let r = m.range(at: g)
        guard r.location != NSNotFound else { return "" }
        return ns.substring(with: r)
    }

    /// SwiftSoup 的 html() 把 <br>/<hr> 序列化为自闭合 "<br />"/"<hr />"(Jsoup 输出字面 "<br>"),
    /// 字面量 components 分隔永远切不开 → 整格塌成一行。按正则切片分隔才是 Jsoup 行为的等价翻译。
    /// NSRange 为 UTF-16 单位, 经 Range(of:) 换回 String.Index 再切片 — 禁 String.Index 偏移直接进 NSRange。
    fileprivate static func splitByRegex(_ s: String, _ pattern: String) -> [String] {
        let re = try! NSRegularExpression(pattern: pattern, options: [])
        let full = NSRange(s.startIndex..., in: s)
        var parts: [String] = []
        var cursor = s.startIndex
        for m in re.matches(in: s, options: [], range: full) {
            guard let r = Range(m.range, in: s) else { continue }
            parts.append(String(s[cursor..<r.lowerBound]))
            cursor = r.upperBound
        }
        parts.append(String(s[cursor...]))
        return parts
    }

    static func confidence(_ source: String, markers: Set<String>) -> Int {
        if markers.contains(where: { source.range(of: $0, options: .caseInsensitive) != nil }) { return 90 }
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return 70 }
        return 0
    }

    static func features(_ source: String, markers: Set<String>) -> [String] {
        markers.compactMap { m in
            source.range(of: m, options: .caseInsensitive) != nil ? "marker=\(m)" : nil
        }
    }

    static func parseShuweiLegacy(_ source: String) -> [JwCourse] {
        guard let root = parseJson(source) else { return [] }
        var result: [JwCourse] = []
        func visit(_ value: Any?) {
            // Kotlin: is JSONArray -> for (i in 0 until value.length()) value.opt(i)?.let(::visit)
            // — 逐元素递归, 单个非对象元素不中断整串遍历
            if let arr = value as? [Any] {
                for item in arr { visit(item) }
            } else if let obj = value as? [String: Any] {
                for key in ["activities", "courseUnits", "unitList"] {
                    if let arr = optArray(obj[key]) {
                        // Kotlin: array.optJSONObject(i) ?: continue
                        for case let row as [String: Any] in arr {
                            if let r = parseActivity(row) { result.append(contentsOf: r) }
                        }
                    }
                }
                for key in obj.keys {
                    visit(obj[key])
                }
            }
        }
        visit(root)
        var seen: Set<String> = []
        return result.filter { c in
            let s = [c.name, String(c.day), String(c.startNode), String(c.startWeek), String(c.endWeek), String(c.type)].joined(separator: "|")
            return seen.insert(s).inserted
        }
    }

    fileprivate static func parseActivity(_ row: [String: Any]) -> [JwCourse]? {
        let name = first(row, "courseName", "course", "name", "kcmc", "KCM")
        guard !isBlank(name), let day = firstInt(row, "weekday", "weekDay", "dayOfWeek", "classDay", "xqj", "day", "xq"), (1...7).contains(day),
              let start = firstInt(row, "startSection", "beginSection", "beginNumber", "startNode", "ksjc", "start"), start > 0 else { return nil }
        let end = firstInt(row, "endSection", "endNumber", "endNode", "jsjc", "end") ?? start
        guard end >= start else { return nil }
        let weeks: [(Int, Int, Int)]
        if row.keys.contains("startWeek") && row.keys.contains("endWeek") {
            guard let from = firstInt(row, "startWeek"), let to = firstInt(row, "endWeek") else { return nil }
            let parity = row.keys.contains("type") ? firstInt(row, "type") : 0
            guard let parity, (0...3).contains(parity) else { return nil }
            weeks = [(from, to, parity)]
        } else { weeks = parseWeekTokens(first(row, "weeksStr", "weekDescription", "week", "weeks", "zc")) }
        guard !weeks.isEmpty, weeks.allSatisfy({ $0.0 > 0 && $0.1 >= $0.0 }) else { return nil }
        return weeks.map { JwCourse(name: name, room: first(row, "room", "classroom", "classroomName", "location", "JASMC", "cdmc"),
            teacher: first(row, "teacher", "teacherName", "teachers", "attendClassTeacher", "SKJS", "xm"), day: day,
            startNode: start, endNode: end, startWeek: $0.0, endWeek: $0.1, type: $0.2) }
    }


    fileprivate static func parseWeekTokens(_ value: String) -> [(Int, Int, Int)] {
        if value.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        let segments = value.replacingOccurrences(of: "周", with: "")
            .components(separatedBy: CharacterSet(charactersIn: ",，;；"))
        var out: [(Int, Int, Int)] = []
        for seg in segments {
            let token = seg.trimmingCharacters(in: .whitespaces)
            if token.isEmpty { continue }
            let type: Int
            if token.contains("单") { type = 1 }
            else if token.contains("双") { type = 2 }
            else { type = 0 }
            let nums = extractInts(token)
            if nums.isEmpty { continue }
            out.append((nums[0], nums.count > 1 ? nums[1] : nums[0], type))
        }
        return out
    }

    /// 顶层 JSON 宽松解析 — 对齐 Kotlin `JSONArray(text)` / `JSONObject(text)`:
    /// 混合/null 元素数组照常返回 [Any](严格 `as? [[String: Any]]` 会整串变 nil 杀掉 JSON 通路)。
    fileprivate static func parseJson(_ source: String) -> Any? {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8) else { return nil }
        let opts: JSONSerialization.ReadingOptions = [.fragmentsAllowed]
        return try? JSONSerialization.jsonObject(with: data, options: opts)
    }

    fileprivate static func parseJsonCourses(_ root: Any) -> [JwCourse] {
        var result: [JwCourse] = []
        func walk(_ value: Any, _ depth: Int) {
            guard depth <= 5 else { return }
            if let array = value as? [Any] {
                for item in array { if let row = item as? [String: Any], let rows = parseActivity(row) { result += rows }; walk(item, depth + 1) }
            } else if let object = value as? [String: Any] { for value in object.values { walk(value, depth + 1) } }
        }
        walk(root, 0); return result
    }


    fileprivate static func parseMarkedTable(_ source: String, markers: Set<String>) -> [JwCourse] {
        var out: [JwCourse] = []
        for row in Jw64.select(Jw64.doc(source), "tr") {
            let cells = Jw64.select(row, "td,th"); guard cells.count >= 3 else { continue }
            let text = cells.map(Jw64.text).joined(separator: " | ")
            if !markers.isEmpty && !markers.contains(where: { source.range(of: $0, options: .caseInsensitive) != nil }) && Jw64.attr(row, "data-day").isEmpty { continue }
            let name = Jw64.attr(row, "data-course").isEmpty ? Jw64.text(cells[0]) : Jw64.attr(row, "data-course")
            guard !name.isEmpty, let day = Int(Jw64.attr(row, "data-day")) ?? extractDay(text), (1...7).contains(day),
                  let node = Int(Jw64.attr(row, "data-node")) ?? extractNode(text), node > 0 else { continue }
            let end = Int(Jw64.attr(row, "data-end-node")) ?? node; guard end >= node else { continue }
            let room = Jw64.attr(row, "data-room").isEmpty ? (cells.count > 3 ? Jw64.text(cells[3]) : "") : Jw64.attr(row, "data-room")
            let teacher = Jw64.attr(row, "data-teacher").isEmpty ? Jw64.text(cells[2]) : Jw64.attr(row, "data-teacher")
            for (from, to, parity) in parseWeekTokens(Jw64.attr(row, "data-weeks")) where from > 0 && to >= from {
                out.append(JwCourse(name: name, room: room, teacher: teacher, day: day, startNode: node, endNode: end, startWeek: from, endWeek: to, type: parity))
            }
        }
        return out
    }


    fileprivate static func parseDelimited(_ source: String) -> [JwCourse] {
        source.components(separatedBy: .newlines).compactMap { line -> JwCourse? in
            let p = line.components(separatedBy: CharacterSet(charactersIn: ",\t"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count >= 5,
                  let day = Int(p[1]), (1...7).contains(day),
                  let node = Int(p[2]) else { return nil }
            return JwCourse(name: p[0], room: p.count > 3 ? p[3] : "", teacher: p.count > 4 ? p[4] : "",
                day: day, startNode: node, endNode: node, startWeek: 1, endWeek: 16)
        }
    }

    fileprivate static func first(_ o: [String: Any], _ keys: String...) -> String {
        // Kotlin: keys.firstNotNullOfOrNull { o.optString(it).takeIf(String::isNotBlank) }
        // — optString 对数字/布尔自动转字符串, 严格 `as? String` 会漏掉数字型课名/教师
        for k in keys {
            let s = optString(o[k])
            if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        }
        return ""
    }
    fileprivate static func firstInt(_ object: [String: Any], _ keys: String...) -> Int? {
        for key in keys { if let value = jw1064Integer(optString(object[key]).trimmingCharacters(in: .whitespacesAndNewlines)) { return value } }
        return nil
    }

    fileprivate static func stripMarkup(_ value: String) -> String {
        let doc = (try? SwiftSoup.parse(value)) ?? Document("")
        return (try? doc.text())?.trimmingCharacters(in: .whitespaces) ?? value
    }
    fileprivate static func extractDay(_ text: String) -> Int? {
        let re = try! NSRegularExpression(pattern: "(?:星期|周)\\s*([一二三四五六日天1-7])", options: [])
        let r = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: r) else { return nil }
        let ns = text as NSString
        let v = ns.substring(with: m.range(at: 1))
        switch v {
        case "一": return 1
        case "二": return 2
        case "三": return 3
        case "四": return 4
        case "五": return 5
        case "六": return 6
        case "日", "天": return 7
        default: return Int(v)
        }
    }
    fileprivate static func extractNode(_ text: String) -> Int? {
        let re = try! NSRegularExpression(pattern: "(?:第\\s*)?(\\d+)\\s*(?:[-~至](\\d+))?\\s*节", options: [])
        let r = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: r) else { return nil }
        let ns = text as NSString
        return Int(ns.substring(with: m.range(at: 1)))
    }
    fileprivate static func timeToNode(_ time: Int) -> Int {
        if time < 1230 { return ((time - 800) / 100) + 1 }
        if time < 1800 { return ((time - 1400) / 100) + 5 }
        return ((time - 1900) / 100) + 9
    }
    fileprivate static func durationToNodes(_ start: Int, _ end: Int) -> Int {
        let delta = end - start
        if (50...99).contains(delta) { return 1 }
        if delta <= 200 { return 2 }
        if (210...340).contains(delta) { return 3 }
        return 4
    }
    fileprivate static func extractInts(_ s: String) -> [Int] {
        let re = try! NSRegularExpression(pattern: "\\d+", options: [])
        let r = NSRange(s.startIndex..., in: s)
        return re.matches(in: s, options: [], range: r).compactMap { m in
            Int((s as NSString).substring(with: m.range))
        }
    }
    fileprivate static func intField(_ v: Any?) -> Int? {
        if let n = v as? Int { return n }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        if let n = v as? Double { return Int(n) }
        if let b = v as? Bool { return b ? 1 : 0 }
        return nil
    }
    /// Kotlin `isBlank()` 等价: 全空白(含换行)视为空。
    fileprivate static func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    /// org.json `optString` 语义: 数字/布尔自动转字符串, null/缺失 → ""。
    fileprivate static func optString(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if v == nil || v is NSNull { return "" }
        if let n = v as? NSNumber {
            // JSON true/false 是 NSNumber 子类(CFBoolean) — Kotlin optString 给 "true"/"false"
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            return d == d.rounded() && !d.isInfinite ? String(n.int64Value) : n.stringValue
        }
        return String(describing: v)
    }
    /// org.json `optJSONArray` 语义: 非数组返回 nil(便于 `?? ` 链回退)。
    fileprivate static func optArray(_ v: Any?) -> [Any]? {
        v as? [Any]
    }
    /// org.json `optJSONObject(i) ?: continue` 语义: 逐元素取字典, 混合/null 元素只跳过该条,
    /// 不像严格 `as? [[String: Any]]` 那样因一个坏元素丢掉整个数组。
    fileprivate static func jsonRows(_ v: Any?) -> [[String: Any]] {
        optArray(v)?.compactMap { $0 as? [String: Any] } ?? []
    }
}

// MARK: - v1.0.62 B7a: JZ super / Kingo super (← JwWakeUpCompatParsers.kt:51/263)

extension WakeUpCompat {

    // — Kotlin 字符串/正则小工具 (文件内私有) —

    fileprivate static func wakeTag(_ el: Element) -> String {
        ((try? el.tagName()) ?? "").lowercased()
    }
    /// Kotlin text().trim() — 各调用点都紧跟 trim, 合并处理。
    fileprivate static func wakeText(_ el: Element) -> String {
        ((try? el.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    fileprivate static func wakeTrim(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    fileprivate static func fragmentText(_ s: String) -> String {
        let d = (try? SwiftSoup.parse(s)) ?? Document("")
        return wakeTrim((try? d.text()) ?? "")
    }
    fileprivate static func wakeAttr(_ el: Element, _ key: String) -> String {
        (try? el.attr(key)) ?? ""
    }
    /// Kotlin matchEntire: 全串命中返回捕获组(0=全串, 未参与组=""), 否则 nil。
    fileprivate static func matchEntire(_ pattern: String, _ s: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let m = re.firstMatch(in: s, options: [], range: full), m.range == full else { return nil }
        return (0..<m.numberOfRanges).map { i -> String in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
    static func containsMatch(_ pattern: String, _ s: String) -> Bool {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = s as NSString
        return re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) != nil
    }
    fileprivate static func reFirstGroup(_ pattern: String, _ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return "" }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else { return "" }
        let r = m.range(at: 1)
        return r.location == NSNotFound ? "" : ns.substring(with: r)
    }
    /// Kotlin Regex(pat).split — 空段保留(与 CharacterSet.split 不同)。
    fileprivate static func wakeSplitRegex(_ s: String, _ pattern: String, ci: Bool = false) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: ci ? [.caseInsensitive] : []) else { return [s] }
        let ns = s as NSString
        var parts: [String] = []
        var last = 0
        for m in re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: last))
        return parts
    }
    fileprivate static func wakeSplitAny(_ s: String, _ chars: [Character]) -> [String] {
        s.split(whereSeparator: { chars.contains($0) }).map(String.init)
    }
    /// Kotlin substringBefore(c): 无分隔符返回全串。
    fileprivate static func before(_ s: String, _ ch: Character) -> String {
        guard let i = s.firstIndex(of: ch) else { return s }
        return String(s[..<i])
    }
    /// Kotlin substringBefore(c, missing): 无分隔符返回 missing。
    fileprivate static func before(_ s: String, _ ch: Character, _ missing: String) -> String {
        guard let i = s.firstIndex(of: ch) else { return missing }
        return String(s[..<i])
    }
    /// Kotlin substringAfter(c, ""): 无分隔符返回 ""。
    fileprivate static func after(_ s: String, _ ch: Character) -> String {
        guard let i = s.firstIndex(of: ch) else { return "" }
        return String(s[s.index(after: i)...])
    }
    /// Kotlin substringAfter(c): 无分隔符返回全串。
    fileprivate static func afterKeep(_ s: String, _ ch: Character) -> String {
        guard let i = s.firstIndex(of: ch) else { return s }
        return String(s[s.index(after: i)...])
    }
    /// Kotlin substringBeforeLast(c, missing): 无分隔符返回 missing。
    fileprivate static func beforeLast(_ s: String, _ ch: Character, _ missing: String = "") -> String {
        guard let i = s.lastIndex(of: ch) else { return missing }
        return String(s[..<i])
    }
    fileprivate static func hasKingoTdGrid(_ source: String) -> Bool {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        return !((try? doc.select("table#mytable td.td")) ?? Elements()).isEmpty()
    }

    // — JZ super (新强智 Njw2017 SPA 2026-10) —

    /// 新强智 Njw2017 SPA (2026-10) 主入口 — ← Kotlin parseJzSuper (JwWakeUpCompatParsers.kt:51)。
    /// 容器 .el-table__body-wrapper; tbody 6 行 × 8 td (col0=节次标签, col1..7=周一..周日);
    /// 格内 div[style] 含 position:relative 者为课程包装器, 8 子 div: [3]课名(前导*剥) [4]教师 [6]节次(周次) [7]教室。
    static func parseJzSuper(_ source: String, errors: inout [String]) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        guard let wrapper = ((try? doc.select(".el-table__body-wrapper")) ?? Elements()).array().first else {
            errors.append("INV-MARKER-MISS 失败: 未找到 el-table__body-wrapper 容器 (新强智 Njw2017 SPA 主入口)")
            return []
        }
        guard let body = ((try? wrapper.select("tbody")) ?? Elements()).array().first else {
            errors.append("INV-TBODY-MISS 失败: el-table__body-wrapper 缺 tbody")
            return []
        }
        let rows = ((try? body.select("tr")) ?? Elements()).array()
        if rows.isEmpty {
            errors.append("INV-ROW-COUNT 失败: tbody 无 tr 行")
            return []
        }
        if rows.count < 6 {
            errors.append("INV-ROW-COUNT-WARN: tbody tr 数 \(rows.count) (<6 行, 仅用于单元测试)")
        }
        // 行 → 默认节次 (QZParser.java#getSectionStart 共识, 仅当 div[6] 不含「节」字时降级)
        let defaultStartByRow = [1, 3, 6, 8, 10, 13]
        let defaultEndByRow = [2, 5, 7, 9, 12, 15]
        let reRowSection = "^([0-9]{1,2})(?:\\s*[-~至]\\s*([0-9]{1,2}))?节$"
        let rePosition = "(?:^|;)\\s*position\\s*:\\s*relative\\s*(?:;|$)"
        let reWeek = "^([0-9]{1,2})(?:\\s*[-~至]\\s*([0-9]{1,2}))?\\s*周?\\s*(单|双)?\\s*周?$"
        var out: [JwCourse] = []
        for (rowIdx, row) in rows.enumerated() {
            let tds = ((try? row.children()) ?? Elements()).array().filter { wakeTag($0) == "td" }
            if tds.count < 8 { continue } // 0=节次标签, 1..7=周一..周日
            let rowLabel = wakeText(tds[0])
            var rowSections: (Int, Int)? = nil
            if let m = matchEntire(reRowSection, rowLabel), let f = Int(m[1]) {
                let l = m[2].isEmpty ? f : (Int(m[2]) ?? f)
                if f >= 1 && f <= 30 && l >= f && l <= 30 { rowSections = (f, l) }
            } else if rowLabel.isEmpty, rows.count == 6, rowIdx < defaultStartByRow.count {
                rowSections = (defaultStartByRow[rowIdx], defaultEndByRow[rowIdx])
            }
            for col in 1...7 {
                let td = tds[col]
                // INV-POSITION-WRAPPER: 用 div[style] 选出 position: relative 课程包装器
                let wrappers = ((try? td.select("div[style]")) ?? Elements()).array()
                    .filter { containsMatch(rePosition, wakeAttr($0, "style")) }
                for wrapperEl in wrappers {
                    let info = ((try? wrapperEl.children()) ?? Elements()).array().filter { wakeTag($0) == "div" }
                    if info.count < 8 { continue } // 8 字段包装器(实测), 不足视为非课程包装器
                    let nameRaw = wakeText(info[3])
                    if nameRaw.isEmpty { continue }
                    // INV-NAME-STRIP-ASTERISK: QZParser.java#getClassName char[0]=='*' → 剥前导 *
                    var name = nameRaw
                    if name.hasPrefix("*") { name = String(name.dropFirst()) }
                    name = wakeTrim(name)
                    if name.isEmpty { continue }
                    let teacher = wakeText(info[4])
                    let weeksText = wakeText(info[6])
                    let room = wakeText(info[7])
                    let startNode: Int
                    let endNode: Int
                    if weeksText.contains("节") {
                        let head = wakeTrim(before(before(weeksText, "("), "（"))
                        guard let m = matchEntire(reRowSection, head), let f = Int(m[1]) else { continue }
                        let l = m[2].isEmpty ? f : (Int(m[2]) ?? f)
                        if !(1...366).contains(f) || !(f...30).contains(l) { continue }
                        startNode = f
                        endNode = l
                    } else {
                        guard let fb = rowSections else { continue } // INV-SECTIONS-FALLBACK
                        startNode = fb.0
                        endNode = fb.1
                    }
                    // INV-WEEKS-EXTRACT-PAREN: 取括号内周次 (QZParser.java#getWeeksList)
                    let weeksRaw = reFirstGroup("[\\(（]([^\\)）]+)[\\)）]", weeksText)
                    for token in wakeSplitAny(weeksRaw, [",", "，", ";", "；"]) {
                        let cleaned = String(token.filter { !$0.isWhitespace })
                        guard let m = matchEntire(reWeek, cleaned), let f = Int(m[1]) else { continue }
                        let l = m[2].isEmpty ? f : (Int(m[2]) ?? f)
                        if !(1...60).contains(f) || !(f...60).contains(l) { continue }
                        let type: Int
                        switch m[3] {
                        case "单": type = 1
                        case "双": type = 2
                        default: type = 0
                        }
                        out.append(JwCourse(name: name, room: room, teacher: teacher, day: col,
                                           startNode: startNode, endNode: endNode,
                                           startWeek: f, endWeek: l, type: type))
                    }
                }
            }
        }
        return out
    }

    static func parseJzSuper(_ source: String) -> [JwCourse] {
        var errors: [String] = []
        return parseJzSuper(source, errors: &errors)
    }

    // — Kingo super (新青果 2026-10) HTML 3 链降级 —

    /// ← Kotlin parseKingoSuperHtml (JwWakeUpCompatParsers.kt:263)。
    /// chain1 #mytable 正选网格(compact/xkinfo); chain2 thead 课程+节次 表; chain3 #kbDiv 7 列网格。
    static func parseKingoSuperHtmlLegacy(_ source: String, errors: inout [String]) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")

        func nodes(_ text: String) -> (Int, Int)? {
            guard let m = matchEntire("^\\s*([0-9]{1,2})(?:\\s*[-~至]\\s*([0-9]{1,2}))?\\s*(?:节)?\\s*$", text),
                  let f = Int(m[1]) else { return nil }
            let l = m[2].isEmpty ? f : (Int(m[2]) ?? f)
            return (f >= 1 && f <= 30 && l >= f && l <= 30) ? (f, l) : nil
        }
        func emit(_ name: String, _ teacher: String, _ room: String, _ day: Int,
                  _ nodeText: String, _ weeksText: String) -> [JwCourse] {
            guard let (start, end) = nodes(nodeText) else { return [] }
            if wakeTrim(name).isEmpty || !(1...7).contains(day) { return [] }
            // 本源周次语法保持严格 (Kotlin weekPattern); 泛兼容链才刻意宽松。
            let re = "^([0-9]{1,2})(?:[-~至]([0-9]{1,2}))?周?(?:[\\(（]([单双])[）\\)]|([单双])周?)?$"
            var out: [JwCourse] = []
            for raw in wakeSplitAny(weeksText, [",", "，", ";", "；"]) {
                let cleaned = String(raw.filter { !$0.isWhitespace })
                guard let m = matchEntire(re, cleaned), let f = Int(m[1]) else { continue }
                let l = m[2].isEmpty ? f : (Int(m[2]) ?? f)
                if !(1...60).contains(f) || !(f...60).contains(l) { continue }
                let parity = m[3].isEmpty ? m[4] : m[3]
                let type: Int
                switch parity {
                case "单": type = 1
                case "双": type = 2
                default: type = 0
                }
                out.append(JwCourse(name: name, room: room, teacher: teacher, day: day,
                                    startNode: start, endNode: end,
                                    startWeek: f, endWeek: l, type: type))
            }
            return out
        }

        func isDayHeader(_ text: String, _ day: Int) -> Bool {
            let t = wakeTrim(text)
            let name = ["一", "二", "三", "四", "五", "六", "日"][day - 1]
            return t == name || (day == 7 && t == "天") ||
                t.contains("星期\(name)") || (day == 7 && t.contains("星期天")) ||
                t.contains("周\(name)") || (day == 7 && t.contains("周天")) ||
                t.contains("星期\(day)") || t.contains("周\(day)")
        }

        // chain1: #mytable
        var myTable: [JwCourse] = []
        for table in ((try? doc.select("#mytable")) ?? Elements()).array() {
            var totalDays = 7
            for row in ((try? table.select("tr")) ?? Elements()).array() {
                let texts = row.children().array().map { wakeText($0) }
                let hasMonday = texts.contains { isDayHeader($0, 1) }
                if hasMonday && texts.contains(where: { isDayHeader($0, 6) || isDayHeader($0, 7) }) { break }
                if hasMonday && texts.contains(where: { isDayHeader($0, 5) }) { totalDays = 5; break }
            }
            let tableCompact = ((try? table.select("div.div1")) ?? Elements()).array()
                .contains { ((try? $0.html()) ?? "").contains("xkinfo") }
            for row in ((try? table.select("tr:not(.H)")) ?? Elements()).array() {
                if !((try? row.select("th")) ?? Elements()).isEmpty() { continue }
                let rowTexts = row.children().array().map { wakeText($0) }
                // 课程名可含「周一」，带节次的课程格不能当作表头跳过。
                if rowTexts.contains(where: { isDayHeader($0, 1) && !$0.contains("[") }) { continue }
                let allCells = ((try? row.select("td")) ?? Elements()).array()
                for (column, cell) in allCells.enumerated() {
                    // 从右端对齐，兼容行首节次/时段水槽及其 rowspan。
                    let day = allCells.count >= totalDays ? totalDays - (allCells.count - 1 - column) : column + 1
                    if !(1...7).contains(day) { continue }
                    var compact = tableCompact
                    let rawBlocks = cell.children().array().filter { wakeTag($0) == "div" }
                    let hasBracket = containsMatch(#"\[[[:space:]]*[0-9]+"#, wakeText(cell))
                    let blocks = rawBlocks.isEmpty && hasBracket ? [cell] : rawBlocks
                    for block in blocks {
                        if wakeTag(block) == "div" && block.hasClass("div1") {
                            let h = (try? block.html()) ?? ""
                            compact = h.contains("xkinfo") && h.contains("&nbsp;")
                            continue
                        }
                        let rawHtml = (try? block.html()) ?? ""
                        let html = compact
                            ? wakeSplitRegex(rawHtml, "(?:&nbsp;)+", ci: true).joined(separator: " ")
                            : rawHtml
                        let lines = wakeSplitRegex(html, "<br[^>]*>", ci: true)
                            .map { fragmentText($0) }.filter { !$0.isEmpty }
                        guard let detailIdx = lines.firstIndex(where: {
                            $0.contains("]") && containsMatch(#"\[[[:space:]]*[0-9]+"#, $0)
                        }), detailIdx > 0 else { continue }
                        let detail = lines[detailIdx]
                        let name = lines.first ?? ""
                        let beforeBracket = wakeTrim(before(detail, "["))
                        let compactMode = compact || (detailIdx == 1 && beforeBracket.contains(" ") &&
                            !beforeBracket.contains(",") && !beforeBracket.contains("，"))
                        let teacher: String
                        let weekText: String
                        if compactMode && beforeBracket.contains(" ") {
                            teacher = wakeTrim(before(detail, " "))
                            weekText = wakeTrim(before(after(detail, " "), "["))
                        } else {
                            teacher = wakeTrim(lines.dropFirst().prefix(detailIdx - 1).joined(separator: " "))
                            weekText = beforeBracket
                        }
                        let room = wakeTrim(lines.dropFirst(detailIdx + 1).joined(separator: " "))
                        let nodeText = wakeTrim(before(after(detail, "["), "]"))
                        if !weekText.isEmpty && !nodeText.isEmpty {
                            myTable.append(contentsOf: emit(name, teacher, room, day, nodeText, weekText))
                        }
                    }
                }
            }
        }
        if !myTable.isEmpty { return myTable }
        errors.append("chain1 #mytable: no valid weekday cell")

        // chain2: thead 课程+节次 表
        var formatTwo: [JwCourse] = []
        for table in ((try? doc.select("table")) ?? Elements()).array() {
            guard let tr = ((try? table.select("thead tr")) ?? Elements()).array().first else { continue }
            let headers = ((try? tr.select("th,td")) ?? Elements()).array().map { wakeText($0) }
            let nameIndex = headers.firstIndex(of: "课程") ?? -1
            let nodeIndex = headers.firstIndex { $0.contains("节次") } ?? -1
            if nameIndex < 0 || nodeIndex < 0 { continue }
            let teacherIndex = headers.firstIndex { $0.contains("教师") } ?? -1
            let roomIndex = headers.firstIndex { $0.contains("地点") } ?? -1
            let weeksIndex = headers.firstIndex { $0.contains("周次") } ?? -1
            let parityIndex = headers.firstIndex { $0.contains("单双周") } ?? -1
            for row in ((try? table.select("tbody tr")) ?? Elements()).array() {
                let cells = ((try? row.children()) ?? Elements()).array()
                func cellText(_ i: Int) -> String {
                    (i >= 0 && cells.indices.contains(i)) ? wakeText(cells[i]) : ""
                }
                let name = wakeTrim(afterKeep(cellText(nameIndex), "]"))
                let timing = cellText(nodeIndex)
                guard let day = extractDay(before(timing, "[")) else { continue }
                let nodeText = before(after(timing, "["), "]")
                let weeks = weeksIndex >= 0 ? cellText(weeksIndex)
                    : beforeLast(after(timing, "("), ")")
                let parity = cellText(parityIndex)
                let typedWeeks = wakeSplitAny(weeks, [",", "，", ";", "；"])
                    .map { part -> String in
                        let t = wakeTrim(part)
                        return (t.contains("单") || t.contains("双") || parity.isEmpty) ? t : t + parity
                    }
                    .joined(separator: ",")
                formatTwo.append(contentsOf: emit(name, wakeTrim(afterKeep(cellText(teacherIndex), "]")),
                                                  cellText(roomIndex), day, nodeText, typedWeeks))
            }
        }
        if !formatTwo.isEmpty { return formatTwo }
        errors.append("chain2 thead: no valid course row")

        // chain3: #kbDiv
        var kbDiv: [JwCourse] = []
        for table in ((try? doc.select("#kbDiv")) ?? Elements()).array() {
            guard let body = ((try? table.select("tbody")) ?? Elements()).array().last else { continue }
            for (rowIndex, row) in ((try? body.select("tr")) ?? Elements()).array().enumerated() {
                let allCells = ((try? row.select("td")) ?? Elements()).array()
                if allCells.count < 7 { continue }
                let cells = Array(allCells.suffix(7))
                for (dayIndex, cell) in cells.enumerated() {
                    let text = wakeText(cell)
                    let name = wakeTrim(before(text, "("))
                    let detail = beforeLast(after(text, "("), ")")
                    let parts = wakeSplitRegex(detail, "\\s+").filter { !$0.isEmpty }
                    if name.isEmpty || parts.isEmpty { continue }
                    kbDiv.append(contentsOf: emit(name, "", parts.count > 1 ? parts[1] : "",
                                                  dayIndex + 1, String(rowIndex + 1), parts[0]))
                }
            }
        }
        if !kbDiv.isEmpty { return kbDiv }
        errors.append("chain3 #kbDiv: no valid timetable cell")
        return []
    }

    static func parseKingoSuperHtmlLegacy(_ source: String) -> [JwCourse] {
        var errors: [String] = []
        return parseKingoSuperHtml(source, errors: &errors)
    }
}

// MARK: - WakeUpMarkerParser 基类与 8 concrete parsers

class WakeUpMarkerParserBase: JwParser, JwParserConfidenceReporting {
    let source: String
    let markers: Set<String>
    init(_ source: String, _ markers: Set<String>) {
        self.source = source
        self.markers = markers
    }
    func generateCourseList() throws -> [JwCourse] { WakeUpCompat.parse(source, markers: markers) }
    var confidenceValue: Int { WakeUpCompat.confidence(source, markers: markers) }
    var matchedFeatureList: [String] { WakeUpCompat.features(source, markers: markers) }
}

final class JwKingoParser: WakeUpMarkerParserBase {
    // v1.0.62: markers 扩至 8 (JwWakeUpCompatParsers.kt:885), 覆盖 ScheduleTaskBean/xkinfo/kbDiv。
    init(_ source: String) {
        super.init(source, ["kingosoft", "courseTableForStd", "courseTableStudent", "new TaskActivity",
                            "CourseTableForStd", "ScheduleTaskBean", "xkinfo", "kbDiv"])
    }
    override var confidenceValue: Int {
        // td.td 正选老 ZX 网格 (首个 td 可能是节次水槽) → 让位 KINGO_ZX
        if source.contains("id=\"kbDiv\"") || source.contains("id='kbDiv'") { return 95 }
        if source.contains("<thead") && source.contains("课程") && source.contains("节次")
            && WakeUpCompat.containsMatch(#"(?:星期|周)[一二三四五六日天1-7]"#, source) { return 93 }
        if source.contains("id=\"mytable\"") || source.contains("id='mytable'") { return 91 }
        return super.confidenceValue
    }
    override func generateCourseList() throws -> [JwCourse] {
        // 声明 KINGO_NEW 的学校仍可能回供老正选网格 → 委托 ZX 保留节次水槽/稀疏周次语义
        // Kingo Super 2026-10 三阶段降级: HTML 3 链 → TaskActivity JS grid → 父类 markers
        var errors: [String] = []
        let superHtml = WakeUpCompat.parseKingoSuperHtml(source, errors: &errors)
        if !superHtml.isEmpty { return superHtml }
        let taskActivity = WakeUpCompat.parseKingoTaskActivity(source)
        if !taskActivity.isEmpty { return taskActivity }
        let parent = try super.generateCourseList()
        if !parent.isEmpty { return parent }
        // 全失败 — INV-ERROR-AGGREGATE: 错误列表聚合抛出 (Kotlin IllegalStateException 同义)
        errors.append("TaskActivity JS grid 链 (chain1/老 kingo) 解析为空")
        errors.append("父类 WakeUpMarkerParser 链 (markers 命中回退) 解析为空")
        throw JwParseError(message: "JwKingoParser (新青果 super 2026-10) 全链降级失败:\n" + errors.joined(separator: "\n"))
    }
}

final class JwJzParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["courseTableForStd", "courseTableStudent", "wisedu", "JinZhi"]) }
    private var nativeFeatures: [String] {
        let doc = Jw64.doc(source.replacingOccurrences(of: "divclass=", with: "div class="))
        var features = ["table[id=1]", "table#CourseFormTable", "table.CourseFormTable", ".wut_table .mtt_arrange_item", ".wut_tablex td[data-role][data-week]", ".x-table", "table[id^=jsTbl_] td[xq][jc]", "td[data-role=item] .mtt_arrange_item"].filter { Jw64.first(doc, $0) != nil }.map { "jz=" + $0 }
        if !Jw64.matches(#"\bvar\s+scheduleList\s*="#, source).isEmpty, !Jw64.matches(#"\bvar\s+notArrangedList\s*="#, source).isEmpty { features.append("jz=scheduleList") }
        return features
    }
    override var confidenceValue: Int { nativeFeatures.isEmpty ? super.confidenceValue : 95 }
    override var matchedFeatureList: [String] { nativeFeatures + super.matchedFeatureList }
}

final class JwJzSuperParser: WakeUpMarkerParserBase {
    // ← 原版本 JwJzSuperParser (kt:920): 新强智 super 形态专用; 主链 parse() 已含 parseJzSuper。
    init(_ source: String) {
        super.init(source, ["el-table__body-wrapper", "Njw2017", "course-list", "v-jsxsd", "studentTableVms", "JinZhi"])
    }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseJzSuper(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwSouthSoftParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["studentTableVms", "studentTableVm", "activities", "south_soft"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseSouthSoft(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwChaoxingLegacyParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["kckbData", "LessonArray", "queryKbForGrdb", "Powered by ChaoXing"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseChaoxing(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwShuweiParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["courseUnits", "unitCount", "activities", "wut_table", "shuwei"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseShuwei(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwSudaParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["print-schedule-table", "default2.aspx", "xskbcx.aspx", "suda"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseSuda(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwCumtbParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["eams5-student", "schedule-table", "course-table", "cumtb"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseCumtb(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwXjuParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["xjtu", "xju", "courseTable", "课程表"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseXju(source)
        if source.contains("contentParent_dgData") { return primary }
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

final class JwUmoocParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["timetable", "infolist_hr_common", "academic/common/security"]) }
    override func generateCourseList() throws -> [JwCourse] {
        return WakeUpCompat.parseUmooc(source)
    }
}

final class JwYlParser: WakeUpMarkerParserBase {
    init(_ source: String) { super.init(source, ["CourseTimeTable-styles-timeTable", "lyuapServer", "奕联"]) }
    override func generateCourseList() throws -> [JwCourse] {
        let primary = WakeUpCompat.parseYl(source)
        return primary.isEmpty ? try super.generateCourseList() : primary
    }
}

// MARK: - UMOOC / 奕联(YL) 课表解析

extension WakeUpCompat {

    /// UMOOC 教务课表: 容器 `.timetable` 或 `#timetable`, 行内单元格文本按行拆成
    /// [课程名, 教师, 教室, 周次信息], 周次信息形如 "1-16周" / "1-16周(单)"。
    ///
    /// ★ 与 原版本 的实现差异(两处, 均有实证):
    ///   a. 原版本 写 `cell.text().trim().split("\n")` 并要求 `lines.size >= 2`。
    ///      Jsoup 的 `Element.text()` 会把 `<br>` 折成一个空格、并把换行也折成空格,
    ///      所以 split("\n") 永远只得到 1 行 ⇒ **原版本 的 parseUmooc/parseYl 是死代码,
    ///      永远返回空列表**。本实现改用 `html()` + `<br>` 正则切分(与 Jsoup 的
    ///      `html()` 行为等价), 才能真正取到多行字段。
    ///   b. 单双周 type 取值: 原版本 写 单→1 / 双→0 / 其余→2, 与 `JwCourse.type`
    ///      的 0=每周 / 1=单周 / 2=双周 语义以及 `JwParity.adjustedRange` 冲突 ——
    ///      双周课会被当每周、每周课会被当双周。本实现取自然映射 单→1 / 双→2 / 其余→0。
    ///      原版本 侧没有 UMOOC/YL 的单测与 fixture, 该差异无上游断言覆盖。
    static func parseUmoocLegacy(_ source: String) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        // Kotlin: selectFirst(".timetable") ?: selectFirst("#timetable") ?: return emptyList()
        guard let timetable = (try? doc.select(".timetable"))?.first()
                ?? (try? doc.select("#timetable"))?.first() else { return [] }
        var result: [JwCourse] = []
        for (rowIndex, row) in ((try? timetable.select("tr")) ?? Elements()).enumerated() {
            for (cellIndex, cell) in ((try? row.select("td")) ?? Elements()).enumerated() {
                let text = ((try? cell.text()) ?? "").trimmingCharacters(in: .whitespaces)
                if text.isEmpty || text == "节次" { continue }
                let lines = splitByRegex((try? cell.html()) ?? "", #"<br\s*/?>"#)
                    .map { chunk -> String in
                        let t = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.isEmpty { return "" }
                        guard let d = try? SwiftSoup.parse(t) else { return t }
                        return ((try? d.text()) ?? t).trimmingCharacters(in: .whitespaces)
                    }
                    .filter { !$0.isEmpty }
                guard lines.count >= 2 else { continue }
                let name = lines[0]
                let teacher = lines.count > 1 ? lines[1] : ""
                let room = lines.count > 2 ? lines[2] : ""
                let weekInfo = lines.count > 3 ? lines[3] : ""
                guard let m = reWeekDash.firstMatch(
                    in: weekInfo, range: NSRange(weekInfo.startIndex..., in: weekInfo)) else { continue }
                let ns = weekInfo as NSString
                guard let startWeek = Int(ns.substring(with: m.range(at: 1))),
                      let endWeek = Int(ns.substring(with: m.range(at: 2))) else { continue }
                let type: Int
                if weekInfo.contains("单") { type = 1 }
                else if weekInfo.contains("双") { type = 2 }
                else { type = 0 }
                let day = cellIndex + 1
                guard (1...7).contains(day) else { continue }
                let startNode = rowIndex + 1
                result.append(JwCourse(name: name, room: room, teacher: teacher, day: day,
                                        startNode: startNode, endNode: startNode,
                                        startWeek: startWeek, endWeek: endWeek, type: type))
            }
        }
        var seen = Set<String>()
        return result.filter { c in
            let key = [c.name, String(c.day), String(c.startNode), String(c.startWeek),
                       String(c.endWeek), String(c.type)].joined(separator: "|")
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    /// 奕联(YL) 教务课表: 容器 class 含 "CourseTimeTable" 的表, 取其 tbody 的行。
    /// 字段与 UMOOC 相同(见 parseUmooc 的注释, 含与 原版本 的两处差异说明)。
    static func parseYlLegacy(_ source: String) -> [JwCourse] {
        let doc = (try? SwiftSoup.parse(source)) ?? Document("")
        // Kotlin: selectFirst(".app-components-CourseTimeTable-styles-timeTable")
        //         ?: selectFirst("[class*=CourseTimeTable]") ?: return emptyList()
        let container = (try? doc.select(".app-components-CourseTimeTable-styles-timeTable"))?.first()
            ?? (try? doc.select("[class*=CourseTimeTable]"))?.first()
        guard let timeTable = container else { return [] }
        guard let tbody = (try? timeTable.select("tbody"))?.first() else { return [] }
        var result: [JwCourse] = []
        for (rowIndex, row) in ((try? tbody.select("tr")) ?? Elements()).enumerated() {
            for (cellIndex, cell) in ((try? row.select("td")) ?? Elements()).enumerated() {
                let text = ((try? cell.text()) ?? "").trimmingCharacters(in: .whitespaces)
                if text.isEmpty || text == "节次" { continue }
                let lines = splitByRegex((try? cell.html()) ?? "", #"<br\s*/?>"#)
                    .map { chunk -> String in
                        let t = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
                        if t.isEmpty { return "" }
                        guard let d = try? SwiftSoup.parse(t) else { return t }
                        return ((try? d.text()) ?? t).trimmingCharacters(in: .whitespaces)
                    }
                    .filter { !$0.isEmpty }
                guard lines.count >= 2 else { continue }
                let name = lines[0]
                let teacher = lines.count > 1 ? lines[1] : ""
                let room = lines.count > 2 ? lines[2] : ""
                let weekInfo = lines.count > 3 ? lines[3] : ""
                guard let m = reWeekDash.firstMatch(
                    in: weekInfo, range: NSRange(weekInfo.startIndex..., in: weekInfo)) else { continue }
                let ns = weekInfo as NSString
                guard let startWeek = Int(ns.substring(with: m.range(at: 1))),
                      let endWeek = Int(ns.substring(with: m.range(at: 2))) else { continue }
                let type: Int
                if weekInfo.contains("单") { type = 1 }
                else if weekInfo.contains("双") { type = 2 }
                else { type = 0 }
                let day = cellIndex + 1
                guard (1...7).contains(day) else { continue }
                let startNode = rowIndex + 1
                result.append(JwCourse(name: name, room: room, teacher: teacher, day: day,
                                        startNode: startNode, endNode: startNode,
                                        startWeek: startWeek, endWeek: endWeek, type: type))
            }
        }
        var seen = Set<String>()
        return result.filter { c in
            let key = [c.name, String(c.day), String(c.startNode), String(c.startWeek),
                       String(c.endWeek), String(c.type)].joined(separator: "|")
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    /// "1-16周" 里的数字区间。
    private static let reWeekDash = try! NSRegularExpression(pattern: "(\\d+)-(\\d+)", options: [])
}
