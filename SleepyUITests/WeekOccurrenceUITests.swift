import XCTest

final class WeekOccurrenceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        let week = app.buttons["seg_Week"]
        XCTAssertTrue(week.waitForExistence(timeout: 10))
        week.tap()
        makeHittable(lesson)
    }

    override func tearDown() { app.terminate() }

    private var lesson: XCUIElement { app.buttons["lesson_1"] }

    private func makeHittable(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            if element.isHittable && app.frame.contains(element.frame) { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue(app.frame.contains(element.frame))
    }

    private func waitUntilGone(_ element: XCUIElement) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
    }

    func testWeekTapShowsDetailsAndHoldOpensOccurrenceMenuWithoutAlsoTapping() {
        lesson.tap()
        let close = app.buttons["detail_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail_edit"].exists)
        XCTAssertFalse(app.buttons["course_occurrence_actions"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["occurrence_menu"].exists)
        close.tap()
        waitUntilGone(close)

        makeHittable(lesson)
        lesson.press(forDuration: 1)
        let adjust = app.buttons["occurrence_adjust"]
        XCTAssertTrue(adjust.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["occurrence_delete"].exists)
        XCTAssertFalse(app.buttons["occurrence_delete_confirm"].exists,
                       "周视图长按先进入操作菜单，不能直接触发删除确认")
        XCTAssertFalse(close.exists, "长按松手不能再次触发普通详情")
        adjust.tap()
        let room = app.descendants(matching: .any)["occurrence_room"]
        XCTAssertTrue(room.waitForExistence(timeout: 5))
        XCTAssertEqual(room.value as? String, "教 1-101")
        app.buttons["occurrence_cancel"].tap()
        waitUntilGone(room)
        makeHittable(lesson)
        lesson.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5), "完成长按后新的普通点击仍须有效")
    }

    func testWeekLongPressDeleteCancellationPreservesCourseAndUndo() {
        lesson.press(forDuration: 1)
        let delete = app.buttons["occurrence_delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirmation = app.buttons["occurrence_delete_confirm"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        app.buttons["occurrence_prompt_cancel"].firstMatch.tap()
        waitUntilGone(confirmation)
        XCTAssertTrue(app.buttons["occurrence_adjust"].exists)
        app.descendants(matching: .any)["occurrence_menu"].swipeDown()
        waitUntilGone(app.descendants(matching: .any)["occurrence_editor"])
        makeHittable(lesson)
        lesson.tap()
        XCTAssertTrue(app.buttons["detail_close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["1-2 (Week 1-20)"].exists)
        app.buttons["detail_close"].tap()
        waitUntilGone(app.buttons["detail_close"])
        let undo = app.buttons["undo_button"]
        XCTAssertFalse(undo.exists && undo.isEnabled, "取消删除不能消费撤回历史")
    }
}
