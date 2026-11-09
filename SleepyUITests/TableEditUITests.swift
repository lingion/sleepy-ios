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

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return condition()
    }

    /// A partially visible row can be hittable while its drag endpoint is below
    /// the SE window. Keep both complete rows clear of the fixed header/footer.
    private func makeFullyVisible(_ elements: [XCUIElement],
                                  file: StaticString = #filePath, line: UInt = #line) {
        for element in elements {
            XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        }
        let viewport = app.frame.insetBy(dx: 2, dy: 82)
        for _ in 0..<12 {
            if elements.allSatisfy({ $0.isHittable && viewport.contains($0.frame) }) { return }
            if elements.contains(where: { $0.frame.minY < viewport.minY }) {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
        XCTAssertTrue(elements.allSatisfy { $0.isHittable && viewport.contains($0.frame) },
                      "The complete control or drag row must fit in the visible scroll area", file: file, line: line)
    }

    private func setTime(_ field: XCUIElement, hour: String, minute: String,
                         file: StaticString = #filePath, line: UInt = #line) {
        makeFullyVisible([field], file: file, line: line)
        field.tap()
        let confirm = app.buttons["time_picker_confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), file: file, line: line)
        let wheels = app.pickerWheels
        XCTAssertEqual(wheels.count, 2, "The en_GB time picker must expose hour and minute wheels", file: file, line: line)
        wheels.element(boundBy: 0).adjust(toPickerWheelValue: hour)
        wheels.element(boundBy: 1).adjust(toPickerWheelValue: minute)
        // Scroll only the sheet's empty trailing gutter if its actions need room;
        // a swipe through the middle would change the selected wheel value.
        for _ in 0..<3 where !confirm.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.84))
                .press(forDuration: 0.05, thenDragTo:
                    app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.42)))
        }
        XCTAssertTrue(confirm.isHittable, file: file, line: line)
        confirm.tap()
        XCTAssertTrue(waitUntil { !confirm.exists }, file: file, line: line)
        XCTAssertTrue(field.label.contains("\(hour):\(minute)"), file: file, line: line)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        // 20s: 批量跑套件时首启冷启动+seed 注入可远超 10s(批量失败即栽在此行, 单跑全绿)
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 20))
        app.switchToPillTab("manage")
        XCTAssertTrue(app.staticTexts["Manage"].waitForExistence(timeout: 5))
        app.descendants(matching: .any)["manage_edit_current"].tap()
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()   // 隔离: 每用例杀进程重启, 防跨用例状态串扰
    }

    // MARK: 2 个文本字段 + 周数数字输入
    // (周数现态 = FieldTextField numberPad — d03c426 曾 Stepper 化, 后续按
    //  原 maxWeekText 语义改回数字文本; 锚点 field_Total Weeks)

    func testBasicInfoFieldsAcceptInput() {
        let nameField = app.descendants(matching: .any)["field_Schedule Name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "名称字段锚点未找到")
        XCTAssertTrue(app.descendants(matching: .any)["field_Semester Start Date"].exists)
        // 周数字段: identifier 锚点(placeholder 不进 label 谓词 — probe 实证)
        let weeksField = app.descendants(matching: .any)["field_Total Weeks"]
        XCTAssertTrue(weeksField.waitForExistence(timeout: 3), "周数行应在")
        XCTAssertEqual(weeksField.value as? String, "20", "周数字段应携带种子表当前值")

        nameField.tap()
        nameField.typeText("2")
        weeksField.tap()
        weeksField.typeText("5")   // 数字键盘追加 → 不崩即可
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

    func testLongPressReorderRejectsReversedTimesAndLeavesTimeButtonsUsable() {
        forceTap(app.buttons["edit_table_slots_header"].firstMatch)
        let first = app.descendants(matching: .any)["slot_row_1"].firstMatch
        let second = app.descendants(matching: .any)["slot_row_2"].firstMatch
        forceTap(app.descendants(matching: .any)["seg_Manual mode"].firstMatch)
        for _ in 0..<5 where !second.isHittable { app.swipeUp() }
        XCTAssertTrue(first.exists && second.isHittable)
        let start = app.buttons["slot_start_1"].firstMatch
        let nextStart = app.buttons["slot_start_2"].firstMatch
        let original = start.label
        let nextOriginal = nextStart.label
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(forDuration: 0.65,
                   thenDragTo: second.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.65)))
        XCTAssertTrue(app.staticTexts["slot_reorder_invalid"].firstMatch.waitForExistence(timeout: 3),
                      "A real long-press drag must reject reversed clock times")
        XCTAssertEqual(start.label, original)
        XCTAssertEqual(nextStart.label, nextOriginal)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "reorder-invalid-times-kept"
        attachment.lifetime = .keepAlways
        add(attachment)
        start.tap()
        XCTAssertTrue(app.buttons["time_picker_cancel"].firstMatch.waitForExistence(timeout: 5),
                      "The reorder gesture must still allow a normal tap to edit a time")
        app.buttons["time_picker_cancel"].firstMatch.tap()
        XCTAssertEqual(start.label, original)
    }

    func testStandaloneBellScheduleTimeButtonWorksWhenReorderingIsDisabled() {
        XCUIDevice.shared.orientation = .portrait
        app.buttons["topbar_back"].firstMatch.tap()
        let entry = app.buttons["manage_period_tables"].firstMatch
        makeFullyVisible([entry])
        entry.tap()
        XCTAssertTrue(app.staticTexts["period_tables_screen"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["period_tables_new"].firstMatch.tap()
        XCTAssertTrue(app.buttons["period_table_slots_header"].firstMatch.waitForExistence(timeout: 5))
        let start = app.buttons["slot_start_1"].firstMatch
        // New standalone schedules open expanded; wait for their rows to load.
        makeFullyVisible([start])
        let original = start.label
        start.tap()
        let cancel = app.buttons["time_picker_cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5),
                      "Disabling row reordering must retain the standalone editor's time Button gesture")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "standalone-bell-schedule-time-picker"
        attachment.lifetime = .keepAlways
        add(attachment)
        cancel.tap()
        XCTAssertTrue(waitUntil { !cancel.exists })
        XCTAssertEqual(start.label, original, "Cancel must preserve the original standalone period time")
    }

    func testLegalBlankPeriodReorderSavesAndSurvivesReopening() {
        XCUIDevice.shared.orientation = .portrait
        forceTap(app.buttons["edit_table_slots_header"].firstMatch)
        let addRow = app.buttons["slot_add"].firstMatch
        XCTAssertTrue(addRow.waitForExistence(timeout: 5))
        forceTap(addRow)
        let previousLast = app.descendants(matching: .any)["slot_row_12"].firstMatch
        let blank = app.descendants(matching: .any)["slot_row_13"].firstMatch
        makeFullyVisible([previousLast, blank])
        let start12 = app.buttons["slot_start_12"].firstMatch
        let end12 = app.buttons["slot_end_12"].firstMatch
        let start13 = app.buttons["slot_start_13"].firstMatch
        let end13 = app.buttons["slot_end_13"].firstMatch
        let originalLastStart = start12.label
        let originalLastEnd = end12.label
        XCTAssertTrue(start13.label.contains("Not set") && end13.label.contains("Not set"))
        blank.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5))
            .press(forDuration: 0.65, thenDragTo:
                previousLast.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.1)))
        XCTAssertTrue(waitUntil {
            start12.label.contains("Not set") && end12.label.contains("Not set")
                && start13.label == originalLastStart && end13.label == originalLastEnd
        }, "A legal drag must publish the blank row at period 12 and move the old period 12 to 13")
        XCTAssertFalse(app.staticTexts["slot_reorder_invalid"].firstMatch.exists)

        // Blank rows are legal reorder targets but must be completed before the
        // schedule editor permits saving. Fill the moved row between 11 and 13.
        setTime(start12, hour: "21", minute: "40")
        setTime(end12, hour: "21", minute: "44")
        let expectedStart12 = start12.label
        let expectedEnd12 = end12.label
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "legal-blank-period-moved-and-completed"
        attachment.lifetime = .keepAlways
        add(attachment)
        let save = app.buttons["edit_table_save"].firstMatch
        makeFullyVisible([save])
        save.tap()
        let edit = app.buttons["manage_edit_current"].firstMatch
        XCTAssertTrue(waitUntil { !save.exists && edit.isHittable }, "The reordered draft must save successfully")
        edit.tap()
        XCTAssertTrue(app.buttons["edit_table_slots_header"].firstMatch.waitForExistence(timeout: 5))
        forceTap(app.buttons["edit_table_slots_header"].firstMatch)
        XCTAssertTrue(start13.waitForExistence(timeout: 5), "The saved schedule must retain its thirteenth period")
        makeFullyVisible([app.descendants(matching: .any)["slot_row_12"].firstMatch,
                          app.descendants(matching: .any)["slot_row_13"].firstMatch])
        XCTAssertEqual(start12.label, expectedStart12)
        XCTAssertEqual(end12.label, expectedEnd12)
        XCTAssertEqual(start13.label, originalLastStart)
        XCTAssertEqual(end13.label, originalLastEnd)
        let persisted = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        persisted.name = "legal-reorder-persisted-after-reopening"
        persisted.lifetime = .keepAlways
        add(persisted)
    }
}
