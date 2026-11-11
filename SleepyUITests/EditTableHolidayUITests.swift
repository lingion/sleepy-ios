import XCTest

final class EditTableHolidayUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func waitUntil(timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        return condition()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        func viewport() -> CGRect {
            var area = app.windows.firstMatch.frame.insetBy(dx: 2, dy: 4)
            if let scroll = app.scrollViews.allElementsBoundByIndex.reversed().first(where: {
                $0.descendants(matching: element.elementType)
                    .matching(identifier: element.identifier).firstMatch.exists
            }) {
                area = area.intersection(scroll.frame)
            }
            if let back = app.buttons.matching(identifier: "topbar_back")
                .allElementsBoundByIndex.last(where: { $0.isHittable }), back.frame.minY < area.midY {
                let bottom = area.maxY
                area.origin.y = max(area.minY, back.frame.maxY + 4)
                area.size.height = max(0, bottom - area.minY)
            }
            if let keyboard = app.keyboards.allElementsBoundByIndex.first {
                area.size.height = max(0, min(area.maxY, keyboard.frame.minY - 12) - area.minY)
            }
            return area
        }
        func visible() -> Bool {
            element.exists && element.isHittable && element.frame.width > 0
                && element.frame.height > 0 && viewport().contains(element.frame)
        }
        for _ in 0..<16 {
            if visible() { return }
            let area = viewport()
            guard area.width > 0, area.height > 0 else { break }
            let earlier = element.frame.minY < area.minY
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: area.minX + 16,
                dy: area.minY + area.height * (earlier ? 0.40 : 0.70)))
            let end = origin.withOffset(CGVector(dx: area.minX + 16,
                dy: area.minY + area.height * (earlier ? 0.62 : 0.38)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(waitUntil { visible() }, "The complete control must be reachable", file: file, line: line)
    }

    private func replace(_ field: XCUIElement, with text: String) {
        reveal(field)
        let oldValue = field.value as? String ?? ""
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count) + text)
        XCTAssertEqual(field.value as? String, text)
    }

    private func tapBack(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.buttons.matching(identifier: "topbar_back").allElementsBoundByIndex
            .last { $0.isHittable }
        XCTAssertNotNil(back, file: file, line: line)
        back?.tap()
    }

    private func assertCurrentRow(_ row: XCUIElement,
                                  file: StaticString = #filePath, line: UInt = #line) {
        reveal(row, file: file, line: line)
        let current = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Current · Week'"))
        XCTAssertTrue(current.firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertEqual(current.count, 1, file: file, line: line)
        XCTAssertLessThan(abs(current.firstMatch.frame.midY - row.frame.midY), 40,
                          "Opening holiday rules must preserve the foreground timetable", file: file, line: line)
    }

    private func exerciseNonCurrentTableHolidayReturn(style: String) {
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED", "-SLEEPY_UI_TEST_HOLIDAYS", "-ui_style", style]
        app.sleepyLaunch()
        app.switchToPillTab("mine")
        let tables = app.buttons["mine_all_tables"].firstMatch
        reveal(tables)
        tables.tap()

        let source = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'table_select_' AND label == %@", "我的课表")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        let sourceID = source.identifier.replacingOccurrences(of: "table_select_", with: "")
        assertCurrentRow(source)
        let duplicate = app.buttons["table_duplicate_\(sourceID)"].firstMatch
        reveal(duplicate)
        duplicate.tap()
        let copyName = app.descendants(matching: .any)["table_copy_name"].firstMatch
        let targetName = "Holiday Target"
        replace(copyName, with: targetName)
        let confirm = app.buttons["table_copy_confirm"].firstMatch
        reveal(confirm)
        XCTAssertTrue(confirm.isEnabled)
        confirm.tap()

        let target = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'table_select_' AND label == %@", targetName)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        let targetID = target.identifier.replacingOccurrences(of: "table_select_", with: "")
        XCTAssertNotEqual(targetID, sourceID)
        assertCurrentRow(source)
        let edit = app.buttons["table_edit_\(targetID)"].firstMatch
        reveal(edit)
        edit.tap()
        let name = app.textFields["field_Schedule Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        XCTAssertEqual(name.value as? String, targetName)
        let draftName = "Holiday Draft"
        replace(name, with: draftName)
        let holiday = app.buttons["edit_table_holiday"].firstMatch
        reveal(holiday)
        capture("edit-table-holiday-entry-\(style)")
        holiday.tap()

        let title = app.staticTexts["Holidays & Make-up Days"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        let targetSegment = app.buttons["seg_\(targetName)"].firstMatch
        let sourceSegment = app.buttons["seg_我的课表"].firstMatch
        reveal(targetSegment)
        XCTAssertTrue(waitUntil { targetSegment.isSelected })
        XCTAssertFalse(sourceSegment.isSelected,
                       "The holiday page must initially select the edited table, not the foreground table")
        capture("edit-table-holiday-target-selected-\(style)")
        sourceSegment.tap()
        XCTAssertTrue(waitUntil { sourceSegment.isSelected && !targetSegment.isSelected })
        targetSegment.tap()
        XCTAssertTrue(waitUntil { targetSegment.isSelected && !sourceSegment.isSelected })
        tapBack()
        XCTAssertTrue(waitUntil { !title.exists && name.exists }, "Back must restore the schedule editor")
        XCTAssertEqual(name.value as? String, draftName, "Returning must preserve the unsaved editor draft")
        reveal(holiday)
        XCTAssertTrue(waitUntil { !title.exists && app.buttons["edit_table_holiday"].isHittable })
        reveal(name)
        XCTAssertEqual(name.value as? String, draftName, "Returning must preserve the unsaved editor draft")
        capture("edit-table-holiday-returned-draft-\(style)")

        tapBack()
        XCTAssertTrue(target.waitForExistence(timeout: 8))
        XCTAssertEqual(target.label, targetName, "Cancelling the editor must not persist its draft")
        XCTAssertFalse(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'table_select_' AND label == %@", draftName)).firstMatch.exists)
        assertCurrentRow(source)
        capture("edit-table-holiday-kept-current-table-\(style)")
    }

    func testClassicNonCurrentTableHolidayEntryReturnsWithoutChangingCurrentTable() {
        exerciseNonCurrentTableHolidayReturn(style: "classic")
    }

    func testNativeNonCurrentTableHolidayEntryReturnsWithoutChangingCurrentTable() {
        exerciseNonCurrentTableHolidayReturn(style: "liquid_glass")
    }
}
