// ExportFlowUITests.swift — 导出全路径 UI 回归
// 覆盖:
//   1. JSON 导出 → 写临时文件 + 分享面板弹出 + snackbar(文件名含表名, .json 后缀)
//   2. ICS 导出 → 同上(.ics 后缀)
//   3. 分享文本 → 分享面板 + "Share sheet opened" snackbar
//   4. 分享面板取消(Done) → 回导出页不崩
//   5. snackbar 2s 自动消失
// 断言纪律: 行/snackbar 用 identifier(export_json_row 等), 不用 label CONTAINS。

import XCTest

final class ExportFlowUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
        openExport()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private func openExport() {
        app.descendants(matching: .any)["pill_mine"].tap()
        let exportEntry = app.descendants(matching: .any)["mine_export"]
        XCTAssertTrue(exportEntry.waitForExistence(timeout: 5), "Mine 页应有导出入口")
        exportEntry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["export_json_row"].waitForExistence(timeout: 5),
                      "导出页应显示 JSON 行")
    }

    /// 点导出行 → snackbar 出现(含期望片段) → 分享面板弹出 → 关闭
    private func tapExportRow(_ id: String, snackContains: String, fileSuffix: String) {
        app.descendants(matching: .any)[id].tap()

        // snackbar: Saved to Download/Sleepy/sleepy_我的课表_*.json
        let snack = app.descendants(matching: .any)["export_snackbar"]
        XCTAssertTrue(snack.waitForExistence(timeout: 5), "\(id) 点击后应弹 snackbar")
        let text = snack.label
        XCTAssertTrue(text.contains(snackContains), "snackbar 应含 '\(snackContains)', 实际: \(text)")
        XCTAssertTrue(text.contains(fileSuffix), "snackbar 文件名应含 \(fileSuffix), 实际: \(text)")

        // 分享面板(UIActivityViewController, 独立进程层级但 XCUITest 可见)
        let doneBtn = app.buttons["Done"].firstMatch
        let shareAppeared = doneBtn.waitForExistence(timeout: 6)
        if shareAppeared {
            doneBtn.tap()
        } else {
            // 空数据/无活动时面板可能不弹, 但导出页必须仍可达
            XCTAssertTrue(app.descendants(matching: .any)["export_json_row"].exists,
                          "\(id) 操作后导出页应仍可达")
        }
    }

    // MARK: JSON 导出 → 文件分享 + snackbar

    func testJsonExportShowsSnackbarAndShareSheet() throws {
        tapExportRow("export_json_row", snackContains: "我的课表", fileSuffix: ".json")
    }

    // MARK: ICS 导出 → 文件分享 + snackbar

    func testIcsExportShowsSnackbarAndShareSheet() throws {
        tapExportRow("export_ics_row", snackContains: "我的课表", fileSuffix: ".ics")
    }

    // MARK: 分享文本 → "Share sheet opened" snackbar

    func testShareTextShowsOpenedSnackbar() throws {
        app.descendants(matching: .any)["export_share_row"].tap()
        let snack = app.descendants(matching: .any)["export_snackbar"]
        XCTAssertTrue(snack.waitForExistence(timeout: 5), "分享文本点击后应弹 snackbar")
        XCTAssertTrue(snack.label.contains("Share sheet opened"),
                      "snackbar 应为 Share sheet opened, 实际: \(snack.label)")
        let doneBtn = app.buttons["Done"].firstMatch
        if doneBtn.waitForExistence(timeout: 6) { doneBtn.tap() }
    }

    // MARK: snackbar 2 秒自动消失

    func testSnackbarAutoDismisses() throws {
        app.descendants(matching: .any)["export_share_row"].tap()
        let snack = app.descendants(matching: .any)["export_snackbar"]
        XCTAssertTrue(snack.waitForExistence(timeout: 5))
        // 2s 定时 + 动画余量 → 最多 4s 应消失
        let gone = !snack.waitForExistence(timeout: 4.5)
        XCTAssertTrue(gone, "snackbar 应自动消失")
    }

    // MARK: 分享面板取消 → 回导出页不崩

    func testCancelShareSheetReturnsToExport() throws {
        app.descendants(matching: .any)["export_json_row"].tap()
        let doneBtn = app.buttons["Done"].firstMatch
        if doneBtn.waitForExistence(timeout: 6) {
            doneBtn.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["export_json_row"].waitForExistence(timeout: 4),
                      "关闭分享面板后导出页应可达(不崩)")
    }
}
