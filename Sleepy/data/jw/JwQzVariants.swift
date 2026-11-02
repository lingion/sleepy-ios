// JwQzBrParser.swift / JwQzWithNodeParser.swift / JwOldQzParser.swift
// — ← JwQzBrParser.kt / JwQzWithNodeParser.kt / JwOldQzParser.kt
//
// 强智 qz 三个变体解析器(QzBr / QzWithNode 同 QzParser 骨架; OldQz 完全独立)。
// 逐文件注释见对应 Kotlin 原文。

import Foundation
import SwiftSoup

/// ← Kotlin `String.substringAfter(delimiter)`：分隔符缺失时返回**整串**
/// （Swift `components(separatedBy:).dropFirst().joined()` 缺分隔符时会返回 ""，
/// 直接照搬会让节次 "3-4节" 这种裸形态解析成 1-1，必须显式复刻 Kotlin 语义）
private func qzSubstringAfter(_ s: String, _ delimiter: String) -> String {
    guard let r = s.range(of: delimiter) else { return s }
    return String(s[r.upperBound...])
}

/// ← Kotlin `String.removeSurrounding(prefix, suffix)`：
/// 仅当同时以 prefix 开头、以 suffix 结尾时才剥掉两端（缺任一返回原串）。
/// 与 `trimmingCharacters(in: CharacterSet("[]"))` 语义不同：后者会剥掉
/// 任意多个两端字符，包括不成对的 "[1-2节"。
private func qzRemoveSurrounding(_ s: String, _ prefix: String, _ suffix: String) -> String {
    guard s.count >= prefix.count + suffix.count, s.hasPrefix(prefix), s.hasSuffix(suffix) else { return s }
    return String(s.dropFirst(prefix.count).dropLast(suffix.count))
}

/// SwiftSoup(= Jsoup 的 iOS 移植)在 html() 序列化时把空元素写成 `<br />`/`<br/>`
/// (Element.outerHtmlHead 的 `accum.append(" />")` 分支), 而 Android 端 Jsoup 输出
/// `<br>`。qz 家族所有字面量 `"<br>"` 探针(substringBefore("<br>") 课名截断、
/// 基类循环 '-----' 分隔后的 <br> 步进、qz_old 的行切分)作用在**序列化输出**上,
/// SwiftSoup 下全部落空: 课名带原始标签整段污染、同格多课第二条起整条丢失。
/// 消费序列化 HTML 前把两种形态归一成 `<br>`, 恢复与 Android 的字节级语义一致。
private func qzNormalizeBrTags(_ html: String) -> String {
    html.replacingOccurrences(of: "<br />", with: "<br>")
        .replacingOccurrences(of: "<br/>", with: "<br>")
}

