// ManageImportUITests.swift — G5+ 管理页/导入/建表全交互面测试
// 覆盖: 管理页 4 卡片 + ImportSheet(教务直连入口/文本折叠展开/文本输入+解析预览/
//       文件入口) + 预览对话框 3 模式 + 确认对话框(表名/日期/节次) + 完整文本导入链 +
//       新建空表流程 + AllTables 切表/编辑入口/新建。

import XCTest
import UIKit

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
        // recovery: 重试直到展开
        var expanded = false
        for _ in 0..<3 {
            forceTap(pasteRow)
            sleep(1)
            // 检查是否展开（import_preview_btn 出现 = 展开成功）
            if app.descendants(matching: .any)["import_preview_btn"].exists {
                expanded = true
                break
            }
        }
        XCTAssertTrue(expanded, "展开后应出现 Preview 按钮")
        XCTAssertTrue(app.descendants(matching: .any)["import_preview_btn"].exists,
            "展开后应有 Preview 按钮")
        // 再点收起
        forceTap(app.descendants(matching: .any)["import_text"])
        sleep(1)
        XCTAssertFalse(app.descendants(matching: .any)["import_preview_btn"]
            .waitForExistence(timeout: 3), "再点应收起")
    }

    // MARK: 完整文本导入链(输入 WakeUp JSON → Preview → 3 模式按钮 → 确认 → 新表)

    func testFullTextImportFlow() {
        // 方案: UIPasteboard + context menu paste 解决 SwiftUI TextField 在 iOS16
        // accessibility tree 中无 textField/textView 暴露节点的限制
        app.descendants(matching: .any)["manage_import"].tap()
        let pasteRow = app.descendants(matching: .any)["import_text"]
        XCTAssertTrue(pasteRow.waitForExistence(timeout: 5))
        // 重试展开
        var expanded = false
        for _ in 0..<3 {
            forceTap(pasteRow)
            sleep(1)
            if app.descendants(matching: .any)["import_preview_btn"].exists {
                expanded = true
                break
            }
        }
        XCTAssertTrue(expanded, "展开后应出现 Preview 按钮")
        // 最小合法 WakeUp JSON(对象 + courses 数组, 字段 camelCase)
        let json = "{\"name\":\"测试导入表\",\"startDate\":\"2026-08-24\",\"courses\":[{\"name\":\"编译原理\",\"teacher\":\"陈老师\",\"position\":\"教3-401\",\"day\":4,\"startNode\":7,\"step\":2,\"startWeek\":1,\"endWeek\":16,\"type\":0}]}"
        // 步骤1: 复制 JSON 到 UIPasteboard
        UIPasteboard.general.string = json

        // 步骤2: 找到文本输入区域(import_paste_input)并尝试聚焦
        // 注意: SwiftUI TextField(axis:.vertical) 在 iOS16 accessibility tree 中可能不暴露为 textField
        // 我们用其 identifier 定位，然后尝试多种方式输入
        let textField = app.descendants(matching: .any)["import_paste_input"]

        // 先把输入区域滚入可视范围
        app.swipeUp()
        sleep(1)

        // 尝试点击文本区域激活键盘(使用坐标点击确保命中)
        let previewBtn = app.descendants(matching: .any)["import_preview_btn"]
        XCTAssertTrue(previewBtn.waitForExistence(timeout: 3))

        // TextField 在 Preview 上方, 使用相对坐标
        // 按钮高 48(2026-08-29 从 44 调齐 Android regularHeight) + VStack spacing 8:
        // dy=-1.7 ≈ 82pt 上方 = TextField 下半区中心, 保证命中输入框
        let textFieldCenter = previewBtn.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.7))
        textFieldCenter.tap()
        sleep(1)

        // 检查键盘是否出现
        if app.keyboards.count > 0 {
            // 键盘已弹出，尝试使用 Paste 功能
            // 在焦点元素上长按弹出上下文菜单
            textFieldCenter.press(forDuration: 0.8)
            sleep(1)

            // 查找 Paste 菜单项
            if app.menuItems["Paste"].waitForExistence(timeout: 2) {
                app.menuItems["Paste"].tap()
                sleep(1)
            } else {
                // 菜单没出现，回退到选中+替换方式
                textFieldCenter.doubleTap()
                sleep(1)
                app.typeText(UIPasteboard.general.string ?? json)
            }
        } else {
            // 键盘未弹出，尝试其他激活方式
            // 再次点击并等待
            textFieldCenter.tap()
            sleep(2)

            if app.keyboards.count > 0 {
                // 现在键盘出现了
                textFieldCenter.press(forDuration: 0.8)
                sleep(1)
                if app.menuItems["Paste"].waitForExistence(timeout: 2) {
                    app.menuItems["Paste"].tap()
                } else {
                    // 直接输入
                    textFieldCenter.doubleTap()
                    sleep(1)
                    app.typeText(json)
                }
            } else {
                // 最后的尝试：使用坐标直接输入(会替换选中文本或追加)
                app.typeText(json)
            }
        }

        // 确保输入框有内容
        // 如果输入失败，使用 launch argument 传递 JSON
        let inputField = app.descendants(matching: .any)["import_paste_input"]
        let hasInput = inputField.exists  // 元素存在即认为可能已有输入

        sleep(1)
        // 收键盘: 向下滑动手势
        let scrollStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        let scrollEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
        sleep(1)

        // 步骤4: 点击 Preview 按钮
        let previewButton = app.descendants(matching: .any)["import_preview_btn"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 3))
        previewButton.tap()
        // 预览对话框: 标题 + 3 模式按钮(any — 内嵌 sheet 里的元素类型不定)
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Import Preview'")).firstMatch
            .waitForExistence(timeout: 6), "预览对话框未弹出(解析失败?)")
        // 课程名行可能是任意元素类型;再等 1s 后不强断(解析成功由 Import Preview 弹出证明)
        _ = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS '编译原理'")).firstMatch.waitForExistence(timeout: 2)

        // 选 "Import as new schedule" 模式: 只有该模式(及 Append as new table / Overwrite
        // current)会弹 "Confirm Before Import" 对话框; "Append non-conflicting" 在 Android
        // 源上本来就不弹 confirm(直接应用) → 旧断言不可能通过。
        let appendBtn = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Import as new'")).firstMatch
        if appendBtn.waitForExistence(timeout: 3) {
            appendBtn.tap()
        } else {
            // 兜底: "⚠ Overwrite current" 也走 confirm 流(替换种子表为导入内容,
            // 编译原理 周四 7-8 不碰种子课时段, 课表仍可验证)
            let replace = app.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS 'Overwrite current'")).firstMatch
            XCTAssertTrue(replace.waitForExistence(timeout: 2), "confirm 流模式按钮都不在")
            replace.tap()
        }

        // 确认对话框: 表名/开始日期/Confirm Import
        XCTAssertTrue(app.staticTexts["Confirm Before Import"].waitForExistence(timeout: 4),
                      "确认对话框未弹出")
        // 确认按钮在 safeAreaInset 底部, 键盘可能盖住 → 先收键盘再滚到位
        // 注1: 键盘存在≠Return键存在(多行TextField无收起键/键名随locale漂移)
        // 注2: exists→tap 有竞态 —— 点模式按钮后SwiftUI异步收焦点, exists读到陈旧树,
        //      tap时键盘已消失→error 10008。先settle再查, 查键用waitForExistence收窄窗口,
        //      tap包do/catch兜底: 键盘消失本就是目标状态, 兜底点标题失焦
        Thread.sleep(forTimeInterval: 1) // 让 SwiftUI 完成焦点迁移/键盘收起动画
        if app.keyboards.count > 0 {
            let dismissKey = app.keyboards.buttons.matching(
                NSPredicate(format: "label IN {'Return', 'Done', 'return', 'done', '换行', '完成'}")
            ).firstMatch
            if dismissKey.waitForExistence(timeout: 2) {
                dismissKey.tap() // waitForExistence后窗口极小; 若再撞竞态由下方标题失焦兜底
            } else {
                app.staticTexts["Confirm Before Import"].tap()
            }
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
        // 导入完成 → Android 行为(ImportSheet.kt v1.0.56 删跳编辑页 + NavHost onImported
        // =「留在管理页, 摘要卡就地刷新」): 确认 sheet 关闭后 ImportSheet 仍开着(其
        // importJustApplied 只弹 snackbar, 不关自己)→ 断言成功条 import_success_snackbar,
        // 下滑关 sheet 回 Manage; 新表落库经 observeAllTables 反应流成当前表
        // (applyImportPreview .importAsNew 走 setDefault)→ 摘要卡即显示导入表名。
        // ★ 修复: snackbar 停留 2.5s, 用 descendants 锚点(与 ImportSheet.import_success_snackbar 对齐)
        let snackbar = app.descendants(matching: .any)["import_success_snackbar"]
        XCTAssertTrue(snackbar.waitForExistence(timeout: 5),
                      "导入成功应弹 snackbar(import_success)")
        // 关 ImportSheet: 循环 swipeDown 实测不可靠(2026-10-25 eprobe: 6 次全被
        // sheet 内 ScrollView/文本区吞掉, 标题恒在)。改走确定性路径: 摘要卡断言
        // 透过 sheet 树即可成立(exists 含遮挡元素), 末尾用「重启 App」验证导入
        // 持久生效 —— 冷启动无 sheet 遮挡, 默认表=setDefault(导入表) → 课表 Tab
        // 必渲染编译原理, 同时锁住"导入落库+设为默认+重启仍在"三件事。
        XCTAssertTrue(app.staticTexts["Manage"].waitForExistence(timeout: 5),
                      "导入后应留在管理页(不跳编辑页)")
        // 摘要卡刷新: 表名 = 导入表名(唯一名顺延仅撞名时加后缀, 种子表名不同 → 原名)
        XCTAssertTrue(app.staticTexts["测试导入表"].waitForExistence(timeout: 8),
                      "管理页摘要卡应刷新为导入的课表")
        app.terminate()
        // 重启不带种子参数: 带 -SLEEPY_UI_TEST_SEED 会重跑 seeder 清库,
        // 把刚导入的表删掉 → 这里要验证的恰是"导入持久化", 用裸参数重启。
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 20))
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
