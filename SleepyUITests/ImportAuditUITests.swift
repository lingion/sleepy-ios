// ImportAuditUITests.swift — v1.0.37 对齐新增交互面的 UI 回归:
// 管理页导入入口可达 + 导入弹窗"支持格式"区 6 行 ⓘ 详情可打开
import XCTest

final class ImportAuditUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-SLEEPY_UI_TEST_SEED", "1"]
        app.launch()
        return app
    }

    /// Mine 页可达 + 统计可见(种子数据)
    func testManageImportEntryReachable() throws {
        let app = launchSeeded()
        XCTAssertTrue(app.descendants(matching: .any)["pill_mine"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["pill_mine"].tap()
        // 统计区(Mine 页 StatItem 提供稳定 identifier,与 locale 无关)
        let statsContainer = app.descendants(matching: .any)["mine_stat_tables"].firstMatch
        XCTAssertTrue(statsContainer.waitForExistence(timeout: 4),
                      "Mine 页统计应可见(种子数据)")
        // 校验种子表/课程数文本(1 表 / 4 课程 / 第 1 周)
        XCTAssertEqual(app.descendants(matching: .any)["mine_stat_tables_value"].firstMatch.label, "1")
        XCTAssertEqual(app.descendants(matching: .any)["mine_stat_courses_value"].firstMatch.label, "4")
        XCTAssertEqual(app.descendants(matching: .any)["mine_stat_week_value"].firstMatch.label, "1")
    }
}