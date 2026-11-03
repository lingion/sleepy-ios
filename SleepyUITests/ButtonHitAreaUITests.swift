// ButtonHitAreaUITests.swift — a.v.1.0.41 按钮热区修复(用户报障端到端):
// "所有 material 按钮点击那一整条色块不行, 必须点击图标或者文字才触发"。
// 根因: PlainButtonStyle hit-test 只认 label 前景内容 glyph 边界, padding +
// background 色块不参与命中(原版本 Material 按钮整个 View bounds 可点)。
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
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))

        app.switchToPillTab("mine")
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
        // 结果信号有两条(按 UpdateManager 结果分支):
        //   - 有更新  → sheet: "New version ... / Download / Cancel"
        //   - 已是最新 → snackbar "You're on the latest version vX"(不是 sheet!)
        //   - 拉取失败 → sheet: "Retry / Cancel"
        // ★ v1.0.62 对齐修正: 旧版只等 sheet 标签, 而「无更新」分支走 snackbar
        //   (AboutScreen.checkUpdate → uiState == .idle + snackMessage),
        //   于是 app 行为正确却被判失败 25s 超时。
        //   现改为「snackbar 或 sheet 任一出现」即视为动作已触发。
        let dialog = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'New version' OR label == 'Download' OR label == 'Retry' OR label == 'Cancel'"))
            .firstMatch
        let snackbar = app.descendants(matching: .any)["about_snackbar"]
        // 25s: fetch 走 UpdateManager 15s 超时(对齐 原版本 connectTimeout)→
        // failed sheet 最迟 ~15s+渲染 才出现; 15s 等待与 app 超时同值必竞态
        //
        // ★ 条件等待(轮询), 不给固定 sleep。
        //   注: 不能用 XCTNSPredicateExpectation —— 它的 predicate 在**后台线程**
        //   求值, 而 XCUIElement 查询只在主线程有效 ⇒ 谓词永远取不到真实状态,
        //   于是「app 已经出了 snackbar」也会被判失败。
        //   这里在主线程手动轮询两个信号。
        let deadline = Date().addingTimeInterval(25)
        var triggered = false
        while Date() < deadline {
            if dialog.exists || snackbar.exists { triggered = true; break }
            usleep(300_000)   // 0.3s
        }
        XCTAssertTrue(triggered,
                      "点击按钮色块区(非文字/图标)应触发检查更新动作(snackbar 或结果 sheet 出现)")
    }
}
