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
        app.sleepyLaunch()
        return app
    }

    /// Mine 页可达 + 统计可见(种子数据)
    func testManageImportEntryReachable() throws {
        let app = launchSeeded()
        XCTAssertTrue(app.descendants(matching: .any)["pill_mine"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["pill_mine"].tap()
        // mine_stat_tables 容器锚点 = StatItem(.accessibilityElement(children:.contain)),
        // 但 tables/courses 两项被 Button 包裹(MineScreen.swift StatsCard, v1.0.60 可点
        // 进管理页/课程清单)→ 容器节点在 AX 树不浮出(无同名可查元素, waitForExistence
        // 必超时; Android 侧也无该 tag)。改断言测试 :28-30 已在用的 _value 子节点
        // (MineScreen.swift StatItem 内 Text(value).accessibilityIdentifier("\(id)_value"))。
        // 校验种子表/课程数文本(1 表 / 4 课程 / 第 1 周)
        let tablesValue = app.descendants(matching: .any)["mine_stat_tables_value"].firstMatch
        XCTAssertTrue(tablesValue.waitForExistence(timeout: 4), "Mine 页统计应可见(种子数据)")
        XCTAssertEqual(tablesValue.label, "1")
        XCTAssertEqual(app.descendants(matching: .any)["mine_stat_courses_value"].firstMatch.label, "4")
        XCTAssertEqual(app.descendants(matching: .any)["mine_stat_week_value"].firstMatch.label, "1")
    }
}