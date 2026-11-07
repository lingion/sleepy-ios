// GridPinchRowHeightUITests.swift — v1.0.64 双指捏放行高端到端回归。
// 验证链: 周 pager 上双指放大 → 顶栏出现未提交 tick(scale_keep) → 点 tick
// 提交 → tick 熄灭 + 值落盘 → relaunch 后 tick 仍不出现(持久化生效)。
// 注: pinchWithScale:velocity: 为 XCUIElement 无 availability 标注的老 API
// (SDK 头文件实证), 全测试运行时可用; 合成双指纵向 span 主导 → 触发
// locksVerticalResize。行为断言由用户真机/CI 执行(用户令)。
import XCTest

final class GridPinchRowHeightUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPinchShowsTickAndCommitPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"]
                        .waitForExistence(timeout: 10), "课表 tab 应出现")

        let pager = app.collectionViews["schedule_week_pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10), "周 pager 应存在(CourseDragUITests 同锚点)")

        let tick = app.descendants(matching: .any)["scale_keep"]
        XCTAssertFalse(tick.exists, "捏合前不应出现未提交 tick")

        // 双指放大(纵向 span 主导 → locksVerticalResize 置锁)
        pager.pinch(withScale: 1.5, velocity: 0.6)

        XCTAssertTrue(tick.waitForExistence(timeout: 5),
                      "双指放大应使顶栏出现 scale_keep(手势→scale→tick 链路)")

        tick.tap()
        let deadline = Date().addingTimeInterval(3)
        while tick.exists && Date() < deadline { usleep(100_000) }
        XCTAssertFalse(tick.exists, "tick 提交后应消失(值已落盘)")

        // 持久化: 重启后不该再出现未提交态
        app.terminate()
        app.launch()
        XCTAssertTrue(app.collectionViews["schedule_week_pager"]
                        .waitForExistence(timeout: 15), "重启后课表应恢复")
        XCTAssertFalse(app.descendants(matching: .any)["scale_keep"].exists,
                       "重启后 scale 应等于落盘值(无未提交差量)")
    }
}
