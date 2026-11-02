// JwNewUrpSuperParser.swift — ← JwNewUrpSuperParser.kt
//
// WakeUp `NewUrpSuperParser` 第二变体 (smali 类名 `o0O0o`) — flat JSON 数组 + skzc 位图。
//
// 协议特征:
//   1. 顶层是 JSON **数组** (与第一变体 `o0` 的 dateList[].selectCourseList[].timeAndPlaceList[]
//      嵌套结构互斥),
//   2. 每项含 kcm(课名) / jsm(教师) / jxlm+jasm(教学楼+教室) / cxjc(持续节数) /
//      id.skxq(星期 1..7) / id.skjc(起始节) / id.skzc(周次位图 '0'/'1' 串)。
//   3. 周次位图按 1-based 索引: 第 i 位 = 是否第 i 周上课。
//
// 真源: tools/reverse/wakeup-fresh/smali_classes4/.../o0O0o.smali (反编译)。
//
// 与 Android 的实现差异(等价翻译):
//   a. org.json JSONArray → JSONSerialization (严格模式, 不开 fragments)。
//   b. Jsoup script.data() → 原始源码 `<script>` 块正则抽取 (内容等价, 免依赖
//      SwiftSoup data 节点 API 的行为差异)。
//   c. 正则一律 [0-9] 字符类 (PR #22 教训: iOS 26 ICU \d 吞全角数字)。

import Foundation