/// 复刻 JwQzParser.generateCourseList 的单元格遍历, 唯一差异是 courseHtml 先经
/// `qzNormalizeBrTags` 归一。基类循环在本文件之外(不在本次可改范围), qz_br /
/// qz_with_node 覆写 generateCourseList 走此通路; 缺 #kbtable 的 JwParseError
/// 快照字段与基类逐字一致(parserName 固定 "JwQzParser" —— Android 继承基类抛出
/// 的同源行为; confidence/matchedFeatures 动态取子类覆写值)。
private func qzCourseList(from parser: JwQzParser) throws -> [JwCourse] {
    var courseList: [JwCourse] = []
    guard let doc = try? SwiftSoup.parse(parser.source) else { return courseList }
    guard let kbTable = (try? doc.getElementById("kbtable")) ?? nil else {
        throw JwParseError(
            message: "页面缺少 #kbtable，可能未到达课表页/选错教务类型",
            attempts: [ParserAttemptSnapshot(
                parserName: "JwQzParser",
                type: JwProtocol.TYPE_QZ,
                courseCount: 0,
                confidence: (parser as? JwParserConfidenceReporting)?.confidenceValue ?? 0,
                matchedFeatures: (parser as? JwParserConfidenceReporting)?.matchedFeatureList ?? [],
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
                let courseElements = (try? div.getElementsByClass(parser.tableName)) ?? Elements()
                let text = (try? courseElements.text()) ?? ""
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let courseHtml = qzNormalizeBrTags((try? courseElements.html()) ?? "")
                var startIndex = courseHtml.startIndex
                var splitIndex = courseHtml.range(of: "-----")?.lowerBound
                while let si = splitIndex {
                    let sub = String(courseHtml[startIndex..<si])
                    parser.convert(day: day, nodeCount: nodeCount, infoStr: sub, courseList: &courseList)
                    // ← startIndex = courseHtml.indexOf("<br>", splitIndex) + 4
                    // (upperBound 即 '>' 后一位 = Kotlin +4; 基类 index(after:) 多跳一字符,
                    // 此处按 Android 语义取 upperBound, 差异仅一个前导空白, 消费点均 trim)
                    if let brRange = courseHtml.range(of: "<br>", range: si..<courseHtml.endIndex) {
                        startIndex = brRange.upperBound  // "<br>" 长 4
                    } else {
                        startIndex = courseHtml.endIndex
                    }
                    splitIndex = courseHtml.range(of: "-----", range: startIndex..<courseHtml.endIndex)?.lowerBound
                }
                parser.convert(
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

/// 强智 qz_br 变体解析器。
///
/// 与 JwQzParser 的唯一差异：单元格内课名行后跟 `<br>` 而非 `<font>`，
/// 因此课名提取必须用 `substringBefore("<br>")` 而非 `substringBefore("<font")`。
///
/// 样本学校（上游 WakeupSchedule_BUPT SchoolListActivity.kt 实证）：
///   - 北京林业大学 newjwxt.bjfu.edu.cn
///   - 长春大学 cdjwc.ccu.edu.cn/jsxsd
///   - 长沙理工 xk.csust.edu.cn
///   - 广东金融 jwxt.gduf.edu.cn
///   - 江西农大南昌商学院 223.83.249.67:8080/jsxsd
///
/// 上游源码：dIT8Zv/WakeupSchedule_BUPT QzBrParser.kt (Apache-2.0)
final class JwQzBrParser: JwQzParser {

    /// 课名提取：用课名后第一个 `<br>` 截断，不再走 `<font` 路径。
    /// 上游原始实现见 QzBrParser.parseCourseName。
    ///
    /// 注意：上游没有对 substringBefore 缺失 `<br>` 做兜底，强行走 Jsoup 解析会
    /// 把整段 HTML 当课名；我们保留上游忠实行为，依赖 `generateCourseList`
    /// 入口处的 `courseElements.html()` 必然含 `<br>`（强智单元格结构）。
    override func parseCourseName(_ infoStr: String) -> String {
        (infoStr.components(separatedBy: "<br>").first ?? infoStr)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 覆写基类入口: 单元格遍历走 `qzCourseList`(html() 先归一 `<br />`→`<br>`),
    /// 否则 SwiftSoup 序列化下 parseCourseName 的 "<br>" 探针与基类分隔符步进全落空。
    /// 缺 #kbtable 抛出的 JwParseError 快照与基类逐字一致。
    override func generateCourseList() throws -> [JwCourse] {
        try qzCourseList(from: self)
    }

    /// T8 §2.5: 继承 kbtable 锚点 + br-not-font 特征
    override var matchedFeatureList: [String] {
        super.matchedFeatureList + ["br-not-font"]
    }
}

/// 强智 qz_with_node 变体解析器。
///
/// 差异：title="周次(节次)" 的文本携带节次信息（不再让节次=所在大格位置），
/// 支持三种文本形态：
///   1) 含空格 → "1-16(周) 1-2节" — 按空格拆 [周次段, 节次段]
///   2) 无空格且无 [ ] → 独立 title="周次" + title="节次"
///   3) 其它 → "周N-X节[Y-Z节]" / "1-16(周)[1-2节]" 格式按 '周[' ']' 拆
///
/// 样本学校：北邮 jwgl.bupt.edu.cn/jsxsd、广外 jxgl.gdufs.edu.cn/jsxsd、
///          北邮 WebVPN、北理工、北理工珠海、海南大学、江苏师大等 14 所。
///
/// 上游源码：dIT8Zv/WakeupSchedule_BUPT QzWithNodeParser.kt (Apache-2.0)
final class JwQzWithNodeParser: JwQzParser {

    /// ← Kotlin `String.toInt()` 的 NumberFormatException: Android 侧坏数字段
    /// (weeks[0].toInt() / nodeList.first().substringBefore('节').toInt()) 直接
    /// 中断整次解析 → 0 课 + 异常上抛, Registry 记 attempt 后回退其它 parser。
    /// convert 签名继承自基类(非 throws), 无法就地抛错, 因此首个坏值记入本字段,
    /// 循环继续(默认值兜底), 由下方 generateCourseList 覆写统一抛出 —— 课程整份
    /// 丢弃, 最终状态与 Android 一致(异常 + 0 课计入 Registry)。
    /// 有意保留的宽容差: 先 trim 再 Int —— Kotlin " 17".toInt() 也抛, 这里与
    /// 兄弟 iOS 基类 JwQzParser 的 trim 惯例保持一致; 非数字仍按 Android 失败。
    private var pendingNumericFailure: String?

    /// Int(s) 失败时登记首次异常描述并返回 nil(调用点用原默认值继续)。
    private func kToInt(_ raw: String, _ context: String) -> Int? {
        if let v = Int(raw.trimmingCharacters(in: .whitespaces)) { return v }
        if pendingNumericFailure == nil {
            pendingNumericFailure = "NumberFormatException: For input string: \"\(raw)\" (\(context))"
        }
        return nil
    }

    /// 覆写基类入口: 缺 #kbtable 的 JwParseError 由 `qzCourseList` 先行抛出(与 Android
    /// getElementById 检查在 convert 之前的顺序一致); 数值失败在解析完成后抛出,
    /// 丢弃全部课程 —— 等价 Android 中途抛 NumberFormatException 的效果。
    /// 单元格遍历走 `qzCourseList`(html() 归一 `<br />`→`<br>`), 否则 SwiftSoup 下
    /// convert 的 "<font"/"<span>" 与分隔符 "<br>" 探针全落空。
    override func generateCourseList() throws -> [JwCourse] {
        pendingNumericFailure = nil
        let courses = try qzCourseList(from: self)
        if let failure = pendingNumericFailure {
            throw JwParseError(
                message: "课表格周次/节次数值格式异常: \(failure)",
                attempts: [ParserAttemptSnapshot(
                    parserName: "JwQzWithNodeParser",
                    type: JwProtocol.TYPE_QZ,
                    courseCount: 0,
                    confidence: confidenceValue,
                    matchedFeatures: matchedFeatureList,
                    exception: failure)])
        }
        return courses
    }

    override func convert(day: Int, nodeCount: Int, infoStr: String, courseList: inout [JwCourse]) {
        let courseHtml = try! SwiftSoup.parse(infoStr)
        // 课名提取：上游 substringBefore("<font").substringBefore("<span>")
        // 第二段 needle 是 "<span>"（带尖括号），对 "<span title=..>" 永不命中，
        // 因此 with_node 页面必须用 <font title=..> 结构（实测 BUPT/JSNU 适配器一致）
        var namePart = infoStr.components(separatedBy: "<font").first ?? infoStr
        namePart = namePart.components(separatedBy: "<span>").first ?? namePart
        let courseName = ((try? SwiftSoup.parse(namePart.trimmingCharacters(in: .whitespaces)).text()) ?? "")
        let teacher = ((try? courseHtml.getElementsByAttributeValue("title", "老师").text()) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let room = (((try? courseHtml.getElementsByAttributeValue("title", "教室").text()) ?? "")
            + ((try? courseHtml.getElementsByAttributeValue("title", "分组").text()) ?? ""))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tempStr = ((try? courseHtml.getElementsByAttributeValue("title", "周次(节次)").text()) ?? "")

        // 三分支周次/节次提取(严格复刻 Kotlin substringAfter / removeSurrounding 语义)
        let weekStr: String
        let nodeList: [String]
        if tempStr.contains(" ") {
            let parts = tempStr.components(separatedBy: " ")
            weekStr = parts.first ?? ""
            let nodePart = parts.count > 1 ? parts[1] : ""
            nodeList = qzRemoveSurrounding(nodePart, "[", "]")
                .components(separatedBy: "-")
        } else if tempStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            weekStr = ((try? courseHtml.getElementsByAttributeValue("title", "周次").text()) ?? "")
            let nodeRaw = ((try? courseHtml.getElementsByAttributeValue("title", "节次").text()) ?? "")
            // ← .substringAfter(')') — 无 ')' 时 Kotlin 返回原串("3-4节" 裸形态靠此可拆)
            nodeList = qzRemoveSurrounding(qzSubstringAfter(nodeRaw, ")"), "[", "]")
                .components(separatedBy: "-")
        } else {
            // ← text.substringBefore(')'):剥掉 ')' 之后不再补回
            weekStr = tempStr.components(separatedBy: ")").first ?? tempStr
            nodeList = qzRemoveSurrounding(qzSubstringAfter(tempStr, ")"), "[", "]")
                .components(separatedBy: "-")
        }

        let weekList = weekStr.components(separatedBy: ",")
        var startWeek = 0
        var endWeek = 0
        var type = 0

        for item in weekList {
            if item.contains("-") {
                let weeks = item.components(separatedBy: "-")
                if !weeks.isEmpty { startWeek = kToInt(weeks[0], "weeks[0]") ?? startWeek }
                if weeks.count > 1 {
                    type = {
                        if weeks[1].contains("单") { return 1 }
                        if weeks[1].contains("双") { return 2 }
                        return 0
                    }()
                    // ← weeks[1].substringBefore('(').toInt()
                    let before = weeks[1].components(separatedBy: "(").first ?? weeks[1]
                    endWeek = kToInt(before, "weeks[1].substringBefore('(')") ?? endWeek
                }
            } else {
                // ← item.substringBefore('(').toInt()
                let before = item.components(separatedBy: "(").first ?? item
                let v = kToInt(before, "weekItem") ?? startWeek
                startWeek = v
                endWeek = v
            }
            // ← nodeList.first().substringBefore('节').toInt()
            let startNode = kToInt((nodeList.first ?? "1").components(separatedBy: "节").first ?? "1",
                                   "nodeList.first") ?? 1
            // ← nodeList.last().substringBefore('节').toInt()
            let endNode = kToInt((nodeList.last ?? "1").components(separatedBy: "节").first ?? "1",
                                 "nodeList.last") ?? startNode
            courseList.append(JwCourse(
                name: courseName,
                room: room,
                teacher: teacher,
                day: day,
                startNode: startNode,
                endNode: endNode,
                startWeek: startWeek,
                endWeek: endWeek,
                type: type))
        }
    }

    /// T8 §2.5: 继承 + title=周次(节次) 含空格 / 独立 title=周次+节次 特征
    override var matchedFeatureList: [String] {
        let base = super.matchedFeatureList
        guard let jsoup = try? SwiftSoup.parse(source) else { return base }
        let withNode = (try? jsoup.getElementsByAttributeValue("title", "周次(节次)")) ?? Elements()
        var hasSpace = false
        for el in withNode {
            if (((try? el.text()) ?? "").contains(" ")) { hasSpace = true; break }
        }
        if hasSpace { return base + ["title=周次(节次)空格"] }
        if ((try? jsoup.getElementsByAttributeValue("title", "周次")) ?? Elements()).isEmpty() == false {
            return base + ["title=周次独立", "title=节次独立"]
        }
        return base
    }
}

/// 强智 qz_old 变体解析器（"需要 IE 的那种"老强智教务，如湖南工学院）。
///
/// 与新版 QzParser 完全不同：单元格内无 title 属性，靠 `<br>` 分隔 + 时间串
/// 含 `[` + `]` + `周` + `节` 四要素来定位。type 恒为 0，不识别单/双周。
///
/// 样本学校（上游 SchoolListActivity.kt 实证）：湖南工学院等 3 所。
///
/// 上游源码：dIT8Zv/WakeupSchedule_BUPT OldQzParser.kt (Apache-2.0)
/// v1.0.62: 稳定 qz_old 入口 — 变薄壳委托 JwOldQzSuperParser
/// (old-qz-super-cross-verify-2026-10-13 取证; 解析/置信度/特征全由 Super 承担)。
final class JwOldQzParser: JwParser, JwParserConfidenceReporting {

    let source: String

    private let delegate: JwOldQzSuperParser

    init(_ source: String) {
        self.source = source
        self.delegate = JwOldQzSuperParser(source)
    }

    func generateCourseList() throws -> [JwCourse] {
        try delegate.generateCourseList()
    }

    var confidenceValue: Int {
        delegate.confidenceValue
    }

    var matchedFeatureList: [String] {
        delegate.matchedFeatureList
    }
}
