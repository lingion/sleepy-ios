// FileImportUITests.swift — 文件导入 UI 路径(系统面板层)
// 覆盖:
//   1. File 行 → 系统 fileImporter 面板弹出
//   2. 面板取消 → 回 ImportSheet 不崩, 无预览误弹
// 说明: 面板内选文件依赖模拟器 Files app 内容(不可脚本化注入), "选文件→读取→预览"
//   的核心逻辑由 unit 层 ExportImportRoundTrip/ParserAudit + buildImportPreview 覆盖;
//   此处锁定 UI 到系统面板的桥接与取消路径。
// ★ iOS16 模拟器 fileImporter 面板是 remote view, 元素树经 app 折射, 断言用 Documents/Fil
//   e 面板特征元素; 若面板未弹出立即失败。

import XCTest

final class FileImportUITests: XCTestCase {

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

    private func openImportSheet() {
        app.descendants(matching: .any)["pill_manage"].tap()
        let title = app.descendants(matching: .any)["manage_page_title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "应切到 Manage 页")
        // manage_import 卡 → ImportSheet(sheet) 弹出, 文件行即可见
        let importCard = app.descendants(matching: .any)["manage_import"]
        XCTAssertTrue(importCard.waitForExistence(timeout: 5), "导入卡应存在")
        importCard.tap()
        let fileRow = app.descendants(matching: .any)["import_file"]
        XCTAssertTrue(fileRow.waitForExistence(timeout: 5), "ImportSheet 应弹出(文件行可见)")
    }

    // MARK: File 行 → 系统文件面板弹出 → 取消 → 回 ImportSheet

    func testFilePickerCancelReturnsToSheet() throws {
        openImportSheet()
        app.descendants(matching: .any)["import_file"].tap()

        // 系统面板: 特征元素( Buttons: Browse/Cancel/Docs 或导航栏)。remote view 折射下
        // 最稳的是 Cancel 按钮或 "Documents" 导航标题, 双保险等待任一出现。
        let cancel = app.buttons["Cancel"].firstMatch
        let browse = app.buttons["Browse"].firstMatch
        let appeared = cancel.waitForExistence(timeout: 6) || browse.waitForExistence(timeout: 2)
        XCTAssertTrue(appeared, "点文件行应弹系统文件面板")

        if cancel.exists {
            cancel.tap()
        } else if browse.exists {
            // Browse 形态下先退一层再找 Cancel
            browse.tap()
            let cancel2 = app.buttons["Cancel"].firstMatch
            XCTAssertTrue(cancel2.waitForExistence(timeout: 4), "Browse 后应有 Cancel")
            cancel2.tap()
        }

        // 回到 ImportSheet: 文件行仍在, 无预览误弹
        XCTAssertTrue(app.descendants(matching: .any)["import_file"].waitForExistence(timeout: 5),
                      "取消后应回 ImportSheet")
        XCTAssertFalse(app.descendants(matching: .any)["import_preview_title"].exists,
                       "取消选文件不应弹预览")
    }
}
