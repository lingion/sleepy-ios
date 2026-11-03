// JwNwpuPostParser.swift — ← JwNwpuPostParser.kt
//
// 西北工业大学研究生教务系统 (NWPU Post-graduate) 课表解析器。
//
// 协议特点:
// 1. 一维清单式表格, 以 id="sample-table-1" 为主特征锚点;
// 2. thead/th 列头匹配: 院系、课程编号、课程名称、班级名称、主讲教师、学分、班级说明、上课时间;
// 3. 上课时间字段支持换行, 逐行提取: 教室 + (周次 + 星期 + 节次);
// 4. 周次提取: `第([0-9]+)-([0-9]+)周` 或 `第([0-9]+)周`, 包含单周/双周标识;
// 5. 星期拆分: `星期.+?(?=<|星期|$)`, 支持星期一至星期日映射;
// 6. 时段与节次偏移: 上(0), 中(4), 下(6), 晚(10) + 节次序号; 连续节次自动合并;
// 7. 本解析器只输出课程, 不推断校区作息时间或学期起始日期。
//
// 与 原版本 的实现差异(等价翻译):
//   a. Jsoup `br→TextNode("\n") + wholeText()` → SwiftSoup `html()` + `<br>` 正则
//      替换为换行 + 逐行 parse().text() (与 JwKingoZxParser 同款字符串层翻译)。
//   b. 正则一律 [0-9] 字符类 (PR #22 教训)。

import Foundation
import SwiftSoup

