// CourseColorWriteGlueTests.swift — ← util/CourseColorRecalcTest.kt + CourseColorPersistedHueTest.kt
// 逐用例移植 (v1.0.62, GPL-3.0)
//
// 覆盖两个 原版本 契约套件:
//   A. CourseColorRecalcTest — 重算层契约(spec §2.3 时机1/2/3/6)
//      · CLASSIC(anchor=null)零写红线;脏 gid(空白/重复)过滤去重;
//      · 重算结果仍满足安全弧禁区不变量 + 同批 ≥10° 间距;
//      · 换 anchor 整体重排;同输入逐 bit 相等。
//   B. CourseColorPersistedHueTest — 渲染层契约(spec §2.1/§2.3/§6 测试3′/4/8)
//      · CLASSIC 零变化(persistedHue=null ⇒ 与 v1.0.61 stableHue 路径逐值相等);
//      · persistedHue 注入,明暗只切 S/L 不动 hue;
//      · 优先级红线:单课自定义色 > colorless > 派生取色;
//      · resolveAnchor 三档决策 + Int/Color 两路径 hue 解析一致;
//      · AppPrefs 两新键字面量稳定。
//
// 平台差异: 原版本 FakeDao 记录写入;iOS 用 AppDatabase.inMemory() 真 DAO(更贴近实际)。
// 原版本 Compose Color ↔ SwiftUI Color: 用 UIColor.getRed 分量比对(仓库既有约定)。

import XCTest
import SwiftUI
import GRDB
@testable import Sleepy

final class CourseColorWriteGlueTests: XCTestCase {

    private let neutral = Color(red: 0, green: 1, blue: 0)
    private let neutralInt: Int = 0xFF00FF00

    // MARK: - 夹具

    private func course(color: String = "#FF6750A4", groupId: String = "grp-A",
                        id: Int64 = 1) -> CourseEntity {
        CourseEntity(groupId: groupId, tableId: 1, courseName: "高等数学",
                     day: 1, startNode: 1, step: 2, startWeek: 1, endWeek: 16,
                     color: color, id: id)
    }

    private func groupRow(_ id: Int64, gid: String = "g1", color: String = "",
                          mode: Int = CourseColorMode.GROUP) -> CourseEntity {
        CourseEntity(groupId: gid, tableId: 1, courseName: "x", room: "r\(id)",
                     day: 1, startNode: 1, step: 1, startWeek: 1, endWeek: 16,
                     color: color, colorMode: mode, id: id)
    }

    private func colorsEqual(_ a: Color, _ b: Color) -> Bool {
        let ua = UIColor(a), ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return r1 == r2 && g1 == g2 && b1 == b2 && a1 == a2
    }

