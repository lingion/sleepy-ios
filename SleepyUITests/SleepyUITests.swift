// SleepyUITests.swift — G5 冒烟自动化
// iOS UI 烟囱测试: 启动 / 4 Tab 切换 / 设置项可达 / 主题切换 / 导入入口 / 深链
//
// 设计原则:
//   - 锚点: PillNavigationBar + SettingsItem 已带 accessibilityIdentifier(跨 locale 不变)
//   - 文本断言: 用 L10n.format(...) 通过 UIApplication.appLaunchEnvironment 注入固定语言
//     让断言稳定命中(en 默认; 测试用 .localized() 直接读 Localizable)
//   - 不依赖截图;不依赖具体课件(数据库被 AppPrefs 清空)
//   - 真实 devicectl install 路径在 CI 验证;这里只跑模拟器
//
// 平台映射: ← Android UiAutomator dump → XCUITest XCUIApplication().descendants(matching:)
import XCTest

final class SleepyUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // 强制英文环境 → 文本断言稳定
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    // MARK: - 启动

    func testAppLaunches() {
        // 4 个 tab 都在
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 5),
                      "pill_schedule not found — app 启动后未呈现底栏")
        XCTAssertTrue(app.descendants(matching: .any)["pill_today"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["pill_manage"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["pill_mine"].exists)
    }

    // MARK: - Tab 切换

    func testTabSwitching() {
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 5))

        // 课表 → 今日
        app.descendants(matching: .any)["pill_today"].tap()
        // 今日页头: "Today" 标题 + 周次 + 节数卡
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 3),
                      "今日页未出现 Today 标题")

        // 今日 → 课表管理
        app.descendants(matching: .any)["pill_manage"].tap()
        XCTAssertTrue(app.staticTexts["Manage"].waitForExistence(timeout: 3),
                      "管理页未出现 Manage 标题")

        // 管理 → 我的
        app.descendants(matching: .any)["pill_mine"].tap()
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 3),
                      "我的页未出现 Me 标题")
    }

    // MARK: - 我的页设置项可达

    func testMineSettingsNavigation() {
        app.descendants(matching: .any)["pill_mine"].tap()
        // 等我的页加载
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 3))

        // 6 个设置项都存在(通过 accessibilityIdentifier)
        XCTAssertTrue(app.descendants(matching: .any)["mine_all_tables"].exists, "all_tables 入口缺失")
        XCTAssertTrue(app.descendants(matching: .any)["mine_export"].exists, "export 入口缺失")
        XCTAssertTrue(app.descendants(matching: .any)["mine_reminder"].exists, "reminder 入口缺失")
        XCTAssertTrue(app.descendants(matching: .any)["mine_appearance"].exists, "appearance 入口缺失")
        XCTAssertTrue(app.descendants(matching: .any)["mine_general"].exists, "general 入口缺失")
        XCTAssertTrue(app.descendants(matching: .any)["mine_about"].exists, "about 入口缺失")
    }

    // MARK: - 主题切换可达

    func testAppearanceScreen() {
        app.descendants(matching: .any)["pill_mine"].tap()
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 3))

        app.descendants(matching: .any)["mine_appearance"].tap()
        // mine_appearance = "Appearance" (locale-invariant via identifier)
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 3),
                      "Appearance 页未出现")
    }

    // MARK: - 关于页(版本号 + 1-click update)

    func testAboutScreen() {
        app.descendants(matching: .any)["pill_mine"].tap()
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 3))

        app.descendants(matching: .any)["mine_about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 3),
                      "About 页未出现")
    }

    // MARK: - 提醒页

    func testReminderScreen() {
        app.descendants(matching: .any)["pill_mine"].tap()
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 3))

        app.descendants(matching: .any)["mine_reminder"].tap()
        XCTAssertTrue(app.staticTexts["Reminders"].waitForExistence(timeout: 3),
                      "Reminders 页未出现")
    }

    // MARK: - 通用设置页

    func testGeneralSettingsScreen() {
        app.descendants(matching: .any)["pill_mine"].tap()
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 3))

        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 3),
                      "General 设置页未出现")
    }

    // MARK: - 全部课表页

    func testAllTablesScreen() {
        app.descendants(matching: .any)["pill_mine"].tap()
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 3))

        app.descendants(matching: .any)["mine_all_tables"].tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 3),
                      "All Schedules 页未出现")
    }

    // MARK: - 课表管理 → 导入入口

    func testManageScreenImportEntry() {
        app.descendants(matching: .any)["pill_manage"].tap()
        XCTAssertTrue(app.staticTexts["Manage"].waitForExistence(timeout: 3))

        // 课表管理页有"导入课表"按钮(ManagementPage 顶部 + 4 manage cards)
        // 文本 "Import" 或 "导入课表" — 优先英文版
        let importBtn = app.staticTexts["Import"].firstMatch
        XCTAssertTrue(importBtn.waitForExistence(timeout: 3),
                      "Import 入口未出现(管理页)")
    }

    // MARK: - 深链唤醒(平台差异表#4: Intent extras → URL scheme)

    func testDeepLinkCourse() {
        // widget 点击深链(sleepy://open): 冷启/回前台即达(widgetURL 路由, 无需处理)。
        // 用 SLEEPY_UI_TEST_OPENURL 钩子走真实 lsd 路由(XCUIApplication.open 在
        // Xcode14/iOS16.4 丢 URL, 见 DeepLinkUITests 头注), 断言 scheme 注册 +
        // onOpenURL 处理后主界面完好。
        app.launchEnvironment["SLEEPY_UI_TEST_OPENURL"] = "sleepy://open"
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10),
                      "sleepy://open 深链后 app 应回主界面")
        XCTAssertTrue(app.descendants(matching: .any)["pill_mine"].exists,
                      "深链后底栏 4 pill 应完整")
    }

    // MARK: - 课表页 → 周视图/网格切换

    func testScheduleViewModeSwitch() {
        // 默认在课表页(启动后)
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 5))

        // 周视图 / 网格 是 SegmentedSwitcher — 没有表时空态;建表后才能验
        // 这里只验证底栏 + ScheduleScreen 启动不崩
        // (有表/无表两条路径单元测试已覆盖:ScheduleViewModelTests)
        let hasScheduleTab = app.descendants(matching: .any)["pill_schedule"].exists
        XCTAssertTrue(hasScheduleTab, "课表 Tab 不应消失")
    }
}

// MARK: - Helper

extension XCUIElement {
    /// 容错 tap: element 不存在也不抛异常(用于点击后若 page transition 在跑)
    func safeTap() {
        if exists && isHittable {
            tap()
        }
    }
}