// ButtonHitAreaUITests.swift — a.v.1.0.41 按钮热区修复(用户报障端到端):
// "所有 material 按钮点击那一整条色块不行, 必须点击图标或者文字才触发"。
// 根因: PlainButtonStyle hit-test 只认 label 前景内容 glyph 边界, padding +
// background 色块不参与命中(Android Material 按钮整个 View bounds 可点)。
// 修复: SleepyButtonStyle(.plain 语义 + contentShape(Rectangle())), 全 app
// buttonStyle(.plain) 机械替换。
// 验证: 取按钮真实 frame, 点它的"色块边缘"(frame 内但文字 glyph 外,
// 归一化 dx=0.06 左边缘), 断言检查更新动作触发(结果 sheet 出现)。
// 注: XCUITest 合成 tap 部分场景走 accessibility 捷径, 本用例不能完全代表
// 真机手指 hit-test; 用例价值 = 回归保护 + 动作信号验证, 真机手感以用户验收为准。
import XCTest

final class ButtonHitAreaUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 点"色块但非文字"区域: 元素 frame 左边缘内 6% 处(图标/文字居中, 左 6% 必是纯色块)
    private func tapColorBlockOnly(_ el: XCUIElement) {
        guard el.waitForExistence(timeout: 8) else {
            XCTFail("元素不存在: \(el)")
            return
        }
        el.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
    }

    /// Mine → 关于页 "检查更新" 主按钮(整宽 44pt 色块, 最典型的用户报障形态)
    func testAboutCheckUpdateFullBlockClickable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))

        app.descendants(matching: .any)["pill_mine"].tap()
        let aboutEntry = app.descendants(matching: .any)["mine_about"]
        XCTAssertTrue(aboutEntry.waitForExistence(timeout: 8), "关于入口未出现")
        aboutEntry.tap()

        let checkUpdate = app.descendants(matching: .any)["about_check_update"]
        XCTAssertTrue(checkUpdate.waitForExistence(timeout: 8), "检查更新按钮未出现")
        // 点左边缘色块区(非图标非文字)→ checkUpdate() 触发。
        // 结果信号 = 任一结果 sheet 出现:
        //   - updateAvailable → "New version .../ Download / Cancel"
        //   - fetch 失败      → failed sheet(Cancel / Retry)
        // Checking 文字是瞬态不作锚点; Download 只在 updateAvailable 时出现不作锚点。
        tapColorBlockOnly(checkUpdate)
        let dialog = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'New version' OR label == 'Download' OR label == 'Retry' OR label == 'Cancel'"))
            .firstMatch
        let triggered = dialog.waitForExistence(timeout: 15)
        XCTAssertTrue(triggered, "点击按钮色块区(非文字/图标)应触发检查更新动作(结果 sheet 出现)")
    }
}
