import XCTest

final class WatchTimeStripSettingsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var originalToggleValue: String?

    private var tomorrowToggle: XCUIElement {
        app.switches["watch_time_strip_tomorrow_toggle"].firstMatch
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        originalToggleValue = nil
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        app.switchToPillTab("mine")
        XCTAssertTrue(app.descendants(matching: .any)["mine_all_tables"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        defer { app?.terminate() }
        guard let original = originalToggleValue else { return }
        if app.state != .runningForeground {
            app.sleepyLaunch()
            app.switchToPillTab("mine")
        }
        if !tomorrowToggle.exists { openWidgetSettings() }
        XCTAssertTrue(scrollIntoView(tomorrowToggle), "The toggle must remain reachable for restoration")
        if tomorrowToggle.value as? String != original { tomorrowToggle.tap() }
        XCTAssertTrue(pollUntil { self.tomorrowToggle.value as? String == original },
                      "Restore the setting so this test does not affect later tests")
    }

    func testTomorrowTogglePersistsWhenRevisitingWidgetSettings() throws {
        openWidgetSettings()
        XCTAssertEqual(tomorrowToggle.label, "Show tomorrow after today ends")
        let original = try XCTUnwrap(tomorrowToggle.value as? String)
        XCTAssertTrue(["0", "1"].contains(original), "The setting must expose native switch state")
        originalToggleValue = original
        let changed = original == "1" ? "0" : "1"

        tomorrowToggle.tap()
        XCTAssertTrue(pollUntil { self.tomorrowToggle.value as? String == changed })
        try returnToMine()
        openWidgetSettings()
        XCTAssertEqual(tomorrowToggle.value as? String, changed,
                       "Reopening the screen must read the persisted value, not the previous view's State")

        tomorrowToggle.tap()
        XCTAssertTrue(pollUntil { self.tomorrowToggle.value as? String == original })
        try returnToMine()
        openWidgetSettings()
        XCTAssertEqual(tomorrowToggle.value as? String, original,
                       "Both enabled and disabled values must persist")
    }

    private func openWidgetSettings() {
        let entry = app.descendants(matching: .any)["mine_widget"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10), "Me must contain the Widgets entry")
        XCTAssertTrue(scrollIntoView(entry))
        entry.tap()
        XCTAssertTrue(tomorrowToggle.waitForExistence(timeout: 10),
                      "Widgets must expose the Apple Watch option as a native switch")
        XCTAssertTrue(scrollIntoView(tomorrowToggle))
    }

    private func returnToMine() throws {
        // Use the visible top bar button, not a coordinate or an underlying covered screen.
        let back = try XCTUnwrap(app.buttons.matching(identifier: "topbar_back")
            .allElementsBoundByIndex.last(where: { $0.isHittable }))
        back.tap()
        XCTAssertTrue(pollUntil { !self.tomorrowToggle.exists }, "The Widgets screen must actually close")
        XCTAssertTrue(app.descendants(matching: .any)["mine_all_tables"].waitForExistence(timeout: 10))
    }

    @discardableResult
    private func scrollIntoView(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        let usableBottom = app.windows.firstMatch.frame.height - 110
        for _ in 0..<maxSwipes {
            if element.exists {
                let frame = element.frame
                if frame.minY >= 80 && frame.maxY <= usableBottom && element.isHittable { return true }
                if frame.minY < 80 { app.swipeDown() } else { app.swipeUp() }
            } else {
                app.swipeUp()
            }
        }
        return element.exists && element.isHittable
            && element.frame.minY >= 80 && element.frame.maxY <= usableBottom
    }

    @discardableResult
    private func pollUntil(_ timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            usleep(200_000)
        }
        return condition()
    }
}
