// JwNuitParser.swift — ← JwNuitParser.kt
//
// 南开大学 Wisedu 课表对象解析器。
//
// 协议: JwProtocol.TYPE_NUIT = "nuit"
//
// 数据来源: Wisedu JSON { "datas": [...] } 每行 classDateAndPlace 形如:
//   "1-3周,5,7 / 星期二 / 第3-4节 / 张老师[主讲] / 教室名"
//
// 关键语义: classDateAndPlace 中 Week 部分用「周」描述(不含「星期」),
//   单双周用 "(单)" / "(双)" 标记。

import Foundation

final class JwNuitParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    // MARK: - T8

    func generateCourseList() throws -> [JwCourse] {
        // 对齐 Android `Json { ignoreUnknownKeys = true; isLenient = true }`: 宽松解析 +
        // 标量/非对象 root 落到空列表; rows 逐元素判类型, 非对象行跳过(不整表作废)。
        guard let root = jsonObj(jwParseJSONLenient(source)),
              let rows = jsonArr(root["datas"]) else {
            return []
        }

        let dayMap = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7]
        let regex = try! NSRegularExpression(
            pattern: "^(.+?)\\s*/\\s*星期([一二三四五六日])\\s*/\\s*第(\\d+)节-第(\\d+)节\\s*/\\s*(.+?)\\[主讲\\]\\s*/\\s*(.+)$",
            options: []
        )
        var out: [JwCourse] = []
        for element in rows {
            guard let obj = jsonObj(element) else { continue }
            let name = jstr(obj, "courseName")
            let details = jstr(obj, "classDateAndPlace")
            if name.isEmpty || details.isEmpty { continue }

            // Android details.split('，', ','): 全角与半角逗号都是分隔符
            let parts = details.components(separatedBy: CharacterSet(charactersIn: "，,"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .flatMap { detail -> [JwCourse] in
                    let range = NSRange(detail.startIndex..., in: detail)
                    // Android matchEntire: 必须整段匹配, 前后缀垃圾直接丢弃
                    guard let m = regex.firstMatch(in: detail, options: [.anchored], range: range),
                          m.range == range else { return [] }
                    let ns = detail as NSString
                    let weekPart = ns.substring(with: m.range(at: 1))
                    guard let dayChar = ns.substring(with: m.range(at: 2)).first,
                          let day = dayMap[String(dayChar)] else { return [] }
                    // Android toIntOrNull() ?: return emptyList(): 起始节数解析失败整条丢弃
                    guard let start = Int(ns.substring(with: m.range(at: 3))) else { return [] }
                    let end = Int(ns.substring(with: m.range(at: 4))) ?? start
                    let teacher = ns.substring(with: m.range(at: 5)).trimmingCharacters(in: .whitespaces)
                    let room = ns.substring(with: m.range(at: 6)).trimmingCharacters(in: .whitespaces)

                    let weeks = parseWeeks(weekPart)
                    return weeks.map { week in
                        JwCourse(name: name, room: room, teacher: teacher,
                            day: day, startNode: start, endNode: end,
                            startWeek: week, endWeek: week)
                    }
                }
            out.append(contentsOf: parts)
        }
        return out
    }

    private func parseWeeks(_ text: String) -> [Int] {
        let cleaned = text
            .replacingOccurrences(of: "\\[[^]]*]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "周", with: "")
            .replacingOccurrences(of: " ", with: "")

        return cleaned
            .components(separatedBy: CharacterSet(charactersIn: ",，"))
            .flatMap { segment -> [Int] in
                let odd = segment.contains("(单)")
                let even = segment.contains("(双)")
                let clean = segment.replacingOccurrences(of: "(单)", with: "")
                    .replacingOccurrences(of: "(双)", with: "")

                // Android clean.split('-', limit = 2).mapNotNull { it.toIntOrNull() }:
                // 只在第一个 '-' 处切两段, 每侧整段必须是纯 Int
                // ("1-3-5" -> ["1","3-5"] -> [1] -> 1..1; "第1-3" -> ["第1","3"] -> 3..3),
                // 倒挂区间(5..1)在 Kotlin 为空 IntRange → 不产出周次, 不交换。
                var sides: [String]
                if let dash = clean.firstIndex(of: "-") {
                    sides = [String(clean[clean.startIndex..<dash]),
                             String(clean[clean.index(after: dash)...])]
                } else {
                    sides = [clean]
                }
                let bounds = sides.compactMap { Int($0) }
                let range: ClosedRange<Int>?
                switch bounds.count {
                case 2: range = bounds[0]...bounds[1]
                case 1: range = bounds[0]...bounds[0]
                default: range = nil
                }
                guard let r = range, r.lowerBound <= r.upperBound else { return [] }
                return r.filter { (!odd || $0 % 2 == 1) && (!even || $0 % 2 == 0) }
            }
    }

    // MARK: - T9

    var confidenceValue: Int {
        // Android: datas 只要是 JsonArray 且 source 含 "classDateAndPlace" 即 90,
        // 不要求元素是对象({"datas":["x"]} 也得分)。
        guard let root = jsonObj(jwParseJSONLenient(source)),
              root["datas"] is [Any],
              source.contains("classDateAndPlace") else { return 0 }
        return 90
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("student/courses.do") { out.append("student/courses.do") }
        if source.contains("classDateAndPlace") { out.append("classDateAndPlace") }
        if source.contains("courseName") { out.append("courseName") }
        return out
    }
}
