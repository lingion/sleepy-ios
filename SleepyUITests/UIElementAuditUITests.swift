// UIElementAuditUITests.swift — v1.0.34 UI对齐审计专用
// 用途:捕获完整UI元素+点击矩阵截图,作为对齐审计可验证证据。
// 约束:不删不改任何已有测试;仅追加本文件。
// 运行: xcodebuild test -scheme Sleepy -destination 'platform=iOS Simulator,id=E457BAD9-947A-469A-BD6B-0286F69267CD' -only-testing:SleepyUITests/UIElementAuditUITests

import XCTest
import CoreGraphics

final class UIElementAuditUITests: XCTestCase {

    var app: XCUIApplication!
    /// 截图落盘目录。
    /// ★ 原为硬编码外部机器路径 "/Users/lingion_k/Desktop/sleepy-ios/audit_shots",
    ///   在别的机器上该目录不存在 → `try? data.write(to:)` 静默失败, PNG 从未落盘,
    ///   随后 `assertDarkScreenshot` 的 `CGDataProvider(url:)` 解码必然失败 →
    ///   A6_* 深色矩阵 10 个用例全部报「无法解码截图」(测试夹具缺陷, 非产品缺陷)。
    /// 改为进程临时目录并在 setUp 里创建, 保证可写。
    var outputDir: String = NSTemporaryDirectory() + "sleepy_audit_shots"

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        try? FileManager.default.createDirectory(atPath: outputDir,
                                                withIntermediateDirectories: true)
        // 默认:Light + zh-Hans (通过 AppleLanguages/zh-Hans 注入)
        // 注意:-SLEEPY_UI_TEST_SEED 触发种子数据
    }

    override func tearDownWithError() throws {
        // 每个测试方法后终止,确保下个测试干净状态
        app.terminate()
    }

    // MARK: - 辅助方法

    private func launchApp(language: String = "zh-Hans", appearance: String = "light", uiStyle: String? = nil) {
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
        if let uiStyle { app.launchArguments += ["-ui_style", uiStyle] }
        app.sleepyLaunch()

        // 等待 Pill 栏出现(种子后)
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10),
                      "App launch failed or seed not applied")
        sleep(2) // 动画稳定
    }

    private func captureScreenshot(named name: String) {
        // Selection traits update before the production 0.42s content spring.
        // Let that transition finish so captures show a stable page rather than
        // the outgoing schedule superimposed on the incoming management page.
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
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
        // ★ 复用统一 helper: 断言「真的切过去了」(选中 trait 翻转)并对被吞掉的 tap 重试。
        //   旧写法 tap + sleep 无切换断言 → tap 丢失时错误现场与病因脱节。
        app.switchToPillTab(tabId)
    }

    // MARK: - 导航到子页面

    private func waitForAuditCondition(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        return condition()
    }

    /// Reveal the complete control inside its foreground scroll area and above the dock.
    /// Short drags can recover in either direction without jumping past a nearby row.
    private func revealAuditControl(_ element: XCUIElement,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        func owningScroll() -> XCUIElement? {
            let containers = app.scrollViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
                + app.collectionViews.allElementsBoundByIndex
            return containers.reversed().first { container in
                guard container.exists else { return false }
                let query = container.descendants(matching: element.elementType)
                return element.identifier.isEmpty
                    ? query.matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
                    : query.matching(identifier: element.identifier).firstMatch.exists
            }
        }
        func viewport(_ scroll: XCUIElement?) -> CGRect {
            var frame = app.windows.firstMatch.frame.insetBy(dx: 2, dy: 4)
            if let scroll { frame = frame.intersection(scroll.frame) }
            if let back = app.buttons.matching(identifier: "topbar_back").allElementsBoundByIndex.last(where: { $0.isHittable }),
               back.frame.minY < frame.midY {
                let bottom = frame.maxY
                frame.origin.y = max(frame.minY, back.frame.maxY + 4)
                frame.size.height = max(0, bottom - frame.minY)
            }
            let dockFrames = ["pill_schedule", "pill_today", "pill_manage", "pill_mine"]
                .map { app.buttons[$0].firstMatch }.filter { $0.exists && $0.isHittable }.map(\.frame)
            if let first = dockFrames.first {
                let dock = dockFrames.dropFirst().reduce(first) { $0.union($1) }
                if dock.width > dock.height, dock.minY > frame.midY {
                    frame.size.height = max(0, min(frame.maxY, dock.minY - 4) - frame.minY)
                }
            }
            if let keyboard = app.keyboards.allElementsBoundByIndex.first {
                frame.size.height = max(0, min(frame.maxY, keyboard.frame.minY - 44) - frame.minY)
            }
            return frame
        }
        func visible() -> Bool {
            element.exists && element.isHittable && element.frame.width > 0 && element.frame.height > 0
                && viewport(owningScroll()).contains(element.frame)
        }
        for _ in 0..<16 {
            if visible() { return }
            let area = viewport(owningScroll())
            guard area.width > 0, area.height > 0 else { break }
            let earlier = element.frame.minY < area.minY
            let start = CGPoint(x: area.midX, y: area.minY + area.height * (earlier ? 0.40 : 0.65))
            let end = CGPoint(x: area.midX, y: area.minY + area.height * (earlier ? 0.58 : 0.47))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: start.x, dy: start.y)).press(forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: end.x, dy: end.y)))
        }
        XCTAssertTrue(waitForAuditCondition { visible() },
                      "The complete control must be visible above navigation and keyboard", file: file, line: line)
    }

    private func tapAuditBack(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.buttons.matching(identifier: "topbar_back").allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(back, "The foreground page must expose its back action", file: file, line: line)
        back?.tap()
    }

    /// 点 Mine 设置项(SettingsItem 是 Button,identifier 前缀 mine_)并断言子页真实打开。
    private func openMineSetting(_ itemId: String, assertAnchor anchorId: String, scroll _: Bool = true) {
        switchToTab("mine")
        let item = app.buttons[itemId].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Mine 设置项 \(itemId) 未找到")
        revealAuditControl(item)
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
        switchToTab("manage")
        let export = app.descendants(matching: .any)["manage_export"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        XCTAssertTrue(app.buttons["topbar_back"].firstMatch.waitForExistence(timeout: 5))
    }

    private func navigateToAbout() {
        openMineSetting("mine_about", assertAnchor: "topbar_back")
    }

    private func navigateToAllTables() {
        openMineSetting("mine_all_tables", assertAnchor: "topbar_back", scroll: false)
    }

    private func navigateToAddCourseEmpty() {
        // 管理页先选择添加方式，再进入手动课程表单。
        switchToTab("manage")
        let addBtn = app.buttons["manage_add_course"].firstMatch
        XCTAssertTrue(addBtn.waitForExistence(timeout: 5), "manage_add_course 未找到")
        addBtn.tap()
        let manual = app.buttons["import_manual"].firstMatch
        XCTAssertTrue(manual.waitForExistence(timeout: 5), "添加课程方式页缺少手动入口")
        manual.tap()
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
        // Mine 有三个统计卡:mine_stat_tables / mine_stat_courses / mine_stat_period_tables
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
        navigateToAddCourseEmpty()
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

    // MARK: - A.9 Remaining schedule and widget navigation surfaces

    func testA9_ScheduleViewsAndTopTablePickerCapture() {
        launchApp(language: "en", uiStyle: "classic")
        let gridCourse = app.descendants(matching: .any)["gridcell_1"].firstMatch
        XCTAssertTrue(gridCourse.waitForExistence(timeout: 10))
        captureScreenshot("A9_schedule-grid")
        let switchTable = app.buttons["switch_table"].firstMatch
        revealAuditControl(switchTable)
        switchTable.tap()
        let table = app.buttons["switch_table_1"].firstMatch
        revealAuditControl(table)
        XCTAssertTrue(table.label.contains("我的课表"))
        captureScreenshot("A9_schedule-top-table-picker")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.015, dy: 0.5)).tap()
        XCTAssertTrue(waitForAuditCondition { !table.exists && gridCourse.exists })
        let week = app.buttons["seg_Week"].firstMatch
        revealAuditControl(week)
        week.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lesson_1"].firstMatch.waitForExistence(timeout: 10))
        captureScreenshot("A9_schedule-week-view")
        let grid = app.buttons["seg_Grid"].firstMatch
        revealAuditControl(grid)
        grid.tap()
        XCTAssertTrue(gridCourse.waitForExistence(timeout: 10))
    }

    func testA9_ScheduleSettingsMiddleAndBottomCapture() {
        launchApp(language: "en", uiStyle: "classic")
        openMineSetting("mine_schedule_settings", assertAnchor: "schedule_display_settings")
        let week = app.staticTexts["Two-column week view"].firstMatch
        revealAuditControl(week)
        captureScreenshot("A9_schedule-settings-week-content")
        let subInfo = app.staticTexts["Grid card sub-info"].firstMatch
        revealAuditControl(subInfo)
        captureScreenshot("A9_schedule-settings-grid-content")
        let pinch = app.staticTexts["Pinch to resize rows"].firstMatch
        revealAuditControl(pinch)
        captureScreenshot("A9_schedule-settings-grid-advanced")
        let conflict = app.staticTexts["Conflicting course style"].firstMatch
        revealAuditControl(conflict)
        captureScreenshot("A9_schedule-settings-conflicts")
        let holiday = app.buttons["settings_holiday_entry"].firstMatch
        revealAuditControl(holiday)
        captureScreenshot("A9_schedule-settings-holidays-bottom")
        tapAuditBack()
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 10))
    }

    func testA9_WidgetSettingsAndManagementEmptyStateCapture() {
        launchApp(language: "en", uiStyle: "classic")
        openMineSetting("mine_widget", assertAnchor: "settings_widget_manage_entry")
        let manage = app.buttons["settings_widget_manage_entry"].firstMatch
        revealAuditControl(manage)
        captureScreenshot("A9_widget-settings")
        manage.tap()
        let add = app.buttons["widget_gallery_add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        let empty = app.buttons["widget_empty_gallery"].firstMatch
        revealAuditControl(empty)
        captureScreenshot("A9_widget-management-empty-state")
        tapAuditBack()
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        tapAuditBack()
        XCTAssertTrue(app.buttons["mine_widget"].waitForExistence(timeout: 10))
    }

    // MARK: - A.8 Theme and whole-course editor surfaces

    func testA8_CustomThemeRolesAndNativePickerCapture() {
        launchApp(language: "en", uiStyle: "classic")
        openMineSetting("mine_appearance", assertAnchor: "theme_system_card")
        let create = app.buttons["theme_new_entry"].firstMatch
        revealAuditControl(create)
        create.tap()
        let name = app.descendants(matching: .any)["field_Theme name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        captureScreenshot("A8_custom-theme-editor")
        let seed = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Build from a primary color")).firstMatch
        revealAuditControl(seed)
        seed.tap()
        let pickerCancel = app.navigationBars.buttons["Cancel"].firstMatch
        XCTAssertTrue(pickerCancel.waitForExistence(timeout: 10))
        captureScreenshot("A8_theme-seed-native-color-picker")
        pickerCancel.tap()
        XCTAssertTrue(waitForAuditCondition { !pickerCancel.exists && name.exists })
        let manual = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Pick roles manually")).firstMatch
        revealAuditControl(manual)
        manual.tap()
        let primary = app.buttons["theme_role_Primary"].firstMatch
        revealAuditControl(primary)
        captureScreenshot("A8_custom-theme-role-colors")
        primary.tap()
        XCTAssertTrue(pickerCancel.waitForExistence(timeout: 10))
        captureScreenshot("A8_theme-primary-native-color-picker")
        pickerCancel.tap()
        XCTAssertTrue(waitForAuditCondition { !pickerCancel.exists && primary.exists })
        tapAuditBack()
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        let recalc = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Re-arrange all course colors")).firstMatch
        revealAuditControl(recalc)
        captureScreenshot("A8_appearance-course-colors-lower")
    }

    func testA8_ExistingCourseFieldsColorAndDeleteCancelCapture() {
        launchApp(language: "en", uiStyle: "classic")
        let course = app.descendants(matching: .any)["gridcell_1"].firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 10))
        course.tap()
        let edit = app.buttons["detail_edit"].firstMatch
        revealAuditControl(edit)
        captureScreenshot("A8_course-detail-portrait")
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit Course"].firstMatch.waitForExistence(timeout: 10))
        captureScreenshot("A8_existing-course-editor-top")
        let groupColor = app.buttons["Change group color"].firstMatch
        revealAuditControl(groupColor)
        groupColor.tap()
        let cancelColor = app.navigationBars.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancelColor.waitForExistence(timeout: 10))
        captureScreenshot("A8_existing-course-group-color-picker")
        cancelColor.tap()
        XCTAssertTrue(waitForAuditCondition { !cancelColor.exists && groupColor.exists })
        let addSlot = app.buttons["course_add_slot"].firstMatch
        revealAuditControl(addSlot)
        captureScreenshot("A8_existing-course-editor-slots")
        let delete = app.buttons["course_delete"].firstMatch
        revealAuditControl(delete)
        captureScreenshot("A8_existing-course-editor-bottom")
        delete.tap()
        let confirmation = app.alerts["Confirm Delete"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 10))
        XCTAssertTrue(confirmation.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "高等数学")).firstMatch.exists)
        captureScreenshot("A8_existing-course-delete-confirmation")
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(waitForAuditCondition { !confirmation.exists && delete.exists })
        tapAuditBack()
        XCTAssertTrue(course.waitForExistence(timeout: 10), "Canceling deletion must retain the existing course")
    }

    // MARK: - A.7 Secondary surfaces captured through their production routes

    func testA7_ExportTargetAndCalendarConfigurationCapture() {
        launchApp(language: "en", uiStyle: "classic")
        navigateToExport()
        let targetCard = app.buttons["export_table_card"].firstMatch
        revealAuditControl(targetCard)
        targetCard.tap()
        let tableRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'export_table_row_'"))
            .firstMatch
        revealAuditControl(tableRow)
        XCTAssertTrue(tableRow.label.contains("我的课表"))
        captureScreenshot("A7_export-target-picker")
        // The picker dismisses on its scrim; no export target is changed.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.015, dy: 0.5)).tap()
        XCTAssertTrue(waitForAuditCondition { !tableRow.exists })

        let calendarEntry = app.buttons["export_calendar_import_row"].firstMatch
        revealAuditControl(calendarEntry)
        calendarEntry.tap()
        let systemAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if systemAlert.waitForExistence(timeout: 3) {
            let allow = systemAlert.buttons.matching(NSPredicate(format: "label IN %@", [
                "Allow Full Access", "Allow Access to All Events", "Allow", "OK",
                "允许完全访问", "允许访问所有日程", "允许", "好"
            ])).firstMatch
            XCTAssertTrue(allow.waitForExistence(timeout: 5), "Calendar permission must expose an explicit allow action")
            allow.tap()
        }
        let calendar = app.descendants(matching: .any)["calendar_import_dialog"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        let calendarTarget = app.buttons["calendar_target_picker"].firstMatch
        revealAuditControl(calendarTarget)
        captureScreenshot("A7_calendar-target-configuration")
        let range = app.buttons["calendar_range_NEXT_WEEK"].firstMatch
        revealAuditControl(range)
        XCTAssertTrue(app.staticTexts["Import range"].exists)
        captureScreenshot("A7_calendar-range-configuration")
        let cancel = calendar.buttons["Cancel"].firstMatch
        revealAuditControl(cancel)
        cancel.tap()
        XCTAssertTrue(waitForAuditCondition { !calendar.exists })
        XCTAssertTrue(calendarEntry.exists, "Cancel must return to export without writing events")
    }

    func testA7_BellScheduleRebindPreviewCanCancelCapture() {
        launchApp(language: "en", uiStyle: "classic")
        switchToTab("manage")
        let periods = app.buttons["manage_period_tables"].firstMatch
        revealAuditControl(periods)
        periods.tap()
        let newPeriod = app.buttons["period_tables_new"].firstMatch
        revealAuditControl(newPeriod)
        newPeriod.tap()
        let name = app.descendants(matching: .any)["field_Bell schedule name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        let slots = app.buttons["period_table_slots_header"].firstMatch
        revealAuditControl(slots)
        slots.tap()
        revealAuditControl(name)
        let oldName = name.value as? String ?? ""
        let sourceName = "Capture bell \(UUID().uuidString.prefix(8))"
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count))
        app.typeText(sourceName + "\n")
        XCTAssertTrue(waitForAuditCondition { !self.app.keyboards.firstMatch.exists })
        XCTAssertEqual(name.value as? String, sourceName)
        let savePeriod = app.buttons["period_table_save"].firstMatch
        revealAuditControl(savePeriod)
        savePeriod.tap()
        let savePreview = app.buttons["period_table_preview_confirm"].firstMatch
        revealAuditControl(savePreview)
        captureScreenshot("A7_bell-schedule-save-preview")
        savePreview.tap()
        XCTAssertTrue(waitForAuditCondition { !savePreview.exists })
        switchToTab("manage")
        let edit = app.buttons["manage_edit_current"].firstMatch
        revealAuditControl(edit)
        edit.tap()
        let tableSlots = app.buttons["edit_table_slots_header"].firstMatch
        revealAuditControl(tableSlots)
        tableSlots.tap()
        let bellTab = app.buttons["seg_Bell schedule"].firstMatch
        revealAuditControl(bellTab)
        bellTab.tap()
        let source = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", sourceName)).firstMatch
        revealAuditControl(source)
        source.tap()
        let saveTable = app.buttons["edit_table_save"].firstMatch
        revealAuditControl(saveTable)
        saveTable.tap()
        let rebind = app.alerts["Confirm rebind"].firstMatch
        XCTAssertTrue(rebind.waitForExistence(timeout: 10))
        XCTAssertTrue(rebind.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'custom-time courses are unaffected'")).firstMatch.exists)
        captureScreenshot("A7_bell-schedule-rebind-preview")
        rebind.buttons["Cancel"].tap()
        XCTAssertTrue(waitForAuditCondition { !rebind.exists })
        revealAuditControl(saveTable)
        // A canceled rebind is still pending; saving again must ask before any commit.
        saveTable.tap()
        XCTAssertTrue(rebind.waitForExistence(timeout: 10), "A canceled rebind must ask again before saving")
        rebind.buttons["Cancel"].tap()
        XCTAssertTrue(waitForAuditCondition { !rebind.exists })
        tapAuditBack()
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
    }

    func testA7_WidgetSharedDisplayAndPeriodHeadersCapture() {
        launchApp(language: "en", uiStyle: "classic")
        openMineSetting("mine_widget", assertAnchor: "settings_widget_manage_entry")
        let shared = app.buttons["settings_widget_shared_display"].firstMatch
        revealAuditControl(shared)
        shared.tap()
        let display = app.descendants(matching: .any)["schedule_display_settings"].firstMatch
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Schedule settings"].firstMatch.isHittable)
        captureScreenshot("A7_widget-shared-display")
        let headers = app.buttons["settings_period_header"].firstMatch
        revealAuditControl(headers)
        captureScreenshot("A7_shared-display-period-header-entry")
        headers.tap()
        XCTAssertTrue(app.staticTexts["Period headers"].firstMatch.waitForExistence(timeout: 10))
        let preview = app.staticTexts["Live preview"].firstMatch
        revealAuditControl(preview)
        captureScreenshot("A7_period-headers-live-preview")
        let layout = app.staticTexts["Layout"].firstMatch
        revealAuditControl(layout)
        captureScreenshot("A7_period-headers-layout")
        tapAuditBack()
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        tapAuditBack()
        XCTAssertTrue(shared.waitForExistence(timeout: 10))
        tapAuditBack()
        XCTAssertTrue(app.buttons["mine_widget"].waitForExistence(timeout: 10))
    }

}
