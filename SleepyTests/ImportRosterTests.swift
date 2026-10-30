// ImportRosterTests.swift — ← data/repository/CourseColorKinshipTest.kt 逐用例移植 (v1.0.62, GPL-3.0)
//
// 认亲契约(spec §2.4/§6 测试7):
//   1. 认亲 — 二次导入同名课 → groupId 继承 → 持久 hue 直接命中 → 颜色跨导入不变;
//   2. 新课只增不改 — 增量 hue 规划永不移动既有组的色相(钉死性, spec §2.3);
//   3. CLASSIC 档零写入 — anchor=null 时规划产出空表。
//
// 身份键口径 = 仓库既有 courseName 规范化(trim/折叠空白/小写),严于 spec 原文的精确匹配表述:
// 同一身份规则单点, 两处导入路径(教务/文件)行为一致。

import XCTest
import SwiftUI
@testable import Sleepy

final class ImportRosterTests: XCTestCase {

    private let neutral = Color(red: 0, green: 1, blue: 0)

    private func row(name: String, gid: String = UUID().uuidString) -> CourseEntity {
        CourseEntity(groupId: gid, tableId: 1, courseName: name,
                     day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16, color: "")
    }

    private func colorsEqual(_ a: Color, _ b: Color) -> Bool {
        let ua = UIColor(a), ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return r1 == r2 && g1 == g2 && b1 == b2 && a1 == a2
    }