final class JwNwpuPostParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    /// 时段基准节次: 上(0) 中(4) 下(6) 晚(10)。
    private static let sectionBaseMap: [Character: Int] = ["上": 0, "中": 4, "下": 6, "晚": 10]
    private static let dayNames = ["星期一", "星期二", "星期三", "星期四", "星期五", "星期六", "星期日"]

    private static let reWeekRange = try! NSRegularExpression(pattern: "第([0-9]+)-([0-9]+)周")
    private static let reWeekSingle = try! NSRegularExpression(pattern: "第([0-9]+)周")
    private static let reDaySegment = try! NSRegularExpression(pattern: "星期.+?(?=<|星期|$)")
    private static let reNodeRange = try! NSRegularExpression(pattern: "([上中下晚])?([0-9]+)(?:-([0-9]+))?节?")

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        var score = 0
        if source.contains("id=\"sample-table-1\"") || source.contains("id='sample-table-1'") { score += 70 }
        if source.contains("上课时间") && source.contains("课程编号") { score += 20 }
        if source.contains("主讲教师") || source.contains("班级名称") { score += 10 }
        return min(score, 100)
    }

    var matchedFeatureList: [String] {
        var out: [String] = []
        if source.contains("sample-table-1") { out.append("id:sample-table-1") }
        if source.contains("上课时间") { out.append("col:上课时间") }
        if source.contains("主讲教师") { out.append("col:主讲教师") }
        return out
    }

    // MARK: - JwParser

    func generateCourseList() throws -> [JwCourse] {
        JwNwpuPostParser.parse(source)
    }

    // MARK: - 解析主体

    static func parse(_ html: String) -> [JwCourse] {
        guard let doc = try? SwiftSoup.parse(html) else { return [] }
        guard let table = (try? doc.select("#sample-table-1").first()) ?? nil else { return [] }

        let thHeaders = ((try? table.select("thead tr th")) ?? Elements()).array()
            .map { ((try? $0.text()) ?? "").trimmingCharacters(in: .whitespaces) }
        let trRows = (try? table.select("tbody tr")) ?? Elements()
        if trRows.isEmpty() { return [] }

        var courses: [JwCourse] = []

        for tr in trRows {
            let tds = (try? tr.select("td")) ?? Elements()
            if tds.isEmpty() { continue }

            var department = ""
            var courseCode = ""
            var courseName = ""
            var className = ""
            var teacher = ""
            var classNote = ""
            var timeRoomRaw = ""

            for (colIdx, td) in tds.array().enumerated() {
                // ← br→TextNode("\n") + wholeText(): 字符串层等价翻译, 避免换行被折叠
                let rawHtml = (try? td.html()) ?? ""
                let withBreaks = rawHtml.replacingOccurrences(
                    of: #"<br\s*/?\s*>"#, with: "\n", options: .regularExpression)
                let d = (try? SwiftSoup.parse(withBreaks)) ?? Document("")
                let tdText = ((try? d.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let thText = colIdx < thHeaders.count ? thHeaders[colIdx] : ""

                if thText.contains("院系") { department = tdText }
                else if thText.contains("课程编号") { courseCode = tdText }
                else if thText.contains("课程名称") { courseName = tdText }
                else if thText.contains("班级名称") { className = tdText }
                else if thText.contains("主讲教师") { teacher = tdText }
                else if thText.contains("学分") { _ = Float(tdText) }  // credit 仅解析不使用 (Sleepy 无学分字段)
                else if thText.contains("班级说明") { classNote = tdText }
                else if thText.contains("上课时间") { timeRoomRaw = tdText }
            }

            if courseName.isEmpty || timeRoomRaw.isEmpty { continue }

            let combinedName = className.isEmpty ? courseName : "\(courseName)(\(className))"
            let note = [department, courseCode, classNote].filter { !$0.isEmpty }.joined(separator: " ")
            _ = note  // ← Kotlin note 变量保留形态 (Sleepy 无 note 字段, 不落 JwCourse)

            // 每行一个时段地点
            let lines = timeRoomRaw
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for line in lines {
                let room: String
                if !line.hasPrefix("(") && line.contains("(") {
                    room = before(line, "(").replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
                } else if !line.contains("(") {
                    room = line.replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
                } else {
                    room = "无地点"
                }

                let timeContent: String
                if line.contains("(") && line.contains(")") {
                    timeContent = before(after(line, "("), ")")
                } else {
                    timeContent = line
                }

                // 周次
                let weekNs = timeContent as NSString
                var startWeek = 0
                var endWeek = 0
                if let m = reWeekRange.firstMatch(in: timeContent, options: [], range: NSRange(location: 0, length: weekNs.length)) {
                    guard let s = Int(weekNs.substring(with: m.range(at: 1))),
                          let e = Int(weekNs.substring(with: m.range(at: 2))) else { continue }
                    startWeek = s
                    endWeek = e
                } else if let m = reWeekSingle.firstMatch(in: timeContent, options: [], range: NSRange(location: 0, length: weekNs.length)) {
                    guard let s = Int(weekNs.substring(with: m.range(at: 1))) else { continue }
                    startWeek = s
                    endWeek = s
                } else {
                    continue
                }
                guard (1...60).contains(startWeek), (startWeek...60).contains(endWeek) else { continue }

                let weekType: Int
                if startWeek == endWeek {
                    weekType = 0
                } else if timeContent.contains("单周") {
                    weekType = 1
                } else if timeContent.contains("双周") {
                    weekType = 2
                } else {
                    weekType = 0
                }

                // 星期分段: 星期.+?(?=<|星期|$) — 文本里 < 不会出现, 段界即下一个 星期 或串尾
                var daySegments: [String] = []
                let dayNs = timeContent as NSString
                for m in reDaySegment.matches(in: timeContent, options: [], range: NSRange(location: 0, length: dayNs.length)) {
                    daySegments.append(dayNs.substring(with: m.range))
                }
                if daySegments.isEmpty && timeContent.contains("星期") {
                    daySegments.append(timeContent)
                }

                for daySeg in daySegments {
                    let dayStr = String(daySeg.prefix(3))
                    guard let dayIdx = dayNames.firstIndex(of: dayStr) else { continue }
                    let day = dayIdx + 1

                    // 节次(含范围): [上中下晚](N)(-M)?节? — 只取 "第" 之前的时段文本,
                    // 周次数字不会混进节次 (week digits never become nodes)。
                    let nodeSource = before(daySeg, "第")
                    let nodeNs = nodeSource as NSString
                    var nodes: [Int] = []
                    for m in reNodeRange.matches(in: nodeSource, options: [], range: NSRange(location: 0, length: nodeNs.length)) {
                        let sectionChar = m.range(at: 1).location != NSNotFound
                            ? nodeNs.substring(with: m.range(at: 1)) : nil
                        guard let startNum = Int(nodeNs.substring(with: m.range(at: 2))) else { continue }
                        let endNum = m.range(at: 3).location != NSNotFound
                            ? (Int(nodeNs.substring(with: m.range(at: 3))) ?? startNum) : startNum
                        let base = sectionChar.flatMap { sectionBaseMap[$0.first] } ?? 0
                        guard (1...13).contains(startNum), (startNum...13).contains(endNum),
                              base + endNum <= 13 else { continue }
                        for n in startNum...endNum {
                            nodes.append(base + n)
                        }
                    }
                    if nodes.isEmpty { continue }

                    let orderedNodes = Array(Set(nodes)).sorted()

                    // 连续节次聚类合并
                    var curStart = orderedNodes[0]
                    var curEnd = orderedNodes[0]
                    func emit() {
                        courses.append(JwCourse(
                            name: combinedName, room: room, teacher: teacher,
                            day: day, startNode: curStart, endNode: curEnd,
                            startWeek: startWeek, endWeek: endWeek, type: weekType))
                    }
                    for i in 1..<orderedNodes.count {
                        if orderedNodes[i] == curEnd + 1 {
                            curEnd = orderedNodes[i]
                        } else {
                            emit()
                            curStart = orderedNodes[i]
                            curEnd = orderedNodes[i]
                        }
                    }
                    emit()
                }
            }
        }

        return courses
    }

    // MARK: - Kotlin substring 语义

    private static func before(_ s: String, _ delim: String) -> String {
        guard let r = s.range(of: delim) else { return s }
        return String(s[s.startIndex..<r.lowerBound])
    }

    private static func after(_ s: String, _ delim: String) -> String {
        guard let r = s.range(of: delim) else { return s }
        return String(s[r.upperBound...])
    }
}
