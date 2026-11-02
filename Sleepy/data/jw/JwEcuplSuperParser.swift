// JwEcuplSuperParser.swift — ← JwEcuplSuperParser.kt
//
// 华东政法大学 (ECUPL) Super 解析器 — 3-parser 调度器。
//
// 调度策略: 独立实现的两个已观察到的协议分支。
//   1. 主路径: JwEcuplParser (双 .listTable + 5 列模糊匹配)
//   2. Script 路径: JwEcuplScriptParser (R5/R6/R7 script 子协议)
//   3. Super fallback: 两个 parser 各自独立尝试, 合并去重结果
//
// 协议证据: LonelyMarch/OpenWakeUp EcuplParser.kt @ 9c2d0436;
// 历史 APK 反编译归档 lingion/wakeup-mod @ 879f0d6 (许可未确认)。

import Foundation

final class JwEcuplSuperParser: JwParser, JwParserConfidenceReporting {

    let source: String

    private let mainParserImpl: JwEcuplParser
    private let scriptParserImpl: JwEcuplScriptParser

    init(_ source: String) {
        self.source = source
        self.mainParserImpl = JwEcuplParser(source)
        self.scriptParserImpl = JwEcuplScriptParser(source)
    }

    /// Super 调度:
    ///  - 主 parser 优先 (HTML 是首校路径)
    ///  - Script parser 补齐 (script 子协议, 教务通知页路径)
    ///  - 合并去重: 仅完全相同的排课记录视为重复
    func generateCourseList() throws -> [JwCourse] {
        let mainCourses = (try? mainParserImpl.generateCourseList()) ?? []
        let scriptCourses = (try? scriptParserImpl.generateCourseList()) ?? []

        var merged: [JwCourse] = []
        var seen = Set<JwCourse>()

        // 主 parser 优先 (HTML 是首校路径)
        for c in mainCourses where seen.insert(c).inserted {
            merged.append(c)
        }
        // Script parser 补齐 (通知页路径)
        for c in scriptCourses where seen.insert(c).inserted {
            merged.append(c)
        }
        return merged
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        // 取 max (双 parser 联合判别)
        max(mainParserImpl.confidenceValue, scriptParserImpl.confidenceValue)
    }

    var matchedFeatureList: [String] {
        var out = mainParserImpl.matchedFeatureList
        out.append(contentsOf: scriptParserImpl.matchedFeatureList)
        if out.isEmpty { out.append("guard:no-ecupl-super-markers") }
        return out
    }

    // MARK: - 复用锚点 (← companion HAS_LIST_TABLE / HAS_NEW_ACTIVITY)

    /// 复用 main parser 的 JwEcuplParser.reListTable (cached)。
    static let hasListTable: (String) -> Bool = { html in
        JwEcuplParser.contains(JwEcuplParser.reListTable, html)
    }

    /// 复用 script parser 的 JwEcuplScriptParser.reNewActivity (cached)。
    static let hasNewActivity: (String) -> Bool = { html in
        JwEcuplScriptParser.firstMatch(JwEcuplScriptParser.reNewActivity, html) != nil
    }
}