final class JwNewUrpSuperParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        var result: [JwCourse] = []

        // 1. 从源里抠出 JSON 数组字符串
        guard let jsonText = JwNewUrpSuperParser.extractJsonArray(source) else { return result }

        // 2. 解析 JSON 数组 (org.json JSONArray → [Any]; 解析失败回空列表)
        guard let data = jsonText.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            return result
        }
        if arr.isEmpty { return result }

        for element in arr {
            guard let item = element as? [String: Any] else { continue }
            let name = (item["kcm"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { continue }

            let teacher = (item["jsm"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let building = (item["jxlm"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let room = (item["jasm"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let fullRoom = (building + room).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let id = item["id"] as? [String: Any] else { continue }
            // ← org.json optInt: Number 或数字串都接受
            let day = Self.optInt(id["skxq"]) ?? 0
            guard (1...7).contains(day) else { continue }

            let startNode = Self.optInt(id["skjc"]) ?? 0
            guard (1...30).contains(startNode) else { continue }

            let continuing = Self.optInt(item["cxjc"]) ?? 1
            guard (1...30).contains(continuing), startNode <= 30 - continuing + 1 else { continue }
            let realEndNode = startNode + continuing - 1

            let skzc = (id["skzc"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if skzc.isEmpty { continue }

            // 解析 skzc 位图: '1' 的位置 = 上课的周
            let weekBits = Self.parseWeekBits(skzc)
            if weekBits.isEmpty { continue }

            let ranges = Self.weekBitsToRanges(weekBits)
            for r in ranges {
                result.append(JwCourse(
                    name: name,
                    room: fullRoom,
                    teacher: teacher,
                    day: day,
                    startNode: startNode,
                    endNode: realEndNode,
                    startWeek: r.0,
                    endWeek: r.1,
                    type: r.2))
            }
        }
        return result
    }

    // MARK: - 测试/判型辅助

    /// 从 HTML/JSON 源里抠顶层 JSON 数组 (供测试直接调用 ← extractJsonArrayForTest)。
    func extractJsonArrayForTest(_ source: String) -> String? {
        JwNewUrpSuperParser.extractJsonArray(source)
    }

    /// A timetable frame may be structurally valid while the selected term has no active weeks.
    /// (判型用: 源里存在 flat-array 形态即 true, 不要求位图有 1)
    func hasFlatArraySchema() -> Bool {
        JwNewUrpSuperParser.extractJsonArray(source) != nil
    }

    // MARK: - JSON 数组抽取

    static func extractJsonArray(_ source: String) -> String? {
        if let hit = scanArray(source) { return hit }
        // HTML attributes may contain unrelated quotes; scan script data alone.
        if source.range(of: "<script", options: .caseInsensitive) != nil {
            for script in scriptBodies(source) {
                if let hit = scanArray(script) { return hit }
            }
        }
        return nil
    }

    /// `<script ...>...</script>` 原始内容抽取 (等价 Jsoup select("script").data())。
    private static func scriptBodies(_ source: String) -> [String] {
        let re = try? NSRegularExpression(
            pattern: "<script[^>]*>([\\s\\S]*?)</script>", options: [.caseInsensitive])
        let ns = source as NSString
        var out: [String] = []
        for m in re?.matches(in: source, options: [], range: NSRange(location: 0, length: ns.length)) ?? [] {
            if m.range(at: 1).location != NSNotFound {
                out.append(ns.substring(with: m.range(at: 1)))
            }
        }
        return out
    }

    /// 平衡括号扫描候选数组。
    /// 从 skzc 往回找 '[' 会落进课名或嵌套数组的 '[' — 所以从前往后配对扫描,
    /// 真课表同时含 kcm/skzc/id 关键字; 关键字计数为 0 的括号段直接跳过。
    private static func scanArray(_ source: String) -> String? {
        guard source.contains("\"skzc\""), source.contains("\"kcm\"") else { return nil }
        let chars = Array(source)
        let n = chars.count
        // 前缀计数: kcm[i+1] = 前 i 个字符里关键字出现次数 (startsWith 语义, 允许跨引号)
        var kcmCount = [Int](repeating: 0, count: n + 1)
        var skzcCount = [Int](repeating: 0, count: n + 1)
        var idCount = [Int](repeating: 0, count: n + 1)
        func startsWith(_ word: [Character], at i: Int) -> Bool {
            guard i + word.count <= n else { return false }
            for (k, c) in word.enumerated() where chars[i + k] != c { return false }
            return true
        }
        let kcmW: [Character] = ["k", "c", "m"]
        let skzcW: [Character] = ["s", "k", "z", "c"]
        let idW: [Character] = ["i", "d"]
        for i in 0..<n {
            kcmCount[i + 1] = kcmCount[i] + (startsWith(kcmW, at: i) ? 1 : 0)
            skzcCount[i + 1] = skzcCount[i] + (startsWith(skzcW, at: i) ? 1 : 0)
            idCount[i + 1] = idCount[i] + (startsWith(idW, at: i) ? 1 : 0)
        }
        var starts: [Int] = []
        var parsedChars = 0
        var inString = false
        var escaped = false
        for end in 0..<n {
            let ch = chars[end]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            switch ch {
            case "\"":
                inString = true
            case "[":
                if starts.isEmpty { parsedChars = 0 }
                starts.append(end)
            case "]":
                if !starts.isEmpty {
                    let start = starts.removeLast()
                    // 括号段内不含任何目标关键字 → 不可能是课表, 跳过 (免 JSON 解析)
                    if kcmCount[end + 1] == kcmCount[start] || skzcCount[end + 1] == skzcCount[start]
                        || idCount[end + 1] == idCount[start] { continue }
                    let length = end - start + 1
                    // 合法大数组只解析一次; 嵌套候选受累计解析字节预算约束
                    if parsedChars + length > n * 3 { continue }
                    parsedChars += length
                    let candidate = String(chars[start...(end)])
                    guard let data = candidate.data(using: .utf8),
                          let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { continue }
                    let valid = array.contains { element in
                        guard let item = element as? [String: Any],
                              let idObj = item["id"] as? [String: Any] else { return false }
                        return item["kcm"] != nil && idObj["skzc"] != nil
                    }
                    if valid { return candidate }
                }
            default:
                break
            }
        }
        return nil
    }

    // MARK: - 位图解析

    /// '0'/'1' 串 → 上课周列表 (1-based); 非位图字符或长度 > 60 → 空。
    static func parseWeekBits(_ s: String) -> [Int] {
        if s.isEmpty || s.count > 60 { return [] }
        var out: [Int] = []
        var index = 0
        for c in s {
            index += 1
            if c == "1" { out.append(index) }
            else if c != "0" { return [] }
        }
        return out
    }

    /// 周次数组归并成 (start, end, type) 范围 (复制自 JwNewUrpParser 语义)。
    /// type: 0=每周 1=单周 2=双周
    static func weekBitsToRanges(_ weeks: [Int]) -> [(Int, Int, Int)] {
        if weeks.isEmpty { return [] }
        var result: [(Int, Int, Int)] = []
        var i = 0
        while i < weeks.count {
            let start = weeks[i]
            var end = start
            if i + 1 < weeks.count {
                let gap = weeks[i + 1] - start
                switch gap {
                case 1:
                    var k = i + 1
                    end = weeks[k]
                    while k + 1 < weeks.count && weeks[k + 1] - weeks[k] == 1 { k += 1; end = weeks[k] }
                    result.append((start, end, 0))
                    i = k + 1
                case 2:
                    var k = i + 1
                    end = weeks[k]
                    while k + 1 < weeks.count && weeks[k + 1] - weeks[k] == 2 { k += 1; end = weeks[k] }
                    let type = start % 2 != 0 ? 1 : 2
                    result.append((start, end, type))
                    i = k + 1
                default:
                    result.append((start, end, 0))
                    i += 1
                }
            } else {
                result.append((start, end, 0))
                i += 1
            }
        }
        return result
    }

    // MARK: - 置信度 (按锚点强度)

    var confidenceValue: Int {
        let hasSkzc = source.contains("\"skzc\"")
        let hasId = source.contains("\"id\"")
        let hasKcm = source.contains("\"kcm\"")
        if hasSkzc && hasId && hasKcm { return 100 }
        if hasSkzc && hasId { return 70 }
        if hasSkzc { return 30 }
        return 0
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("\"skzc\"") { out.append("skzc") }
        if source.contains("\"id\"") { out.append("id") }
        if source.contains("\"kcm\"") { out.append("kcm") }
        if source.contains("\"jxlm\"") { out.append("jxlm") }
        if source.contains("\"cxjc\"") { out.append("cxjc") }
        return out
    }

    /// org.json `optInt` 等价: Int 直取; 数字字符串 trim 后解析; 其余 nil。
    private static func optInt(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let d = v as? Double, d == d.rounded() { return Int(d) }
        return nil
    }
}
