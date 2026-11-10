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
/// (Element.outerHtmlHead 的 `accum.append(" />")` 分支), 而 原版本 端 Jsoup 输出
/// `<br>`。qz 家族所有字面量 `"<br>"` 探针(substringBefore("<br>") 课名截断、
/// 基类循环 '-----' 分隔后的 <br> 步进、qz_old 的行切分)作用在**序列化输出**上,
/// SwiftSoup 下全部落空: 课名带原始标签整段污染、同格多课第二条起整条丢失。
/// 消费序列化 HTML 前把两种形态归一成 `<br>`, 恢复与 原版本 的字节级语义一致。
private func qzNormalizeBrTags(_ html: String) -> String {
    html.replacingOccurrences(of: "<br />", with: "<br>")
        .replacingOccurrences(of: "<br/>", with: "<br>")
}

/// 复刻 JwQzParser.generateCourseList 的单元格遍历, 唯一差异是 courseHtml 先经
/// `qzNormalizeBrTags` 归一。基类循环在本文件之外(不在本次可改范围), qz_br /
/// qz_with_node 覆写 generateCourseList 走此通路; 缺 #kbtable 的 JwParseError
/// 快照字段与基类逐字一致(parserName 固定 "JwQzParser" —— 原版本 继承基类抛出
/// 的同源行为; confidence/matchedFeatures 动态取子类覆写值)。
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
        Jw64.plain(infoStr.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression).components(separatedBy: "\n").first ?? infoStr)
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

    // Explicit sections share the base decoder.

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
