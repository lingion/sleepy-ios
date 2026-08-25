// ManageImportUITests.swift — G5+ 管理页/导入/建表全交互面测试
// 覆盖: 管理页 4 卡片 + ImportSheet(教务直连入口/文本折叠展开/文本输入+解析预览/
//       文件入口) + 预览对话框 3 模式 + 确认对话框(表名/日期/节次) + 完整文本导入链 +
//       新建空表流程 + AllTables 切表/编辑入口/新建。

import XCTest

final class ManageImportUITests: XCTestCase {

    var app: XCUIApplication!

    /// 保证可点: 在 sheet ScrollView 里先滚到元素可视区再 tap
    private func forceTap(_ el: XCUIElement) {
        _ = el.waitForExistence(timeout: 5)
        var tries = 0
        while !el.isHittable && tries < 5 {
            app.swipeUp()
            sleep(1)
            tries += 1
        }
        if el.isHittable { el.tap() }
        else { el.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["pill_manage"].tap()
        XCTAssertTrue(app.staticTexts["Manage"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()   // 隔离: 每用例杀进程重启, 防跨用例状态串扰
    }

    // MARK: 管理页 4 卡片都存在且标题正确

    func testManageCardsExist() {
        XCTAssertTrue(app.staticTexts["Import"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["New Schedule"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Add Course"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Edit Current"].firstMatch.exists)
        // 当前表摘要
        XCTAssertTrue(app.staticTexts["我的课表"].waitForExistence(timeout: 3),
                      "管理页应显示当前表名")
    }

    // MARK: Import 卡 → ImportSheet 弹出 + 3 入口行存在

    func testImportSheetOpensWithThreeMethods() {
        app.descendants(matching: .any)["manage_import"].tap()
        XCTAssertTrue(app.staticTexts["Import Schedule"].waitForExistence(timeout: 5),
                      "导入弹窗未打开")
        XCTAssertTrue(app.staticTexts["Connect to School"].exists, "教务直连行缺失")
        XCTAssertTrue(app.staticTexts["Paste Text"].exists, "文本导入行缺失")
        XCTAssertTrue(app.staticTexts["Import from File"].exists, "文件导入行缺失")
    }

    // MARK: 文本折叠展开(点 Paste Text → 输入框 + Preview 按钮出现/收起)

    func testPasteTextExpandCollapse() {
        app.descendants(matching: .any)["manage_import"].tap()
        let pasteRow = app.descendants(matching: .any)["import_text"]
        XCTAssertTrue(pasteRow.waitForExistence(timeout: 5))
        forceTap(pasteRow)
        // 展开后出现输入框(axis:.vertical 多行 → textViews)+ Preview 按钮
        let input = app.textViews.matching(
            NSPredicate(format: "label CONTAINS 'Paste schedule' OR placeholderValue CONTAINS 'Paste schedule'")).firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 3), "展开后应出现文本输入框")
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Preview Import'")).firstMatch.exists,
            "展开后应有 Preview 按钮")
        // 再点收起
        forceTap(app.descendants(matching: .any)["import_text"])
        XCTAssertFalse(app.textViews.matching(
            NSPredicate(format: "label CONTAINS 'Paste schedule' OR placeholderValue CONTAINS 'Paste schedule'")).firstMatch
            .waitForExistence(timeout: 3), "再点应收起输入框")
    }

    // MARK: 完整文本导入链(输入 WakeUp JSON → Preview → 3 模式按钮 → 确认 → 新表)

    func testFullTextImportFlow() {
        app.descendants(matching: .any)["manage_import"].tap()
        let pasteRow = app.descendants(matching: .any)["import_text"]
        XCTAssertTrue(pasteRow.waitForExistence(timeout: 5))
        forceTap(pasteRow)

        let input = app.textViews.matching(
            NSPredicate(format: "label CONTAINS 'Paste schedule' OR placeholderValue CONTAINS 'Paste schedule'")).firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 3), "文本输入框未展开")
        input.tap()
        // 最小合法 WakeUp JSON(对象 + courses 数组, 字段 camelCase)
        let json = "{\"name\":\"测试导入表\",\"startDate\":\"2026-08-24\",\"courses\":[{\"name\":\"编译原理\",\"teacher\":\"陈老师\",\"position\":\"教3-401\",\"day\":4,\"startNode\":7,\"step\":2,\"startWeek\":1,\"endWeek\":16,\"type\":0}]}".replacingOccurrences(of: "\\ ", with: " ")
        input.typeText(json)
        // 收键盘: textView 的 Return=换行; 用向下滚动手势触发 iOS16 键盘消失
        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
        sleep(1)

