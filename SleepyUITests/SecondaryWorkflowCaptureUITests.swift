import XCTest

/// Local production workflows; named captures remain pending until runtime succeeds.
final class SecondaryWorkflowCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED", "-ui_style", "classic"]
        app.sleepyLaunch()
        app.switchToPillTab("manage")
        XCTAssertTrue(app.buttons["manage_add_course"].waitForExistence(timeout: 10))
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

    /// Reveal complete controls with short, reversible drags in their owning scroll area.
    /// An expanded card uses only its header as the navigation target.
    private func reveal(_ element: XCUIElement, headerOnly: Bool = false,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        func scrollArea() -> XCUIElement? {
            let containers = app.scrollViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
                + app.collectionViews.allElementsBoundByIndex
            return containers.reversed().first { container in
                let children = container.descendants(matching: element.elementType)
                return element.identifier.isEmpty
                    ? children.matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
                    : children.matching(identifier: element.identifier).firstMatch.exists
            }
        }
        func viewport() -> CGRect {
            var area = app.windows.firstMatch.frame.insetBy(dx: 2, dy: 4)
            if let scroll = scrollArea() { area = area.intersection(scroll.frame) }
            if let back = app.buttons.matching(identifier: "topbar_back").allElementsBoundByIndex.last(where: { $0.isHittable }),
               back.frame.minY < area.midY {
                let bottom = area.maxY
                area.origin.y = max(area.minY, back.frame.maxY + 4)
                area.size.height = max(0, bottom - area.minY)
            }
            let docks = ["pill_schedule", "pill_today", "pill_manage", "pill_mine"]
                .map { app.buttons[$0].firstMatch }.filter { $0.exists && $0.isHittable }.map(\.frame)
            if let first = docks.first {
                let dock = docks.dropFirst().reduce(first) { $0.union($1) }
                if dock.width > dock.height, dock.minY > area.midY {
                    area.size.height = max(0, min(area.maxY, dock.minY - 4) - area.minY)
                }
            }
            if let keyboard = app.keyboards.allElementsBoundByIndex.first {
                area.size.height = max(0, min(area.maxY, keyboard.frame.minY - 12) - area.minY)
            }
            return area
        }
        func targetFrame() -> CGRect {
            let frame = element.frame
            return headerOnly ? CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: min(48, frame.height)) : frame
        }
        func visible() -> Bool {
            element.exists && element.isHittable && targetFrame().width > 0 && targetFrame().height > 0
                && viewport().contains(targetFrame())
        }
        for _ in 0..<16 {
            if visible() { return }
            let area = viewport()
            guard area.width > 0, area.height > 0 else { break }
            let earlier = targetFrame().minY < area.minY
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: area.minX + 16, dy: area.minY + area.height * (earlier ? 0.40 : 0.65)))
            let end = origin.withOffset(CGVector(dx: area.minX + 16, dy: area.minY + area.height * (earlier ? 0.58 : 0.47)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(waitUntil { visible() }, "The complete target must be visible above navigation", file: file, line: line)
    }

    private func tapBack(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.buttons.matching(identifier: "topbar_back").allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(back, file: file, line: line)
        back?.tap()
    }

    private func openTextSource(entryID: String, text: String) {
        let entry = app.buttons[entryID].firstMatch
        reveal(entry)
        entry.tap()
        let textSource = app.buttons["import_text"].firstMatch
        reveal(textSource)
        textSource.tap()
        let input = app.descendants(matching: .any)["import_paste_input"].firstMatch
        reveal(input)
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        input.typeText(text)
        XCTAssertEqual(input.value as? String, text)
        let parse = app.buttons["import_preview_btn"].firstMatch
        reveal(parse)
        XCTAssertTrue(parse.isEnabled)
        parse.tap()
    }

    func testTextCourseSelectionPreviewAndNewTableConfigurationCanCancelCapture() {
        // Same local text fixture as AddCoursesEntryUITests; no school service is involved.
        let text = "#sleepy-v1\nTBatch Source|2026-11-02|20|12\nCAdded Orbit|1|3-4|1-20|Ada|A||||keep\nCSkipped Orbit|1|5-6|1-20|Grace|B||||skip"
        openTextSource(entryID: "manage_add_course", text: text)
        let included = app.descendants(matching: .any)["select_course#0"].firstMatch
        let excluded = app.descendants(matching: .any)["select_course#1"].firstMatch
        reveal(included)
        XCTAssertTrue(included.label.contains("Added Orbit"))
        XCTAssertEqual(included.value as? String, "1")
        reveal(excluded)
        XCTAssertTrue(excluded.label.contains("Skipped Orbit"))
        XCTAssertEqual(excluded.value as? String, "1")
        capture("workflow-text-course-selection")
        excluded.tap()
        XCTAssertTrue(waitUntil { excluded.value as? String == "0" })
        let select = app.buttons["import_select_confirm"].firstMatch
        reveal(select)
        select.tap()
        let backup = app.descendants(matching: .any)["import_preview_backup"].firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 8))
        XCTAssertEqual(backup.value as? String, "1")
        XCTAssertEqual(app.descendants(matching: .any)["import_preview_append"].firstMatch.value as? String, "0")
        let apply = app.buttons["import_preview_apply"].firstMatch
        reveal(apply)
        capture("workflow-selected-course-import-preview")
        let cancel = app.buttons["import_preview_cancel"].firstMatch
        reveal(cancel)
        cancel.tap()
        XCTAssertTrue(waitUntil { !apply.exists && app.buttons["import_text"].exists })
        tapBack()
        XCTAssertTrue(app.buttons["manage_import"].waitForExistence(timeout: 5))

        // Management's new-table route intentionally skips selection and opens configuration.
        let json = "{\"name\":\"Workflow Preview\",\"startDate\":\"2026-08-24\",\"courses\":[{\"name\":\"Preview Orbit\",\"teacher\":\"Ada\",\"position\":\"A101\",\"day\":4,\"startNode\":7,\"step\":2,\"startWeek\":1,\"endWeek\":16,\"type\":0}]}"
        openTextSource(entryID: "manage_import", text: json)
        XCTAssertTrue(app.descendants(matching: .any)["import_confirm_title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["import_confirm_course_count"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["import_confirm_periods_scroll"].waitForExistence(timeout: 8))
        let confirm = app.buttons["import_dialog_confirm"].firstMatch
        reveal(confirm)
        XCTAssertTrue(confirm.isEnabled)
        capture("workflow-new-table-import-configuration")
        let back = app.buttons["import_dialog_back"].firstMatch
        reveal(back)
        back.tap()
        XCTAssertTrue(waitUntil { !confirm.exists && app.buttons["import_text"].exists })
        XCTAssertFalse(app.descendants(matching: .any)["import_success_snackbar"].exists)
        tapBack()
        XCTAssertTrue(app.buttons["manage_add_course"].waitForExistence(timeout: 5))
    }

    func testOffGridPeriodCandidateAndNewPeriodDialogsCanCancelCapture() {
        let add = app.buttons["manage_add_course"].firstMatch
        reveal(add)
        add.tap()
        let manual = app.buttons["import_manual"].firstMatch
        reveal(manual)
        manual.tap()
        XCTAssertTrue(app.buttons["course_save"].waitForExistence(timeout: 8))
        let advanced = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Advanced options'")).firstMatch
        reveal(advanced)
        advanced.tap()
        let irregular = app.staticTexts["Irregular period"].firstMatch
        reveal(irregular)
        let toggle = app.switches.allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
            .min { abs($0.frame.midY - irregular.frame.midY) < abs($1.frame.midY - irregular.frame.midY) }
        XCTAssertNotNil(toggle, "The irregular-period row must expose its real switch")
        if let toggle {
            XCTAssertLessThan(abs(toggle.frame.midY - irregular.frame.midY), 45)
            XCTAssertEqual(toggle.value as? String, "0")
            toggle.tap()
        }
        XCTAssertTrue(app.staticTexts["Choose period"].waitForExistence(timeout: 5))
        let newPeriod = app.buttons["Period 0 (new)"].firstMatch
        reveal(newPeriod)
        capture("workflow-off-grid-period-candidates")
        newPeriod.tap()
        let title = app.staticTexts["New period 0"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // Classic blank TimePickerField exposes its Button label, unlike the native branch's ID.
        XCTAssertTrue(app.buttons["Start time"].exists)
        XCTAssertTrue(app.buttons["End time"].exists)
        let create = app.buttons["Add"].firstMatch
        XCTAssertTrue(create.exists)
        XCTAssertFalse(create.isEnabled, "A new period needs both times before it can be added")
        capture("workflow-off-grid-new-period")
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel'"))
            .allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(cancel)
        cancel?.tap()
        XCTAssertTrue(waitUntil { !title.exists && app.buttons["course_save"].exists })
        tapBack()
        XCTAssertTrue(app.buttons["manage_add_course"].waitForExistence(timeout: 5))
    }
}
