// WidgetLogicTests.swift — G4 链条测试: widget 渲染数据层
// VerticalNameTokenizer(v21 竖排 token 化) / parseTimeSlots / WidgetTableResolver /
// WidgetLoader loadDataSync 全链(DB→resolver→过滤→排序)。

import XCTest
import WidgetKit
@testable import Sleepy

final class WidgetLogicTests: XCTestCase {

    // ==================== VerticalNameTokenizer ====================

    // 纯 CJK → 单 CJK token
    func testTokenizePureCjk() {
        let tokens = VerticalNameTokenizer.tokenize("高等数学", useVertForms: false)
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].type, .cjk)
        XCTAssertEqual(tokens[0].text, "高等数学")
    }

    // Latin run≥2 → 单 LATIN token(整组旋转)
    func testTokenizeLatinRun() {
        let tokens = VerticalNameTokenizer.tokenize("英语AB课", useVertForms: false)
        XCTAssertEqual(tokens.count, 3)
        XCTAssertEqual(tokens[0].type, .cjk)   // 英语
        XCTAssertEqual(tokens[1].type, .latin) // AB (run≥2 保持 LATIN)
        XCTAssertEqual(tokens[1].text, "AB")
        XCTAssertEqual(tokens[2].type, .cjk)   // 课
    }

    // Latin run=1 → 改判 CJK(直立)
    func testTokenizeSingleLatinUpright() {
        let tokens = VerticalNameTokenizer.tokenize("数学B", useVertForms: false)
        XCTAssertEqual(tokens.count, 2)
        XCTAssertEqual(tokens[0].type, .cjk)
        XCTAssertEqual(tokens[1].type, .cjk)  // B 单字符 → 直立
        XCTAssertEqual(tokens[1].text, "B")
    }

    // 标点方案A': 保持原样, 归 PUNCT
    func testTokenizePunctPlanA() {
        let tokens = VerticalNameTokenizer.tokenize("体育(二)", useVertForms: false)
        // 体育 CJK / ( PUNCT / 二 CJK / ) PUNCT
        XCTAssertEqual(tokens.map(\.type), [.cjk, .punct, .cjk, .punct])
    }

    // 标点方案B: 替换 Vertical Forms → 归 CJK 直立
    func testTokenizePunctPlanB() {
        let tokens = VerticalNameTokenizer.tokenize("体育(二)", useVertForms: true)
        // ( → ︵(U+FE35), 归 CJK
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(tokens[0].type, .cjk)
        XCTAssertTrue(tokens[0].text.contains("︵"))
        XCTAssertFalse(tokens[0].text.contains("("))
    }

    // 去空白(空格/换行)
    func testTokenizeStripsWhitespace() {
        let tokens = VerticalNameTokenizer.tokenize("大学 物理\n基础", useVertForms: false)
        XCTAssertEqual(tokens.flatMap { Array($0.text) }, ["大", "学", "物", "理", "基", "础"])
    }

    // 空串 → 空
    func testTokenizeEmpty() {
        XCTAssertTrue(VerticalNameTokenizer.tokenize("", useVertForms: false).isEmpty)
        XCTAssertTrue(VerticalNameTokenizer.tokenize("  \n ", useVertForms: false).isEmpty)
    }

    // unitHeight: CJK 每字 1.0 (直立逐字); LATIN/PUNCT 走真实 measureText
    // (measureUnitHeight 探针, 拉丁组高 = 实测组宽 / 1pt 探针字号)。
    // WeekGrid v1.0.61 对齐后弃用旧的固定系数 (latin 0.55 / punct 0.5) — 那些是
    // SwiftUI 无 measureText 时的近似, 现已有 UIKit NSString 实测口径。
    func testUnitHeight() {
        let cjk = VerticalNameTokenizer.tokenize("高数", useVertForms: false)
        XCTAssertEqual(VerticalNameTokenizer.unitHeight(cjk), 2.0)
        // 拉丁组 "AB" 旋转后占高 = 实测宽度比值; 1pt 探针下 "AB" 宽 ≈ 1.4pt → 单位高 ≈ 1.4
        // (非旧固定 1.1)。锁「实测 > 0 且落在合理区间」而非具体系数, 避免字体度量漂移脆断。
        let latin = [NameToken(type: .latin, text: "AB")]
        let lh = VerticalNameTokenizer.unitHeight(latin)
        XCTAssertGreaterThan(lh, 0)
        XCTAssertGreaterThan(lh, 1.1, "拉丁组高应为真实测量值, 大于旧固定系数 1.1")
        XCTAssertLessThan(lh, 3.0, "拉丁组高不应异常膨胀")
        // 标点同走实测
        let punct = [NameToken(type: .punct, text: "·")]
        XCTAssertGreaterThan(VerticalNameTokenizer.unitHeight(punct), 0)
    }

    // greedyDraw: 高度充足 → 全部保留
    func testGreedyDrawFitsAll() {
        let tokens = VerticalNameTokenizer.tokenize("高数", useVertForms: false)
        let drawn = VerticalNameTokenizer.greedyDraw(tokens: tokens, charSize: 10, nameAvailH: 100)
        XCTAssertEqual(drawn.count, 2)
        XCTAssertEqual(drawn[0].text, "高")
        XCTAssertEqual(drawn[0].h, 10)
    }

    // greedyDraw: 高度不够 → 截断 + 省略号
    func testGreedyDrawTruncates() {
        let tokens = VerticalNameTokenizer.tokenize("高等数学", useVertForms: false)
        // 25 高度: 高(10)+等(20) 放下, 数(30>25) 截断 → 腾省略号(20+10>25 → 移除等) → 高+…
        let drawn = VerticalNameTokenizer.greedyDraw(tokens: tokens, charSize: 10, nameAvailH: 25)
        XCTAssertEqual(drawn.count, 2)
        XCTAssertEqual(drawn[0].text, "高")
        XCTAssertEqual(drawn.last?.text, "…")
    }

    // greedyDraw: 连一个字都放不下 → 缩放首字(极端矮卡)
    func testGreedyDrawExtremeShort() {
        let tokens = VerticalNameTokenizer.tokenize("高数", useVertForms: false)
        let drawn = VerticalNameTokenizer.greedyDraw(tokens: tokens, charSize: 10, nameAvailH: 4)
        XCTAssertEqual(drawn.count, 1)
        XCTAssertEqual(drawn[0].text, "高")
        XCTAssertEqual(drawn[0].size, 4)  // 缩放至 nameAvailH
    }

    // ==================== timeSlotsFor (原 parseTimeSlots 消费面) ====================

    func testParseTimeSlotsValidJson() {
        let json = #"[{"start":"08:00","end":"08:45"},{"start":"08:55","end":"09:40"}]"#
        let slots = TimeTableUtils.timeSlotsFor(timeJson: json)
        XCTAssertEqual(slots.map(\.start), ["08:00", "08:55"])
        XCTAssertEqual(slots.map(\.end), ["08:45", "09:40"])
    }

    /// WeekGrid 对齐 v1.0.61 后 slots 口径 = 原版本 timeSlotsFor:
    /// 非法/空 → 空数组 (旧入口的「回退默认 12 节」是 iOS 私有语义, 原版本 无此分支,
    /// 已随 parseTimeSlots 移除; 默认 12 节兜底语义由 parseTimeSlotRows (编辑面) 承担)
    func testParseTimeSlotsInvalidFallsBackToEmpty() {
        XCTAssertEqual(TimeTableUtils.timeSlotsFor(timeJson: "not json"), [])
    }

    // ==================== WidgetTableResolver(默认表优先链) ====================

    // 默认表有课 → 选默认表
    func testResolverPrefersDefaultWithCourses() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        let t1 = try repo.insertTable(TimeTableEntity(name: "主表", startDate: "2026-08-24", timeJson: TimeTableUtils.DEFAULT_TIME_JSON, isDefault: true))
        let t2 = try repo.insertTable(TimeTableEntity(name: "副表", startDate: "2026-08-24", timeJson: TimeTableUtils.DEFAULT_TIME_JSON, isDefault: false))
        try repo.insertCourse(makeCourse(t2, "课A", startNode: 1))
        try repo.insertCourse(makeCourse(t2, "课B", startNode: 3))
        // 默认表无课 → 回退课程数最多的表
        XCTAssertEqual(WidgetTableResolver.resolveCurrentTable(repo)?.id, t2)
        try repo.insertCourse(makeCourse(t1, "课C", startNode: 1))
        // 默认表有课 → 选它(尽管课程更少)
        XCTAssertEqual(WidgetTableResolver.resolveCurrentTable(repo)?.id, t1)
    }

    // 无任何课 → nil(widget 显示"请先创建课表")
    func testResolverNilWhenNoCourses() throws {
        let db = try AppDatabase.inMemory()
        let repo = ScheduleRepository(db)
        _ = try repo.insertTable(TimeTableEntity(name: "空表", startDate: "2026-08-24", timeJson: TimeTableUtils.DEFAULT_TIME_JSON, isDefault: true))
        XCTAssertNil(WidgetTableResolver.resolveCurrentTable(repo))
    }

    // ==================== WidgetEditCompactWindowSection.appliesTo(三天窗口族门控) ====================
    // ← 原 WidgetCompactWindowCoreTest `appliesTo only matches the two small
    //   week receivers` (L50-58): 仅 WeekList/WeekView 两族的「· 小」档显示本节,
    //   其余族与小/中/大其它档与未知族(nil)全部 false。锁死防止族门控漂移。

    func testCompactWindowAppliesToOnlyWeekListAndWeekViewSmall() {
        // 5 个 iOS kind × {systemSmall, systemMedium, systemLarge, nil} 全矩阵
        let kinds = ["WeekGridWidgetV19", "TodayWidgetRV", "WeekListWidgetRV",
                     "WeekViewWidgetRV", "TwoDayWidgetRV"]
        let expectedTrue: Set<String> = ["WeekListWidgetRV", "WeekViewWidgetRV"]
        for kind in kinds {
            XCTAssertEqual(
                WidgetEditCompactWindowSection.appliesTo(kind: kind, family: .systemSmall),
                expectedTrue.contains(kind),
                "systemSmall gate wrong for \(kind)"
            )
            for family in [WidgetFamily.systemMedium, .systemLarge] {
                XCTAssertFalse(
                    WidgetEditCompactWindowSection.appliesTo(kind: kind, family: family),
                    "\(kind) on non-small family must hide the section"
                )
            }
            XCTAssertFalse(
                WidgetEditCompactWindowSection.appliesTo(kind: kind, family: nil),
                "\(kind) with unknown family must hide the section (原 null→false)"
            )
        }
    }

    // ==================== WidgetEditCore.displayBinding(哨兵 0 → 默认选中) ====================
    // ← 原 WidgetEditCoreTest L140-161: 首装哨兵 0/非正值/缺失 → nil
    //   (=「默认」行选中); 正值原样。makeWidgetEditScope 已接此函数, 此处锁语义。

    func testDisplayBindingSentinelAndPositive() {
        XCTAssertNil(WidgetEditCore.displayBinding(nil))
        XCTAssertNil(WidgetEditCore.displayBinding(0), "first-add sentinel → follow default")
        XCTAssertNil(WidgetEditCore.displayBinding(-3), "non-positive → follow default")
        XCTAssertEqual(WidgetEditCore.displayBinding(7), 7, "explicit binding preserved")
    }

    // ==================== helpers ====================

    private func makeCourse(_ tableId: Int64, _ name: String, startNode: Int,
                            startWeek: Int = 1, endWeek: Int = 20) -> CourseEntity {
        CourseEntity(
            groupId: name,
            tableId: tableId,
            courseName: name,
            teacher: "师",
            room: "A101",
            day: DateUtils.todayDayOfWeek(today: Date()),
            startNode: startNode, step: 2,
            startWeek: startWeek, endWeek: endWeek, type: 0,
            color: "#FF6750A4",
            id: 0
        )
    }
}
