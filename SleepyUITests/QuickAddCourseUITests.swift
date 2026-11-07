import XCTest

final class QuickAddCourseUITests: XCTestCase {
    private var app: XCUIApplication!
    private var pager: XCUIElement { app.collectionViews["schedule_week_pager"] }
    private var capsule: XCUIElement { app.buttons["quick-add-capsule"] }
    private func cell(_ day: Int, _ node: Int) -> XCUIElement { pager.buttons["add-course-\(day)-\(node)"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(pager.waitForExistence(timeout: 15))
        waitForWeek(1)
        XCTAssertTrue(cell(6, 5).waitForExistence(timeout: 5), "主会话必须接通 onAddAt，不能以普通加课按钮替代")
    }

    override func tearDown() { app.terminate() }

    private func waitForWeek(_ week: Int) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Week \(week)"),
                                                   object: app.buttons["week_label"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func assertDismissed() {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: capsule)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func coordinate(_ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    func testOutsidePressCancelsWithoutOpeningCourseOrReselectingCell() {
        cell(6, 5).tap()
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        // 点实体课只取消，第二次点才可打开详情。
        let course = pager.buttons["gridcell_1"]
        coordinate(CGPoint(x: course.frame.midX, y: course.frame.midY)).tap()
        assertDismissed()
        XCTAssertFalse(app.buttons["detail_close"].exists)
        course.tap()
        XCTAssertTrue(app.buttons["detail_close"].waitForExistence(timeout: 5))
        app.buttons["detail_close"].tap()

        cell(6, 5).tap()
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        let next = cell(7, 5).frame
        coordinate(CGPoint(x: next.midX, y: next.midY)).tap()
        assertDismissed()
        cell(7, 5).tap()
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        XCTAssertEqual(capsule.frame.midX, next.midX, accuracy: 2)
        // 顶栏也遵循第一次按下只取消，第二次才能翻周。
        let forward = app.buttons["week_next"].frame
        coordinate(CGPoint(x: forward.midX, y: forward.midY)).tap()
        assertDismissed()
        waitForWeek(1)
        app.buttons["week_next"].tap()
        waitForWeek(2)
        XCTAssertFalse(capsule.exists)
        for id in ["undo_button", "redo_button"] {
            XCTAssertFalse(app.buttons[id].exists && app.buttons[id].isEnabled)
        }
    }

    func testBothHandlesPrefillSingleWeekAndSavePersistsExactPlacement() {
        app.buttons["week_next"].tap()
        waitForWeek(2)
        app.buttons["week_next"].tap()
        waitForWeek(3)
        let first = cell(6, 4).frame
        let last = cell(6, 6).frame
        cell(6, 5).tap()
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        let top = app.descendants(matching: .any)["quick-add-top"]
        let bottom = app.descendants(matching: .any)["quick-add-bottom"]
        XCTAssertTrue(top.exists)
        XCTAssertTrue(bottom.exists)
        top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: coordinate(CGPoint(x: first.midX, y: first.minY + 7)))
        bottom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: coordinate(CGPoint(x: last.midX, y: last.maxY - 7)))
        XCTAssertEqual(capsule.frame.minY, first.minY, accuracy: 2)
        XCTAssertEqual(capsule.frame.maxY, last.maxY, accuracy: 2)
        XCTAssertEqual(capsule.frame.midX, first.midX, accuracy: 2)
        capsule.tap()
        let name = app.textFields["field_Course Name *"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let save = app.buttons["course_save"]
        XCTAssertTrue(save.exists)
        XCTAssertFalse(save.isEnabled, "快速加课不能绕过空名称校验")
        name.tap()
        name.typeText("Quick Add CI")
        XCTAssertEqual(name.value as? String, "Quick Add CI", "保留真实输入断言")
        let returnKey = app.keyboards.buttons["Return"]
        if returnKey.exists { returnKey.tap() }
        for _ in 0..<6 {
            if save.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(save.isHittable)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        waitForWeek(3)
        assertSavedPlacement()

        app.terminate()
        app.launchArguments.removeAll { $0 == "-SLEEPY_UI_TEST_SEED" }
        app.sleepyLaunch()
        waitForWeek(1)
        XCTAssertEqual(savedCards().count, 0)
        app.buttons["week_next"].tap()
        waitForWeek(2)
        XCTAssertEqual(savedCards().count, 0)
        app.buttons["week_next"].tap()
        waitForWeek(3)
        assertSavedPlacement()
        app.buttons["week_next"].tap()
        waitForWeek(4)
        XCTAssertEqual(savedCards().count, 0, "快速加课只预填指定单周")
    }

    private func savedCards() -> [XCUIElement] {
        pager.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "gridcell_", "Quick Add CI")).allElementsBoundByIndex.filter(\.isHittable)
    }

    private func assertSavedPlacement() {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in savedCards().count == 1 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        let card = savedCards()[0]
        let first = cell(6, 4).frame
        let last = cell(6, 6).frame
        XCTAssertEqual(card.frame.midX, first.midX, accuracy: 3)
        XCTAssertEqual(card.frame.minY, first.minY, accuracy: 3)
        XCTAssertEqual(card.frame.maxY, last.maxY, accuracy: 3)
        card.tap()
        XCTAssertTrue(app.buttons["detail_close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Period 4-6"].exists)
        XCTAssertTrue(app.staticTexts["4-6 (Week 3-3)"].exists)
        app.buttons["detail_close"].tap()
    }
}
