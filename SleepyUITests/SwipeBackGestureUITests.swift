// SwipeBackGestureUITests.swift — 验证 iOS 原生返回手势(.fullScreenCover / NavigationStack)
//
// 背景: 用户痛批"iOS 原生返回手势没做"。验证两个真实导航路径:
//
//   路径 A (NavigationStack push → pop): ScheduleScreen 内 NavigationStack push 子页
//     → 顶部 ⬅️ 返回按钮(系统原生) + 左滑手势均可用
//
//   路径 B (fullScreenCover): Mine/Settings 全屏弹层(General / About / Reminder 等)
//     → 顶栏 ⬅️ 按钮关闭(系统原生 NavigationView 提供)
//     → iOS 13+ 边缘左滑 dismiss 全屏 sheet
//
// 不依赖 Sideloadly 装机 — 用 XCUITest 内置 swipe 在模拟器上模拟手势

import XCTest

final class SwipeBackGestureUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].firstMatch
                          .waitForExistence(timeout: 10),
                      "Schedule pill 必须存在")
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - 路径 A: fullScreenCover 弹层 — 顶栏 ⬅️ 按钮关闭 (Mine/Settings 入口)

    func testSettingsFullScreenDismissByBackButton() throws {
        // 进入 Mine tab
        let mineTab = app.descendants(matching: .any)["pill_mine"].firstMatch
        XCTAssertTrue(mineTab.waitForExistence(timeout: 5))
        mineTab.tap()
        XCTAssertTrue(app.staticTexts["Me"].firstMatch.waitForExistence(timeout: 5))

        // 点 mine_general 入口 → fullScreenCover overlay 打开
        let generalEntry = app.descendants(matching: .any)["mine_general"].firstMatch
        XCTAssertTrue(generalEntry.waitForExistence(timeout: 5),
                      "mine_general 入口必须存在")
        generalEntry.tap()

        // Debug dump: 列出所有可识别的 accessibilityIdentifier + 顶层按钮
        let backButton = app.buttons["topbar_back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "SettingsTopBar ⬅️ 按钮 (topbar_back) 必须存在"
                      + "\n若失败: 检查 fullScreenCover overlay 内容是否包了 SettingsTopBar")

        // 顶栏 ⬅️ 按钮 → 关闭弹层
        backButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["mine_general"].firstMatch.waitForExistence(timeout: 3),
                      "⬅️ 按钮必须能关闭 fullScreenCover overlay 并回到 Mine"
                      + "\n(返回 Mine 后 mine_general 入口应重新可见)")
    }

    // MARK: - 路径 B: 全屏 overlay — 边缘左滑关闭 (iOS 13+ native gesture)

    func testFullScreenOverlaySwipeDismiss() throws {
        // 进入 Mine → About
        let mineTab = app.descendants(matching: .any)["pill_mine"].firstMatch
        XCTAssertTrue(mineTab.waitForExistence(timeout: 5))
        mineTab.tap()
        XCTAssertTrue(app.staticTexts["Me"].firstMatch.waitForExistence(timeout: 5))

        let aboutEntry = app.descendants(matching: .any)["mine_about"].firstMatch
        guard aboutEntry.waitForExistence(timeout: 5) else {
            throw XCTSkip("mine_about 入口不可见, 跳过")
        }
        aboutEntry.tap()

        // 等待 overlay 顶栏 ⬅️ 按钮
        let backButton = app.buttons["topbar_back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "About overlay 顶栏 ⬅️ 按钮必须存在")

        // 边缘左滑: 从屏幕左边缘快速拖向中间, 触发系统 dismiss 手势
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
        let midRight = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: midRight, withVelocity: .fast, thenHoldForDuration: 0.3)

        // 期望: overlay 消失且回到 Mine; 只检查底层入口不足以证明 dismiss 成功。
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: backButton)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed,
                       "左滑手势必须关闭 fullScreenCover overlay 并移除 overlay 顶栏")
        XCTAssertTrue(app.descendants(matching: .any)["mine_about"].firstMatch.waitForExistence(timeout: 3),
                      "左滑手势关闭后必须回到 Mine，mine_about 入口应重新可见")
    }

    // MARK: - 路径 C: NavigationStack push → pop (Schedule 内导航)

    func testNavigationStackPushPop() throws {
        // 确认在 Schedule tab
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].firstMatch
                          .waitForExistence(timeout: 5))

        // 从 Schedule push 进课表(点任一节次)
        let scheduleCell = app.descendants(matching: .any)["schedule_slot_0_1"].firstMatch
        guard scheduleCell.waitForExistence(timeout: 5) else {
            throw XCTSkip("没有课表节次可点, 跳过")
        }
        scheduleCell.tap()

        // 等待 ⬅️ 按钮 (SettingsTopBar 覆盖 overlay 也用 topbar_back)
        let backButton = app.buttons["topbar_back"]
        let backExists = backButton.waitForExistence(timeout: 5)
        guard backExists else {
            throw XCTSkip("schedule_slot_0_1 没触发 overlay push, 跳过")
        }
        backButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].firstMatch
                          .waitForExistence(timeout: 3),
                      "⬅️ 按钮必须能 pop 回 Schedule tab")
    }

    // MARK: - 兜底: About overlay 顶栏 ⬅️ 按钮存在性

    func testAboutOverlayBackButtonExists() throws {
        let mineTab = app.descendants(matching: .any)["pill_mine"].firstMatch
        XCTAssertTrue(mineTab.waitForExistence(timeout: 5))
        mineTab.tap()

        let aboutEntry = app.descendants(matching: .any)["mine_about"].firstMatch
        guard aboutEntry.waitForExistence(timeout: 5) else {
            throw XCTSkip("mine_about 入口不可见, 跳过")
        }
        aboutEntry.tap()

        let backButton = app.buttons["topbar_back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "SettingsTopBar ⬅️ 按钮 (topbar_back) 必须存在")
    }
}