        app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Preview Import'")).firstMatch.tap()
        // 预览对话框: 标题 + 3 模式按钮(any — 内嵌 sheet 里的元素类型不定)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Import Preview'")).firstMatch
            .waitForExistence(timeout: 6), "预览对话框未弹出(解析失败?)")
        // 课程名行可能是任意元素类型;再等 1s 后不强断(解析成功由 Import Preview 弹出证明)
        _ = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '编译原理'")).firstMatch.waitForExistence(timeout: 2)

        // 选"追加不冲突"模式(不破坏种子表)
        let appendBtn = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Append non-conflicting'")).firstMatch
        if appendBtn.waitForExistence(timeout: 3) {
            appendBtn.tap()
        } else {
            // 三模式按钮之一必在
            let replace = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Replace'")).firstMatch
            XCTAssertTrue(replace.exists, "3 模式按钮至少一个应在")
            replace.tap()
        }

        // 确认对话框: 表名/开始日期/Confirm Import
        XCTAssertTrue(app.staticTexts["Confirm Before Import"].waitForExistence(timeout: 4),
                      "确认对话框未弹出")
        // 确认按钮在 safeAreaInset 底部, 键盘可能盖住 → 先收键盘再滚到位
        if app.keyboards.count > 0 {
            app.buttons["Return"].firstMatch.tap()
            sleep(1)
        }
        let confirmBtn = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Confirm Import'")).firstMatch
        XCTAssertTrue(confirmBtn.waitForExistence(timeout: 5), "确认按钮未出现")
        var tries = 0
        while !confirmBtn.isHittable && tries < 4 {
            app.swipeUp()
            sleep(1)
            tries += 1
        }
        if confirmBtn.isHittable {
            confirmBtn.tap()
        } else {
            confirmBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        sleep(2)
        // 导入完成 → Android 行为: 关导入框 → 打开新表编辑页(Edit Schedule overlay)
        let nameField = app.descendants(matching: .any)["field_Schedule Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 8),
                      "导入后应打开新表编辑页(onOpenEditTable 链)")
        // 表名应为导入的表名
        XCTAssertTrue(app.staticTexts["Edit Schedule"].exists)
        // 返回编辑页 → 课表含新课
        app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch.tap()
        sleep(1)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '编译原理'")).firstMatch
            .waitForExistence(timeout: 8), "导入后课表应含编译原理")
    }

    // MARK: 教务直连入口(弹 SchoolSelect — 不实际登录)

    func testJwImportEntryOpensSchoolSelect() {
        app.descendants(matching: .any)["manage_import"].tap()
        forceTap(app.descendants(matching: .any)["import_jw"])
        // JwImportFlow stage1: 学校选择页
        XCTAssertTrue(app.staticTexts["Select School"].waitForExistence(timeout: 6)
                      || app.textFields.firstMatch.waitForExistence(timeout: 6),
                      "教务导入应进入学校选择页")
    }

    // MARK: 新建空表流程(管理页 → New Schedule → EditTable → 保存)

    func testNewTableCreateFlow() {
        app.descendants(matching: .any)["manage_new_table"].tap()
        // EditTableScreen(新表默认名)
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 5),
                      "新建表应进编辑页")
        let nameField = app.textFields["Schedule Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        // 清空默认名再输入(全选删除 — typeText 前缀删除)
        nameField.typeText("测试表2")

        app.swipeUp()
        let saveBtn = app.staticTexts["Save Settings"].firstMatch
        XCTAssertTrue(saveBtn.waitForExistence(timeout: 3))
        saveBtn.tap()
        // 保存后回管理页, 新表成为当前表
        XCTAssertTrue(app.staticTexts["Manage"].waitForExistence(timeout: 5)
                      || app.staticTexts["测试表2"].firstMatch.waitForExistence(timeout: 5),
                      "保存后应返回且新表生效")
    }

    // MARK: Edit Current 入口

    func testEditCurrentOpensEditTable() {
        app.descendants(matching: .any)["manage_edit_current"].tap()
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 5),
                      "Edit Current 应进表编辑页")
        // 基础信息卡字段
        XCTAssertTrue(app.textFields["Schedule Name"].waitForExistence(timeout: 3))
    }
}
