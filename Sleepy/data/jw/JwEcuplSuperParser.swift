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

    private let mainParserImpl: any JwParser
    private let scriptParserImpl: any JwParser

    init(_ source: String) {
        self.source = source
        self.mainParserImpl = JwEcuplParser(source)
        self.scriptParserImpl = JwEcuplScriptParser(source)
    }

    init(_ source: String, mainParser: any JwParser, scriptParser: any JwParser) {
        self.source = source; self.mainParserImpl = mainParser; self.scriptParserImpl = scriptParser
    }

    func generateCourseList() throws -> [JwCourse] {
        var errors: [String] = []
        for (name, parser) in [("ECUPLParser", mainParserImpl), ("ECUPLScriptParser", scriptParserImpl)] {
            do {
                let courses = try parser.generateCourseList()
                if !courses.isEmpty { return courses }
            } catch is CancellationError { throw CancellationError() }
            catch { errors.append("\(name): \(error.localizedDescription)") }
        }
        if !errors.isEmpty { throw JwParseError(message: errors.joined(separator: "\n")) }
        return []
    }

    // MARK: - JwParserConfidenceReporting

    var confidenceValue: Int {
        // 取 max (双 parser 联合判别)
        max((mainParserImpl as? JwParserConfidenceReporting)?.confidenceValue ?? 0,
            (scriptParserImpl as? JwParserConfidenceReporting)?.confidenceValue ?? 0)
    }

    var matchedFeatureList: [String] {
        var out = (mainParserImpl as? JwParserConfidenceReporting)?.matchedFeatureList ?? []
        out.append(contentsOf: (scriptParserImpl as? JwParserConfidenceReporting)?.matchedFeatureList ?? [])
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
