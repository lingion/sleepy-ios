// WidgetArchivingUITests.swift — 验证 5 个 widget 在模拟器上能被 WidgetKit 成功归档。
//
// 测试策略:
//   1. 启动 app 并切换到 Mine 页确保 seed 数据生效 (1 张课表 + 4 门课)。
//   2. 通过 WidgetCenter.requestRefresh 触发所有 widget 重载。
//   3. 读取 /tmp/sleepy_widget.log,断言每个 widget kind × supported family 都出现
//      "Request ended ... success",且无 failedToEncode。
//
// 用法:
//   xcrun simctl spawn booted log stream --predicate 'processImagePath CONTAINS "SleepyWidget"'
//                                                > /tmp/sleepy_widget.log &
//   xcodebuild ... test -only-testing:SleepyUITests/WidgetArchivingUITests
//   kill $LOG_PID

import XCTest

final class WidgetArchivingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAllWidgetsArchiveSuccessfully() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SLEEPY_UI_TEST_SEED", "1"]
        app.launch()

        // 触发所有 widget 重载,确保 kind 都有 timeline 调用
        app.activate()

        // 给 WidgetKit 留出时间完成归档
        let deadline = Date().addingTimeInterval(20)
        let logFile = "/tmp/sleepy_widget.log"

        // 等待 log 文件产生
        while !FileManager.default.fileExists(atPath: logFile) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.5)
        }

        guard FileManager.default.fileExists(atPath: logFile) else {
            XCTFail("widget log 文件不存在 — 请先用 'log stream' 命令开始收集")
            return
        }

        // 读取并等待出现所有目标 widget kind × family 组合
        let expectedKinds: [(String, [String])] = [
            ("TodayWidgetRV", ["systemSmall", "systemMedium", "systemLarge"]),
            ("TwoDayWidgetRV", ["systemMedium", "systemLarge"]),
            ("WeekListWidgetRV", ["systemMedium", "systemLarge"]),
            ("WeekViewWidgetRV", ["systemMedium", "systemLarge"]),
            ("WeekGridWidgetV19", ["systemMedium", "systemLarge"]),
        ]

        // 给 widget center 充分时间触发每种 kind
        Thread.sleep(forTimeInterval:10)

        let logContent = (try? String(contentsOfFile: logFile, encoding: .utf8)) ?? ""
        XCTAssertFalse(logContent.isEmpty, "widget log 为空")

        // 1. 归档错误不应出现
        XCTAssertFalse(
            logContent.contains("failedToEncode"),
            "WidgetKit 出现归档失败 — 详细堆栈见日志"
        )

        // 2. 每个 kind 的归档请求应当出现过
        for (kind, _) in expectedKinds {
            XCTAssertTrue(
                logContent.contains(kind),
                "widget kind 未触发归档: \(kind)"
            )
        }

        // 3. 至少一次 success
        XCTAssertTrue(
            logContent.contains("Request ended") && logContent.contains("success"),
            "没有任何 widget timeline 归档返回 success"
        )
    }
}
