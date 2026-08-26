// UIElementAuditUITests.swift — v1.0.34 UI对齐审计专用
// 用途:捕获完整UI元素+点击矩阵截图,作为对齐审计可验证证据。
// 约束:不删不改任何已有测试;仅追加本文件。
// 运行: xcodebuild test -scheme Sleepy -destination 'platform=iOS Simulator,id=E457BAD9-947A-469A-BD6B-0286F69267CD' -only-testing:SleepyUITests/UIElementAuditUITests

import XCTest

final class UIElementAuditUITests: XCTestCase {

    var app: XCUIApplication!
    var outputDir: String = "/Users/lingion_k/Desktop/sleepy-ios/audit_shots"

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        // 默认:Light + zh-Hans (通过 AppleLanguages/zh-Hans 注入)
        // 注意:-SLEEPY_UI_TEST_SEED 触发种子数据
    }

    override func tearDownWithError() throws {
        // 每个测试方法后终止,确保下个测试干净状态
        app.terminate()
    }

    // MARK: - 辅助方法

    private func launchApp(language: String = "zh-Hans", appearance: String = "light") {
        app = XCUIApplication()
        // 主题:通过环境变量模拟
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "zh-Hans" ? "zh_CN" : (language == "zh-Hant" ? "zh_TW" : "\(language)_US")",
            "-SLEEPY_UI_TEST_SEED", "1",
            "-UILaunchScreen_Generation", "YES" // 防止首屏黑屏
        ]
        app.launch()

        // 等待 Pill 栏出现(种子后)
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10),
                      "App launch failed or seed not applied")
        sleep(2) // 动画稳定
    }

    private func captureScreenshot(named name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        // 保存到磁盘(不依赖 Xcode 结果存档)
        let url = URL(fileURLWithPath: "\(outputDir)/\(name).png")
        if let data = screenshot.pngRepresentation {
            try? data.write(to: url)
        }
        add(attachment)
    }

    // MARK: - Tab 导航

    private func switchToTab(_ tabId: String) {
        let tab = app.descendants(matching: .any)["pill_\(tabId)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Tab \(tabId) not found")
        tab.tap()
        sleep(1) // 动画
    }

    // MARK: - 导航到子页面

    private func navigateToAppearance() {
        switchToTab("mine")
        // 找"外观"按钮(通过静态文本匹配,跨locale用L10n key)
        // MineScreen: "appearance" → L10n.format("appearance")
        let appearanceBtn = app.staticTexts.element(matching: .any, identifier: "appearance").firstMatch
        if appearanceBtn.exists {
            appearanceBtn.tap()
        } else {
            // 备选:scroll + 找包含"外观"的文本
            app.swipeUp()
        }
        sleep(1)
    }

    private func navigateToGeneralSettings() {
        switchToTab("mine")
        app.swipeUp()
        let generalBtn = app.staticTexts.element(matching: .any, identifier: "general").firstMatch
        if generalBtn.exists { generalBtn.tap() }
        sleep(1)
    }

    private func navigateToReminder() {
        switchToTab("mine")
        app.swipeUp()
        let reminderBtn = app.staticTexts.element(matching: .any, identifier: "reminder").firstMatch
        if reminderBtn.exists { reminderBtn.tap() }
        sleep(1)
    }

    private func navigateToExport() {
        switchToTab("mine")
        app.swipeUp()
        let exportBtn = app.staticTexts.element(matching: .any, identifier: "export").firstMatch
        if exportBtn.exists { exportBtn.tap() }
        sleep(1)
    }

    private func navigateToAbout() {
        switchToTab("mine")
        app.swipeUp()
        let aboutBtn = app.staticTexts.element(matching: .any, identifier: "about").firstMatch
        if aboutBtn.exists { aboutBtn.tap() }
        sleep(1)
    }

    private func navigateToAllTables() {
        switchToTab("mine")
        let allTablesBtn = app.staticTexts.element(matching: .any, identifier: "all_tables").firstMatch
        if allTablesBtn.exists { allTablesBtn.tap() }
        sleep(1)
    }

    private func navigateToAddCourseEmpty() {
        // 从 schedule tab 点击添加按钮
        switchToTab("schedule")
        // 找添加按钮(静态文本"添加课程"或 accessibilityIdentifier)
        let addBtn = app.buttons.element(matching: .any, identifier: "course_add_slot").firstMatch
        if !addBtn.exists {
            // 备选:找导航栏右侧按钮
            let navAdd = app.buttons.element(matching: .any, identifier: "nav_add")
            if navAdd.exists { navAdd.tap() }
        } else {
            addBtn.tap()
        }
        sleep(1)
    }

    private func navigateToEditTableEmpty() {
        switchToTab("manage")
        // 从 manage 页面找编辑课表按钮
        let editTableBtn = app.staticTexts.element(matching: .any, identifier: "edit_current_table")
        if editTableBtn.exists { editTableBtn.tap() }
        sleep(1)
    }

    private func navigateToSchoolSelect() {
        switchToTab("manage")
        // 找导入入口 -> 选学校
        let importBtn = app.staticTexts.element(matching: .any, identifier: "import_school_select")
        if importBtn.exists { importBtn.tap() }
        sleep(1)
    }

    private func navigateToImportSheet() {
        switchToTab("manage")
        // 找导入按钮
        let importBtn = app.staticTexts.element(matching: .any, identifier: "import_sheet_entry")
        if importBtn.exists { importBtn.tap() }
        sleep(1)
    }

    private func openFormatDetail(_ formatId: String) {
        // ImportSheet 打开 format help dialog
        // 格式: wakeupShare/wakeupJson/ics/csv/html/plain
        // 通过 info.circle 按钮触发
        let infoBtns = app.buttons.allElementsBoundByAccessibilityElement
        for btn in infoBtns {
            if btn.label.contains("info") || btn.label.contains("详情") {
                btn.tap()
                sleep(0.5)
                break
            }
        }
    }

    // MARK: - A.1 Light + zh-Hans 测试

    func testA1_Schedule_Main() {
        launchApp(language: "zh-Hans", appearance: "light")
        captureScreenshot("A1_schedule_zh-Hans_light")
    }

    func testA1_Today_Main() {
        launchApp(language: "zh-Hans", appearance: "light")
        switchToTab("today")
        captureScreenshot("A1_today_zh-Hans_light")
    }

    func testA1_Manage_Main() {
        launchApp(language: "zh-Hans", appearance: "light")
        switchToTab("manage")
        captureScreenshot("A1_manage_zh-Hans_light")
    }

    func testA1_Mine_Main() {
        launchApp(language: "zh-Hans", appearance: "light")
        switchToTab("mine")
        // Mine 有三个统计卡:mine_stat_tables / mine_stat_courses / mine_stat_week
        captureScreenshot("A1_mine_zh-Hans_light")
    }

    func testA1_Appearance_Page() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToAppearance()
        // 外观页:系统主题卡 + 5预设卡 + 3模式按钮
        captureScreenshot("A1_appearance_zh-Hans_light")
    }

    func testA1_General_Settings() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToGeneralSettings()
        captureScreenshot("A1_general_zh-Hans_light")
    }

    func testA1_Reminder_Page() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToReminder()
        captureScreenshot("A1_reminder_zh-Hans_light")
    }

    func testA1_Export_Page() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToExport()
        captureScreenshot("A1_export_zh-Hans_light")
    }

    func testA1_About_Page() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToAbout()
        captureScreenshot("A1_about_zh-Hans_light")
    }

    func testA1_AddCourse_Empty() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToAddCourseEmpty()
        captureScreenshot("A1_addCourse_empty_zh-Hans_light")
    }

    func testA1_EditTable_Empty() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToEditTableEmpty()
        captureScreenshot("A1_editTable_empty_zh-Hans_light")
    }

    func testA1_AllTables_Page() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToAllTables()
        captureScreenshot("A1_allTables_zh-Hans_light")
    }

    func testA1_SchoolSelect_FirstScreen() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToSchoolSelect()
        captureScreenshot("A1_schoolSelect_zh-Hans_light")
    }

    func testA1_ImportSheet_Entry() {
        launchApp(language: "zh-Hans", appearance: "light")
        navigateToImportSheet()
        captureScreenshot("A1_importSheet_zh-Hans_light")
    }

    // MARK: - A.2 Light → Dark 切换后 4 Tab

    func testA2_Schedule_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        captureScreenshot("A2_schedule_zh-Hans_dark")
    }

    func testA2_Today_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        switchToTab("today")
        captureScreenshot("A2_today_zh-Hans_dark")
    }

    func testA2_Manage_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        switchToTab("manage")
        captureScreenshot("A2_manage_zh-Hans_dark")
    }

    func testA2_Mine_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        switchToTab("mine")
        captureScreenshot("A2_mine_zh-Hans_dark")
    }

    // MARK: - A.3 Language 切换测试

    func testA3_Schedule_en() {
        launchApp(language: "en", appearance: "light")
        captureScreenshot("A3_schedule_en_light")
    }

    func testA3_Mine_en() {
        launchApp(language: "en", appearance: "light")
        switchToTab("mine")
        captureScreenshot("A3_mine_en_light")
    }

    func testA3_Schedule_es() {
        launchApp(language: "es", appearance: "light")
        captureScreenshot("A3_schedule_es_light")
    }

    func testA3_Mine_es() {
        launchApp(language: "es", appearance: "light")
        switchToTab("mine")
        captureScreenshot("A3_mine_es_light")
    }

    func testA3_Schedule_ja() {
        launchApp(language: "ja", appearance: "light")
        captureScreenshot("A3_schedule_ja_light")
    }

    func testA3_Mine_ja() {
        launchApp(language: "ja", appearance: "light")
        switchToTab("mine")
        captureScreenshot("A3_mine_ja_light")
    }

    func testA3_Schedule_zh-Hant() {
        launchApp(language: "zh-Hant", appearance: "light")
        captureScreenshot("A3_schedule_zh-Hant_light")
    }

    func testA3_Mine_zh-Hant() {
        launchApp(language: "zh-Hant", appearance: "light")
        switchToTab("mine")
        captureScreenshot("A3_mine_zh-Hant_light")
    }
}
