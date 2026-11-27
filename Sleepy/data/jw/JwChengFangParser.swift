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
import SwiftSoup

final class JwChengFangParser: JwParser, JwParserConfidenceReporting {

    let source: String

    private lazy var courseData = Self.courseLiteral(source)

    init(_ source: String) {
        self.source = source
    }

    func generateCourseList() throws -> [JwCourse] {
        var result: [JwCourse] = []
        guard let arr = courseData?.value as? [Any] else { return result }

        for case let o as [String: Any] in arr {
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

    static func extractKbxxJsonForTest(_ html: String) -> String? { courseLiteral(html)?.json }

    private static func courseLiteral(_ source: String) -> JwStaticJSON.Literal? {
        let keys = ["kcmc", "xq", "jcdm2", "zcs"]
        let populated = keys.allSatisfy { source.contains($0) } ? JwStaticJSON.find(source) { literal in
            guard let array = literal.value as? [Any] else { return false }
            return array.contains { value in
                guard let row = value as? [String: Any] else { return false }
                return keys.allSatisfy { row[$0] != nil }
            }
        } : nil
        if let populated = populated { return populated }
        // Anonymous empty arrays do not establish a protocol; only the known empty-term field does.
        guard source.contains("kbxx") else { return nil }
        return JwStaticJSON.find(source) { literal in
            literal.binding?.split(separator: ".").last == "kbxx" && (literal.value as? [Any])?.isEmpty == true
        }
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

    var confidenceValue: Int {
        guard let rows = courseData?.value as? [Any] else { return 0 }
        return rows.isEmpty ? 70 : 100
    }

    var matchedFeatureList: [String] { courseData == nil ? [] : ["cf-course-schema"] }
}

/// Static JSON in script elements. No scripts are evaluated, and no variable name is
/// required for data that matches a known schema. Bounds match the released Android scanner.
enum JwStaticJSON {
    struct Literal {
        let json: String
        let value: Any
        let binding: String?
    }

    static func find(_ source: String, accepts: (Literal) -> Bool) -> Literal? {
        guard source.utf8.count <= 8 * 1024 * 1024 else { return nil }
        let scripts: [String]
        if source.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            guard let doc = try? SwiftSoup.parse(source), let elements = try? doc.select("script") else { return nil }
            scripts = elements.array().map { $0.data() }
        } else {
            scripts = [source]
        }
        let assignment = try? NSRegularExpression(pattern: #"([\w$]+(?:\.[\w$]+)*)\s*=\s*$"#)
        for script in scripts {
            let bytes = Array(script.utf8)
            var budget = bytes.count * 3
            for range in ranges(bytes).sorted(by: { $0.lowerBound < $1.lowerBound }) {
                guard range.count <= budget else { continue }
                budget -= range.count
                let data = Data(bytes[range])
                guard let value = try? JSONSerialization.jsonObject(with: data) else { continue }
                let tail = String(decoding: bytes[max(0, range.lowerBound - 256)..<range.lowerBound], as: UTF8.self)
                let binding = assignment?.firstMatch(in: tail, range: NSRange(tail.startIndex..., in: tail))
                    .flatMap { Range($0.range(at: 1), in: tail).map { String(tail[$0]) } }
                let literal = Literal(json: String(decoding: data, as: UTF8.self), value: value, binding: binding)
                if accepts(literal) { return literal }
            }
        }
        return nil
    }

    private static func ranges(_ bytes: [UInt8]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var pending: [Range<Int>] = []
        var stack: [(offset: Int, token: UInt8)] = []
        var depth = 0
        var quote: UInt8?
        var escaped = false
        var lineComment = false
        var blockComment = false
        var invalidGroup = false
        var i = 0
        while i < bytes.count {
            let token = bytes[i]
            let next = i + 1 < bytes.count ? bytes[i + 1] : 0
            defer { i += 1 }
            if lineComment {
                if token == 10 || token == 13 { lineComment = false }
            } else if blockComment {
                if token == 42 && next == 47 { blockComment = false; i += 1 }
            } else if let activeQuote = quote {
                if escaped { escaped = false }
                else if token == 92 { escaped = true }
                else if token == activeQuote { quote = nil }
            } else if token == 47 && next == 47 {
                lineComment = true
                i += 1
            } else if token == 47 && next == 42 {
                blockComment = true
                i += 1
            } else if token == 34 || token == 39 || token == 96 {
                quote = token
            } else if token == 91 || token == 123 {
                depth += 1
                if depth <= 64 { stack.append((i, token)) }
                else { invalidGroup = true }
            } else if (token == 93 || token == 125) && depth > 0 {
                if depth <= 64, let open = stack.popLast() {
                    if (open.token == 91) != (token == 93) { invalidGroup = true }
                    if !invalidGroup { pending.append(open.offset..<(i + 1)) }
                }
                depth -= 1
                if depth == 0 {
                    if !invalidGroup { result.append(contentsOf: pending) }
                    pending.removeAll(keepingCapacity: true)
                    invalidGroup = false
                }
            }
        }
        return result
    }
}
