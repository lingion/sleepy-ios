// JwChengFangParser.swift — ← JwChengFangParser.kt
//
// 青果/乘方教务（CF）解析器 — T3。
//
// 协议：JwProtocol.TYPE_CF = "cf"
// 上游：dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) ChengFangParser.kt
//
// 页面结构：HTML 内嵌 `var kbxx = [{kcmc,teaxms,jxcdmcs,xq,jcdm2,zcs},...]`（通常跨多行 script）。
// 字段语义（全 String）：
//   kcmc=课名  teaxms=教师（整体保留不拆分）  jxcdmcs=教室
//   xq=星期(1-7 数字串)  jcdm2=节次代码("1,2"/"05,06"/"11")  zcs=周次("1,3,5")
//
// 对上游的有意偏离（fixture 实证）：
//   ① substringBefore(';') → 括号配对提取（教室值内含分号/转义引号时不截断）
//   ② zcs toInt() → toIntOrNull()（空周次跳过该条而非 NumberFormatException）

import Foundation

final class JwChengFangParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        var result: [JwCourse] = []
        guard let json = Self.extractKbxxJson(source) else { return result }
        guard let data = json.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return result }

        for o in arr {
            func str(_ k: String) -> String {
                ((o[k] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let name = str("kcmc")
            if name.isEmpty { continue }
            let teacher = str("teaxms")
            let room = str("jxcdmcs")
            guard let day = jw1064Integer(str("xq")), (1...7).contains(day) else { continue }
            let nodeValues = str("jcdm2").components(separatedBy: ",").map { jw1064Integer($0.trimmingCharacters(in: .whitespaces)) }
            guard !nodeValues.isEmpty, nodeValues.allSatisfy({ ($0 ?? 0) > 0 }) else { continue }
            let nodes = Set(nodeValues.compactMap { $0 }).sorted()
            var blocks: [(Int, Int)] = []
            for node in nodes {
                if let previous = blocks.last, node == previous.1 + 1 {
                    blocks[blocks.count - 1] = (previous.0, node)
                } else { blocks.append((node, node)) }
            }
            let weekValues = str("zcs").components(separatedBy: ",").map { jw1064Integer($0.trimmingCharacters(in: .whitespaces)) }
            guard !weekValues.isEmpty, weekValues.allSatisfy({ ($0 ?? 0) > 0 }) else { continue }
            for (first, last) in blocks {
                for wb in Self.weekIntList2WeekBeanList(weekValues.compactMap { $0 }) {
                    result.append(JwCourse(name: name, room: room, teacher: teacher, day: day,
                                           startNode: first, endNode: last,
                                           startWeek: wb.0, endWeek: wb.1, type: wb.2))
                }
            }
        }
        return result
    }

    // MARK: - companion ← static

    /// 从 HTML 里抠 `var kbxx = [...]`（测试入口）。
    static func extractKbxxJsonForTest(_ html: String) -> String? {
        extractKbxxJson(html)
    }

    /// 字符串感知的括号配对，找不到标记 / 找不到 '[' / 括号不平衡 → nil。
    private static func extractKbxxJson(_ html: String) -> String? {
        let marker = "var kbxx"
        guard let idx = html.range(of: marker)?.upperBound else { return nil }
        let chars = Array(html)
        var arrStart = chars.startIndex
        let startOffset = html.distance(from: html.startIndex, to: idx)
        var offset = startOffset
        while offset < chars.count && chars[offset] != "[" { offset += 1 }
        if offset >= chars.count { return nil }
        arrStart = offset

        var depth = 0
        var inStr = false
        var esc = false
        var i = arrStart
        while i < chars.count {
            let c = chars[i]
            if esc { esc = false; i += 1; continue }
            if c == "\\" { esc = true; i += 1; continue }
            if c == "\"" { inStr.toggle(); i += 1; continue }
            if inStr { i += 1; continue }
            if c == "[" { depth += 1 }
            if c == "]" {
                depth -= 1
                if depth == 0 {
                    return String(chars[arrStart...(i)])
                }
            }
            i += 1
        }
        return nil
    }

    static func weekIntList2WeekBeanList(_ input: [Int]) -> [(Int, Int, Int)] {
        if input.isEmpty { return [] }
        let a = Array(Set(input)).sorted()
        var reset = 0
        var start = 0, end = 0, type = -1
        var list: [(Int, Int, Int)] = []
        func flush() { list.append((start, end, type)); type = -1; reset = 0 }
        for i in a.indices {
            if reset == 1 { flush() }
            if i < a.count - 1 {
                let gap = a[i + 1] - a[i]
                if type == -1 {
                    start = a[i]
                    switch gap {
                    case 1: type = 0; end = a[i + 1]
                    case 2: type = a[i] % 2 != 0 ? 1 : 2; end = a[i + 1]
                    default: end = a[i]; type = 0; reset = 1
                    }
                } else {
                    switch true {
                    case type == 0 && gap == 1: end = a[i + 1]
                    case (type == 1 || type == 2) && gap == 2: end = a[i + 1]
                    default: reset = 1
                    }
                }
            }
            if i == a.count - 1 {
                if type == -1 { start = a[i]; end = a[i]; type = 0 }
                list.append((start, end, type))
            }
        }
        return list
    }

    /// T8: var kbxx + CF 字段四件套 = 100; 仅 var kbxx = 70
    var confidenceValue: Int {
        if !source.contains("var kbxx") { return 0 }
        let hasFields = source.contains("kcmc") && (source.contains("teaxms") ||
            source.contains("jxcdmcs") || source.contains("jcdm2"))
        return hasFields ? 100 : 70
    }

    var matchedFeatureList: [String] {
        if !source.contains("var kbxx") { return [] }
        var out: [String] = ["var kbxx"]
        if source.contains("kcmc") { out.append("字段=kcmc") }
        if source.contains("teaxms") { out.append("字段=teaxms") }
        if source.contains("jxcdmcs") { out.append("字段=jxcdmcs") }
        if source.contains("jcdm2") { out.append("字段=jcdm2") }
        return out
    }
}
