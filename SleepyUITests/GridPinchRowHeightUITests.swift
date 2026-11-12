import XCTest

final class GridPinchRowHeightUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPinchShowsTickAndCommitPersists() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-SLEEPY_UI_TEST_SEED",
                               "-grid_pinch_zoom", "YES", "-grid_adaptive_height", "NO",
                               "-grid_long_break_spacing", "NO", "-grid_scale", "1"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"]
                        .waitForExistence(timeout: 10), "课表 tab 应出现")
        let pager = app.scheduleWeekPager
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        let card = pager.buttons["gridcell_1"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        let beforeHeight = card.frame.height
        let enlarge = beforeHeight < 128
        let physics = pager.buttons["gridcell_3"]
        XCTAssertTrue(physics.waitForExistence(timeout: 5))
        // Pinch the full application so XCTest's screen margins are symmetric.
        // Pinching the pager clips only its bottom on small phones, shifting the
        // actual two-finger midpoint away from the pager frame's center.
        let anchorY = app.frame.midY
        XCTAssertTrue(pager.frame.contains(CGPoint(x: app.frame.midX, y: anchorY)))
        let beforeAnchorDistance = anchorY - physics.frame.minY
        let beforeRowHeight = (physics.frame.height + 4) / 2
        let tick = app.descendants(matching: .any)["scale_keep"]
        XCTAssertFalse(tick.exists)

        // The CI recording for scale 1.5 has a 10 pt vertical span at 0.1s and 16.47 pt
        // at release. It doesn't record recognition time; use a larger gesture rather than weakening 8 pt.
        app.pinch(withScale: enlarge ? 4.0 : 0.25, velocity: enlarge ? 1.0 : -1.0)
        XCTAssertTrue(tick.waitForExistence(timeout: 5), "A full vertical pinch must change row height")
        let resizedHeight = card.frame.height
        if enlarge { XCTAssertGreaterThan(resizedHeight, beforeHeight + 4) }
        else { XCTAssertLessThan(resizedHeight, beforeHeight - 4) }
        if enlarge {
            // The same fractional row under the two-finger midpoint must remain there.
            // Checking the tick alone would pass the old grid-top anchored implementation.
            let newRowHeight = (physics.frame.height + 4) / 2
            let resizedAnchorY = physics.frame.minY + beforeAnchorDistance * newRowHeight / beforeRowHeight
            XCTAssertEqual(resizedAnchorY, anchorY, accuracy: 10,
                           "Pinch must preserve content under the two-finger midpoint")
        }
        tick.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: tick)
        wait(for: [gone], timeout: 3)
        let committedHeight = card.frame.height

        app.terminate()
        app.launchArguments.removeAll { $0 == "-SLEEPY_UI_TEST_SEED" }
        app.sleepyLaunch()
        let restored = app.scheduleWeekPager.buttons["gridcell_1"]
        XCTAssertTrue(restored.waitForExistence(timeout: 15))
        XCTAssertEqual(restored.frame.height, committedHeight, accuracy: 1)
        XCTAssertGreaterThan(abs(restored.frame.height - beforeHeight), 4)
        XCTAssertFalse(app.descendants(matching: .any)["scale_keep"].exists)
    }
}
