// NewScreensWiringUITests.swift — v1.0.60 新屏幕接线验证
// 验证: 我的页 → 作息表入口 → PeriodTablesScreen 真实可达(AppRoot overlay 挂载)
// 一次性验收测试; 同款模式参照 MineSettingsUITests。

import XCTest

final class NewScreensWiringUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testMinePeriodTablesEntryOpensScreen() {
        let app = XCUIApplication()
        app.sleepyLaunch()

        // 我的 tab(PillNavigationBar 的 id 约定 = pill_<item.id>)
        let mineTab = app.descendants(matching: .any)["pill_mine"]
        if mineTab.waitForExistence(timeout: 8) {
            mineTab.tap()
        } else {
            // 底栏无 id 时按坐标右起第一个(4 tab 布局: mine 最右)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.875, dy: 0.96)).tap()
        }

        // 作息表入口行
        let entry = app.descendants(matching: .any)["mine_period_tables"]
        XCTAssertTrue(entry.waitForExistence(timeout: 6), "我的页应有作息表入口行")
        entry.tap()

        // PeriodTablesScreen 出现(列表容器 id)
        let screen = app.descendants(matching: .any)["period_tables_screen"]
        XCTAssertTrue(screen.waitForExistence(timeout: 6), "点入口后应进入作息表管理页")
    }
}
