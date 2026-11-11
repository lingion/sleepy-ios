// TableSwitchUITests.swift — 表切换/新建/删除全链路测试(AllTables 深挖)
// 导航语义(与 Android v1.0.64 SleepyNavHost 的 navigator.pop() 一致):
//   新建→编辑页; back=discard(pendingNewTableId)→AllTables; save→AllTables;
//   delete→AllTables(根Tab切至Schedule); 行点击非当前表=留在AllTables并更新选中态。
//   删除/切表后回退与刷新由 observeAllTables sink 驱动(异步)。
//   因此动作后重新走 mine_all_tables 进列表复查, 不假设停留页内容。

import XCTest

final class TableSwitchUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: 导航助手

    /// Mine → All Schedules。列表页锚点 = 顶栏返回键(Mine 页无 topbar_back;
    /// 注意 Mine 页入口按钮 label 也是 "All Schedules", 不能用它区分页面)。
    private func openAllTables() {
        app.switchToPillTab("mine")
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5))
        app.buttons["mine_all_tables"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["topbar_back"].waitForExistence(timeout: 5),
                      "未进入 All Schedules 列表页")
    }

    /// 在 AllTables 页新建表+命名+保存，并验证真实父列表及当前表保持。
    private func createNamedTable(_ name: String) {
        app.buttons["New Schedule"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 5),
                      "新建应进表编辑页")
        let nameField = app.descendants(matching: .any)["field_Schedule Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 4), "名称字段应存在")
        nameField.tap()
        // 字段预填自动名("Default N"), typeText 是追加语义(TableEditUITests "-v2" 同源)
        // → 先退格清空再输入, 保证表名恰为 name
        for _ in 0..<15 { nameField.typeText("\u{8}") }
        nameField.typeText(name)
        let named = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", name),
                                             object: nameField)
        XCTAssertEqual(XCTWaiter.wait(for: [named], timeout: 5), .completed)
        app.swipeUp()
        let save = app.descendants(matching: .any)["edit_table_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 4))
        save.tap()
        let savedRow = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'table_select_' AND label == %@", name)).firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 6), "保存后应回到包含新课表的父列表")
        XCTAssertFalse(app.buttons["edit_table_save"].exists)
        assertCurrentTable("我的课表")
        backToMine()
    }

    private func assertCurrentTable(_ name: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let row = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'table_select_' AND label == %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), file: file, line: line)
        let current = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Current · Week'"))
        XCTAssertTrue(current.firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(current.count, 1, file: file, line: line)
        XCTAssertLessThan(abs(current.firstMatch.frame.midY - row.frame.midY), 40,
                          "当前课表必须是指定的同一行", file: file, line: line)
    }

    /// 断言 AllTables 列表包含给定表名, 且恰一行是当前表(唯一 "Current · Week N" 副标题)。
    private func assertList(_ names: [String], current: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        openAllTables()
        for n in names {
            XCTAssertTrue(app.staticTexts[n].firstMatch.waitForExistence(timeout: 4),
                          "表 \"\(n)\" 应在列表", file: file, line: line)
        }
        let currentSubtitles = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Current · Week'"))
        XCTAssertEqual(currentSubtitles.count, 1,
                       "应恰有一个当前表副标题", file: file, line: line)
        // 非当前行显示 Start，当前副标题必须落在指定课表的同一行。
        if names.count > 1 {
            let startSubs = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Start: '"))
            XCTAssertEqual(startSubs.count, names.count - 1,
                           "非当前表应有 Start: 副标题", file: file, line: line)
        }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'" )).count,
                       names.count, "课表集合不得多出临时表", file: file, line: line)
        assertCurrentTable(current, file: file, line: line)
        // 回到 Mine, 保持状态干净
        app.descendants(matching: .any)["topbar_back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5))
    }

    /// 行点击切表(d3200bb ← 原版本 ce7f7924: 选表后留在本页, 选中态就地高亮)。
    /// 断言 "Current · Week" 副标题出现在该表名同一行(y 中心差 < 40 = 就地变当前)。
    private func selectTableRowInPlace(_ name: String) {
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 4), "行 \(name) 不存在")
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["topbar_back"].firstMatch
                        .waitForExistence(timeout: 5),
                      "选表后应仍留在 All Schedules 页(不再强制弹出)")
        let cur = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Current · Week'"))
        let y = row.frame.midY
        XCTAssertTrue(cur.allElementsBoundByIndex.contains { abs($0.frame.midY - y) < 40 },
                      "\"\(name)\" 行应就地变为当前表")
    }

    /// All Schedules 顶栏返回 → Mine。
    private func backToMine() {
        app.descendants(matching: .any)["topbar_back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5),
                      "返回后应在 Mine 页")
    }

    /// 课程可见性锚点(视图模式无关): cards 模式课程名被 Button+SleepyButtonStyle
    /// 合并为 button label, week 模式 DaySummaryCell 是 plain Text(staticText)。
    /// 旧写法 staticTexts[名] 只在 week 树成立 → 起始视图(cards, AppPrefs 默认)
    /// 且无前序用例切 week 时必假阴(2026-10-23 全量腐化根因, AX 树探针实证)。
    /// descendants(.any)+label 谓词覆盖两种树形(ScheduleFlow/ManageImport 同款)。
    private func courseElement(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    // MARK: 1. 新建表不保存 = discard(pendingNewTableId 语义, 原版本 同构)

    func testUnsavedNewTableIsDiscarded() {
        openAllTables()
        app.buttons["New Schedule"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 5))
        // handleBack: pendingNewTableId != nil → discard → AllTables 父列表
        app.descendants(matching: .any)["topbar_back"].firstMatch.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'table_select_' AND label == %@", "我的课表"))
            .firstMatch.waitForExistence(timeout: 6), "discard 后应回 AllTables 父列表")
        XCTAssertFalse(app.buttons["edit_table_save"].exists)
        backToMine()
        // 库中仍只有种子表
        assertList(["我的课表"], current: "我的课表")
    }

    // MARK: 2. 新建保存 → 两行 → 切换 → 选中态迁移 + Schedule 数据联动

    func testCreateSaveSwitchAndDataBinding() {
        openAllTables()
        // 种子表是当前: 唯一 "Current · Week" 副标题
        let cur = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Current · Week'"))
        XCTAssertTrue(cur.firstMatch.waitForExistence(timeout: 4), "种子表应为当前表")
        XCTAssertEqual(cur.count, 1)

        createNamedTable("B表")
        // 保存后重进: 两行, 种子表仍当前(commitSelection:false 不切选中)
        assertList(["我的课表", "B表"], current: "我的课表")

        // 切换到 B表: 行点击 → 就地高亮(d3200bb 起不再弹回 Mine), 选中态迁移到 B表
        openAllTables()
        selectTableRowInPlace("B表")

        // 数据联动: B表 无课 → 离开 AllTables 回 Mine → Schedule 页不再显示种子课程
        backToMine()
        app.switchToPillTab("schedule")
        XCTAssertFalse(courseElement("高等数学").waitForExistence(timeout: 3),
                       "切到空表 B表 后 Schedule 不应显示种子课程")
        // 切回种子表, 课程恢复(就地选表 → 回 Mine → 手动回 Schedule)
        openAllTables()
        selectTableRowInPlace("我的课表")
        backToMine()
        app.switchToPillTab("schedule")
        XCTAssertTrue(courseElement("高等数学").waitForExistence(timeout: 8),
                      "切回种子表后课程应恢复")
    }

    // MARK: 3. 删除非当前表 → 父列表 → 返回 Schedule 并验证原课程

    func testDeleteNonDefaultTableFallsBackToDefault() {
        openAllTables()
        createNamedTable("C表")
        openAllTables()
        // 两行, C表 非当前
        XCTAssertTrue(app.staticTexts["C表"].firstMatch.waitForExistence(timeout: 4))
        // 进 C表 编辑页: 齿轮 identifier = table_edit_<id>。SwiftUI 嵌套 Button 会让
        // 同一齿轮在层级里重复出现, boundBy 索引不稳 → 按 y 坐标匹配 C表 所在行的齿轮。
        let gears = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'table_edit_'"))
        XCTAssertTrue(gears.firstMatch.waitForExistence(timeout: 4), "应有编辑入口")
        let cText = app.staticTexts["C表"].firstMatch
        XCTAssertTrue(cText.waitForExistence(timeout: 3))
        let cY = cText.frame.midY
        // 嵌套 Button 会让齿轮在层级里重复出现 → 按 y 坐标匹配 C表 所在行的齿轮
        let target = gears.allElementsBoundByIndex.first {
            abs($0.frame.midY - cY) < 40
        }
        XCTAssertTrue(target != nil, "未找到 C表 行的编辑入口")
        target?.tap()
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 5),
                      "齿轮应打开 C表 编辑页")
        let nf = app.descendants(matching: .any)["field_Schedule Name"]
        XCTAssertTrue(nf.waitForExistence(timeout: 3))
        XCTAssertEqual((nf.value as? String) ?? "", "C表", "应打开的是 C表")

        // 删除 → 确认
        app.swipeUp()
        let delete = app.descendants(matching: .any)["edit_table_delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 4))
        delete.tap()
        XCTAssertTrue(app.staticTexts["Confirm Delete"].waitForExistence(timeout: 3))
        let delBtn = app.buttons.matching(NSPredicate(format: "label == 'Delete'")).firstMatch
        XCTAssertTrue(delBtn.waitForExistence(timeout: 3))
        delBtn.tap()
        // onDeleted: pop 回真实父列表，根Tab切至Schedule；返回后检查课程联动。
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'table_select_' AND label == %@", "我的课表"))
            .firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["C表"].exists)
        XCTAssertFalse(app.buttons["edit_table_save"].exists)
        assertCurrentTable("我的课表")
        app.buttons["topbar_back"].tap()
        XCTAssertTrue(courseElement("高等数学").waitForExistence(timeout: 8),
                      "删除 C表 后应回退默认表, 课程恢复")
        // 列表只剩种子表
        assertList(["我的课表"], current: "我的课表")
    }
}
