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

    private var tableRows: [String: String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'"))
            .allElementsBoundByIndex.reduce(into: [:]) { rows, element in
                rows[element.identifier] = element.label
            }
    }

    private func openTables() {
        let entry = app.buttons["manage_all_tables"].firstMatch
        reveal(entry)
        entry.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'"))
            .firstMatch.waitForExistence(timeout: 8))
    }

    private func openPeriodTables() {
        let screen = app.staticTexts["period_tables_screen"].firstMatch
        if !screen.exists {
            let entry = app.buttons["manage_period_tables"].firstMatch
            reveal(entry)
            entry.tap()
        }
        XCTAssertTrue(screen.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["period_tables_back"].firstMatch.isHittable)
    }

    private func replaceText(_ field: XCUIElement, with text: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        reveal(field, file: file, line: line)
        let oldValue = field.value as? String ?? ""
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        if !oldValue.isEmpty {
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldValue.count))
        }
        if !text.isEmpty { app.typeText(text) }
        XCTAssertEqual(field.value as? String, text, file: file, line: line)
    }

    private func assertMethodsRestored(pasteDraft: String? = nil,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let scroll = app.scrollViews["import_methods_scroll"].firstMatch
        XCTAssertTrue(waitUntil {
            scroll.exists && scroll.isHittable && self.app.buttons["import_text"].exists
        }, "Cancelling must restore the original import methods", file: file, line: line)
        if let pasteDraft {
            let input = app.descendants(matching: .any)["import_paste_input"].firstMatch
            XCTAssertTrue(input.exists, "The text source must remain expanded", file: file, line: line)
            XCTAssertEqual(input.value as? String, pasteDraft, file: file, line: line)
            XCTAssertTrue(app.buttons["import_preview_btn"].exists, file: file, line: line)
        }
    }

    private func openTextSource(entryID: String, text: String, preview: Bool = true) {
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
        guard preview else { return }
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

    func testExistingSourcesEmptyCopiedAndEmptyTableErrorCanCancelCapture() throws {
        openTables()
        let originalTables = tableRows
        XCTAssertEqual(originalTables.count, 1, "The seed supplies only the target timetable")
        let target = try XCTUnwrap(originalTables.first)
        let targetID = target.key.replacingOccurrences(of: "table_select_", with: "")
        tapBack()

        let draft = "#sleepy-v1\nTExisting Source Draft|2026-11-02|20|12\nCUnimported Source Orbit|6|3-4|1-20|Ada|A||||keep"
        openTextSource(entryID: "manage_add_course", text: draft, preview: false)
        let existing = app.buttons["import_existing"].firstMatch
        reveal(existing)
        existing.tap()
        let empty = app.staticTexts["add_course_no_source"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertEqual(empty.label, "No other timetables available. Add a timetable first.")
        XCTAssertFalse(app.buttons["import_source_" + targetID].exists)
        let sourceCancel = app.buttons["import_source_cancel"].firstMatch
        reveal(sourceCancel)
        capture("workflow-existing-source-empty")
        sourceCancel.tap()
        XCTAssertTrue(waitUntil { !sourceCancel.exists && !empty.exists })
        assertMethodsRestored(pasteDraft: draft)
        tapBack()

        // Build the source through the real copy form; the original stays the target.
        openTables()
        let duplicate = app.buttons["table_duplicate_" + targetID].firstMatch
        reveal(duplicate)
        duplicate.tap()
        let copiedName = "Workflow Source " + String(UUID().uuidString.prefix(8))
        let copyField = app.descendants(matching: .any)["table_copy_name"].firstMatch
        replaceText(copyField, with: copiedName)
        let copyConfirm = app.buttons["table_copy_confirm"].firstMatch
        reveal(copyConfirm)
        XCTAssertTrue(copyConfirm.isEnabled)
        copyConfirm.tap()
        XCTAssertTrue(waitUntil { !copyConfirm.exists && self.tableRows.count == 2 })
        XCTAssertEqual(tableRows[target.key], target.value)
        let copied = try XCTUnwrap(tableRows.first { $0.value == copiedName })
        let copiedID = copied.key.replacingOccurrences(of: "table_select_", with: "")
        tapBack()

        openTextSource(entryID: "manage_add_course", text: draft, preview: false)
        reveal(existing)
        existing.tap()
        let copiedSource = app.buttons["import_source_" + copiedID].firstMatch
        reveal(copiedSource)
        XCTAssertEqual(copiedSource.label, copiedName)
        XCTAssertEqual(app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'import_source_' AND identifier != 'import_source_cancel'")).count, 1)
        XCTAssertFalse(empty.exists)
        XCTAssertFalse(app.buttons["import_source_" + targetID].exists)
        XCTAssertFalse(app.staticTexts["import_source_error"].exists)
        capture("workflow-existing-source-copied-list")
        copiedSource.tap()
        let selectCancel = app.buttons["import_select_cancel"].firstMatch
        reveal(selectCancel)
        let selectedCourse = app.descendants(matching: .any)["select_course#0"].firstMatch
        reveal(selectedCourse)
        XCTAssertEqual(selectedCourse.value as? String, "1")
        XCTAssertTrue(["高等数学", "大学英语", "大学物理", "体育", "数据结构"].contains {
            selectedCourse.label.contains($0)
        }, "The copied source must offer a real seeded course")
        capture("workflow-existing-source-copied-selection")
        selectCancel.tap()
        XCTAssertTrue(waitUntil { !selectCancel.exists && !sourceCancel.exists })
        assertMethodsRestored(pasteDraft: draft)
        tapBack()

        // A saved blank table is a valid list entry but contains no importable courses.
        let create = app.buttons["manage_import"].firstMatch
        reveal(create)
        create.tap()
        let blank = app.buttons["manage_new_table"].firstMatch
        reveal(blank)
        blank.tap()
        let blankName = "Workflow Empty " + String(UUID().uuidString.prefix(8))
        replaceText(app.textFields["field_Schedule Name"].firstMatch, with: blankName)
        let save = app.buttons["edit_table_save"].firstMatch
        reveal(save)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(waitUntil { !save.exists })
        assertMethodsRestored()
        tapBack()
        openTables()
        XCTAssertTrue(waitUntil { self.tableRows.count == 3 })
        let fixtures = tableRows
        let blankRow = try XCTUnwrap(fixtures.first { $0.value == blankName })
        let blankID = blankRow.key.replacingOccurrences(of: "table_select_", with: "")
        let original = app.buttons[target.key].firstMatch
        reveal(original)
        original.tap()
        tapBack()

        openTextSource(entryID: "manage_add_course", text: draft, preview: false)
        reveal(existing)
        existing.tap()
        let emptySource = app.buttons["import_source_" + blankID].firstMatch
        reveal(emptySource)
        emptySource.tap()
        let error = app.staticTexts["import_source_error"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, "Content is empty")
        XCTAssertTrue(emptySource.exists, "A rejected source must remain in the source dialog")
        XCTAssertFalse(app.buttons["import_select_confirm"].exists)
        reveal(sourceCancel)
        capture("workflow-existing-source-empty-table-error")
        sourceCancel.tap()
        XCTAssertTrue(waitUntil { !sourceCancel.exists && !error.exists })
        assertMethodsRestored(pasteDraft: draft)
        capture("workflow-existing-source-cancel-methods")
        tapBack()
        openTables()
        XCTAssertEqual(tableRows, fixtures, "Cancelled selection and a rejected empty source must not create an import or backup table")
    }

    func testPurePeriodNameRejectsBlankAndTrimmedDuplicateThenCancelsToDraftCapture() throws {
        openTables()
        let originalTables = tableRows
        let target = try XCTUnwrap(originalTables.first)
        tapBack()

        // SleepyNativeExporter.exportPeriodTableJson uses tableInfo.timeList and no courses.
        let json = #"{"name":"Capture Bell","tableInfo":{"nodesPerDay":2,"timeList":[{"node":1,"startTime":"08:00","endTime":"08:45"},{"node":2,"startTime":"09:00","endTime":"09:45"}]}}"#
        openTextSource(entryID: "manage_import", text: json)
        let title = app.staticTexts["import_pure_period_title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        let name = app.descendants(matching: .any)["import_pure_period_field"].firstMatch
        reveal(name)
        let suggested = try XCTUnwrap(name.value as? String)
        XCTAssertFalse(suggested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        let confirm = app.buttons["import_pure_period_confirm"].firstMatch
        reveal(confirm)
        XCTAssertTrue(confirm.isEnabled)
        XCTAssertFalse(app.buttons["import_dialog_confirm"].exists)
        XCTAssertFalse(app.buttons["import_select_confirm"].exists)
        capture("workflow-pure-period-suggested-name")

        let duplicate = app.staticTexts["This name is already used by another table"].firstMatch
        replaceText(name, with: "   ")
        XCTAssertTrue(waitUntil { !confirm.isEnabled })
        XCTAssertFalse(duplicate.exists, "Whitespace blocks confirmation without reporting a duplicate")
        capture("workflow-pure-period-blank-name")
        replaceText(name, with: "  " + target.value + "  ")
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        XCTAssertFalse(confirm.isEnabled, "Trimmed names must also be checked against course timetables")
        capture("workflow-pure-period-duplicate-name")

        let discarded = "Workflow Bell " + String(UUID().uuidString.prefix(8))
        replaceText(name, with: discarded)
        XCTAssertTrue(waitUntil { confirm.isEnabled && !duplicate.exists })
        let cancel = app.buttons["import_pure_period_dismiss"].firstMatch
        reveal(cancel)
        capture("workflow-pure-period-name-recovers")
        cancel.tap()
        XCTAssertTrue(waitUntil { !title.exists && !confirm.exists })
        assertMethodsRestored(pasteDraft: json)
        XCTAssertFalse(app.descendants(matching: .any)["import_success_snackbar"].exists)
        capture("workflow-pure-period-cancel-methods")

        let parse = app.buttons["import_preview_btn"].firstMatch
        reveal(parse)
        parse.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertTrue(waitUntil { name.value as? String == suggested })
        XCTAssertNotEqual(name.value as? String, discarded, "A cancelled name must not leak into a new preview")
        XCTAssertFalse(duplicate.exists)
        reveal(cancel)
        cancel.tap()
        XCTAssertTrue(waitUntil { !title.exists })
        assertMethodsRestored(pasteDraft: json)
        tapBack()
        openTables()
        XCTAssertEqual(tableRows, originalTables, "Cancelling pure-period naming must preserve the course timetable list")
    }

    func testSharedSchedulePolicyRegistersThenCancelsWithoutSavingDraftCapture() throws {
        openTables()
        let originalTables = tableRows
        let originalName = try XCTUnwrap(originalTables.first?.value)
        tapBack()
        app.switchToPillTab("mine")
        let periodCount = app.staticTexts["mine_stat_period_tables_value"].firstMatch
        XCTAssertTrue(periodCount.waitForExistence(timeout: 8))
        let originalPeriodCount = try XCTUnwrap(Int(periodCount.label))
        app.switchToPillTab("manage")

        // Save one real source and bind it once. A single owner still exposes all three policies.
        openPeriodTables()
        let create = app.buttons["period_tables_new"].firstMatch
        reveal(create)
        create.tap()
        let sourceName = "Workflow Shared Bell " + String(UUID().uuidString.prefix(8))
        let sourceField = app.descendants(matching: .any)["field_Bell schedule name"].firstMatch
        let sourceSlots = app.buttons["period_table_slots_header"].firstMatch
        reveal(sourceSlots)
        sourceSlots.tap()
        replaceText(sourceField, with: sourceName)
        app.typeText("\n")
        XCTAssertTrue(waitUntil { !self.app.keyboards.firstMatch.exists })
        let saveSource = app.buttons["period_table_save"].firstMatch
        reveal(saveSource)
        saveSource.tap()
        let sourceConfirm = app.buttons["period_table_preview_confirm"].firstMatch
        reveal(sourceConfirm)
        sourceConfirm.tap()
        XCTAssertTrue(waitUntil { !sourceConfirm.exists && !saveSource.exists })
        openPeriodTables()
        let sourceLabel = app.staticTexts[sourceName].firstMatch
        reveal(sourceLabel)
        XCTAssertTrue(sourceLabel.identifier.hasPrefix("period_table_name_"))
        app.buttons["period_tables_back"].tap()

        let edit = app.buttons["manage_edit_current"].firstMatch
        reveal(edit)
        edit.tap()
        let slots = app.buttons["edit_table_slots_header"].firstMatch
        reveal(slots)
        slots.tap()
        let bellTab = app.buttons["seg_Bell schedule"].firstMatch
        reveal(bellTab)
        bellTab.tap()
        let source = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", sourceName)).firstMatch
        reveal(source)
        source.tap()
        let saveTable = app.buttons["edit_table_save"].firstMatch
        reveal(saveTable)
        saveTable.tap()
        let rebind = app.alerts["Confirm rebind"].firstMatch
        XCTAssertTrue(rebind.waitForExistence(timeout: 8))
        let bind = rebind.buttons["Save"].firstMatch
        reveal(bind)
        bind.tap()
        XCTAssertTrue(waitUntil { !rebind.exists && !saveTable.exists && edit.isHittable })

        reveal(edit)
        edit.tap()
        let tableName = app.textFields["field_Schedule Name"].firstMatch
        XCTAssertTrue(tableName.waitForExistence(timeout: 8))
        XCTAssertEqual(tableName.value as? String, originalName)
        let draftName = "Uncommitted Policy " + String(UUID().uuidString.prefix(8))
        replaceText(tableName, with: draftName)
        app.typeText("\n")
        XCTAssertTrue(waitUntil { !self.app.keyboards.firstMatch.exists })
        reveal(slots)
        slots.tap()
        // Remove the unused final period to change valid schedule content without a system time picker.
        let lastPeriod = app.buttons["slot_row_delete_12"].firstMatch
        reveal(lastPeriod)
        lastPeriod.tap()
        XCTAssertTrue(waitUntil { !lastPeriod.exists })
        reveal(saveTable)
        saveTable.tap()
        let policyTitle = app.staticTexts["Where should this schedule change go?"].firstMatch
        reveal(policyTitle)
        XCTAssertTrue(app.staticTexts["Current schedule: \(sourceName) (only this timetable uses it)"].exists)
        let optionTitles = ["Only this timetable", "Create a new schedule and bind", "Sync changes to period table “\(sourceName)”"]
        let options = optionTitles.map { title in
            app.buttons.matching(NSPredicate(format: "identifier == 'schedule_conflict_option' AND label BEGINSWITH %@", title)).firstMatch
        }
        XCTAssertEqual(app.buttons.matching(identifier: "schedule_conflict_option").count, 3)
        for option in options { reveal(option); XCTAssertTrue(option.isEnabled) }
        let cancel = app.buttons["schedule_conflict_cancel"].firstMatch
        reveal(cancel)
        capture("workflow-shared-schedule-three-policies")

        options[0].tap()
        let pending = app.staticTexts["Pending: Only this timetable · takes effect on next save"].firstMatch
        reveal(pending)
        XCTAssertFalse(policyTitle.exists)
        XCTAssertFalse(lastPeriod.exists, "Registering a policy must preserve the changed draft")
        let change = app.buttons["Change"].firstMatch
        reveal(change)
        capture("workflow-shared-schedule-pending-policy")
        change.tap()
        reveal(cancel)
        XCTAssertTrue(policyTitle.exists)
        cancel.tap()
        XCTAssertTrue(waitUntil { !cancel.exists && !pending.exists })
        reveal(lastPeriod)
        reveal(tableName)
        XCTAssertEqual(tableName.value as? String, draftName, "Cancelling the policy restores schedule content while retaining ordinary field drafts")
        capture("workflow-shared-schedule-cancel-restores-draft")
        tapBack()
        XCTAssertTrue(edit.waitForExistence(timeout: 8))

        // A normal restart proves the registered strategy and metadata were never committed.
        app.terminate()
        app.launchArguments.removeAll { $0 == "-SLEEPY_UI_TEST_SEED" }
        app.sleepyLaunch()
        app.switchToPillTab("mine")
        XCTAssertTrue(periodCount.waitForExistence(timeout: 8))
        XCTAssertEqual(periodCount.label, String(originalPeriodCount + 1), "Only the intentionally saved fixture may add a bell schedule")
        XCTAssertEqual(app.staticTexts["mine_stat_courses_value"].firstMatch.label, "5")
        app.switchToPillTab("manage")
        openTables()
        XCTAssertEqual(tableRows, originalTables)
        tapBack()
        reveal(edit)
        edit.tap()
        XCTAssertTrue(tableName.waitForExistence(timeout: 8))
        XCTAssertEqual(tableName.value as? String, originalName)
        reveal(slots)
        slots.tap()
        reveal(lastPeriod)
        XCTAssertFalse(pending.exists)
        capture("workflow-shared-schedule-cancel-keeps-saved-values")
        tapBack()
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
