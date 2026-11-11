import XCTest

final class SecondaryDialogParityUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.buttons["week_label"].waitForExistence(timeout: 20))
        app.switchToPillTab("mine")
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private var dialog: XCUIElement {
        app.descendants(matching: .any)["centered_picker_dialog"].firstMatch
    }

    private var nameField: XCUIElement {
        app.descendants(matching: .any)["table_copy_name"].firstMatch
    }

    private var tableRows: [String: String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'"))
            .allElementsBoundByIndex.reduce(into: [:]) { rows, element in
                rows[element.identifier] = element.label
            }
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return condition()
    }

    private func openTables() {
        app.buttons["mine_all_tables"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'"))
            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(tableRows.isEmpty)
    }

    private func openCopy(sourceID: String? = nil) {
        let copy: XCUIElement
        if let sourceID {
            copy = app.buttons["table_duplicate_" + sourceID.replacingOccurrences(of: "table_select_", with: "")]
        } else {
            copy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_duplicate_'"))
                .firstMatch
        }
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil { copy.isHittable })
        copy.tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 5))
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["table_copy_confirm"].label, "OK")
    }

    private func assertCenteredCompactDialog(file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(waitUntil {
            abs(self.dialog.frame.midX - window.midX) <= 3
                && abs(self.dialog.frame.midY - window.midY) <= 3
                && self.dialog.frame.height < window.height - 96
        }, "The copy dialog must be centered in the complete window", file: file, line: line)
        XCTAssertLessThanOrEqual(dialog.frame.width, 361, file: file, line: line)
        XCTAssertLessThan(dialog.frame.height, window.height - 96,
                          "A short copy form must keep its natural dialog height", file: file, line: line)
        XCTAssertTrue(window.contains(dialog.frame), file: file, line: line)
    }

    private func replaceName(with text: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntil { self.nameField.isHittable }, file: file, line: line)
        let oldValue = nameField.value as? String ?? ""
        nameField.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        if !oldValue.isEmpty {
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count))
        }
        if !text.isEmpty { app.typeText(text) }
        XCTAssertEqual(nameField.value as? String, text, file: file, line: line)
    }

    private func actionIsVisible(_ action: XCUIElement) -> Bool {
        guard action.exists, action.isHittable, action.frame.width > 0, action.frame.height > 0,
              app.windows.firstMatch.frame.insetBy(dx: -1, dy: -1).contains(action.frame) else { return false }
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return true }
        // Match the existing harness's clearance for predictive/accessory chrome.
        let keyboardArea = CGRect(x: keyboard.frame.minX, y: keyboard.frame.minY - 44,
                                  width: keyboard.frame.width, height: keyboard.frame.height + 44)
        let overlap = keyboardArea.intersection(action.frame)
        return overlap.isNull || overlap.width < 1 || overlap.height < 1
    }

    private func reachAction(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let action = app.buttons[identifier].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5), file: file, line: line)
        // A compact landscape viewport may need the dialog's own scroll area.
        // Scroll dismissal of the keyboard is also part of the production form.
        for _ in 0..<4 {
            if actionIsVisible(action) { break }
            dialog.swipeUp()
        }
        XCTAssertTrue(waitUntil { self.actionIsVisible(action) },
                      "The entire copy action must be reachable above the keyboard", file: file, line: line)
        return action
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testShortCopyDialogIsCenteredAndCancelKeepsTableNamesAndCount() {
        openTables()
        let original = tableRows
        openCopy()
        assertCenteredCompactDialog()
        capture("short-copy-dialog-centered")
        app.buttons["table_copy_cancel"].tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 5))
        XCTAssertEqual(tableRows, original, "Cancel must preserve every source name and the table count")
    }

    func testCopyNameValidationRejectsBlankAndTrimmedDuplicateThenRecovers() throws {
        openTables()
        let original = tableRows
        let source = try XCTUnwrap(original.first)
        openCopy(sourceID: source.key)
        let confirm = app.buttons["table_copy_confirm"].firstMatch
        let error = app.staticTexts["table_copy_name_error"].firstMatch
        replaceName(with: "   ")
        XCTAssertTrue(waitUntil { !confirm.isEnabled })
        XCTAssertFalse(error.exists, "Whitespace blocks saving without reporting a duplicate")
        replaceName(with: "  " + source.value + "  ")
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertEqual(error.label, "A timetable with this name already exists")
        XCTAssertFalse(confirm.isEnabled)
        let discarded = "Discarded-" + String(UUID().uuidString.prefix(8))
        replaceName(with: discarded)
        XCTAssertTrue(waitUntil { confirm.isEnabled && !error.exists },
                      "A unique name must clear the error and re-enable confirmation")
        capture("copy-name-validation-recovers")
        reachAction("table_copy_cancel").tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 5))
        XCTAssertEqual(tableRows, original)
        openCopy(sourceID: source.key)
        XCTAssertNotEqual(nameField.value as? String, discarded)
        XCTAssertFalse(error.exists, "Reopening must use a fresh suggested name")
        app.buttons["table_copy_cancel"].tap()
    }

    func testLongCopyNameKeepsKeyboardActionsReachableAndSavesTrimmedNameInLandscape() throws {
        openTables()
        let original = tableRows
        let source = try XCTUnwrap(original.first)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitUntil { self.app.frame.width > self.app.frame.height })
        openCopy(sourceID: source.key)
        assertCenteredCompactDialog()
        let discarded = "Discarded-" + String(repeating: "long course table name ", count: 5)
        replaceName(with: discarded)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let cancel = reachAction("table_copy_cancel")
        capture("long-copy-dialog-cancel-keyboard")
        cancel.tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 5))
        XCTAssertEqual(tableRows, original)

        openCopy(sourceID: source.key)
        XCTAssertNotEqual(nameField.value as? String, discarded)
        let saved = "Copied-" + String(repeating: "long course table name ", count: 5)
            + String(UUID().uuidString.prefix(8))
        replaceName(with: "  " + saved + "  ")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        let confirm = reachAction("table_copy_confirm")
        XCTAssertTrue(confirm.isEnabled)
        capture("long-copy-dialog-save-keyboard")
        confirm.tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitUntil { self.tableRows.count == original.count + 1 })
        XCTAssertEqual(tableRows[source.key], source.value, "Copy must keep the captured source table")
        XCTAssertTrue(tableRows.values.contains(saved), "Only the trimmed confirmed copy name should be saved")
        XCTAssertFalse(tableRows.values.contains(discarded))
        capture("long-copy-dialog-saved-name")
    }

    func testCourseListStartsWithCoursesWithoutTheRemovedSubtitle() {
        let courses = app.descendants(matching: .any)["mine_stat_courses"].firstMatch
        XCTAssertTrue(courses.waitForExistence(timeout: 5))
        courses.tap()
        XCTAssertTrue(app.staticTexts["Course list"].waitForExistence(timeout: 5))
        let course = app.staticTexts.matching(NSPredicate(format: "label IN %@",
            ["高等数学", "大学英语", "大学物理", "体育", "数据结构"])).firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["All courses in the current schedule"].exists)
    }
}
