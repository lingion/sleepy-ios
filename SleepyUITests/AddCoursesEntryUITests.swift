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

    func testBlankTimetableCancelReturnsToImportMethodsAndPreservesPasteDraft() {
        continueAfterFailure = false
        let app = XCUIApplication()
        defer { app.terminate() }
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED", "-ui_style", "classic"]
        app.sleepyLaunch()

        func waitUntil(timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            repeat {
                if condition() { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            } while Date() < deadline
            return condition()
        }

        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        func tableRows() -> [String: String] {
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'"))
                .allElementsBoundByIndex.reduce(into: [:]) { rows, element in
                    rows[element.identifier] = element.label
                }
        }

        func tapForegroundBack() {
            let back = app.buttons.matching(identifier: "topbar_back")
                .allElementsBoundByIndex.last { $0.isHittable }
            XCTAssertNotNil(back, "The foreground page must offer its own Back action")
            back?.tap()
        }

        func openTableList() {
            let allTables = app.buttons["manage_all_tables"].firstMatch
            XCTAssertTrue(allTables.waitForExistence(timeout: 8))
            XCTAssertTrue(waitUntil { allTables.isHittable })
            allTables.tap()
            XCTAssertTrue(app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH 'table_select_'"))
                .firstMatch.waitForExistence(timeout: 8))
        }

        app.switchToPillTab("manage")
        openTableList()
        let originalTables = tableRows()
        XCTAssertFalse(originalTables.isEmpty)
        tapForegroundBack()

        let methods = app.buttons["manage_import"].firstMatch
        XCTAssertTrue(methods.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntil { methods.isHittable })
        methods.tap()
        let textSource = app.descendants(matching: .any)["import_text"].firstMatch
        XCTAssertTrue(textSource.waitForExistence(timeout: 8))
        textSource.tap()
        let input = app.descendants(matching: .any)["import_paste_input"].firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { input.isHittable })
        input.tap()
        let draft = "#sleepy-v1\nTRetained Methods Draft|2026-11-02|20|12\nCUnimported Orbit|1|3-4|1-20|Ada|A||||keep"
        app.typeText(draft)
        XCTAssertEqual(input.value as? String, draft)

        let blank = app.buttons["manage_new_table"].firstMatch
        let scroll = app.scrollViews["import_methods_scroll"].firstMatch
        XCTAssertTrue(blank.waitForExistence(timeout: 5))
        for _ in 0..<8 {
            let keyboard = app.keyboards.firstMatch
            if blank.isHittable && (!keyboard.exists || !blank.frame.intersects(keyboard.frame)) { break }
            var viewport = scroll.frame.intersection(app.frame)
            if keyboard.exists, viewport.intersects(keyboard.frame) {
                viewport.size.height = max(0, keyboard.frame.minY - viewport.minY - 12)
            }
            XCTAssertGreaterThan(viewport.height, 60,
                                 "The methods sheet must retain a scrollable area above the keyboard")
            // The input consumes drags inside its text; use the outer sheet gutter.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = viewport.minX + 10
            origin.withOffset(CGVector(dx: x, dy: viewport.minY + viewport.height * 0.8))
                .press(forDuration: 0.05, thenDragTo:
                    origin.withOffset(CGVector(dx: x, dy: viewport.minY + viewport.height * 0.25)))
        }
        XCTAssertTrue(blank.isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists && blank.frame.intersects(app.keyboards.firstMatch.frame),
                       "Create Blank Timetable must be reachable above the text keyboard")
        capture("manual-new-table-methods-draft")
        blank.tap()

        let name = app.textFields["field_Schedule Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        let oldName = name.value as? String ?? ""
        name.tap()
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldName.count))
        let discardedName = "Discarded Manual Table"
        app.typeText(discardedName)
        XCTAssertEqual(name.value as? String, discardedName)
        capture("manual-new-table-unsaved-editor")
        tapForegroundBack()

        let returned = waitUntil {
            scroll.exists && scroll.isHittable && input.exists
                && app.buttons["import_preview_btn"].exists
        }
        capture("manual-new-table-cancel-return")
        XCTAssertTrue(returned,
                      "Cancelling the new table must restore the original import methods without reopening them")
        XCTAssertEqual(input.value as? String, draft,
                       "The expanded text source and complete paste draft must survive the child editor")
        XCTAssertTrue(app.buttons["manage_new_table"].exists)
        XCTAssertFalse(app.textFields["field_Schedule Name"].exists)

        tapForegroundBack()
        openTableList()
        XCTAssertTrue(waitUntil { tableRows() == originalTables },
                      "Cancelling must discard the unsaved table and preserve every existing table ID and name")
        capture("manual-new-table-cancel-discarded")

        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-ui_style", "classic"]
        app.sleepyLaunch()
        app.switchToPillTab("manage")
        openTableList()
        XCTAssertEqual(tableRows(), originalTables,
                       "The discarded new table must remain absent after a normal restart")
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
