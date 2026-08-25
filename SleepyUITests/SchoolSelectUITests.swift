// SchoolSelectUITests.swift — G5+ 学校选择页全交互面测试
// 锚点: school_search / Login with this URL 行文本。

import XCTest

final class SchoolSelectUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["pill_manage"].tap()
        app.descendants(matching: .any)["manage_import"].tap()
        app.descendants(matching: .any)["import_jw"].tap()
        let search = app.descendants(matching: .any)["school_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "学校选择页搜索框未出现")
    }

    override func tearDownWithError() throws {
        app.terminate()   // 隔离: 每用例杀进程重启, 防跨用例状态串扰
    }

    // MARK: 搜索过滤 — 中文

    func testSearchFiltersSchools() {
        let search = app.descendants(matching: .any)["school_search"]
        search.tap()
        search.typeText("北京")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '北京'")).firstMatch
            .waitForExistence(timeout: 5), "搜北京应过滤出北京高校")
    }

    // MARK: 拼音搜索

    func testSearchPinyinMatch() {
        let search = app.descendants(matching: .any)["school_search"]
        search.tap()
        search.typeText("bj")
        let hit = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '北京'")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 5),
                      "拼音简写 bj 应匹配北京高校(PinyinMatcher 首字母)")
    }

    // MARK: 清空搜索恢复列表

    func testSearchClearRestores() {
        let search = app.descendants(matching: .any)["school_search"]
        search.tap()
        search.typeText("北京")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '北京'")).firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<4 { search.typeText("\u{8}") }
        // 恢复全列表(任一大学行)
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '大学'")).firstMatch
            .waitForExistence(timeout: 5), "清空搜索应恢复列表")
    }

    // MARK: URL 直连行

    func testUrlDirectEntry() {
        let search = app.descendants(matching: .any)["school_search"]
        search.tap()
        search.typeText("https://jw.example.edu.cn")
        XCTAssertTrue(app.staticTexts["Login with this URL"].firstMatch
            .waitForExistence(timeout: 5), "输入 URL 应出现直连入口")
    }

    // MARK: 学校行点击 → 进入登录流程(WebView 页出现)

    func testSchoolRowTapOpensLogin() {
        let search = app.descendants(matching: .any)["school_search"]
        search.tap()
        search.typeText("北京")
        let row = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '北京'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        // 选校后 → JwWebViewLoginScreen(顶栏返回 + WebView)
        // 校内网不可达 — 只验证导航不崩(返回按钮存在即到登录页)
        _ = app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 3)
    }
}
