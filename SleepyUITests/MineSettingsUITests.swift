// MineSettingsUITests.swift — G5+ 我的页设置全交互面测试
// 覆盖: Mine 刷新小组件按钮(带 snackbar) + AllTables(切表/编辑入口/新建) +
//       Appearance(系统主题卡 + 3 态模式分段 + 预设网格) + General(5 张设置卡
//       展开收起 + 每卡内选项/开关 + 周可见日 7 行 + 语言 5 项) + Export(3 格式) +
//       Reminder(总开关 + 子开关 + 时间选择) + About(检查更新按钮)。

import XCTest

final class MineSettingsUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["pill_mine"].tap()
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()   // 隔离: 每用例杀进程重启, 防跨用例状态串扰
    }

    // MARK: 刷新小组件按钮 + snackbar 反馈

    func testRefreshWidgetsButtonShowsSnackbar() {
        let refreshBtn = app.descendants(matching: .any)["mine_refresh_widgets"]
        XCTAssertTrue(refreshBtn.waitForExistence(timeout: 3))
        refreshBtn.tap()
        // snackbar 2 秒
        XCTAssertTrue(app.staticTexts["All widgets refreshed"].waitForExistence(timeout: 3),
                      "点刷新应弹 snackbar")
    }

    // MARK: All Schedules — 切表 / 编辑入口 / 新建按钮

    /// a.v.1.0.41 热区回归: 点行内"空白区"(右端 Spacer 区, 离图标/文字最远)也应触发。
    /// 用户报障 = 点行色块不响应只有图标/文字才触发(SleepyButtonStyle 修复)。
    /// 代表行 2 条: mine_all_tables(普通导航) + mine_export(第二行, 验证同卡多行互不串扰)
    func testAllTablesRowBlankAreaTriggersNav() {
        let row = app.descendants(matching: .any)["mine_all_tables"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        // dx=0.92 → 行右端 8% 处: 文字在左侧, 此处为纯空白色块区
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5),
                      "点'所有课表'行右端空白区应跳转(SleepyButtonStyle 整行热区)")
    }

    func testExportRowBlankAreaTriggersNav() {
        let row = app.descendants(matching: .any)["mine_export"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Export Schedule"].waitForExistence(timeout: 5),
                      "点'导出'行右端空白区应跳转到导出页")
    }

    func testAllTablesSwitchAndEdit() {
        app.descendants(matching: .any)["mine_all_tables"].tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5))
        // 种子表"我的课表"为当前(checkmark)
        XCTAssertTrue(app.staticTexts["我的课表"].firstMatch.exists, "列表应有种子表")
        // 新建按钮存在
        XCTAssertTrue(app.staticTexts["New Schedule"].firstMatch.exists)
        // 表行的编辑齿轮(图标按钮)
        let gear = app.buttons.matching(NSPredicate(format: "label CONTAINS 'gear'")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 3), "表行应有编辑齿轮")
    }

    func testAllTablesNewButtonOpensEditor() {
        app.descendants(matching: .any)["mine_all_tables"].tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5))
        app.staticTexts["New Schedule"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 5),
                      "新建应进表编辑页")
    }

    // MARK: Appearance — 3 态模式分段切换

    func testAppearanceModeSegmented() {
        app.descendants(matching: .any)["mine_appearance"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))

        let light = app.descendants(matching: .any)["theme_mode_light"]
        let dark = app.descendants(matching: .any)["theme_mode_dark"]
        let auto = app.descendants(matching: .any)["theme_mode_system"]
        XCTAssertTrue(light.waitForExistence(timeout: 3), "Light 模式按钮应存在")
        XCTAssertTrue(dark.exists, "Dark 模式按钮应存在")
        XCTAssertTrue(auto.exists, "Auto 模式按钮应存在")

        // 切 Dark → 立即生效不崩
        dark.tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 3), "切深色不应崩")
        // 切回 Light
        light.tap()
        // 切 Auto
        auto.tap()
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
    }

    // MARK: Appearance — 预设主题网格(至少一个预设可点)

    func testAppearancePresetGrid() {
        app.descendants(matching: .any)["mine_appearance"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        app.swipeUp()
        // 预设网格(2 列 N 个)— 任一预设按钮可点不崩
        let presets = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'theme' OR label CONTAINS 'Wake'")).firstMatch
        if presets.exists {
            presets.tap()
            XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 3))
        }
        // 无论预设如何, 页面不崩
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
    }

    // MARK: General — 5 张设置卡全部展开收起

    func testGeneralCardsExpandCollapse() {
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))

        // Time Display 卡: 展开 → 2 选项
        let timeDisplay = app.staticTexts["Time Display"].firstMatch
        XCTAssertTrue(timeDisplay.waitForExistence(timeout: 3))
        timeDisplay.tap()
        XCTAssertTrue(app.staticTexts["Show as periods"].waitForExistence(timeout: 3),
                      "展开后应显示 periods 选项")
        XCTAssertTrue(app.staticTexts["Show as times"].exists)

        // 点选 times 选项
        app.staticTexts["Show as times"].firstMatch.tap()
        // 切回 periods
        app.staticTexts["Show as periods"].firstMatch.tap()

        // Grid card sub-info 卡
        let gridCard = app.staticTexts["Grid card sub-info"].firstMatch
        XCTAssertTrue(gridCard.waitForExistence(timeout: 3))
        gridCard.tap()
        XCTAssertTrue(app.staticTexts["Room"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Teacher"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["None"].firstMatch.exists)
        // 三选项轮点
        app.staticTexts["Room"].firstMatch.tap()
        app.staticTexts["Teacher"].firstMatch.tap()
        app.staticTexts["None"].firstMatch.tap()

        // 收起(再点卡头)
        gridCard.tap()
        XCTAssertFalse(app.staticTexts["None"].firstMatch.waitForExistence(timeout: 2),
                       "收起后选项应消失")
    }

    // MARK: General — Visible Days 7 行开关

    func testGeneralVisibleDaysToggles() {
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        app.swipeUp()
        let daysCard = app.staticTexts["Visible Days"].firstMatch
        XCTAssertTrue(daysCard.waitForExistence(timeout: 3))
        daysCard.tap()
        // 7 行日选择(至少 Monday 行出现)
        let monday = app.staticTexts["Monday"].firstMatch
        if monday.waitForExistence(timeout: 3) {
            monday.tap()   // 关周一 → 再点开
            monday.tap()
        }
        XCTAssertTrue(app.staticTexts["Visible Days"].exists, "操作后卡不崩")
    }

    // MARK: General — Show dates / colorless 开关

    func testGeneralToggles() {
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()

        let showDateCard = app.staticTexts["Show dates on schedule"].firstMatch
        XCTAssertTrue(showDateCard.waitForExistence(timeout: 3))
        showDateCard.tap()
        // Toggle switch(switch 元素)
        let sw = app.switches.firstMatch
        if sw.waitForExistence(timeout: 2) {
            sw.tap()
            sw.tap()   // 开→关→开
        }
        XCTAssertTrue(app.staticTexts["Show dates on schedule"].exists)
    }

    // MARK: General — Widget 设置组(widgetcolorless/separator/vertPunct)

    func testGeneralWidgetSection() {
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        let widgetCard = app.staticTexts["Widget settings"].firstMatch
        if widgetCard.waitForExistence(timeout: 3) {
            widgetCard.tap()
            XCTAssertTrue(app.staticTexts["Uniform widget course colors"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["Week view separator"].exists)
            // 展开状态点第一个选项卡的 switch
            let sw = app.switches.firstMatch
            if sw.exists { sw.tap() }
        }
    }

    // MARK: General — 语言 5 项切换(切 en → ja → 切回 zh 简体)

    func testGeneralLanguageSwitch() {
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        let english = app.buttons["English"].firstMatch
        XCTAssertTrue(english.waitForExistence(timeout: 3), "语言列表应有 English")
        english.tap()
        // 切日语
        let japanese = app.buttons["日本語"].firstMatch
        XCTAssertTrue(japanese.waitForExistence(timeout: 3))
        japanese.tap()
        // 切回简中(保持种子环境一致)
        let zh = app.buttons["简体中文"].firstMatch
        XCTAssertTrue(zh.waitForExistence(timeout: 3))
        zh.tap()
    }

    // MARK: Export — 3 格式行存在

    func testExportScreenThreeFormats() {
        app.descendants(matching: .any)["mine_export"].tap()
        XCTAssertTrue(app.staticTexts["Export Schedule"].waitForExistence(timeout: 5))
        // 3 个格式行(标题 L10n export_json/share/ics)
        let jsonRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'JSON'")).firstMatch
        XCTAssertTrue(jsonRow.waitForExistence(timeout: 3), "JSON 导出行应存在")
        let icsRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'ICS Calendar'")).firstMatch
        XCTAssertTrue(icsRow.exists, "ICS 导出行应存在")
    }

    // MARK: Reminder — 总开关 + 子开关 + 时间行

    func testReminderScreenToggles() {
        // ★ Reminder 深度场景(权限允许/拒绝/时间保存取消/子卡显隐)已迁至
        //   ReminderPermissionUITests(幂等+identifier 版)。此处保留冒烟:
        //   页可达 + master 幂等开 + 操作后不崩。
        app.descendants(matching: .any)["mine_reminder"].tap()
        XCTAssertTrue(app.staticTexts["Reminders"].waitForExistence(timeout: 5))

        let masterSwitch = app.descendants(matching: .any)["reminder_master_toggle"]
        XCTAssertTrue(masterSwitch.waitForExistence(timeout: 3), "总开关应在")
        if (masterSwitch.value as? String) != "1" {
            masterSwitch.tap()
            // 若 notDetermined 会弹权限窗 — 点 Allow 使开关生效(幂等)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allowBtn = springboard.alerts.firstMatch.buttons.matching(
                NSPredicate(format: "label == 'Allow' OR label == '好'")).firstMatch
            if allowBtn.waitForExistence(timeout: 4) { allowBtn.tap() }
        }
        XCTAssertTrue((masterSwitch.value as? String) == "1", "master 应为开")
        XCTAssertTrue(app.staticTexts["Reminders"].exists, "提醒页操作后不崩")
    }

    // MARK: About — 检查更新按钮(点击进入 checking 态, 网络失败回落不崩)

    func testAboutCheckUpdateButton() {
        app.descendants(matching: .any)["mine_about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5))

        let checkBtn = app.descendants(matching: .any)["about_check_update"]
        XCTAssertTrue(checkBtn.waitForExistence(timeout: 3))
        checkBtn.tap()
        // 进入 checking(可能很快过去, 只要页面不崩)
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 3),
                      "检查更新不应崩溃")
    }
}
