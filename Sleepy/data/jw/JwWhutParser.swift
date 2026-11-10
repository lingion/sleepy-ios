// JwWhutParser.swift — ← JwWhutParser.kt
//
// 武汉理工大学 (WHUT) — 金智 wisedu jwapp 变体解析器 (2026-09-05 调研落地)。
//
// WHUT 与 HEU 同属金智 jwapp 家族, 行字段 (KCM/SKJS/JASMC/SKXQ/KSJC/JSJC/SKZC)
// 一一对应, 解析内核完全复用 JwWiseduParser (SKZC bitmap → weekRuns 单双周
// 压缩)。两处 WHUT 特有差异:
//
// 1. **取数微应用不同**: 学生课表主通道是 wdkbby 微应用 (`cxxszhxqkb.do`,
//    响应 `datas.cxxszhxqkb.rows[]`, 2026-09-05 用户采集包实锤 — 学生
//    "我的课表"页面走它; 旧认知 kcbcxby/cxxskcb.do 实为教室课表(教师端),
//    学生账号常 403/空, 降级为兜底通道)。moduleNames 按优先级认三条路径,
//    HEU 数据喂进来也照常解析 (兼容回归测试钉死)。
// 2. **节次 DM ≠ 物理节次**: WHUT 大节 DM 序列 1..16 中 6/7/13 缺位
//    (中课/晚课大节), DM 8→物理6, 9→7, 14→11 …。不映射则下午/晚上课全部
//    错位。表外 DM (教务改版新增) 原值直通, 禁丢行。实机上取数 JS 先拉
//    jcjcx.do 动态映射, 此表兜底。
//
// 上游协议形态参考: XingHeYuZhuan/shiguang_warehouse (MIT) resources/WHUT/whut_01.js
// 与 TokenTeam/iwut (AGPL-3.0, 仅引协议形态不抄码)。代码自写, 节次映射表
// 为事实性数据。
//
// 取数 JS (登录态 WebView fetch): 见 JwWebViewLoginScreen WHUT_FETCH_JS。

import Foundation
import SwiftSoup

final class JwWhutParser: JwWiseduParser {
    private lazy var legacyTable = Jw64.first(Jw64.doc(source), "#xqkb .table-class-even")
    private lazy var dynamicSections: [Int: Int] = {
        guard let root = Jw64.json(source) as? [String: Any], let values = root["sleepyWhutSectionMap"] as? [String: Any] else { return [:] }
        var result: [Int: Int] = [:]
        for (key, value) in values {
            guard let dm = jw1064Integer(key), dm > 0, let node = jw1064Integer(value), (1...EXPLICIT_SCHEDULE_RESOURCE_BOUND).contains(node) else { continue }
            result[dm] = node
        }
        return result
    }()

    override func generateCourseList() throws -> [JwCourse] {
        guard let table = legacyTable else { return try super.generateCourseList() }
        var result: [JwCourse] = []
        for row in Jw64.rows(table) {
            let cells = Jw64.children(row).filter { $0.tagNameNormal() == "td" }.drop(while: { !$0.hasAttr("style") })
            for (index, cell) in cells.enumerated() where (1...7).contains(index + 1) {
                for item in Jw64.select(cell, "a") {
                    let name = ((try? item.ownText()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let children = Jw64.children(item)
                    guard !name.isEmpty, children.count >= 2 else { continue }
                    let timing = Jw64.text(children[1]).replacingOccurrences(of: "（", with: "(").replacingOccurrences(of: "）", with: ")")
                    guard let match = Jw64.full(#"(.+)\(([^()]*)节\)"#, timing) else { continue }
                    let rawRoom = Jw64.text(children[0]), room = rawRoom.hasPrefix("@") ? String(rawRoom.dropFirst()) : rawRoom
                    for (first, last) in schoolNodeRanges(match[2]) {
                        for (from, to, type) in schoolWeekRanges(match[1]) {
                            result.append(JwCourse(name: name, room: room, day: index + 1, startNode: first, endNode: last, startWeek: from, endWeek: to, type: type))
                        }
                    }
                }
            }
        }
        return Jw64.distinct(result)
    }

    /// WHUT 节次 DM → 物理节次 (1..13)。
    /// DM 序列 = 1,2,3,4,5, 8,9,10,11,12, 14,15,16 (6/7/13 缺位)。
    /// 来源: shiguang_warehouse whut_01.js fallback 表 (MIT)。
    static let SECTION_DM_TO_NODE: [Int: Int] = [
        1: 1, 2: 2, 3: 3, 4: 4, 5: 5,
        8: 6, 9: 7, 10: 8, 11: 9, 12: 10,
        14: 11, 15: 12, 16: 13,
    ]

    static func mapSectionDm(_ dm: Int) -> Int {
        SECTION_DM_TO_NODE[dm] ?? dm
    }

    override var moduleNames: [String] { ["cxxszhxqkb", "cxxskcb", "xskcb"] }

    override func mapSection(_ dm: Int) -> Int { dynamicSections[dm] ?? Self.mapSectionDm(dm) }

    override var confidenceValue: Int {
        if legacyTable != nil { return 100 }
        // 2026-09 采集包实锤: 学生课表主通道 wdkbby/cxxszhxqkb.do
        if source.contains("cxxszhxqkb") { return 96 }
        if source.contains("cxxskcb.do") { return 95 }
        // 微应用名 cxxskcb (JSON key 与 URL 段都含), 兼容 pretty-print 响应
        if source.contains("cxxskcb") { return 90 }
        // cxxskcb 与 xskcb 锚点可能同现 (取数 JS 带两条路径痕迹), WHUT 规则优先
        if source.contains("xskcb.do") { return 90 }
        if source.contains("datas.xskcb") { return 80 }
        if source.contains("/jwapp/sys/wdkb/") { return 100 }
        return 0
    }

    override var matchedFeatureList: [String] {
        var out = super.matchedFeatureList
        if legacyTable != nil { out.append("xqkb/table-class-even") }
        if source.contains("cxxszhxqkb") { out.append("wdkbby/cxxszhxqkb.do") }
        if source.contains("cxxskcb.do") { out.append("kcbcxby/cxxskcb.do") }
        if source.contains("cxxskcb") { out.append("datas.cxxskcb.rows") }
        return out
    }
}
