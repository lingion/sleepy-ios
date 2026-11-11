import XCTest

final class RangeSliderUITests: XCTestCase {
    private var app: XCUIApplication!
    private var pager: XCUIElement { app.collectionViews["schedule_week_pager"] }
    private let courseName = "Range Slider Orbit"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(pager.waitForExistence(timeout: 15))
        waitForWeek(1)
    }

    override func tearDown() { app.terminate() }

    // R1–R3: real thumb drags, field synchronization, Apply, save and persisted week boundaries.
    func testBothWeekThumbsSynchronizeFieldsAndPersistAppliedRange() throws {
        let add = app.buttons["topbar_add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isHittable)
        add.tap()
        XCTAssertTrue(app.staticTexts["Create Course"].waitForExistence(timeout: 5))

        let name = app.textFields["field_Course Name *"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        name.typeText(courseName)
        assertValue(name, courseName)
        let returnKey = app.keyboards.buttons["Return"]
        XCTAssertTrue(returnKey.waitForExistence(timeout: 3))
        returnKey.tap()
        wait(app.keyboards.firstMatch, predicate: "exists == false")

        let form = try formScrollView()
        let start = element("course_week_range_start")
        let end = element("course_week_range_end")
        let summary = element("course_week_range_summary")
        let startField = app.textFields["Start Week"]
        let endField = app.textFields["End Week"]
        let apply = app.buttons["course_apply_to_all_slots"]
        try reveal([summary, start, end, startField, endField, apply], in: form)
        assertValue(start, "1")
        assertValue(end, "16")
        assertValue(startField, "1")
        assertValue(endField, "16")

        // The initial endpoint distance spans fifteen weeks; derive both targets
        // from these live frames rather than a screen-size-specific track width.
        let firstCenter = CGPoint(x: start.frame.midX, y: start.frame.midY)
        let lastCenter = CGPoint(x: end.frame.midX, y: end.frame.midY)
        let weekPitch = (lastCenter.x - firstCenter.x) / 15
        XCTAssertGreaterThan(weekPitch, 0, "The English LTR range must run left to right")
        coordinate(firstCenter).press(forDuration: 0.1, thenDragTo:
            coordinate(CGPoint(x: firstCenter.x + 2 * weekPitch, y: firstCenter.y)))
        assertValue(start, "3")
        assertValue(end, "16")
        assertValue(startField, "3")
        assertValue(endField, "16")

        coordinate(CGPoint(x: end.frame.midX, y: end.frame.midY)).press(forDuration: 0.1, thenDragTo:
            coordinate(CGPoint(x: firstCenter.x + 7 * weekPitch, y: lastCenter.y)))
        assertValue(start, "3")
        assertValue(end, "8")
        assertValue(startField, "3")
        assertValue(endField, "8")
        wait(summary, predicate: "label == %@", argument: "Weeks 3–8")
        let blockStart = element("course_slot_1_weeks_start")
        let blockEnd = element("course_slot_1_weeks_end")
        XCTAssertTrue(blockStart.waitForExistence(timeout: 3))
        assertValue(blockStart, "1")
        assertValue(blockEnd, "16")
        XCTAssertTrue(apply.isHittable)
        apply.tap()

        assertValue(blockStart, "3")
        assertValue(blockEnd, "8")
        assertValue(app.textFields["Weeks Start Week"], "3")
        assertValue(app.textFields["Weeks End Week"], "8")

        // Saturday 1–2 is empty in the seed, so a conflict override cannot hide
        // a failed Apply or an unintended extra Monday occurrence.
        let monday = app.buttons["Mon"]
        let saturday = app.buttons["Sat"]
        try reveal([monday, saturday], in: form)
        monday.tap()
        saturday.tap()
        let save = app.buttons["course_save"]
        try reveal([save], in: form)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        wait(save, predicate: "exists == false")
        XCTAssertTrue(pager.waitForExistence(timeout: 8), "Saving the applied range must return to the schedule")
        XCTAssertFalse(app.alerts.firstMatch.exists, "The empty Saturday placement must save without a conflict override")

        app.terminate()
        app.launchArguments.removeAll { $0 == "-SLEEPY_UI_TEST_SEED" }
        app.sleepyLaunch()
        XCTAssertTrue(pager.waitForExistence(timeout: 15))
        waitForWeek(1)
        app.buttons["week_next"].tap()
        waitForWeek(2)
        assertVisibleCourseCount(0)
        app.buttons["week_next"].tap()
        waitForWeek(3)
        try assertSavedCourseDetail()
        jumpToWeek(9)
        assertVisibleCourseCount(0)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func formScrollView() throws -> XCUIElement {
        let forms = app.scrollViews.allElementsBoundByIndex.filter { $0.buttons["course_save"].exists }
        XCTAssertEqual(forms.count, 1, "The course form must have one outer scroll view")
        return try XCTUnwrap(forms.first)
    }

    private func coordinate(_ point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
    }

    private func reveal(_ elements: [XCUIElement], in scroll: XCUIElement,
                        file: StaticString = #filePath, line: UInt = #line) throws {
        for item in elements {
            XCTAssertTrue(item.waitForExistence(timeout: 3), "Expected form control is missing: \(item)", file: file, line: line)
        }
        for _ in 0..<12 {
            let viewport = app.frame.intersection(scroll.frame).insetBy(dx: 4, dy: 8)
            let frames = elements.map(\.frame)
            let extent = frames.reduce(CGRect.null) { $0.union($1) }
            XCTAssertGreaterThan(viewport.height, extent.height, "Requested controls must fit together", file: file, line: line)
            if frames.allSatisfy({ !$0.isEmpty && viewport.contains($0) }) && elements.allSatisfy(\.isHittable) { return }
            let movingUp = extent.maxY > viewport.maxY
            let displacement = min(viewport.height * 0.55, max(50,
                movingUp ? extent.maxY - viewport.maxY + 16 : viewport.minY - extent.minY + 16))
            let x = scroll.frame.minX + 8
            let middle = viewport.midY
            let firstY = middle + (movingUp ? displacement / 2 : -displacement / 2)
            let lastY = middle + (movingUp ? -displacement / 2 : displacement / 2)
            // The outer gutter avoids sliders and text fields consuming scrolls.
            coordinate(CGPoint(x: x, y: firstY)).press(forDuration: 0.05,
                thenDragTo: coordinate(CGPoint(x: x, y: lastY)))
        }
        let viewport = app.frame.intersection(scroll.frame).insetBy(dx: 4, dy: 8)
        XCTAssertTrue(elements.allSatisfy { $0.isHittable && viewport.contains($0.frame) },
                      "Every requested control must be fully inside the real form viewport", file: file, line: line)
    }

    private func wait(_ item: XCUIElement, predicate: String, argument: String? = nil,
                      file: StaticString = #filePath, line: UInt = #line) {
        let condition = argument.map { NSPredicate(format: predicate, $0) } ?? NSPredicate(format: predicate)
        let expectation = XCTNSPredicateExpectation(predicate: condition, object: item)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func assertValue(_ item: XCUIElement, _ value: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        wait(item, predicate: "value == %@", argument: value, file: file, line: line)
    }

    private func waitForWeek(_ week: Int) {
        wait(app.buttons["week_label"], predicate: "label == %@", argument: "Week \(week)")
        wait(pager.buttons["gridcell_1"], predicate: "exists == true AND hittable == true")
    }

    private func jumpToWeek(_ target: Int) {
        let label = app.buttons["week_label"]
        // Away from the actual seeded week, the first label tap returns to it;
        // the second opens the menu. Jump directly instead of paging many times.
        label.tap()
        waitForWeek(1)
        label.tap()
        XCTAssertTrue(element("week_jump_title").waitForExistence(timeout: 4))
        let week = app.buttons["week_num_\(target)"]
        XCTAssertTrue(week.waitForExistence(timeout: 3))
        XCTAssertTrue(week.isHittable)
        week.tap()
        waitForWeek(target)
    }

    private func visibleCourses() -> [XCUIElement] {
        pager.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "gridcell_", courseName)).allElementsBoundByIndex.filter(\.isHittable)
    }

    private func assertVisibleCourseCount(_ count: Int) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            visibleCourses().count == count
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "The saved course must occur exactly in weeks 3–8")
    }

    private func assertSavedCourseDetail() throws {
        assertVisibleCourseCount(1)
        let course = try XCTUnwrap(visibleCourses().first)
        course.tap()
        let close = app.buttons["detail_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Period 1-2"].exists)
        XCTAssertTrue(app.staticTexts["1-2 (Week 3-8)"].exists,
                      "Persistence must retain the exact range applied from the two thumbs")
        close.tap()
        wait(close, predicate: "exists == false")
    }
}
