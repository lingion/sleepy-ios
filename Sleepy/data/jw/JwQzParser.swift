// JwQzParser.swift — ← JwQzParser.kt
// 强智教务系统解析器(基础版)。
//
// 基于 dIT8Zv/WakeupSchedule_BUPT (Apache-2.0) QzParser.kt
// 简化而来(去掉了 CourseBaseBean/CourseDetailBean 转换层)。
//
// 源仓库:https://github.com/dIT8Zv/WakeupSchedule_BUPT/blob/master/app/src/main/java/com/suda/yzune/wakeupschedule/schedule_import/parser/qz/QzParser.kt
//
// 抓取对象:教务系统课表页的 `id="kbtable"` 节点,
// 遍历 tr/td/div[class="tableName"],用 `title="老师"` / `title="教室"` /
// `title="周次(节次)"` 三个属性提数据。同格内多门课用 "-----" 分隔。
//
// 子类(如 JwQzCrazyParser)可重写 tableName 适配不同变体。
// (SwiftSoup = Jsoup API 1:1,方法名同形)

import Foundation
import SwiftSoup

class JwQzParser: JwParser, JwParserConfidenceReporting {

    let source: String

    init(_ source: String) {
        self.source = source
    }

    /// 课表单元格内 class 名(多数强智学校为 "kbcontent",部分 crazy 变体为 "kbcontent1")
    /// ← open val tableName = "kbcontent";子类 override
    var tableName: String { "kbcontent" }