    // 环距与允许弧判定(与 CourseColorHarmonyTests 同一几何定义)
    private func ringDist(_ a: Float, _ b: Float) -> Float {
        let d = ((a - b).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    private func inAllowedArc(anchor: Float, hue: Float) -> Bool {
        func inArc(startDeg: Float, endDeg: Float, h: Float) -> Bool {
            let s = ((startDeg.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            let e = ((endDeg.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
            let d = ((h - s).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            let span = ((e - s).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
            return d < span
        }
        return inArc(startDeg: anchor + 30, endDeg: anchor + 150, h: hue)
            || inArc(startDeg: anchor + 210, endDeg: anchor + 330, h: hue)
    }

    // ───────── 1. 认亲: 同名继承旧 groupId ─────────

    func testKnownNameHitInheritsOldGroupIdEvenWithFreshGidOnRows() {
        // 第一次导入(无名册): 每名字一个新 gid
        let first = ImportRoster.normalizedImportGroups([row(name: "高等数学"), row(name: "线性代数")])
        let known = ImportRoster.knownNameToGroupId(first)
        // 删表重导入: 解析端给的全是新鲜 UUID, 必须被名册接管
        let second = ImportRoster.normalizedImportGroups([row(name: "高等数学"), row(name: "线性代数")],
                                                          knownNameToGroup: known)
        XCTAssertEqual(first[0].groupId, second[0].groupId, "同名课必须继承旧 groupId")
        XCTAssertEqual(first[1].groupId, second[1].groupId)
        XCTAssertNotEqual(second[0].groupId, second[1].groupId, "不同名课仍各自独立")
    }

    func testKinshipKeyUsesExistingNormalizationWhitespaceCaseInsensitive() {
        // 仓库身份口径 = trim + 空白折叠 + 小写(不剥空格, "离散数学"≠"离散 数学" 属不同身份)
        let first = ImportRoster.normalizedImportGroups([row(name: " Discrete  Math ")])
        let known = ImportRoster.knownNameToGroupId(first)
        let second = ImportRoster.normalizedImportGroups([row(name: "discrete math")],
                                                          knownNameToGroup: known)
        XCTAssertEqual(first[0].groupId, second[0].groupId,
                       "大小写/空白差异按仓库身份口径视为同名")
    }

    func testUnknownNameStillFallsBackToRowGidOrNewUuid() {
        let preset = "preset-gid-1"
        let kept = ImportRoster.normalizedImportGroups([row(name: "新课", gid: preset)])
        XCTAssertEqual(preset, kept[0].groupId, "无命中时保留行自带 gid(v1.0.61 行为)")
        let fresh = ImportRoster.normalizedImportGroups([row(name: "全新课", gid: "")])
        XCTAssertFalse(fresh[0].groupId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "空 gid → 分配新 UUID")
        // 同批同名仍归一组
        let pair = ImportRoster.normalizedImportGroups([row(name: "全新课", gid: ""),
                                                        row(name: "全新课", gid: "")])
        XCTAssertEqual(pair[0].groupId, pair[1].groupId)
    }

    func testKnownNameToGroupIdFirstWinsOnNameCollision() {
        let rows = [row(name: "复变函数", gid: "gid-A"), row(name: "复变函数", gid: "gid-B")]
        let known = ImportRoster.knownNameToGroupId(rows)
        XCTAssertEqual("gid-A", known["复变函数"], "同名冲突取首个(id 升序 → 确定性)")
    }

    // ───────── 2. 增量 hue 规划: 新课只增不改 ─────────

    func testSecondImportInheritedGroupsHitPersistedHueNewCourseOnlyAppends() {
        let anchor: Float = 275  // 紫主题
        let firstRows = [row(name: "高等数学"), row(name: "线性代数"), row(name: "大学英语")]
        let first = ImportRoster.normalizedImportGroups(firstRows)
        let hues1 = CourseColorUtil.planHuesForGroups(anchor: anchor, existingHues: [],
                                                      gids: first.map { $0.groupId })
        XCTAssertEqual(3, hues1.count)

        // 重导入 + 一门真新课
        let known = ImportRoster.knownNameToGroupId(first)
        let secondRows = firstRows.map { row(name: $0.courseName) } + [row(name: "概率论")]
        let second = ImportRoster.normalizedImportGroups(secondRows, knownNameToGroup: known)
        let newGids = Array(Set(second.map { $0.groupId })).filter { hues1[$0] == nil }
        XCTAssertEqual(1, newGids.count, "同名课全部命中旧组, 仅新课待补色")

        let hues2 = CourseColorUtil.planHuesForGroups(anchor: anchor,
                                                      existingHues: Array(hues1.values),
                                                      gids: newGids)
        // 钉死性 = 规划只产新课, 旧组不在写集合内(taken 只增不改, spec §2.3)
        XCTAssertEqual(Set([newGids[0]]), Set(hues2.keys), "只规划新课, 旧组 hue 零移动")

        let all = Array(hues1.values) + Array(hues2.values)
        for i in all.indices {
            for j in (i + 1)..<all.count {
                XCTAssertTrue(ringDist(all[i], all[j]) >= 10, "hue 间距 ≥10°")
            }
        }
        for h in all {
            XCTAssertTrue(inAllowedArc(anchor: anchor, hue: h), "hue ∉ 禁区")
        }
    }

    func testPlanHuesForGroupsClassicNullAnchorWritesNothing() {
        XCTAssertTrue(CourseColorUtil.planHuesForGroups(anchor: nil, existingHues: [],
                                                       gids: ["a", "b"]).isEmpty)
    }

    func testPlanHuesForGroupsIsDeterministicSameInputSameOutput() {
        let gids = (1...8).map { "g\($0)" }
        let p1 = CourseColorUtil.planHuesForGroups(anchor: 200, existingHues: [], gids: gids)
        let p2 = CourseColorUtil.planHuesForGroups(anchor: 200, existingHues: [], gids: gids)
        XCTAssertEqual(p1, p2)
    }

    // ───────── 端到端: 两次导入渲染色逐值相等 ─────────

    func testRenderColorIdenticalAcrossReimportViaKinshipAndPersistedHue() {
        let anchor: Float = 275
        let first = ImportRoster.normalizedImportGroups([row(name: "机械设计基础")])
        let hues = CourseColorUtil.planHuesForGroups(anchor: anchor, existingHues: [],
                                                     gids: first.map { $0.groupId })
        let color1 = CourseColorUtil.pickCourseColorSwiftUI(first[0], isDark: false,
                                                            neutralColor: neutral, colorless: false,
                                                            persistedHue: hues[first[0].groupId])
        let second = ImportRoster.normalizedImportGroups([row(name: "机械设计基础")],
                                                          knownNameToGroup: ImportRoster.knownNameToGroupId(first))
        let color2 = CourseColorUtil.pickCourseColorSwiftUI(second[0], isDark: false,
                                                            neutralColor: neutral, colorless: false,
                                                            persistedHue: hues[second[0].groupId])
        XCTAssertTrue(colorsEqual(color1, color2), "重导入同课渲染色必须逐 bit 相等")
    }

    // ───────── importNameKey 口径单点 ─────────

    func testImportNameKeyNormalizesTrimCollapseAndLowercase() {
        XCTAssertEqual("discrete math", ImportRoster.importNameKey("  Discrete   Math  "))
        XCTAssertEqual("", ImportRoster.importNameKey("   "))
        XCTAssertEqual("离散数学", ImportRoster.importNameKey("离散数学"))
    }
}
