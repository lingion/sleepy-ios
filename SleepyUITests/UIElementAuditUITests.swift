// UIElementAuditUITests.swift — v1.0.34 UI对齐审计专用
// 用途:捕获完整UI元素+点击矩阵截图,作为对齐审计可验证证据。
// 约束:不删不改任何已有测试;仅追加本文件。
// 运行: xcodebuild test -scheme Sleepy -destination 'platform=iOS Simulator,id=E457BAD9-947A-469A-BD6B-0286F69267CD' -only-testing:SleepyUITests/UIElementAuditUITests

import XCTest
import CoreGraphics

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
        // 主题: -theme_mode <light|dark> 作为 launch argument 会落入 UserDefaults.standard,
        //       AppPrefs.getThemeMode() 直接读到 → 无需触碰模拟器全局外观
        //       (AppPrefs.isDarkMode: light→false / dark→true / system→跟随)
        app.launchArguments = [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "zh-Hans" ? "zh_CN" : (language == "zh-Hant" ? "zh_TW" : "\(language)_US"),
            "-SLEEPY_UI_TEST_SEED", "1",
            "-UILaunchScreen_Generation", "YES", // 防止首屏黑屏
            "-theme_mode", appearance == "dark" ? "dark" : "light"
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
        let data = screenshot.pngRepresentation
        try? data.write(to: url)
        add(attachment)
    }

    private func captureScreenshot(_ name: String) {
        captureScreenshot(named: name)
    }

    /// 回读刚截的 PNG,计算主体区域(垂直 20%-80%,水平 10%-90%)平均 luma。
    /// 深色主题下主体应 < 80;若 ≥ 100 判定仍为浅色 → fail(防 JW sheet 主题环境丢失回归)。
    private func assertDarkScreenshot(_ name: String, message: String) {
        let url = URL(fileURLWithPath: "\(outputDir)/\(name).png")
        guard let provider = CGDataProvider(url: url as CFURL),
              let cgImage = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            XCTFail("无法解码截图 \(name).png")
            return
        }
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { XCTFail("截图尺寸异常"); return }
        // 整幅重绘到 RGBA 缓冲,一次性取像素
        let bytesPerRow = width * 4
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let base = ctx.data else {
            XCTFail("无法创建 CGContext")
            return
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let buf = base.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        // CG 原点在左下,截图分析按顶部起始换算 y
        func lumaAt(_ x: Int, _ topOriginY: Int) -> Double {
            let y = height - 1 - topOriginY
            let off = y * bytesPerRow + x * 4
            let r = Double(buf[off]), g = Double(buf[off + 1]), b = Double(buf[off + 2])
            return 0.299 * r + 0.587 * g + 0.114 * b
        }
        let y0 = height * 20 / 100, y1 = height * 80 / 100
        let x0 = width * 10 / 100, x1 = width * 90 / 100
        var totalLuma = 0.0
        var count = 0.0
        for y in stride(from: y0, to: y1, by: 16) {
            for x in stride(from: x0, to: x1, by: 16) {
                totalLuma += lumaAt(x, y)
                count += 1
            }
        }
        guard count > 0 else { XCTFail("未采到任何像素"); return }
        let avg = totalLuma / count
        XCTAssertLessThan(avg, 100.0, "\(message) 实测主体 luma=\(Int(avg)) (阈值 100)")
    }


    private func switchToTab(_ tabId: String) {
        let tab = app.descendants(matching: .any)["pill_\(tabId)"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Tab \(tabId) not found")
        tab.tap()
        sleep(1) // 动画
    }

    // MARK: - 导航到子页面

    /// 点 Mine 设置项(SettingsItem 是 Button,identifier 前缀 mine_)并断言子页真实打开。
    private func openMineSetting(_ itemId: String, assertAnchor anchorId: String, scroll: Bool = true) {
        switchToTab("mine")
        if scroll { app.swipeUp() }
        let item = app.buttons[itemId].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Mine 设置项 \(itemId) 未找到")
        item.tap()
        let anchor = app.descendants(matching: .any)[anchorId].firstMatch
        XCTAssertTrue(anchor.waitForExistence(timeout: 5), "点击 \(itemId) 后子页锚点 \(anchorId) 未出现")
        Thread.sleep(forTimeInterval: 1)
    }

    private func navigateToAppearance() {
        openMineSetting("mine_appearance", assertAnchor: "theme_system_card", scroll: false)
    }

    private func navigateToGeneralSettings() {
        openMineSetting("mine_general", assertAnchor: "topbar_back")
    }

    private func navigateToReminder() {
        openMineSetting("mine_reminder", assertAnchor: "topbar_back")
    }

    private func navigateToExport() {
        openMineSetting("mine_export", assertAnchor: "topbar_back")
    }

    private func navigateToAbout() {
        openMineSetting("mine_about", assertAnchor: "about_check_update")
    }

    private func navigateToAllTables() {
        openMineSetting("mine_all_tables", assertAnchor: "topbar_back", scroll: false)
    }

    private func navigateToAddCourseEmpty() {
        // 加课页入口在 manage Tab 的 manage_add_course 卡(schedule 页无固定加课按钮)
        switchToTab("manage")
        let addBtn = app.buttons["manage_add_course"].firstMatch
        XCTAssertTrue(addBtn.waitForExistence(timeout: 5), "manage_add_course 未找到")
        addBtn.tap()
        let back = app.descendants(matching: .any)["topbar_back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5), "加课页未打开(topbar_back 未出现)")
        Thread.sleep(forTimeInterval: 1)
    }

    private func navigateToEditTableEmpty() {
        switchToTab("manage")
        let editTableBtn = app.buttons["manage_edit_current"].firstMatch
        XCTAssertTrue(editTableBtn.waitForExistence(timeout: 5), "manage_edit_current 未找到")
        editTableBtn.tap()
        Thread.sleep(forTimeInterval: 1)
    }

    private func navigateToSchoolSelect() {
        switchToTab("manage")
        let importBtn = app.buttons["manage_import"].firstMatch
        XCTAssertTrue(importBtn.waitForExistence(timeout: 5), "manage_import 未找到")
        importBtn.tap()
        // ImportSheet 打开 → 点教务直连行 → (0.5s sheet 冲突延迟后) JwImportFlow 呈现
        let jwRow = app.buttons["import_jw"].firstMatch
        XCTAssertTrue(jwRow.waitForExistence(timeout: 5), "import_jw 行未出现")
        jwRow.tap()
        let search = app.descendants(matching: .any)["school_search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "SchoolSelect 未打开(school_search 未出现)")
        Thread.sleep(forTimeInterval: 1)
    }

    private func navigateToImportSheet() {
        switchToTab("manage")
        let importBtn = app.buttons["manage_import"].firstMatch
        XCTAssertTrue(importBtn.waitForExistence(timeout: 5), "manage_import 未找到")
        importBtn.tap()
        let pasteInput = app.descendants(matching: .any)["import_paste_input"].firstMatch
        if !pasteInput.exists {
            // 文本导入默认折叠,展开
            let textRow = app.buttons["import_text"].firstMatch
            XCTAssertTrue(textRow.waitForExistence(timeout: 5), "import_text 行未出现")
            textRow.tap()
        }
        Thread.sleep(forTimeInterval: 1)
    }

    private func openFormatDetail(_ formatId: String) {
        // ImportSheet 打开 format help dialog
        // 格式: wakeupShare/wakeupJson/ics/csv/html/plain
        // 通过 info.circle 按钮触发
        let infoBtns = app.buttons.allElementsBoundByAccessibilityElement
        for btn in infoBtns {
            if btn.label.contains("info") || btn.label.contains("详情") {
                btn.tap()
                Thread.sleep(forTimeInterval: 0.5)
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

    func testA3_Schedule_zh_Hant() {
        launchApp(language: "zh-Hant", appearance: "light")
        captureScreenshot("A3_schedule_zh-Hant_light")
    }

    // MARK: - A.4 填充数据交互与返回路径

    func testA4_AddCourseNavigationBack() {
        launchApp(language: "zh-Hans", appearance: "light")
        switchToTab("manage")
        let add = app.buttons["manage_add_course"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "加课入口未出现")
        add.tap()
        let addBack = app.descendants(matching: .any)["topbar_back"].firstMatch
        XCTAssertTrue(addBack.waitForExistence(timeout: 5), "加课页未打开")
        addBack.tap()
        XCTAssertTrue(app.buttons["manage_add_course"].waitForExistence(timeout: 5), "加课页返回后未回到管理页")
    }

    func testA4_EditTableNavigationBack() {
        launchApp(language: "zh-Hans", appearance: "light")
        switchToTab("manage")
        let edit = app.buttons["manage_edit_current"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "编辑当前课表入口未出现")
        edit.tap()
        let editBack = app.descendants(matching: .any)["topbar_back"].firstMatch
        XCTAssertTrue(editBack.waitForExistence(timeout: 5), "编辑课表页未打开")
        editBack.tap()
        XCTAssertTrue(app.buttons["manage_edit_current"].waitForExistence(timeout: 5), "编辑课表页返回后未回到管理页")
    }

    func testA4_ImportSheetNavigationBack() {
        launchApp(language: "zh-Hans", appearance: "light")
        switchToTab("manage")
        let importButton = app.buttons["manage_import"].firstMatch
        XCTAssertTrue(importButton.waitForExistence(timeout: 5), "导入入口未出现")
        importButton.tap()
        // ImportSheet 以 sheet 呈现; 验证其入口行可见后下滑关闭
        XCTAssertTrue(app.buttons["import_jw"].waitForExistence(timeout: 5), "导入 sheet 未打开")
        app.swipeDown()
        XCTAssertTrue(app.buttons["manage_import"].waitForExistence(timeout: 5), "导入页返回后未回到管理页")
    }

    // MARK: - A.6 深色次级页矩阵(补齐 A2 只测了 4 主 tab 的缺口)

    func testA6_Appearance_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToAppearance()
        captureScreenshot("A6_appearance_dark")
        assertDarkScreenshot("A6_appearance_dark", message: "Appearance 深色主题未生效")
    }

    func testA6_General_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToGeneralSettings()
        captureScreenshot("A6_general_dark")
        assertDarkScreenshot("A6_general_dark", message: "General 深色主题未生效")
    }

    func testA6_Reminder_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToReminder()
        captureScreenshot("A6_reminder_dark")
        assertDarkScreenshot("A6_reminder_dark", message: "Reminder 深色主题未生效")
    }

    func testA6_Export_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToExport()
        captureScreenshot("A6_export_dark")
        assertDarkScreenshot("A6_export_dark", message: "Export 深色主题未生效")
    }

    func testA6_About_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToAbout()
        captureScreenshot("A6_about_dark")
        assertDarkScreenshot("A6_about_dark", message: "About 深色主题未生效")
    }

    func testA6_AddCourse_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToAddCourseEmpty()
        captureScreenshot("A6_addCourse_dark")
        assertDarkScreenshot("A6_addCourse_dark", message: "AddCourse 深色主题未生效")
    }

    func testA6_EditTable_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToEditTableEmpty()
        captureScreenshot("A6_editTable_dark")
        assertDarkScreenshot("A6_editTable_dark", message: "EditTable 深色主题未生效")
    }

    func testA6_AllTables_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToAllTables()
        captureScreenshot("A6_allTables_dark")
        assertDarkScreenshot("A6_allTables_dark", message: "AllTables 深色主题未生效")
    }

    func testA6_SchoolSelect_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToSchoolSelect()
        captureScreenshot("A6_schoolSelect_dark")
        assertDarkScreenshot("A6_schoolSelect_dark",
                             message: "SchoolSelect 深色主题未生效:主体仍为浅色(regression: JW sheet 主题环境丢失)")
    }

    func testA6_ImportSheet_Dark() {
        launchApp(language: "zh-Hans", appearance: "dark")
        navigateToImportSheet()
        captureScreenshot("A6_importSheet_dark")
        assertDarkScreenshot("A6_importSheet_dark", message: "ImportSheet 深色主题未生效")
    }

    // MARK: - A.5 zh-CN/zh-TW runtime locale smoke

    func testA5_Schedule_zh_CN_Runtime() {
        // Apple runtime uses zh-Hans + zh_CN for the zh-CN locale.
        launchApp(language: "zh-Hans", appearance: "light")
        captureScreenshot("A5_schedule_zh-CN_light")
    }

    func testA5_Mine_zh_CN_Runtime() {
        launchApp(language: "zh-Hans", appearance: "light")
        switchToTab("mine")
        captureScreenshot("A5_mine_zh-CN_light")
    }

    func testA5_Schedule_zh_TW_Runtime() {
        launchApp(language: "zh-Hant", appearance: "light")
        captureScreenshot("A5_schedule_zh-TW_light")
    }

    func testA5_Mine_zh_TW_Runtime() {
        launchApp(language: "zh-Hant", appearance: "light")
        switchToTab("mine")
        captureScreenshot("A5_mine_zh-TW_light")
    }

}
