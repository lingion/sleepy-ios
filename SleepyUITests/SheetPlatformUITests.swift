import XCTest

/// Keep the existing pill navigation so these tests isolate sheet behavior.
/// Run on both a short iPhone and an iPad: landscape exercises keyboard space
/// on the phone and regular-width NavigationView presentation on the tablet.
final class SheetPlatformUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.buttons["topbar_share"].firstMatch.waitForExistence(timeout: 20))
    }

    override func tearDownWithError() throws {
        app.terminate()
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitUntil(timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return condition()
    }

    private var occurrenceForm: XCUIElement? {
        let editor = app.descendants(matching: .any)["occurrence_editor"].firstMatch
        guard editor.exists else { return nil }
        // A Form may have no hittable point while its visible rows are all
        // controls. Scope by the presented editor, not by the pager underneath.
        return [editor.collectionViews.firstMatch, editor.tables.firstMatch,
                editor.scrollViews.firstMatch].first { $0.exists }
    }

    private var foregroundScrollContainers: [XCUIElement] {
        // SwiftUI Form is backed by a CollectionView on recent iOS versions.
        app.scrollViews.allElementsBoundByIndex + app.tables.allElementsBoundByIndex
            + app.collectionViews.allElementsBoundByIndex
    }

    private func owningScrollView(_ element: XCUIElement) -> XCUIElement? {
        guard element.exists else { return nil }
        let identifier = element.identifier
        let form = occurrenceForm
        let candidates = form.map { [$0] } ?? foregroundScrollContainers.reversed().map { $0 }
        return candidates.first { scroll in
            guard scroll.exists && (form != nil || scroll.isHittable) else { return false }
            let descendants = scroll.descendants(matching: element.elementType)
            return identifier.isEmpty
                ? descendants.matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
                : descendants.matching(identifier: identifier).firstMatch.exists
        }
    }

    private func keyboardOcclusion() -> CGRect? {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return nil }
        let frame = keyboard.frame
        // Keep a control-height of clearance above the key grid for keyboard
        // prediction/accessory chrome, rather than tapping its exposed top edge.
        return CGRect(x: frame.minX, y: frame.minY - 44,
                      width: frame.width, height: frame.height + 44)
    }

    private func visibleViewport(in scroll: XCUIElement?) -> CGRect {
        var viewport = app.frame.insetBy(dx: 2, dy: 4)
        if let scroll {
            viewport = viewport.intersection(scroll.frame.insetBy(dx: 2, dy: 4))
            // The scroll bar provides a conservative bottom boundary. Its
            // automatic top inset can exclude a visible custom sheet header;
            // use the actual navigation bar below for top occlusion instead.
            let verticalBars = scroll.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Vertical scroll bar"))
                .allElementsBoundByIndex.map { $0.frame }
                .filter { $0.width > 0 && $0.height > $0.width && $0.intersects(scroll.frame) }
            if let bar = verticalBars.max(by: { $0.height < $1.height }) {
                let bottom = min(viewport.maxY, bar.maxY)
                viewport.size.height = max(0, bottom - viewport.minY)
            }
        }
        if scroll != nil, occurrenceForm != nil {
            let navigation = app.descendants(matching: .any)["occurrence_editor"].firstMatch.navigationBars.firstMatch
            if navigation.exists, viewport.intersects(navigation.frame) {
                let bottom = viewport.maxY
                viewport.origin.y = max(viewport.minY, navigation.frame.maxY + 4)
                viewport.size.height = max(0, bottom - viewport.minY)
            }
        }
        if let keyboard = keyboardOcclusion(), viewport.intersects(keyboard) {
            viewport.size.height = max(0, min(viewport.maxY, keyboard.minY) - viewport.minY)
        }
        return viewport
    }

    private func fullyVisible(_ element: XCUIElement) -> Bool {
        guard element.exists && element.isHittable,
              element.frame.width > 0 && element.frame.height > 0 else { return false }
        return visibleViewport(in: owningScrollView(element)).contains(element.frame)
    }

    private func makeHittable(_ element: XCUIElement,
                              file: StaticString = #filePath, line: UInt = #line) {
        _ = element.waitForExistence(timeout: 2)
        for _ in 0..<16 {
            if fullyVisible(element) { return }
            // Scope the drag to the control's own foreground scroll view. A
            // whole-app downward swipe can dismiss a sheet instead of scrolling it.
            let scroll = owningScrollView(element) ?? occurrenceForm ?? foregroundScrollContainers
                .reversed().first { $0.exists && $0.isHittable }
            guard let scroll else { break }
            let viewport = visibleViewport(in: scroll)
            guard !viewport.isNull && viewport.height >= 40 else { break }
            let moveDown = element.exists && element.frame.height > 0 && element.frame.minY < viewport.minY
            let missing = element.exists
                ? (moveDown ? viewport.minY - element.frame.minY : element.frame.maxY - viewport.maxY)
                : 80
            let distance = min(80, viewport.height * 0.5, max(56, missing + 6))
            // Begin on non-slider content, where SwiftUI actually hit-tests
            // this ScrollView rather than its transparent padding.
            let candidates = [app.buttons["occurrence_date"].firstMatch,
                              app.staticTexts["occurrence_nodes_summary"].firstMatch, element,
                              app.descendants(matching: .any)["occurrence_fixed_date"].firstMatch,
                              app.descendants(matching: .any)["occurrence_custom_time"].firstMatch]
            let dragFrame = candidates.filter { $0.exists }.map { $0.frame.intersection(viewport) }
                .first { !$0.isNull && $0.height >= 16 && $0.width > 40 } ?? viewport
            let x = dragFrame.midX
            let startY = moveDown
                ? min(viewport.maxY - distance, max(dragFrame.midY, viewport.minY + 4))
                : max(viewport.minY + distance, min(dragFrame.midY, viewport.maxY - 4))
            let endY = startY + (moveDown ? distance : -distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo:
                    origin.withOffset(CGVector(dx: x - app.frame.minX, dy: endY - app.frame.minY)),
                    withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 0.15)
        }
        let diagnostic = XCTAttachment(string: "target=\(element.exists ? String(describing: element.frame) : "missing") viewport=\(visibleViewport(in: owningScrollView(element)))\n\(app.debugDescription)")
        diagnostic.name = "sheet-visibility-diagnostic"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        XCTAssertTrue(fullyVisible(element),
                      "The complete control must fit in its foreground scroll area above the keyboard", file: file, line: line)
    }

    private func assertInteractiveInWindow(_ element: XCUIElement,
                                           file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitUntil { fullyVisible(element) },
                      "The complete action must be visible in the current sheet", file: file, line: line)
        XCTAssertTrue(element.isEnabled, file: file, line: line)
        XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(element.frame),
                      "A sheet action escaped the visible window", file: file, line: line)
        if let keyboard = keyboardOcclusion() {
            let overlap = keyboard.intersection(element.frame)
            XCTAssertTrue(overlap.isNull || overlap.height < 1 || overlap.width < 1,
                          "The keyboard covers the sheet action", file: file, line: line)
        }
    }

    private func replaceText(_ field: XCUIElement, with text: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        makeHittable(field, file: file, line: line)
        let oldValue = field.value as? String ?? ""
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        if !oldValue.isEmpty {
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count))
        }
        app.typeText(text)
        XCTAssertEqual(field.value as? String, text, file: file, line: line)
    }

    private func openImport() {
        app.switchToPillTab("manage")
        let entry = app.buttons["manage_import"].firstMatch
        makeHittable(entry)
        entry.tap()
        XCTAssertTrue(app.buttons["import_text"].firstMatch.waitForExistence(timeout: 10))
    }

    private func openPeriodTables() {
        app.switchToPillTab("manage")
        let entry = app.buttons["manage_period_tables"].firstMatch
        makeHittable(entry)
        entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["period_tables_screen"].firstMatch
            .waitForExistence(timeout: 10))
    }

    /// Create the source through the normal editor and its save preview. The
    /// subsequent lookup also checks that confirming a new table keeps it saved.
    private func createPeriodTable(named name: String) -> String {
        openPeriodTables()
        app.buttons["period_tables_new"].tap()
        let field = app.descendants(matching: .any)["field_Bell schedule name"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        let sections = app.buttons["period_table_slots_header"].firstMatch
        makeHittable(sections)
        sections.tap()
        replaceText(field, with: name)
        app.typeText("\n")
        XCTAssertTrue(waitUntil { !app.keyboards.firstMatch.exists },
                      "Submitting the source-table name must dismiss the keyboard")
        let save = app.buttons["period_table_save"].firstMatch
        makeHittable(save)
        save.tap()
        let confirm = app.buttons["period_table_preview_confirm"].firstMatch
        makeHittable(confirm)
        confirm.tap()
        XCTAssertTrue(waitUntil { !confirm.exists })
        openPeriodTables()
        return periodTableID(named: name)
    }

    private func periodTableID(named name: String) -> String {
        let label = app.staticTexts[name].firstMatch
        makeHittable(label)
        let prefix = "period_table_name_"
        XCTAssertTrue(label.identifier.hasPrefix(prefix))
        return String(label.identifier.dropFirst(prefix.count))
    }

    func testLandscapeFormatHelpShowsContentAndCloses() {
        openImport()
        XCUIDevice.shared.orientation = .landscapeLeft
        let entry = app.buttons["format_help_plain"].firstMatch
        makeHittable(entry)
        entry.tap()
        let content = app.staticTexts["format_help_when"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 10))
        XCTAssertTrue(content.isHittable, "The help body must be visible without revealing a sidebar")
        let close = app.buttons["format_help_close"].firstMatch
        assertInteractiveInWindow(close)
        capture("landscape-format-help")
        close.tap()
        XCTAssertTrue(waitUntil { !close.exists })
        XCTAssertTrue(entry.isHittable, "Closing help must return to the same import-method page")
    }

    func testLandscapeNewTableConfirmationShowsActionsAndBackRetainsDraft() {
        openImport()
        let paste = app.buttons["import_text"].firstMatch
        makeHittable(paste)
        paste.tap()
        let input = app.descendants(matching: .any)["import_paste_input"].firstMatch
        makeHittable(input)
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let json = "{\"name\":\"Sheet Preview\",\"courses\":[{\"name\":\"SheetCourse\",\"day\":1,\"startNode\":1,\"step\":1,\"startWeek\":1,\"endWeek\":20}]}"
        app.typeText(json)
        let preview = app.buttons["import_preview_btn"].firstMatch
        makeHittable(preview)
        XCTAssertTrue(preview.isEnabled, "Typing must update the actual import draft")
        preview.tap()
        let back = app.buttons["import_dialog_back"].firstMatch
        let confirm = app.buttons["import_dialog_confirm"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "A new-table import must open configuration directly")
        XCTAssertFalse(app.buttons["import_mode_overwrite"].exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        assertInteractiveInWindow(back)
        assertInteractiveInWindow(confirm)
        capture("landscape-new-table-confirmation")
        back.tap()
        XCTAssertTrue(waitUntil { !back.exists })
        makeHittable(input)
        XCTAssertEqual(input.value as? String, json, "Back must retain the complete import draft")
        makeHittable(preview)
        XCTAssertTrue(preview.isEnabled)
        preview.tap()
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        assertInteractiveInWindow(back)
        assertInteractiveInWindow(confirm)
        back.tap()
        XCTAssertTrue(waitUntil { !back.exists })
        makeHittable(preview)
        XCTAssertTrue(preview.isEnabled)
    }

    private func exerciseCopy(sourceID: String, sourceName: String, fromEditor: Bool) {
        let suffix = String(UUID().uuidString.prefix(8))
        let cancelledName = "Cancelled-\(suffix)"
        let copiedName = "Copied-\(suffix)"
        XCUIDevice.shared.orientation = .landscapeLeft
        if fromEditor {
            let edit = app.buttons["period_table_edit_\(sourceID)"].firstMatch
            makeHittable(edit)
            edit.tap()
        }
        let entryID = fromEditor ? "period_table_copy" : "period_table_copy_\(sourceID)"
        let copy = app.buttons[entryID].firstMatch
        makeHittable(copy)
        copy.tap()
        let name = app.descendants(matching: .any)["period_table_copy_name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        replaceText(name, with: cancelledName)
        let cancel = app.buttons["period_table_copy_cancel"].firstMatch
        makeHittable(cancel)
        assertInteractiveInWindow(cancel)
        let confirm = app.buttons["period_table_copy_confirm"].firstMatch
        makeHittable(confirm)
        assertInteractiveInWindow(confirm)
        capture(fromEditor ? "landscape-editor-copy-keyboard" : "landscape-list-copy-keyboard")
        cancel.tap()
        XCTAssertTrue(waitUntil { !cancel.exists })
        XCTAssertFalse(app.staticTexts[cancelledName].exists, "Cancel must not create a table")
        makeHittable(copy)
        copy.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertNotEqual(name.value as? String, cancelledName, "Cancel must discard the naming draft")
        replaceText(name, with: copiedName)
        makeHittable(confirm)
        assertInteractiveInWindow(confirm)
        capture(fromEditor ? "landscape-editor-copy-save" : "landscape-list-copy-save")
        confirm.tap()
        XCTAssertTrue(waitUntil { !confirm.exists })
        if fromEditor { openPeriodTables() }
        XCTAssertTrue(app.staticTexts[copiedName].firstMatch.waitForExistence(timeout: 10),
                      "Confirm must create the named table before result-list navigation or scrolling")
        _ = periodTableID(named: copiedName)
        _ = periodTableID(named: sourceName)
        XCTAssertFalse(app.staticTexts[cancelledName].exists)
        capture(fromEditor ? "landscape-editor-copy-result" : "landscape-list-copy-result")
    }

    func testListCopyAllowsCancelAndSaveAfterLandscapeKeyboardInput() {
        let source = "ListSource-\(UUID().uuidString.prefix(8))"
        let sourceID = createPeriodTable(named: source)
        exerciseCopy(sourceID: sourceID, sourceName: source, fromEditor: false)
    }

    func testEditorCopyAllowsCancelAndSaveAfterLandscapeKeyboardInput() {
        let source = "EditorSource-\(UUID().uuidString.prefix(8))"
        let sourceID = createPeriodTable(named: source)
        exerciseCopy(sourceID: sourceID, sourceName: source, fromEditor: true)
    }

    func testLandscapeOccurrenceEditorValidatesSaveAndCancelsDelete() {
        let course = app.collectionViews["schedule_week_pager"].buttons["gridcell_1"].firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 10))
        course.tap()
        let edit = app.buttons["course_occurrence_actions"].firstMatch
        makeHittable(edit)
        edit.tap()
        let cancel = app.buttons["occurrence_cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .landscapeLeft
        assertInteractiveInWindow(cancel)
        let customRow = app.descendants(matching: .any)["occurrence_custom_time"].firstMatch
        // The styled Toggle exposes one actionable accessibility element,
        // with its value bound to the same visible checkbox state.
        let custom = customRow
        makeHittable(customRow)
        XCTAssertTrue(custom.waitForExistence(timeout: 3))
        makeHittable(custom)
        assertInteractiveInWindow(custom)
        XCTAssertEqual(custom.value as? String, "0")
        let rangeStart = app.descendants(matching: .any)["occurrence_nodes_start"].firstMatch
        let rangeEnd = app.descendants(matching: .any)["occurrence_nodes_end"].firstMatch
        makeHittable(rangeStart)
        XCTAssertEqual(rangeStart.value as? String, "1")
        XCTAssertEqual(rangeEnd.value as? String, "2")
        let previousY = custom.frame.minY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let sliderPoint = CGPoint(x: (rangeStart.frame.midX + rangeEnd.frame.midX) / 2, y: rangeStart.frame.midY)
        origin.withOffset(CGVector(dx: sliderPoint.x, dy: sliderPoint.y)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: sliderPoint.x, dy: sliderPoint.y - 80)),
            withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 0.15)
        XCTAssertTrue(waitUntil { custom.frame.minY <= previousY - 20 },
                      "A vertical drag on the period slider must scroll the editor")
        XCTAssertEqual(rangeStart.value as? String, "1", "Vertical scrolling must not edit the range")
        XCTAssertEqual(rangeEnd.value as? String, "2")
        makeHittable(custom)
        custom.tap()
        XCTAssertTrue(waitUntil { custom.value as? String == "1" },
                      "The accessible checkbox must enable the custom-time inputs")
        let start = app.textFields["occurrence_start_time"].firstMatch
        replaceText(start, with: "25:00")
        let save = app.buttons["occurrence_save"].firstMatch
        makeHittable(save)
        assertInteractiveInWindow(save)
        save.tap()
        XCTAssertTrue(app.staticTexts["occurrence_error"].firstMatch.waitForExistence(timeout: 10),
                      "Save must validate the edited time while keeping the editor open")
        capture("landscape-occurrence-validation")
        cancel.tap()
        XCTAssertTrue(waitUntil { !cancel.exists })
        makeHittable(edit)
        edit.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        makeHittable(customRow)
        XCTAssertTrue(custom.waitForExistence(timeout: 3))
        makeHittable(custom)
        XCTAssertEqual(custom.value as? String, "0", "Cancel must discard the custom-time draft")
        let delete = app.buttons["occurrence_delete"].firstMatch
        makeHittable(delete)
        assertInteractiveInWindow(delete)
        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "Delete must ask for confirmation")
        capture("landscape-occurrence-delete-confirmation")
        alert.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(waitUntil { !alert.exists })
        assertInteractiveInWindow(cancel)
        cancel.tap()
        XCTAssertTrue(waitUntil { !cancel.exists })
        let detailClose = app.buttons["detail_close"].firstMatch
        assertInteractiveInWindow(detailClose)
        detailClose.tap()
        XCTAssertTrue(course.waitForExistence(timeout: 10), "Canceling deletion must keep the original course")
    }
}
