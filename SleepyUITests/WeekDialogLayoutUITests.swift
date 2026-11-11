import XCTest

final class WeekDialogLayoutUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.buttons["week_label"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func openDialog() -> XCUIElement {
        app.buttons["week_label"].tap()
        let dialog = app.descendants(matching: .any)["week_jump_dialog"].firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        let screen = app.windows.firstMatch.frame
        XCTAssertEqual(dialog.frame.midX, screen.midX, accuracy: 3)
        XCTAssertEqual(dialog.frame.midY, screen.midY, accuracy: 3)
        XCTAssertGreaterThanOrEqual(dialog.frame.minX, screen.minX)
        XCTAssertLessThanOrEqual(dialog.frame.maxX, screen.maxX)
        XCTAssertGreaterThanOrEqual(dialog.frame.minY, screen.minY)
        XCTAssertLessThanOrEqual(dialog.frame.maxY, screen.maxY)
        return dialog
    }

    func testWeekDialogIsCenteredAndSelectionClosesIt() {
        let dialog = openDialog()
        let picture = XCTAttachment(screenshot: app.screenshot())
        picture.name = "week-dialog-centered"
        picture.lifetime = .keepAlways
        add(picture)
        app.buttons["week_num_17"].tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 4))
        XCTAssertEqual(app.buttons["week_label"].label, "Week 17")
    }

    func testWeekDialogRemainsCenteredInLandscapeAndCancels() {
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["week_label"].waitForExistence(timeout: 5))
        let dialog = openDialog()
        app.buttons["week_jump_cancel"].tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 4))
        XCTAssertEqual(app.buttons["week_label"].label, "Week 1")
    }
}
