// WidgetLogicTests.swift — G4 链条测试: widget 渲染数据层
// VerticalNameTokenizer(v21 竖排 token 化) / parseTimeSlots / WidgetTableResolver /
// WidgetLoader loadDataSync 全链(DB→resolver→过滤→排序)。

import XCTest
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

    // unitHeight: CJK 每字 1.0 / LATIN 每字 0.55 / PUNCT 每字 0.5
    func testUnitHeight() {
        let cjk = VerticalNameTokenizer.tokenize("高数", useVertForms: false)
        XCTAssertEqual(VerticalNameTokenizer.unitHeight(cjk), 2.0)
        let latin = [NameToken(type: .latin, text: "AB")]
        XCTAssertEqual(VerticalNameTokenizer.unitHeight(latin), 1.1, accuracy: 0.001)
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

    // ==================== parseTimeSlots ====================

    func testParseTimeSlotsValidJson() {
        let json = #"[{"start":"08:00","end":"08:45"},{"start":"08:55","end":"09:40"}]"#
        XCTAssertEqual(WeekGridWidgetEntryView.parseTimeSlots(json), ["08:00", "08:55"])
    }

    func testParseTimeSlotsInvalidFallsBackTo12() {
        let slots = WeekGridWidgetEntryView.parseTimeSlots("not json")
        XCTAssertEqual(slots.count, 12)
        XCTAssertEqual(slots.first, "08:00")
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
