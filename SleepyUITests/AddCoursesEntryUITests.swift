import XCTest

final class AddCoursesEntryUITests: XCTestCase {
    private func openSources() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        app.switchToPillTab("manage")
        let add = app.descendants(matching: .any)["manage_add_course"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.descendants(matching: .any)["import_existing"].waitForExistence(timeout: 5))
        return app
    }

    func testManagementAddCoursesOffersExistingAndManualSources() {
        let app = openSources()
        XCTAssertTrue(app.descendants(matching: .any)["import_jw"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["import_text"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["import_manual"].exists)
        app.descendants(matching: .any)["import_existing"].tap()
        XCTAssertTrue(app.staticTexts["add_course_no_source"].waitForExistence(timeout: 4))
        app.terminate()
    }

    func testManualSourceOpensCourseEditor() {
        let app = openSources()
        let manual = app.descendants(matching: .any)["import_manual"]
        if !manual.isHittable { app.swipeUp() }
        manual.tap()
        XCTAssertTrue(app.descendants(matching: .any)["course_save"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testSelectedGroupsAppendPersistAndBackUpOriginalSchedule() {
        let app = openSources()
        defer { app.terminate() }
        app.descendants(matching: .any)["import_text"].tap()
        let input = app.descendants(matching: .any)["import_paste_input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        if !input.isHittable { app.swipeUp() }
        input.tap()
        app.typeText("#sleepy-v1\nTBatch Source|2026-11-02|20|12\nCAdded Orbit|1|3-4|1-20|Ada|A||||keep\nCSkipped Orbit|1|5-6|1-20|Grace|B||||skip")
        let parse = app.descendants(matching: .any)["import_preview_btn"]
        for _ in 0..<8 where !parse.isHittable {
            // A swipe in the multi-line input scrolls its text. Drag the outer
            // sheet's gutter so the real keyboard-dismiss and page scroll run.
            let scroll = app.scrollViews.allElementsBoundByIndex.reversed().first { $0.isHittable }
            var frame = (scroll?.frame ?? app.frame).intersection(app.frame)
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists, frame.intersects(keyboard.frame) {
                frame.size.height = max(0, keyboard.frame.minY - frame.minY - 12)
            }
            XCTAssertGreaterThan(frame.height, 60, "The sheet needs a scrollable viewport above the keyboard")
            let x = frame.minX + 16
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x, dy: frame.minY + frame.height * 0.8))
                .press(forDuration: 0.05, thenDragTo:
                    origin.withOffset(CGVector(dx: x, dy: frame.minY + frame.height * 0.25)))
        }
        XCTAssertTrue(parse.isHittable, "Preview must be reachable after dismissing the text keyboard")
        parse.tap()

        let excluded = app.descendants(matching: .any)["select_course#1"]
        XCTAssertTrue(excluded.waitForExistence(timeout: 6), "Both parsed course groups must be offered")
        XCTAssertTrue(excluded.label.contains("Skipped Orbit"))
        XCTAssertEqual(excluded.value as? String, "1", "All groups start selected")
        excluded.tap()
        XCTAssertEqual(excluded.value as? String, "0", "The second group must be deselected before confirmation")
        app.descendants(matching: .any)["import_select_confirm"].tap()

        let backup = app.descendants(matching: .any)["import_preview_backup"]
        XCTAssertTrue(backup.waitForExistence(timeout: 6))
        XCTAssertEqual(backup.value as? String, "1", "Backing up the target is enabled by default")
        XCTAssertEqual(app.descendants(matching: .any)["import_preview_append"].value as? String, "0",
                       "Conflicting meetings are excluded by default")
        let save = app.descendants(matching: .any)["import_preview_apply"]
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["import_success_snackbar"].waitForExistence(timeout: 6),
                      "Confirmation must persist the selected group")

        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 15))
        let added = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Added Orbit'")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 8), "The chosen group must remain after a normal restart")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Skipped Orbit'")).firstMatch.exists,
                       "The deselected group must never be imported")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '高等数学'")).firstMatch.exists,
                      "Appending must retain the original target courses")
        app.switchToPillTab("manage")
        let allTables = app.descendants(matching: .any)["manage_all_tables"]
        XCTAssertTrue(allTables.waitForExistence(timeout: 5))
        allTables.tap()
        let frozenBackup = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'table_select_' AND label CONTAINS 'Backup'")).firstMatch
        XCTAssertTrue(frozenBackup.waitForExistence(timeout: 5), "Default confirmation must also persist the original-table backup")
    }

}
