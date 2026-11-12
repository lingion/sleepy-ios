import XCTest

/// Drive both production tabs and custom navigation while a simulator recording
/// captures the animated edges. Screenshots after tap() alone miss the exposed
/// window because XCTest waits for the transition to settle.
final class NavigationTransitionCanvasUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testNativeTabsAndSettingsRoundTrips() {
        launch(style: "liquid_glass", forcePill: false)
        exerciseNavigation(forcePill: false)
    }

    func testClassicTabsAndSettingsRoundTrips() {
        launch(style: "classic", forcePill: true)
        exerciseNavigation(forcePill: true)
    }

    private func launch(style: String, forcePill: Bool) {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED", "-ui_style", style,
                               "-theme_mode", "light"]
        app.launchEnvironment["TZ"] = "Asia/Shanghai"
        if forcePill { app.launchArguments.append("-SLEEPY_FORCE_PILL_NAV") }
        // sleepyLaunch() deliberately forces pills, so native coverage must use
        // the production resolver through the ordinary launch entry point.
        app.launch()
        XCTAssertTrue(app.buttons["topbar_share"].firstMatch.waitForExistence(timeout: 15))
    }

    private func exerciseNavigation(forcePill: Bool) {
        for (id, title) in [("mine", "Me"), ("manage", "Manage"),
                            ("today", "Today"), ("schedule", "Schedule"),
                            ("mine", "Me")] {
            if forcePill {
                XCTAssertTrue(app.switchToPillTab(id))
            } else {
                let tab = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
                XCTAssertTrue(tab.waitForExistence(timeout: 10), "Native tab \(title) must exist")
                tab.tap()
            }
        }
        XCTAssertTrue(app.buttons["mine_all_tables"].firstMatch.waitForExistence(timeout: 10))
        for identifier in ["mine_general", "mine_appearance", "mine_reminder"] {
            let entry = app.buttons[identifier].firstMatch
            reveal(entry)
            entry.tap()
            let back = app.buttons["topbar_back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "\(identifier) must open")
            capture("\(forcePill ? "classic" : "native")-\(identifier)")
            back.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                   object: back)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
            XCTAssertTrue(app.buttons["mine_all_tables"].firstMatch.waitForExistence(timeout: 10))
        }
    }

    private func reveal(_ entry: XCUIElement) {
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if entry.isHittable && entry.frame.maxY < app.frame.maxY - 110 { return }
            app.swipeUp()
        }
        XCTAssertTrue(entry.isHittable && entry.frame.maxY < app.frame.maxY - 110,
                      "Settings entry must be above the floating navigation")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