    func parseCourseName(_ infoStr: String) -> String {
        // 兜底:Jsoup 解析在某些裸 HTML 上可能失败,直接取子串
        // ← substringBefore("<font") = 首个 "<font" 前的部分;无则原串
        let before = infoStr.components(separatedBy: "<font").first ?? infoStr
        let trimmed = before.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try SwiftSoup.parse(trimmed).text()
        } catch {
            return trimmed
        }
    }

    func convert(day: Int, nodeCount: Int, infoStr: String, courseList: inout [JwCourse]) {
        let node = nodeCount * 2 - 1
        let courseHtml = try! SwiftSoup.parse(infoStr)  // Jsoup.parse 不抛,Kotlin 侧同
        let courseName = parseCourseName(infoStr)
        let teacher = ((try? courseHtml.getElementsByAttributeValue("title", "老师").text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // T2 修复：上游 wakeup QzParser.kt 只认 "老师"，但 JSNU/UPC/CSUFT 等学校
        // 使用 "教师" 属性名（fixture: edge_teacher_attr.html 已锁现状）。fallback
        // 顺序：老师 → 教师。仅当两者都空才返回空串，不修改 SwiftSoup 大小写行为。
        let teacherFinal = teacher.isEmpty
            ? ((try? courseHtml.getElementsByAttributeValue("title", "教师").text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            : teacher
        let room = ((try? courseHtml.getElementsByAttributeValue("title", "教室").text()) ?? "") +
            ((try? courseHtml.getElementsByAttributeValue("title", "分组").text()) ?? "")
        let weekRaw = (try? courseHtml.getElementsByAttributeValue("title", "周次(节次)").text()) ?? ""
        // ← substringBefore("(周)")
        let weekStr = weekRaw.components(separatedBy: "(周)").first ?? weekRaw
        let weekList = weekStr.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        var startWeek = 0
        var endWeek = 0
        var type = 0

        for weekItem in weekList {
            if weekItem.contains("-") {
                let weeks = weekItem.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                if !weeks.isEmpty { startWeek = Int(weeks[0].trimmingCharacters(in: .whitespaces)) ?? 1 }
                if weeks.count > 1 {
                    type = {
                        if weeks[1].contains("单") { return 1 }
                        if weeks[1].contains("双") { return 2 }
                        return 0
                    }()
                    // 兼容 "1-16周"、"1-16周(单)"、"1-16(单)"、"1-16" 等格式
                    endWeek = Int(weeks[1]
                        .replacingOccurrences(of: "周", with: "")
                        .replacingOccurrences(of: "(", with: "")
                        .replacingOccurrences(of: ")", with: "")
                        .replacingOccurrences(of: "单", with: "")
                        .replacingOccurrences(of: "双", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .filter { $0.isNumber }) ?? startWeek
                }
            } else {
                type = {
                    if weekItem.contains("单") { return 1 }
                    if weekItem.contains("双") { return 2 }
                    return 0
                }()
                let cleaned = weekItem.replacingOccurrences(of: "周", with: "")
                    .replacingOccurrences(of: "单", with: "")
                    .replacingOccurrences(of: "双", with: "")
                    .components(separatedBy: "(").first ?? ""
                let v = Int(cleaned.trimmingCharacters(in: .whitespaces).filter { $0.isNumber }) ?? 1
                startWeek = v
                endWeek = v
            }
            courseList.append(
                JwCourse(
                    name: courseName,
                    room: room,
                    teacher: teacherFinal,
                    day: day,
                    startNode: node,
                    endNode: node + 1,
                    startWeek: startWeek,
                    endWeek: endWeek,
                    type: type
                )
            )
        }
    }

    func generateCourseList() throws -> [JwCourse] {
        var courseList: [JwCourse] = []
        guard let doc = try? SwiftSoup.parse(source) else { return courseList }
        // v1.0.62: 新强智版式 (NNNU) 用显式分节 + 精细 #timetable 视图;
        // 无 #kbtable 但有 table#timetable .kbcontent 时委托 JwQzTimetableParser。
        if ((try? doc.getElementById("kbtable")) ?? nil) == nil,
           ((try? doc.select("table#timetable .kbcontent").first()) ?? nil) != nil {
            return try JwQzTimetableParser(source).generateCourseList()
        }
        // T8: 找不到 #kbtable 抛 JwParseError(NO_TABLE_CONTAINER_MARKER)
        //   而不是静默 return courseList. 让 T9 区分"协议选错"和"课表页为空".
        guard let kbTable = (try? doc.getElementById("kbtable")) ?? nil else {
            throw JwParseError(
                message: "页面缺少 #kbtable，可能未到达课表页/选错教务类型",
                attempts: [ParserAttemptSnapshot(
                    parserName: "JwQzParser",
                    type: JwProtocol.TYPE_QZ,
                    courseCount: 0,
                    confidence: (self as? JwParserConfidenceReporting)?.confidenceValue ?? 0,
                    matchedFeatures: (self as? JwParserConfidenceReporting)?.matchedFeatureList ?? [],
                    exception: JwParseError.NO_TABLE_CONTAINER_MARKER)])
        }
        let trs = (try? kbTable.getElementsByTag("tr")) ?? Elements()

        var nodeCount = 0
        for tr in trs {
            let tds = (try? tr.getElementsByTag("td")) ?? Elements()
            if tds.isEmpty() {
                continue
            }
            nodeCount += 1

            var day = 0
            for td in tds {
                day += 1
                let divs = (try? td.getElementsByTag("div")) ?? Elements()
                for div in divs {
                    let courseElements = (try? div.getElementsByClass(tableName)) ?? Elements()
                    let text = (try? courseElements.text()) ?? ""
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                    let courseHtml = (try? courseElements.html()) ?? ""
                    var startIndex = courseHtml.startIndex
                    var splitIndex = courseHtml.range(of: "-----")?.lowerBound
                    while let si = splitIndex {
                        let sub = String(courseHtml[startIndex..<si])
                        convert(day: day, nodeCount: nodeCount, infoStr: sub, courseList: &courseList)
                        // ← startIndex = courseHtml.indexOf("<br>", splitIndex) + 4
                        if let brRange = courseHtml.range(of: "<br>", range: si..<courseHtml.endIndex) {
                            startIndex = courseHtml.index(after: brRange.upperBound)  // "<br>" 长 4
                        } else {
                            startIndex = courseHtml.endIndex
                        }
                        splitIndex = courseHtml.range(of: "-----", range: startIndex..<courseHtml.endIndex)?.lowerBound
                    }
                    convert(
                        day: day,
                        nodeCount: nodeCount,
                        infoStr: String(courseHtml[startIndex..<courseHtml.endIndex]),
                        courseList: &courseList
                    )
                }
            }
        }
        return courseList
    }

    // MARK: - T8 置信度

    /// 命中 #kbtable 与 font[title=老师/教室/周次(节次)] 三件套 = 100；
    /// 仅命中 kbtable+kbcontent = 70；仅命中 kbtable = 30。
    var confidenceValue: Int {
        guard let doc = try? SwiftSoup.parse(source) else { return 0 }
        guard let kbtable = (try? doc.getElementById("kbtable")) ?? nil else { return 0 }
        // v1.0.62: #timetable 视图 (新强智) — 周次(节次) 列锚点即满分。
        if ((try? doc.select("table#timetable .kbcontent [title='周次(节次)']").first()) ?? nil) != nil {
            return 100
        }
        let fontCount = ((try? doc.getElementsByAttributeValue("title", "老师").size()) ?? 0)
            + ((try? doc.getElementsByAttributeValue("title", "教师").size()) ?? 0)
            + ((try? doc.getElementsByAttributeValue("title", "教室").size()) ?? 0)
            + ((try? doc.getElementsByAttributeValue("title", "周次(节次)").size()) ?? 0)
        if fontCount >= 3 { return 100 }
        if ((try? kbtable.getElementsByClass(tableName)) ?? Elements()).isEmpty() == false { return 70 }
        return 30
    }

    var matchedFeatureList: [String] {
        guard let doc = try? SwiftSoup.parse(source) else { return [] }
        var out: [String] = []
        if ((try? doc.getElementById("kbtable")) ?? nil) != nil { out.append("id=kbtable") }
        if ((try? doc.getElementsByClass(tableName)) ?? Elements()).isEmpty() == false { out.append("class=\(tableName)") }
        if ((try? doc.getElementsByAttributeValue("title", "老师")) ?? Elements()).isEmpty() == false { out.append("title=老师") }
        if ((try? doc.getElementsByAttributeValue("title", "教师")) ?? Elements()).isEmpty() == false { out.append("title=教师") }
        if ((try? doc.getElementsByAttributeValue("title", "教室")) ?? Elements()).isEmpty() == false { out.append("title=教室") }
        if ((try? doc.getElementsByAttributeValue("title", "周次(节次)")) ?? Elements()).isEmpty() == false { out.append("title=周次(节次)") }
        if ((try? doc.select("table#timetable .kbcontent").first()) ?? nil) != nil { out.append("id=timetable") }
        return out
    }
}
