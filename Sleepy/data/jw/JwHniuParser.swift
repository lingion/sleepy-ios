// JwHniuParser.swift — ← JwHniuParser.kt
//
// 湖南信息职业技术学院（HNIU）解析器 — T8。
//
// 协议：JwProtocol.TYPE_HNIU = "hniu"
// Android 1.0.64 使用独立 HNIU 页面布局解析。
// T8 按 §2.5 清单实现 confidence 锚点：bordercolordark="#FFFFFF"。
//
// 解析委托给 JwUndergradSchoolParser 的 HNIU 路由。
// (Kotlin 类名 JwHniuparser 小写 p 是上游手误, Swift 侧按命名规范 JwHniuParser)

import Foundation

final class JwHniuParser: JwParser, JwParserConfidenceReporting {

    let source: String
    private let delegate: JwUndergradSchoolParser

    init(_ source: String) {
        self.source = source
        self.delegate = JwUndergradSchoolParser(source, protocolType: "hniu")
    }

    func generateCourseList() throws -> [JwCourse] {
        try delegate.generateCourseList()
    }

    /// T8 §2.5: 命中 bordercolordark="#FFFFFF" = 100（HNIU 页面专属表格样式锚点）
    var confidenceValue: Int {
        source.lowercased().contains("bordercolordark=\"#ffffff\"") ? 100 : 0
    }

    var matchedFeatureList: [String] {
        source.lowercased().contains("bordercolordark=\"#ffffff\"")
            ? ["bordercolordark=#FFFFFF"]
            : []
    }
}
