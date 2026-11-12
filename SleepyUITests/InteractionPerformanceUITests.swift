import XCTest

/// Opt in with SLEEPY_RUN_PERFORMANCE_TESTS=1 in the test runner's environment.
/// Keep device, build configuration, fixtures and iteration counts identical
/// when comparing runs. UI automation's waiting time is not app render latency.
final class InteractionPerformanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Performance fixtures must only run on a dedicated test simulator")
        #endif
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1",
                          "Run this measurement suite explicitly on an idle simulator")
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["TZ"] = "Asia/Shanghai"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_SHOT_VIEW=cards", "-ui_style", "classic",
                               "-SLEEPY_FORCE_PILL_NAV", "-SLEEPY_UI_TEST_SEED"]
        app.launch()
        XCTAssertTrue(app.buttons["week_label"].waitForExistence(timeout: 20))
        app.terminate()
        // Seed once. Never include clearing/rebuilding the database in launch metrics.
        app.launchArguments.removeAll { $0 == "-SLEEPY_UI_TEST_SEED" }
    }

    override func tearDown() { app?.terminate() }

    private var options: XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        return options
    }

    private var interactionMetrics: [XCTMetric] {
        var metrics: [XCTMetric] = [XCTCPUMetric(application: app),
                                   XCTMemoryMetric(application: app),
                                   XCTStorageMetric(application: app)]
        if #available(iOS 26, *) { metrics.append(XCTHitchMetric(application: app)) }
        return metrics
    }

    func testProcessLaunchToResponsive() {
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: options) {
            app.launch()
            app.terminate()
        }
    }

    func testWarmWeekPaging() {
        app.launch()
        XCTAssertTrue(app.buttons["week_label"].waitForExistence(timeout: 20))
        let next = app.buttons["week_next"].firstMatch
        let previous = app.buttons["week_prev"].firstMatch
        measure(metrics: interactionMetrics, options: options) {
            for _ in 0..<4 { next.tap() }
            for _ in 0..<4 { previous.tap() }
        }
        XCTAssertEqual(app.buttons["week_label"].firstMatch.label, "Week 1")
    }

    func testTabsAndSettingsRoundTrip() {
        app.launch()
        XCTAssertTrue(app.buttons["pill_mine"].waitForExistence(timeout: 20))
        measure(metrics: interactionMetrics, options: options) {
            app.buttons["pill_mine"].tap()
            let appearance = app.buttons["mine_appearance"].firstMatch
            XCTAssertTrue(appearance.waitForExistence(timeout: 20))
            appearance.tap()
            let back = app.buttons["topbar_back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 20))
            back.tap()
            for tab in ["manage", "today", "schedule"] {
                app.buttons["pill_\(tab)"].tap()
            }
        }
        XCTAssertTrue(app.buttons["week_label"].exists)
    }
}