    // 允许弧判定(与 CourseColorHarmonyTests 同一定义)
    private func zoneDist(_ hue: Float, _ anchor: Float) -> Float {
        ((hue - anchor).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
    }

    private func assertInAllowedArc(_ hue: Float, _ anchor: Float, _ ctx: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let dist = zoneDist(hue, anchor)
        let ok = (dist >= 30 && dist < 150) || (dist >= 210 && dist < 330)
        XCTAssertTrue(ok, "\(ctx) hue=\(hue) anchor=\(anchor) dist=\(dist) 落入禁区",
                      file: file, line: line)
    }

    private func ringDelta(_ a: Float, _ b: Float) -> Float {
        let d = ((a - b).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    private func makeDb() throws -> AppDatabase {
        try AppDatabase.inMemory()
    }

    // ═══════════════════════════════════════════════════════════════
    // A. CourseColorRecalcTest — 重算层契约
    // ═══════════════════════════════════════════════════════════════

    func testClassicNullAnchorWritesNothingRedLine() throws {
        let db = try makeDb()
        let dao = db.courseColorDao
        let plan = CourseColorWriteGlue.recalcWithAnchor(anchor: nil, dao: dao, gids: ["g1", "g2"])
        XCTAssertTrue(plan.isEmpty, "CLASSIC 重算必须零写(表不动, 渲染零变化)")
        let written = try dao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertTrue(written.isEmpty, "CLASSIC 重算必须零写(DAO 零调用)")
    }

    func testRecalcCoversEveryNonBlankDistinctGidOnly() throws {
        let db = try makeDb()
        let dao = db.courseColorDao
        let gids = ["g1", "g2", "  ", "", "g1", "g3"]
        let plan = CourseColorWriteGlue.recalcWithAnchor(anchor: 280, dao: dao, gids: gids)
        XCTAssertEqual(Set(["g1", "g2", "g3"]), Set(plan.keys), "空白/重复 gid 须被过滤去重")
        let written = try dao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertEqual(plan.count, written.count, "落库行数 = 规划行数")
        for (gid, hue) in plan {
            XCTAssertEqual(hue, written[gid])
        }
    }

    func testRecalcResultSatisfiesArcAndSpacingInvariants() throws {
        let db = try makeDb()
        let anchor: Float = 120
        // 严格间距只测弧容量内(≤20 门);>~24 门弧饱和 → 文档化退化=保弧弃距(§2.2 ③)
        let gids = (1...20).map { "recalc-g\($0)" }
        let plan = CourseColorWriteGlue.recalcWithAnchor(anchor: anchor, dao: db.courseColorDao, gids: gids)
        XCTAssertEqual(20, plan.count)
        for h in plan.values { assertInAllowedArc(h, anchor, "重算安全弧不变量") }
        let hues = Array(plan.values)
        for i in hues.indices {
            for j in (i + 1)..<hues.count {
                XCTAssertTrue(ringDelta(hues[i], hues[j]) >= CourseColorUtil.MIN_SEP_DEG,
                              "容量内重算间距 \(i)/\(j)")
            }
        }
    }

    func testRecalcArcSaturationDegradesToSpacingCompromiseButArcHolds() throws {
        let db = try makeDb()
        let plan = CourseColorWriteGlue.recalcWithAnchor(
            anchor: 120, dao: db.courseColorDao, gids: (1...30).map { "over-g\($0)" })
        XCTAssertEqual(30, plan.count)
        for h in plan.values { assertInAllowedArc(h, 120, "弧饱和仍不出禁区") }
    }

    func testRecalcDifferentAnchorRelaysOutAllGroupsApprovedBehavior() throws {
        let db = try makeDb()
        let gids = (1...12).map { "g\($0)" }
        let purple = CourseColorWriteGlue.recalcWithAnchor(anchor: 280, dao: db.courseColorDao, gids: gids)
        let warm = CourseColorWriteGlue.recalcWithAnchor(anchor: 40, dao: db.courseColorDao, gids: gids)
        XCTAssertEqual(Set(purple.keys), Set(warm.keys), "gid 覆盖一致")
        XCTAssertNotEqual(Set(purple.values), Set(warm.values),
                          "换 anchor 必须整体重排(用户批准的目标行为, spec §2.5)")
        for h in purple.values { assertInAllowedArc(h, 280, "紫主题重算") }
        for h in warm.values { assertInAllowedArc(h, 40, "暖主题重算") }
    }

    func testRecalcDeterministicSameAnchorSameGids() throws {
        let db = try makeDb()
        let gids = ["高数", "英语", "大物", "体育", "实验"]
        let a = CourseColorWriteGlue.recalcWithAnchor(anchor: 200, dao: db.courseColorDao, gids: gids)
        let b = CourseColorWriteGlue.recalcWithAnchor(anchor: 200, dao: db.courseColorDao, gids: gids)
        XCTAssertEqual(a, b, "同 (anchor, gids) 两次重算逐 bit 相等(手动重排按钮可依赖)")
    }

    func testRecalcEmptyGidListWritesNothing() throws {
        let db = try makeDb()
        let plan = CourseColorWriteGlue.recalcWithAnchor(anchor: 280, dao: db.courseColorDao, gids: [])
        XCTAssertTrue(plan.isEmpty)
        let written = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertTrue(written.isEmpty)
    }

    // ═══════════════════════════════════════════════════════════════
    // B. CourseColorPersistedHueTest — 渲染层契约
    // ═══════════════════════════════════════════════════════════════

    // ───────── 1. CLASSIC 零变化 ─────────

    func testClassicPathNullPersistedHueEqualsStableHueV1_0_61() {
        for gid in ["grp-A", "grp-B", "英语", "物理实验", "0"] {
            let c = course(groupId: gid)
            let legacy = CourseColorUtil.pickCourseColorSwiftUI(c, isDark: false,
                                                                neutralColor: neutral, colorless: false)
            let withNull = CourseColorUtil.pickCourseColorSwiftUI(c, isDark: false,
                                                                 neutralColor: neutral, colorless: false,
                                                                 persistedHue: nil)
            XCTAssertTrue(colorsEqual(legacy, withNull), "CLASSIC 渲染必须与 stableHue 实时算逐值相等")
            XCTAssertTrue(colorsEqual(CourseColorUtil.hslToColor(CourseColorUtil.stableHue(gid), 0.55, 0.82),
                                      withNull),
                          "默认档 hue/S/L 钉死 v1.0.61")
        }
    }

    func testClassicCanvasPathNullPersistedHueEqualsStableHue() {
        let gid = "grp-X"
        let c = course(groupId: gid)
        let legacy = CourseColorUtil.pickCourseColorInt(c, isDark: true,
                                                        neutralColorInt: 0xFF112233, colorless: false)
        let withNull = CourseColorUtil.pickCourseColorInt(c, isDark: true,
                                                          neutralColorInt: 0xFF112233, colorless: false,
                                                          persistedHue: nil)
        XCTAssertEqual(legacy, withNull)
        XCTAssertEqual(CourseColorUtil.hslToColorInt(CourseColorUtil.stableHue(gid), 0.40, 0.28), withNull)
    }

    func testWithGroupRowsClassicUnchangedByNull() {
        let rows = [
            groupRow(1, color: "#FF6750A4", mode: CourseColorMode.GROUP),
            groupRow(2, color: "", mode: CourseColorMode.AUTO)
        ]
        let legacy = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(rows[0], groupRows: rows,
                                                                        isDark: false, neutralColor: neutral)
        let withNull = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(rows[0], groupRows: rows,
                                                                           isDark: false, neutralColor: neutral,
                                                                           colorless: false, persistedHue: nil)
        XCTAssertTrue(colorsEqual(legacy, withNull))
        let autoLegacy = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(rows[1], groupRows: rows,
                                                                            isDark: false, neutralColor: neutral)
        let autoWithNull = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(rows[1], groupRows: rows,
                                                                               isDark: false, neutralColor: neutral,
                                                                               colorless: false, persistedHue: nil)
        XCTAssertTrue(colorsEqual(autoLegacy, autoWithNull))
    }

    // ───────── 2. persistedHue 注入 + 明暗只切 S/L ─────────

    func testPersistedHueOverridesStableHueInDerivedMode() {
        let c = course(groupId: "grp-A")
        let persisted: Float = 100
        let derived = CourseColorUtil.pickCourseColorSwiftUI(c, isDark: false, neutralColor: neutral,
                                                            colorless: false, persistedHue: persisted)
        let classic = CourseColorUtil.pickCourseColorSwiftUI(c, isDark: false, neutralColor: neutral,
                                                            colorless: false)
        XCTAssertFalse(colorsEqual(classic, derived), "派生档 persistedHue 必须覆盖实时 stableHue")
        XCTAssertTrue(colorsEqual(CourseColorUtil.hslToColor(persisted, 0.55, 0.82), derived))
    }

    func testPersistedHueDarkFlipOnlySLChangesHueConstant() {
        let c = course(groupId: "grp-A")
        let persisted: Float = 233
        let light = CourseColorUtil.pickCourseColorSwiftUI(c, isDark: false, neutralColor: neutral,
                                                           colorless: false, persistedHue: persisted)
        let dark = CourseColorUtil.pickCourseColorSwiftUI(c, isDark: true, neutralColor: neutral,
                                                          colorless: false, persistedHue: persisted)
        XCTAssertTrue(colorsEqual(CourseColorUtil.hslToColor(persisted, 0.55, 0.82), light))
        XCTAssertTrue(colorsEqual(CourseColorUtil.hslToColor(persisted, 0.40, 0.28), dark))
        // hue 跨深浅恒定:容差 0.5° = HSL→8bit RGB 量化抖动的物理上限
        XCTAssertEqual(CourseColorUtil.hueOf(light), CourseColorUtil.hueOf(dark), accuracy: 0.5)
    }

    func testCustomCourseColorStillWinsOverPersistedHue() {
        let custom = course(color: "#FF5722", groupId: "grp-A")
        let r = CourseColorUtil.pickCourseColorSwiftUI(custom, isDark: false, neutralColor: neutral,
                                                       colorless: false, persistedHue: 100)
        XCTAssertFalse(colorsEqual(CourseColorUtil.hslToColor(100, 0.55, 0.82), r),
                       "自定义色不得被 persistedHue 覆盖")
    }

    func testColorlessStillWinsOverPersistedHue() {
        let c = course(groupId: "grp-A")
        let r = CourseColorUtil.pickCourseColorSwiftUI(c, isDark: false, neutralColor: neutral,
                                                       colorless: true, persistedHue: 100)
        XCTAssertTrue(colorsEqual(neutral, r), "colorless=true 必须回 neutral, 不消费 persistedHue")
        let ri = CourseColorUtil.pickCourseColorInt(c, isDark: false, neutralColorInt: 0xFF112233,
                                                    colorless: true, persistedHue: 100)
        XCTAssertEqual(0xFF112233, ri)
    }

    func testWithGroupRowsAutoBaseHueFollowsPersistedHueWhenPresent() {
        let rows = [
            groupRow(1, color: "#FF6750A4", mode: CourseColorMode.GROUP),
            groupRow(2, color: "", mode: CourseColorMode.AUTO),
            groupRow(3, color: "", mode: CourseColorMode.AUTO)
        ]
        let persisted: Float = 70
        let c2 = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(rows[1], groupRows: rows,
                                                                    isDark: false, neutralColor: neutral,
                                                                    colorless: false, persistedHue: persisted)
        let c3 = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(rows[2], groupRows: rows,
                                                                    isDark: false, neutralColor: neutral,
                                                                    colorless: false, persistedHue: persisted)
        // idx1 = 70 + 137.508 = 207.508; idx2 = 70 + 275.016 = 345.016(mod 360)
        XCTAssertTrue(colorsEqual(CourseColorUtil.hslToColor(207.508, 0.55, 0.82), c2))
        XCTAssertTrue(colorsEqual(CourseColorUtil.hslToColor(345.016, 0.55, 0.82), c3))
        let c1 = CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(rows[0], groupRows: rows,
                                                                    isDark: false, neutralColor: neutral,
                                                                    colorless: false, persistedHue: persisted)
        XCTAssertTrue(colorsEqual(CourseColorUtil.hslToColor(persisted, 0.55, 0.82), c1))
    }

    // ───────── 3. resolveAnchor 三档决策 + 三路径一致 ─────────

    func testResolveAnchorClassicIsNil() {
        XCTAssertNil(CourseColorUtil.resolveAnchor(mode: AppPrefs.COURSE_COLOR_MODE_CLASSIC,
                                                   themePrimaryArgb: 0xFF6750A4, seedHue: 120))
    }

    func testResolveAnchorFollowThemeUsesThemePrimaryHue() {
        let themePurple = 0xFF6750A4
        let anchor = CourseColorUtil.resolveAnchor(mode: AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME,
                                                  themePrimaryArgb: themePurple, seedHue: -1)
        XCTAssertNotNil(anchor)
        XCTAssertEqual(CourseColorUtil.hueOf(themePurple), anchor!, accuracy: 0.001)
    }

    func testResolveAnchorCustomUsesSeedButFallsBackToThemeWhenUnset() {
        let themePurple = 0xFF6750A4
        let seeded = CourseColorUtil.resolveAnchor(mode: AppPrefs.COURSE_COLOR_MODE_CUSTOM,
                                                   themePrimaryArgb: themePurple, seedHue: 300)
        XCTAssertNotNil(seeded)
        XCTAssertEqual(300, seeded!, accuracy: 0.001)
        // seed 未初始化(-1) → 回落主题 hue(升级首进 CUSTOM 无种子不得崩/不得回 0 红)
        let fallback = CourseColorUtil.resolveAnchor(mode: AppPrefs.COURSE_COLOR_MODE_CUSTOM,
                                                     themePrimaryArgb: themePurple,
                                                     seedHue: AppPrefs.COURSE_COLOR_SEED_UNSET)
        XCTAssertNotNil(fallback)
        XCTAssertEqual(CourseColorUtil.hueOf(themePurple), fallback!, accuracy: 0.001)
    }

    func testHueOfIntAndColorPathsAgree() {
        let argb = 0xFF6750A4
        let color = Color(uiArgb: 0xFF6750A4)
        XCTAssertEqual(CourseColorUtil.hueOf(argb), CourseColorUtil.hueOf(color), accuracy: 1.5)
        let h = CourseColorUtil.hueOf(color)
        XCTAssertTrue((0...360).contains(h), "anchor 必须在 [0,360)")
    }

    // ───────── 4. AppPrefs 新键字面量稳定 ─────────

    func testCourseColorModeKeysAreStableLiterals() {
        XCTAssertEqual("course_color_mode", AppPrefs.KEY_COURSE_COLOR_MODE)
        XCTAssertEqual("course_color_seed_hue", AppPrefs.KEY_COURSE_COLOR_SEED_HUE)
        XCTAssertEqual(0, AppPrefs.COURSE_COLOR_MODE_CLASSIC)
        XCTAssertEqual(1, AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME)
        XCTAssertEqual(2, AppPrefs.COURSE_COLOR_MODE_CUSTOM)
        XCTAssertEqual(-1, AppPrefs.COURSE_COLOR_SEED_UNSET, accuracy: 0)
    }

    // ───────── 5. 写侧胶水与真 DAO 的落库闭环 ─────────

    // 「既有组」口径 = **已在 course_colors 表内** 的组(原版本 persistNewGroupHues
    // 的 `filter { it !in persisted }`), 不是「本次实体列表里出现过」的组。
    // 导入时同批既含旧组又含新组 → 旧组若已在表内则零写, 新组补色。
    func testPersistNewGroupHuesWritesOnlyGroupsAbsentFromTableAndIsIdempotent() throws {
        let db = try makeDb()
        let suite = UserDefaults(suiteName: "test-course-color-glue-\(UUID().uuidString)")!
        let prefs = AppPrefs(defaults: suite)
        prefs.setCourseColorMode(AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME)

        // 预置:old-gid 已在表内(既有组)
        let existing = course(groupId: "old-gid", id: 1)
        let fresh = course(groupId: "new-gid", id: 2)
        try db.courseColorDao.upsert(CourseColorEntity(tableKey: CourseColorEntity.globalTableKey,
                                                       groupId: "old-gid", hue: 42.0))

        let first = CourseColorWriteGlue.persistNewGroupHues(dao: db.courseColorDao,
                                                             entities: [existing, fresh], prefs: prefs)
        XCTAssertEqual(Set(["new-gid"]), Set(first.keys), "既有组不被胶水移动, 只给新组补色")

        let map = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertEqual(Set(["old-gid", "new-gid"]), Set(map.keys))
        XCTAssertEqual(42.0, map["old-gid"] ?? -1, accuracy: 0.001, "既有组 hue 零移动")
        XCTAssertEqual(first["new-gid"], map["new-gid"])

        // 二次调用:新组已在表内 → 零写
        let second = CourseColorWriteGlue.persistNewGroupHues(dao: db.courseColorDao,
                                                              entities: [existing, fresh], prefs: prefs)
        XCTAssertTrue(second.isEmpty, "已在表内的组不重复补色")
    }

    /// 首次导入(表空):本批全部 gid 都是新组 → 全部补色(原版本 同语义)。
    func testPersistNewGroupHuesFirstImportFillsEveryGroupInBatch() throws {
        let db = try makeDb()
        let suite = UserDefaults(suiteName: "test-course-color-glue-first-\(UUID().uuidString)")!
        let prefs = AppPrefs(defaults: suite)
        prefs.setCourseColorMode(AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME)

        let entities = [course(groupId: "g1", id: 1), course(groupId: "g2", id: 2)]
        let plan = CourseColorWriteGlue.persistNewGroupHues(dao: db.courseColorDao,
                                                            entities: entities, prefs: prefs)
        XCTAssertEqual(Set(["g1", "g2"]), Set(plan.keys), "表空时本批全部补色")

        let map = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertEqual(Set(["g1", "g2"]), Set(map.keys))
    }

    func testPersistNewGroupHuesWritesNothingInClassicMode() throws {
        let db = try makeDb()
        let suite = UserDefaults(suiteName: "test-course-color-classic-\(UUID().uuidString)")!
        let prefs = AppPrefs(defaults: suite)
        prefs.setCourseColorMode(AppPrefs.COURSE_COLOR_MODE_CLASSIC)

        let plan = CourseColorWriteGlue.persistNewGroupHues(dao: db.courseColorDao,
                                                            entities: [course(groupId: "g1")], prefs: prefs)
        XCTAssertTrue(plan.isEmpty, "CLASSIC 档绝不写表(升级零变化)")
        let map = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertTrue(map.isEmpty)
    }

    func testRecalcAllUsesPersistedModeAndReplacesAllRows() throws {
        let db = try makeDb()
        let suite = UserDefaults(suiteName: "test-course-color-recalc-all-\(UUID().uuidString)")!
        let prefs = AppPrefs(defaults: suite)
        prefs.setCourseColorMode(AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME)

        let n = CourseColorWriteGlue.recalcAll(dao: db.courseColorDao,
                                               gids: ["g1", "g2", "g3"], prefs: prefs)
        XCTAssertEqual(3, n, "派生档重算应覆盖全部 gid")
        let map = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertEqual(3, map.count)
    }

    func testRecalcAllIsZeroWriteInClassicMode() throws {
        let db = try makeDb()
        let suite = UserDefaults(suiteName: "test-course-color-recalc-classic-\(UUID().uuidString)")!
        let prefs = AppPrefs(defaults: suite)
        prefs.setCourseColorMode(AppPrefs.COURSE_COLOR_MODE_CLASSIC)
        let n = CourseColorWriteGlue.recalcAll(dao: db.courseColorDao,
                                               gids: ["g1", "g2"], prefs: prefs)
        XCTAssertEqual(0, n)
        let map = try db.courseColorDao.getHueMap(CourseColorEntity.globalTableKey)
        XCTAssertTrue(map.isEmpty)
    }
}
