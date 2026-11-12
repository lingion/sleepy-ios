// DeepLinkUITests.swift — 深链全路径回归(★ sleepyscheme 注册修复的回归锁)
// 背景: CFBundleURLTypes 缺失时 simctl/widget 深链报 -10814(构建产物无 scheme)。
// 覆盖:
//   1. sleepy://course/<有效id> → 课程详情/编辑页(种子课程 id 1-4 固定)
//   2. sleepy://course/<非法id> → 不崩溃, 留在主界面
//   3. sleepy://import?text=<json> → 自动解析并进入新课表配置
//   4. sleepy://import?text=<空> → 保持课表可交互，不打开导入
// 机制: XCUIApplication.open(_:) (iOS 16.4+)。
// ★ iOS 16.4 模拟器: 自定义 scheme 首次 open 会被 lsd → SpringBoard
//   "Open in ...?" CFUserNotification 确认框拦截(URL 不进 app 进程),
//   测试必须直接 query springboard 点 Open/打开。审批一次后同 scheme 不再弹。
// 断言纪律: 导入用唯一配置标题和解析出的表名；空载荷用课表顶栏可交互性。
//   底栏 pill 文本全局存在，不能单独当作当前页面证据。

import XCTest

final class DeepLinkUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - helpers

    /// 深链注入: Xcode14/iOS16.4 模拟器 XCUIApplication.open(_:) 丢 URL
    /// (SpringBoard 只收到无 url 的 launch 请求, onOpenURL 永不触发, 见 2026-08-29 stream4 取证)。
    /// 改用 app 内自触发 UIApplication.open(SLEEPY_UI_TEST_OPENURL 环境变量),
    /// 走真实 lsd 路由, onOpenURL 照常触发。已授权 scheme 无确认框。
    private func openDeepLink(_ url: URL) throws {
        app.terminate()
        app.launchEnvironment["SLEEPY_UI_TEST_OPENURL"] = url.absoluteString
        app.sleepyLaunch()
        // 深链会切走主界面(course→编辑页, import→Manage), 等 URL 送达即可,
        // 不能再等 pill_schedule(编辑页弹出后 pill 不在层级)
        _ = app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10)
    }

    // MARK: 有效课程 id → 打开该课程编辑页(经 deepLinkCourse → editingCourse overlay)

    func testCourseDeepLinkOpensEditor() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("openURL 需要 iOS 16.4+") }
        app.switchToPillTab("schedule")
        try openDeepLink(URL(string: "sleepy://course/1")!)
        // 深链 → AddCourseScreen(标题 Edit Course), 姓名字段预填种子课名
        XCTAssertTrue(app.staticTexts["Edit Course"].waitForExistence(timeout: 8),
                      "课程深链应打开 Edit Course 编辑页")
        let nameField = app.descendants(matching: .any)["field_Course Name *"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "编辑页姓名字段缺失")
        // 预填值应为种子课程 id=1(高等数学)
        let value = nameField.value as? String ?? ""
        XCTAssertTrue(value.contains("高等数学"),
                      "深链课程 id=1 应为高等数学, 实际预填: \(value)")
    }

    // MARK: 非法课程 id → 不崩溃, 留在课表主页

    func testCourseDeepLinkInvalidIdStaysOnSchedule() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("openURL 需要 iOS 16.4+") }
        try openDeepLink(URL(string: "sleepy://course/99999")!)
        sleep(2)
        // 不崩溃: app 进程仍活且主界面可达(底栏 pill 可点击)
        XCTAssertTrue(app.descendants(matching: .any)["pill_today"].isHittable,
                      "非法 id 深链后 app 应回主界面不崩溃")
        // 不应打开任何编辑 overlay
        XCTAssertFalse(app.staticTexts["Edit Course"].exists,
                       "非法 id 不应打开编辑页")
    }

    // MARK: 导入深链(JSON 文本) → 解析成功后直接配置新课表

    func testImportDeepLinkShowsPreview() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("openURL 需要 iOS 16.4+") }
        let json = "{\"name\":\"深链导入表\",\"startDate\":\"2026-08-24\",\"courses\":[{\"name\":\"操作系统\",\"teacher\":\"孙老师\",\"position\":\"教2-201\",\"day\":2,\"startNode\":1,\"step\":2,\"startWeek\":1,\"endWeek\":16,\"type\":0}]}"
        let encoded = json.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        try openDeepLink(URL(string: "sleepy://import?text=\(encoded)")!)
        let configure = app.descendants(matching: .any)["import_confirm_title"].firstMatch
        XCTAssertTrue(configure.waitForExistence(timeout: 8),
                      "外部导入应自动进入新课表配置")
        let nameField = app.textFields["Schedule Name"].firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "新课表配置应有表名字段")
        XCTAssertEqual(nameField.value as? String, "深链导入表",
                       "配置页应预填真实解析出的表名")
        for id in ["import_mode_overwrite", "import_mode_append_only",
                   "import_mode_append_conflict", "import_mode_append_as_new"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].exists,
                           "外部新课表导入不能展示已有课表的覆盖或追加模式: \(id)")
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: 空 import 文本 → 保持课表且不打开导入

    func testImportDeepLinkEmptyTextNoCrash() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("openURL 需要 iOS 16.4+") }
        try openDeepLink(URL(string: "sleepy://import?text=")!)
        let share = app.buttons["topbar_share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 8), "空载荷应保留原课表")
        XCTAssertTrue(share.isEnabled && share.isHittable,
                      "空载荷后课表操作必须仍可交互")
        XCTAssertTrue(app.buttons["topbar_add"].firstMatch.isHittable)
        XCTAssertTrue(app.scheduleWeekPager.exists)
        XCTAssertFalse(app.descendants(matching: .any)["manage_page_title"].exists,
                       "空文本不应切换到管理页")
        for id in ["import_confirm_title", "import_preview_title", "import_text"] {
            XCTAssertFalse(app.descendants(matching: .any)[id].exists,
                           "空文本不应打开导入页面: \(id)")
        }
        XCTAssertFalse(app.staticTexts["Edit Course"].exists)
        XCTAssertEqual(app.state, .runningForeground)
    }
}
