// DeepLinkUITests.swift — 深链全路径回归(★ sleepyscheme 注册修复的回归锁)
// 背景: CFBundleURLTypes 缺失时 simctl/widget 深链报 -10814(构建产物无 scheme)。
// 覆盖:
//   1. sleepy://course/<有效id> → 课程详情/编辑页(种子课程 id 1-4 固定)
//   2. sleepy://course/<非法id> → 不崩溃, 留在主界面
//   3. sleepy://import?text=<json> → 切 Manage + 自动弹 Import Preview
//   4. sleepy://import?text=<空> → 不崩溃
// 机制: XCUIApplication.open(_:) (iOS 16.4+)。
// ★ iOS 16.4 模拟器: 自定义 scheme 首次 open 会被 lsd → SpringBoard
//   "Open in ...?" CFUserNotification 确认框拦截(URL 不进 app 进程),
//   测试必须直接 query springboard 点 Open/打开。审批一次后同 scheme 不再弹。
// 断言纪律: Manage/Import Preview 用页面唯一 identifier(manage_page_title/
//   import_preview_title), 底栏 pill 文本全局存在不能当 tab 切换证据。

import XCTest

final class DeepLinkUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.launch()
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
        app.launch()
        // 深链会切走主界面(course→编辑页, import→Manage), 等 URL 送达即可,
        // 不能再等 pill_schedule(编辑页弹出后 pill 不在层级)
        _ = app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10)
    }

    // MARK: 有效课程 id → 打开该课程编辑页(经 deepLinkCourse → editingCourse overlay)

    func testCourseDeepLinkOpensEditor() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("openURL 需要 iOS 16.4+") }
        app.descendants(matching: .any)["pill_schedule"].tap()
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

    // MARK: 导入深链(JSON 文本) → 切 Manage + 自动解析弹 Import Preview

    func testImportDeepLinkShowsPreview() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("openURL 需要 iOS 16.4+") }
        let json = "{\"name\":\"深链导入表\",\"startDate\":\"2026-08-24\",\"courses\":[{\"name\":\"操作系统\",\"teacher\":\"孙老师\",\"position\":\"教2-201\",\"day\":2,\"startNode\":1,\"step\":2,\"startWeek\":1,\"endWeek\":16,\"type\":0}]}"
        let encoded = json.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        try openDeepLink(URL(string: "sleepy://import?text=\(encoded)")!)
        // Manage 页唯一标题(底栏 "Manage" 全局存在, 不能当 tab 证据)
        XCTAssertTrue(app.descendants(matching: .any)["manage_page_title"]
            .waitForExistence(timeout: 8), "导入深链应切到 Manage 页")
        // ImportSheet.onAppear 消费 pending → ImportPreviewDialog
        XCTAssertTrue(app.descendants(matching: .any)["import_preview_title"]
            .waitForExistence(timeout: 8), "导入深链应自动弹 Import Preview(解析成功)")
        // 预览内容: 解析出的表名(PreviewInfoRow 不渲染逐课名, 表名是解析结果的可靠落点)
        XCTAssertTrue(app.descendants(matching: .any)["import_info_Schedule Name"]
            .waitForExistence(timeout: 5), "预览应显示解析出的课表名")
        let nameValue = app.descendants(matching: .any)["import_info_Schedule Name"].label
        XCTAssertTrue(nameValue.contains("深链导入表"),
                      "预览课表名应为 深链导入表, 实际: \(nameValue)")
    }

    // MARK: 空 import 文本 → 不崩溃(不弹预览)

    func testImportDeepLinkEmptyTextNoCrash() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("openURL 需要 iOS 16.4+") }
        try openDeepLink(URL(string: "sleepy://import?text=")!)
        // 空文本走 tab→Manage 但不弹预览; Manage 页稳定可达即不崩溃
        XCTAssertTrue(app.descendants(matching: .any)["manage_page_title"]
            .waitForExistence(timeout: 8), "空导入文本不应崩溃, Manage 页可达")
        XCTAssertFalse(app.descendants(matching: .any)["import_preview_title"].exists,
                       "空文本不应弹 Import Preview")
    }
}
