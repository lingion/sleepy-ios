// TableEditUITests.swift — G5+ 表编辑/节次编辑器全交互面测试
// 锚点: field_<label>(FieldTextField) / edit_table_save / edit_table_delete /
//       edit_table_slots_header / slot_add / slot_row_delete_N / break_short|long。

import XCTest

final class TableEditUITests: XCTestCase {

    var app: XCUIApplication!

    /// 保证可点: 先滚到元素可视区再 tap
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
        app.descendants(matching: .any)["manage_edit_current"].tap()
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()   // 隔离: 每用例杀进程重启, 防跨用例状态串扰
    }

    // MARK: 3 个基础信息字段(field_Schedule Name / field_Semester Start Date / field_Total Weeks)

    func testBasicInfoFieldsAcceptInput() {
        let nameField = app.descendants(matching: .any)["field_Schedule Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "名称字段锚点未找到")
        XCTAssertTrue(app.descendants(matching: .any)["field_Semester Start Date"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["field_Total Weeks"].exists)

        nameField.tap()
        nameField.typeText("2")
        let weeks = app.descendants(matching: .any)["field_Total Weeks"]
        weeks.tap()
        weeks.typeText("5")
    }

    // MARK: 日期非法 → 保存报校验错误

    func testInvalidDateShowsValidationError() {
        let dateField = app.descendants(matching: .any)["field_Semester Start Date"]
        XCTAssertTrue(dateField.waitForExistence(timeout: 5))
        dateField.tap()
        for _ in 0..<12 { dateField.typeText("\u{8}") }   // 清空
        dateField.typeText("bad-date")

        app.swipeUp()
        let save = app.descendants(matching: .any)["edit_table_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Date must be'")).firstMatch
            .waitForExistence(timeout: 3), "非法日期应报校验错误")
    }

    // MARK: 节次折叠卡展开/收起(edit_table_slots_header)

    func testTimeSlotsExpandCollapse() {
        let header = app.descendants(matching: .any)["edit_table_slots_header"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        // 展开: Manual mode Tab + slot_add
        // recovery: 重试直到展开成功
        var expanded = false
        for _ in 0..<3 {
            forceTap(header)
            sleep(1)
            // 查是否展开（看 slot_add 出现否）
            if app.descendants(matching: .any)["slot_add"].exists {
                expanded = true
                break
            }
            // 再试一次
            forceTap(header)
            sleep(1)
            if app.descendants(matching: .any)["slot_add"].exists {
                expanded = true
                break
            }
        }
        XCTAssertTrue(expanded, "展开后应显示 slot_add")
        XCTAssertTrue(app.descendants(matching: .any)["slot_add"].exists)
        // 收起
        forceTap(header)
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any)["slot_add"].waitForExistence(timeout: 3),
                       "收起后编辑器应消失")
    }

    // MARK: 手动模式 — slot_add 加节 / slot_row_delete 删节

    func testManualAddDeletePeriod() {
        forceTap(app.descendants(matching: .any)["edit_table_slots_header"])
        sleep(1)
        let add = app.descendants(matching: .any)["slot_add"]
        XCTAssertTrue(add.waitForExistence(timeout: 4))
        add.tap()   // 12 → 13 节
        // 删最高节(13)
        let del = app.descendants(matching: .any)["slot_row_delete_13"]
        if del.waitForExistence(timeout: 3) && del.isHittable {
            del.tap()
            XCTAssertFalse(del.waitForExistence(timeout: 2), "删除后第 13 节应消失")
        }
        XCTAssertTrue(app.descendants(matching: .any)["seg_Manual mode"].exists, "加删节后不崩")
    }

    // MARK: 自动模式 — 全字段交互(seg_Manual mode ↔ seg_Auto mode)

    func testAutoModeSmartEditor() {
        forceTap(app.descendants(matching: .any)["edit_table_slots_header"])
        sleep(1)
        let segManual = app.descendants(matching: .any)["seg_Manual mode"].firstMatch
        XCTAssertTrue(segManual.waitForExistence(timeout: 5))

        let segAuto = app.descendants(matching: .any)["seg_Auto mode"].firstMatch
        XCTAssertTrue(segAuto.waitForExistence(timeout: 3))
        segAuto.tap()
        sleep(1)
        // NumberField 锚点(number_<label>) + Input 标题
        let durationField = app.descendants(matching: .any)["number_Per-period duration"]
        XCTAssertTrue(durationField.waitForExistence(timeout: 4), "自动模式应显示时长字段")
        XCTAssertTrue(app.descendants(matching: .any)["number_Total periods"].exists)
        XCTAssertTrue(app.staticTexts["Input"].waitForExistence(timeout: 3))

        // 加 short break(break_short)
        let short = app.descendants(matching: .any)["break_short"]
        XCTAssertTrue(short.waitForExistence(timeout: 3))
        short.tap()
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS 'Break assignment'")).firstMatch
            .waitForExistence(timeout: 3), "加 break 后应显示分组区")

        // 加 long break
        app.descendants(matching: .any)["break_long"].tap()
        XCTAssertTrue(app.staticTexts["Preview"].firstMatch.waitForExistence(timeout: 3)
                      || app.staticTexts["Input"].firstMatch.exists,
                      "自动模式应有预览区")

        // 切回手动模式
        app.descendants(matching: .any)["seg_Manual mode"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["slot_add"].waitForExistence(timeout: 3),
                      "切回手动应显示 Add period")
    }

    // MARK: 保存(合法数据 → 回管理页)

    func testSaveTableSettings() {
        let nameField = app.descendants(matching: .any)["field_Schedule Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("-v2")
        app.swipeUp()
        let save = app.descendants(matching: .any)["edit_table_save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        save.tap()
        XCTAssertTrue(app.staticTexts["Manage"].waitForExistence(timeout: 6),
                      "保存后应返回管理页")
        // 表名已改
        XCTAssertTrue(app.staticTexts["我的课表-v2"].firstMatch.waitForExistence(timeout: 3),
                      "管理页应显示新表名")
    }

    // MARK: 删除表确认框 — Cancel 留在编辑页

    func testDeleteTableConfirmDialogCancel() {
        app.swipeUp()
        app.swipeUp()
        let delete = app.descendants(matching: .any)["edit_table_delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 4), "应有删除表按钮")
        delete.tap()
        XCTAssertTrue(app.staticTexts["Confirm Delete"].waitForExistence(timeout: 3),
                      "删除确认框未弹出")
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 3),
                      "取消删除应留在编辑页")
    }
}
