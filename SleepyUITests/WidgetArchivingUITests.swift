// WidgetArchivingUITests.swift — 验证 5 个 widget 在模拟器上能被 WidgetKit 成功归档。
//
// 测试策略:
//   1. 各 widget Provider 的 placeholder/getSnapshot/getTimeline 完成时向 App Group
//      写一行归档记录(widget_archive.log, 见 WidgetArchiveLog.swift —
//      真机排查 widget 空白的观测点)。
//   2. 启动 app (seed 数据) — 重装/启动触发 chronod 预渲染全部 kind × family
//      gallery placeholder 归档 → widget 扩展被拉起 → 日志出现全部 kind。
//   3. 归档日志的读取通道: runner 沙箱无 App Group 权限(containerURL 返回 nil),
//      由 app 进程透出 — Mine 页 -SLEEPY_WIDGET_LOG_HOOK 钩子把日志渲染成
//      accessibility 元素, 测试读 label 断言。
//
// 旧版读宿主机 `log stream` 写的 /tmp/sleepy_widget.log — 实测模拟器上
// processImagePath 谓词收不到 widget 扩展日志, 该带外流程已废弃。

import XCTest

final class WidgetArchivingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAllWidgetsArchiveSuccessfully() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED", "1", "-SLEEPY_WIDGET_LOG_HOOK"]
        app.launch()
        app.activate()

        // 切到 Mine 页(钩子元素在 Mine 页底部)
        XCTAssertTrue(app.descendants(matching: .any)["pill_mine"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["pill_mine"].tap()
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 5))

        let expectedKinds = [
            "TodayWidgetRV",
            "TwoDayWidgetRV",
            "WeekListWidgetRV",
            "WeekViewWidgetRV",
            "WeekGridWidgetV19",
        ]

        // kind×family 组合(supportedFamilies 总计 11):
        // Today: sm+md+lg, 其余 4 个: md+lg
        let expectedKindFamilies: [(String, String)] =
            [("TodayWidgetRV", "systemSmall"),
             ("TodayWidgetRV", "systemMedium"),
             ("TodayWidgetRV", "systemLarge"),
             ("TwoDayWidgetRV", "systemMedium"),
             ("TwoDayWidgetRV", "systemLarge"),
             ("WeekListWidgetRV", "systemMedium"),
             ("WeekListWidgetRV", "systemLarge"),
             ("WeekViewWidgetRV", "systemMedium"),
             ("WeekViewWidgetRV", "systemLarge"),
             ("WeekGridWidgetV19", "systemMedium"),
             ("WeekGridWidgetV19", "systemLarge")]

        // 归档批次在 app 安装/启动后 1-3 秒内跑完; 轮询 Mine 页日志钩子最多 60s
        let logEl = app.descendants(matching: .any)["widget_archive_log"]
        XCTAssertTrue(logEl.waitForExistence(timeout: 10),
                      "Mine 页未渲染 widget_archive_log 钩子 — 启动参数未生效?")

        let deadline = Date().addingTimeInterval(60)
        var logText = ""

        while Date() < deadline {
            logText = logEl.label + "\n" + logEl.value(as: String.self)
            let allPresent = expectedKinds.allSatisfy { kind in
                logText.contains("\(kind):")
            }
            if allPresent { break }
            // 刷新小组件按钮触发 reload → widget 扩展重新归档
            let refresh = app.descendants(matching: .any)["mine_refresh_widgets"]
            if refresh.exists { refresh.tap() }
            Thread.sleep(forTimeInterval: 3)
        }

        XCTAssertFalse(logText.contains("ARCHIVE_LOG_EMPTY"),
                       "归档日志为空 — widget 扩展未被拉起(App Group 不可写或 chronod 未触发)")
        XCTAssertFalse(logText.isEmpty, "归档日志 label 无内容")

        // 1. 无失败记录
        XCTAssertFalse(
            logText.lowercased().contains("error"),
            "WidgetKit 归档出现失败记录 — 见 widget_archive.log"
        )

        // 2. 每个 kind 至少一条 success
        for kind in expectedKinds {
            XCTAssertTrue(
                logText.contains("\(kind):") && logText.contains("success"),
                "widget kind 未成功归档: \(kind)"
            )
        }

        // 3. 每个 kind×family 组合至少一条归档(gallery placeholder 覆盖全部 family;
        //    归档行格式 "kind:family result")
        var missing = ""
        for (kind, family) in expectedKindFamilies {
            let prefix = "\(kind):\(family)"
            if !logText.contains(prefix) { missing += prefix + " " }
        }
        XCTAssertTrue(missing.isEmpty, "kind×family 归档缺失: \(missing)\nlog=\(logText)")
    }
}

private extension XCUIElement {
    /// label 之外再取 value(SwiftUI Text 的内容在 label, 部分元素在 value)
    func value<T>(as type: T.Type) -> String where T: LosslessStringConvertible {
        (value as? String) ?? ""
    }
}
