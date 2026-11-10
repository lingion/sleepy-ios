import XCTest

/// Exercise the production navigation resolver; sleepyLaunch() intentionally pins
/// the older suites to pills and cannot verify native tabs or responsive rails.
final class DeviceAdaptationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.launchEnvironment["TZ"] = "Asia/Shanghai"
        app.launch()
        XCTAssertTrue(app.buttons["topbar_share"].firstMatch.waitForExistence(timeout: 15))
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

    // iPadOS places native tabs at the top and exposes them as Buttons rather
    // than an XCUI TabBar. Both are the production TabView navigation.
    private func nativeTab(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func waitFor(_ predicate: @escaping () -> Bool, timeout: TimeInterval = 10) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return predicate()
    }

    private func makeHittable(_ element: XCUIElement,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), file: file, line: line)
        for _ in 0..<8 {
            if element.isHittable { break }
            app.swipeUp()
        }
        for _ in 0..<8 {
            if element.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(element.isHittable, file: file, line: line)
    }

    private func revealOccurrenceControl(_ element: XCUIElement,
                                         file: StaticString = #filePath, line: UInt = #line) {
        let editor = app.descendants(matching: .any)["occurrence_editor"].firstMatch
        XCTAssertTrue(editor.exists, file: file, line: line)
        let form = [editor.collectionViews.firstMatch, editor.tables.firstMatch,
                    editor.scrollViews.firstMatch].first { $0.exists }
        guard let form else { return XCTFail("The occurrence editor must expose a scroll container", file: file, line: line) }

        func viewport() -> CGRect {
            var rect = app.frame.intersection(form.frame).insetBy(dx: 2, dy: 4)
            // The Form frame includes chrome below its scrollable content.
            // Its vertical scroll bar exposes the actual visible content span.
            let verticalBars = form.descendants(matching: .any)
                .matching(NSPredicate(format: "label BEGINSWITH %@", "Vertical scroll bar"))
                .allElementsBoundByIndex.map { $0.frame }
                .filter { $0.width > 0 && $0.height > $0.width && $0.intersects(form.frame) }
            if let bar = verticalBars.max(by: { $0.height < $1.height }) {
                let bottom = min(rect.maxY, bar.maxY)
                rect.origin.y = max(rect.minY, bar.minY)
                rect.size.height = max(0, bottom - rect.minY)
            }
            let navigation = editor.navigationBars.firstMatch
            if navigation.exists, rect.intersects(navigation.frame) {
                let bottom = rect.maxY
                rect.origin.y = max(rect.minY, navigation.frame.maxY + 4)
                rect.size.height = max(0, bottom - rect.minY)
            }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists {
                let bottom = min(rect.maxY, keyboard.frame.minY - 44)
                rect.size.height = max(0, bottom - rect.minY)
            }
            return rect
        }

        for _ in 0..<16 {
            let visible = viewport()
            if element.exists && element.isHittable && visible.contains(element.frame) { return }
            guard !visible.isNull && visible.height >= 40 else { break }
            let moveDown = element.exists && element.frame.height > 0 && element.frame.minY < visible.minY
            let missing = element.exists
                ? (moveDown ? visible.minY - element.frame.minY : element.frame.maxY - visible.maxY)
                : 80
            let distance = min(80, visible.height * 0.5, max(56, missing + 6))
            // Start on visible non-slider content. SwiftUI's transparent
            // padding does not reliably participate in ScrollView hit testing.
            let candidates = [app.buttons["occurrence_date"].firstMatch,
                              app.staticTexts["occurrence_nodes_summary"].firstMatch, element,
                              app.descendants(matching: .any)["occurrence_fixed_date"].firstMatch,
                              app.descendants(matching: .any)["occurrence_custom_time"].firstMatch]
            let dragFrame = candidates.filter { $0.exists }.map { $0.frame.intersection(visible) }
                .first { !$0.isNull && $0.height >= 16 && $0.width > 40 } ?? visible
            let x = dragFrame.midX
            let startY = moveDown
                ? min(visible.maxY - distance, max(dragFrame.midY, visible.minY + 4))
                : max(visible.minY + distance, min(dragFrame.midY, visible.maxY - 4))
            let endY = startY + (moveDown ? distance : -distance)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x - app.frame.minX, dy: startY - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo:
                    origin.withOffset(CGVector(dx: x - app.frame.minX, dy: endY - app.frame.minY)),
                    withVelocity: XCUIGestureVelocity(rawValue: 300), thenHoldForDuration: 0.15)
        }
        let diagnostic = XCTAttachment(string: "target=\(element.exists ? String(describing: element.frame) : "missing") viewport=\(viewport())\n\(app.debugDescription)")
        diagnostic.name = "occurrence-visibility-diagnostic"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        XCTAssertTrue(element.exists && element.isHittable && viewport().contains(element.frame),
                      "The complete occurrence control must be visible above the keyboard", file: file, line: line)
    }

    private func assertFocusedTimeVisibleAfterRotation(_ field: XCUIElement,
                                                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitFor {
            let keyboard = self.app.keyboards.firstMatch
            let editor = self.app.descendants(matching: .any)["occurrence_editor"].firstMatch
            let navigation = editor.navigationBars.firstMatch
            guard field.exists && field.isHittable && keyboard.exists && navigation.exists else { return false }
            // TextField's AX frame can include only its glyphs. Check the whole
            // 56pt outlined control without a manual scroll after rotation.
            let height = max(56, field.frame.height)
            let outline = CGRect(x: field.frame.minX, y: field.frame.midY - height / 2,
                                 width: field.frame.width, height: height)
            return outline.minY >= navigation.frame.maxY + 4
                && outline.maxY <= keyboard.frame.minY - 44
        }, "Rotation must keep the keyboard and automatically reveal the complete focused time field",
                      file: file, line: line)
    }

    private func assertImportInputVisibleAfterRotation(_ field: XCUIElement,
                                                       file: StaticString = #filePath, line: UInt = #line) {
        let visible = waitFor {
            let keyboard = self.app.keyboards.firstMatch
            let scroll = self.app.scrollViews["import_methods_scroll"].firstMatch
            let input = self.app.descendants(matching: .any)["import_paste_viewport"].firstMatch
            guard field.exists && field.isHittable && keyboard.exists,
                  scroll.exists && input.exists && input.frame.height >= 44 else { return false }
            var viewport = self.app.frame.intersection(scroll.frame).insetBy(dx: 2, dy: 4)
            viewport.size.height = max(0, min(viewport.maxY, keyboard.frame.minY - 44) - viewport.minY)
            return !viewport.isNull && viewport.contains(input.frame) && viewport.contains(field.frame)
        }
        if !visible {
            let diagnostic = XCTAttachment(string: app.debugDescription)
            diagnostic.name = "import-rotation-visibility-diagnostic"
            diagnostic.lifetime = .keepAlways
            add(diagnostic)
            capture("import-rotation-input-obscured")
        }
        XCTAssertTrue(visible,
                      "Rotation must retain the keyboard and automatically reveal the complete import editing viewport",
                      file: file, line: line)
    }

    func testPortraitNativeTabsAndBellScheduleStatistic() {
        let mine = nativeTab("Me")
        XCTAssertTrue(mine.waitForExistence(timeout: 10), "Portrait must expose the native tab bar")
        mine.tap()
        let count = app.descendants(matching: .any)["mine_stat_period_tables_value"].firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        XCTAssertNotNil(Int(count.label))
        XCTAssertFalse(app.descendants(matching: .any)["mine_export"].exists,
                       "Export belongs to the management page, matching 1.0.63")
        capture("portrait-mine")
        count.tap()
        XCTAssertTrue(app.staticTexts["New bell schedule"].firstMatch.waitForExistence(timeout: 10))
        capture("portrait-bell-schedules")
    }

    func testLandscapeRailPreservesReachableHeaderAndRotationSelection() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let combined = app.buttons["rail_schedule_today"].firstMatch
        let schedule = app.buttons["rail_schedule"].firstMatch
        XCTAssertTrue(waitFor { combined.exists || schedule.exists },
                      "Landscape must expose a rail, including Schedule in compact widths")
        let identifiers = ["switch_table", "week_prev", "week_label", "week_next", "topbar_add", "topbar_share"]
        let controls = identifiers.map { app.buttons[$0].firstMatch }
        for (id, control) in zip(identifiers, controls) {
            XCTAssertTrue(control.exists && control.isHittable, "Unreachable header action: \(id)")
            XCTAssertTrue(app.frame.insetBy(dx: -1, dy: -1).contains(control.frame),
                          "Header action escaped the visible window: \(id)")
        }
        for i in controls.indices {
            for j in controls.indices where j > i {
                let overlap = controls[i].frame.intersection(controls[j].frame)
                XCTAssertTrue(overlap.isNull || overlap.width < 1 || overlap.height < 1,
                              "Header actions overlap: \(identifiers[i]) / \(identifiers[j])")
            }
        }
        capture("landscape-schedule")
        app.buttons["rail_mine"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["mine_all_tables"].firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(nativeTab("Me").waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["mine_all_tables"].firstMatch.exists,
                      "Rotation must preserve the selected tab")
        capture("rotated-portrait-mine")
    }

    func testAllShareFormatsReachableOnSmallScreen() {
        capture("portrait-before-share")
        app.buttons["topbar_share"].firstMatch.tap()
        let native = app.buttons["share_format_native"].firstMatch
        XCTAssertTrue(native.waitForExistence(timeout: 10))
        for _ in 0..<4 where !native.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(native.isHittable, "The fourth share format must remain reachable")
        capture("portrait-share-bottom")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitFor { native.exists })
        for _ in 0..<4 where !native.isHittable {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(native.isHittable, "The fourth share format must remain reachable after rotation")
        capture("landscape-share-bottom")
    }

    func testShareFormatsRemainReachableWithLargestAccessibilityText() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName",
                                "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["topbar_share"].firstMatch.waitForExistence(timeout: 15))
        testAllShareFormatsReachableOnSmallScreen()
    }
    func testLandscapeDatePickerRetainsConfirmationAndCancel() {
        nativeTab("Manage").tap()
        let edit = app.buttons["manage_edit_current"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let calendar = app.buttons["Select date"].firstMatch
        XCTAssertTrue(calendar.waitForExistence(timeout: 10))
        calendar.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let confirm = app.buttons["date_picker_confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        for _ in 0..<4 where !confirm.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(confirm.isHittable)
        let cancel = app.buttons["date_picker_cancel"].firstMatch
        XCTAssertTrue(cancel.isHittable)
        capture("landscape-date-picker")
        cancel.tap()
        XCTAssertTrue(app.buttons["edit_table_save"].firstMatch.waitForExistence(timeout: 10))
    }

    func testImportDraftSurvivesNativeToRailRotation() {
        nativeTab("Manage").tap()
        let open = app.buttons["manage_import"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let paste = app.buttons["import_text"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 10))
        paste.tap()
        let field = app.descendants(matching: .any)["import_paste_input"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<4 where !field.isHittable { app.scrollViews.firstMatch.swipeUp() }
        for _ in 0..<3 {
            field.tap()
            if app.keyboards.firstMatch.waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "The import draft must have keyboard focus before typing")
        field.typeText("Rotation keeps this draft")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Rotation must retain the active import sheet")
        XCTAssertTrue((field.value as? String ?? "").contains("Rotation keeps this draft"),
                      "Changing the navigation layout must preserve unsaved import text")
        assertImportInputVisibleAfterRotation(field)
        field.typeText(" after landscape")
        XCTAssertTrue((field.value as? String ?? "").contains("Rotation keeps this draft after landscape"))
        capture("landscape-import-draft")
        XCUIDevice.shared.orientation = .portrait
        assertImportInputVisibleAfterRotation(field)
        XCTAssertTrue((field.value as? String ?? "").contains("Rotation keeps this draft after landscape"))
        field.typeText(" after portrait")
        XCTAssertTrue((field.value as? String ?? "").contains("Rotation keeps this draft after landscape after portrait"))
        capture("portrait-import-draft")
    }

    func testOccurrenceDraftSurvivesNativeAndRailRotation() {
        XCTAssertTrue(nativeTab("Schedule").waitForExistence(timeout: 10),
                      "Start with the production native navigation")
        let course = app.collectionViews["schedule_week_pager"].buttons["gridcell_1"].firstMatch
        let cancel = app.buttons["occurrence_cancel"].firstMatch
        let customRow = app.descendants(matching: .any)["occurrence_custom_time"].firstMatch
        // The styled Toggle exposes one actionable accessibility element,
        // with its value bound to the same visible checkbox state.
        let custom = customRow
        let start = app.textFields["occurrence_start_time"].firstMatch

        func enterDraft(_ text: String) {
            let edit = app.buttons["course_occurrence_actions"].firstMatch
            for _ in 0..<3 {
                makeHittable(course)
                course.tap()
                if edit.waitForExistence(timeout: 3) { break }
            }
            makeHittable(edit)
            edit.tap()
            XCTAssertTrue(cancel.waitForExistence(timeout: 10))
            revealOccurrenceControl(customRow)
            XCTAssertTrue(custom.waitForExistence(timeout: 3))
            revealOccurrenceControl(custom)
            XCTAssertEqual(custom.value as? String, "0", "The previous unsaved draft must be discarded")
            custom.tap()
            XCTAssertTrue(waitFor { custom.value as? String == "1" })
            // Reveal the custom-time section inside the foreground editor
            // before requiring the input to be fully visible.
            revealOccurrenceControl(start)
            let oldValue = start.value as? String ?? ""
            for _ in 0..<3 {
                revealOccurrenceControl(start)
                start.tap()
                if app.keyboards.firstMatch.waitForExistence(timeout: 3) { break }
            }
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count))
            app.typeText(text)
            XCTAssertEqual(start.value as? String, text)
        }

        func cancelDraftAndCloseDetail() {
            makeHittable(cancel)
            cancel.tap()
            XCTAssertTrue(waitFor { !cancel.exists })
            let close = app.buttons["detail_close"].firstMatch
            makeHittable(close)
            close.tap()
            XCTAssertTrue(waitFor { !close.exists })
        }

        enterDraft("08:23")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(start.waitForExistence(timeout: 10), "The occurrence editor must survive native-to-rail rotation")
        XCTAssertEqual(start.value as? String, "08:23", "Rotation must retain the entered occurrence draft")
        XCTAssertEqual(custom.value as? String, "1")
        assertFocusedTimeVisibleAfterRotation(start)
        capture("landscape-occurrence-draft")
        cancelDraftAndCloseDetail()
        XCTAssertTrue(waitFor {
            self.app.buttons["rail_schedule_today"].firstMatch.exists || self.app.buttons["rail_schedule"].firstMatch.exists
        }, "Closing the retained detail must reveal the production rail")

        enterDraft("08:47")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(start.waitForExistence(timeout: 10), "The occurrence editor must survive rail-to-native rotation")
        XCTAssertEqual(start.value as? String, "08:47")
        XCTAssertEqual(custom.value as? String, "1")
        assertFocusedTimeVisibleAfterRotation(start)
        capture("portrait-occurrence-draft")
        cancelDraftAndCloseDetail()
        XCTAssertTrue(nativeTab("Schedule").waitForExistence(timeout: 10))
        XCTAssertTrue(course.waitForExistence(timeout: 10), "Discarding the draft must keep the original course")
    }

}
