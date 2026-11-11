import XCTest

/// Real settings entry points. Captures are evidence only after these tests run successfully.
final class SecondarySettingsCaptureUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED", "-SLEEPY_UI_TEST_HOLIDAYS",
                               "-ui_style", "classic"]
        app.sleepyLaunch()
        app.switchToPillTab("mine")
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 10))
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

    /// Reveal complete controls with short, reversible drags in their owning scroll gutter.
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
            // The center can hit a native settings slider instead of scrolling.
            let gutterX = min(area.maxX - 1, area.minX + 10)
            let start = origin.withOffset(CGVector(dx: gutterX, dy: area.minY + area.height * (earlier ? 0.40 : 0.65)))
            let end = origin.withOffset(CGVector(dx: gutterX, dy: area.minY + area.height * (earlier ? 0.58 : 0.47)))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertTrue(waitUntil { visible() }, "The complete target must be visible above navigation", file: file, line: line)
    }

    private func tapBack(file: StaticString = #filePath, line: UInt = #line) {
        let back = app.buttons.matching(identifier: "topbar_back").allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(back, file: file, line: line)
        back?.tap()
    }

    private func openScheduleSettings() {
        let entry = app.buttons["mine_schedule_settings"].firstMatch
        reveal(entry)
        entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["schedule_display_settings"].waitForExistence(timeout: 8))
    }

    private func tapForegroundCancel() {
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel'"))
            .allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(cancel, "The open editor must expose its Cancel action")
        if let cancel {
            reveal(cancel)
            cancel.tap()
        }
    }

    private func cancelOccurrencePrompt(_ alert: XCUIElement,
                                        file: StaticString = #filePath, line: UInt = #line) {
        let cancel = alert.buttons["occurrence_prompt_cancel"].firstMatch
        XCTAssertEqual(cancel.label, "Go back", file: file, line: line)
        XCTAssertTrue(cancel.isHittable, file: file, line: line)
        XCTAssertTrue(cancel.isEnabled, file: file, line: line)
        cancel.tap()
    }

    private func cancelSystemFilesPanel(file: StaticString = #filePath, line: UInt = #line) {
        for step in 0...8 {
            var cancel: XCUIElement?
            if waitUntil(timeout: 3, {
                cancel = self.app.buttons.matching(NSPredicate(format: "label == 'Cancel'"))
                    .allElementsBoundByIndex.last { $0.isHittable }
                return cancel != nil
            }), let cancel {
                cancel.tap()
                return
            }
            // Run19 AX: On My iPhone exposes BackButton / Browse in this
            // native bar. Return through Files navigation to its actual Cancel.
            let navigation = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"].firstMatch
            let back = navigation.buttons["BackButton"].firstMatch
            guard step < 8, navigation.exists && back.exists && back.isHittable,
                  navigation.frame.contains(back.frame) else { break }
            capture("secondary-backup-system-before-navigation-back")
            back.tap()
        }
        capture("secondary-backup-system-cancel-missing")
        let snapshot = app.debugDescription
        let attachment = XCTAttachment(string: snapshot)
        attachment.name = "secondary-backup-system-cancel-missing-ax"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("The open Files panel must expose its actual Cancel action.\n\(snapshot)", file: file, line: line)
    }

    private var tableRows: [String: String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'"))
            .allElementsBoundByIndex.reduce(into: [:]) { $0[$1.identifier] = $1.label }
    }

    private func savedTableRows() -> [String: String] {
        let tables = app.buttons["mine_all_tables"].firstMatch
        reveal(tables)
        tables.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'"))
            .firstMatch.waitForExistence(timeout: 8))
        let rows = tableRows
        tapBack()
        XCTAssertTrue(tables.waitForExistence(timeout: 5))
        return rows
    }

    private func restartWithoutSeed() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "-SLEEPY_UI_TEST_SEED" || $0 == "-SLEEPY_UI_TEST_HOLIDAYS" }
        app.sleepyLaunch()
        app.switchToPillTab("mine")
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 10))
    }

    private func retainFailure(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        capture(name)
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name + "-accessibility"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTFail("The real system control must be reachable; inspect the retained accessibility tree", file: file, line: line)
    }

    /// Use Files' real Browse/location navigation, including a remembered subfolder.
    private func openLocalFilesRoot(file: StaticString = #filePath, line: UInt = #line) {
        let root = app.otherElements.matching(NSPredicate(format:
            "identifier BEGINSWITH 'DOC.browsingRoot Source: com.apple.FileProvider.LocalStorage, Title: On My '")).firstMatch
        for _ in 0..<8 {
            if root.exists { return }
            let location = app.descendants(matching: .any).matching(NSPredicate(
                format: "label IN {'On My iPhone', 'On My iPad'}"))
                .allElementsBoundByIndex.first { $0.isHittable }
            if let location {
                location.tap()
                if waitUntil(timeout: 3, { root.exists }) { return }
                continue
            }
            let back = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
                .buttons["BackButton"].firstMatch
            if back.exists && back.isHittable {
                back.tap()
            } else if app.tabBars.buttons["Browse"].firstMatch.isHittable {
                app.tabBars.buttons["Browse"].firstMatch.tap()
            } else {
                break
            }
        }
        retainFailure("secondary-backup-local-files-root-missing", file: file, line: line)
    }

    private var fixtureCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = fixtureCalendar.timeZone
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private func selectOccurrenceDate(_ target: Date, from original: Date,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let field = app.buttons["occurrence_date"].firstMatch
        reveal(field, file: file, line: line)
        field.tap()
        let confirm = app.buttons["date_picker_confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), file: file, line: line)
        let picker = app.datePickers.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), file: file, line: line)
        let calendar = fixtureCalendar
        let originalMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: original))!
        let targetMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: target))!
        let months = calendar.dateComponents([.month], from: originalMonth, to: targetMonth).month!
        XCTAssertTrue((0...5).contains(months), "The fixture must remain near the seeded semester", file: file, line: line)
        for _ in 0..<max(0, months) {
            let next = picker.buttons["Next Month"].firstMatch
            guard next.waitForExistence(timeout: 3), next.isHittable else {
                retainFailure("secondary-holiday-occurrence-month-navigation-missing", file: file, line: line)
                return
            }
            next.tap()
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, MMMM d"
        let labels = [formatter.string(from: target), fullDate(target)]
        let days = picker.buttons.matching(NSPredicate(format: "label IN %@", labels))
        let day = days.firstMatch
        guard day.waitForExistence(timeout: 3), day.isEnabled else {
            retainFailure("secondary-holiday-occurrence-date-missing", file: file, line: line)
            return
        }
        XCTAssertEqual(days.count, 1, "Select the exact civil date", file: file, line: line)
        reveal(day, file: file, line: line)
        day.tap()
        reveal(confirm, file: file, line: line)
        confirm.tap()
        XCTAssertTrue(waitUntil { !confirm.exists && field.label.contains(self.fullDate(target)) }, file: file, line: line)
    }

    func testHolidayTransferDestinationDirectAndOutgoingPromptsCancelWithoutSavingCourseCapture() throws {
        let originalTables = savedTableRows()
        let courseCount = app.staticTexts["mine_stat_courses_value"].firstMatch
        XCTAssertEqual(courseCount.label, "5")
        let calendar = fixtureCalendar
        let today = calendar.startOfDay(for: Date())
        let monday = calendar.date(byAdding: .day,
            value: -((calendar.component(.weekday, from: today) + 5) % 7), to: today)!
        let nextYear = calendar.component(.year, from: today) + 1
        let source = try XCTUnwrap(calendar.date(from: DateComponents(year: nextYear, month: 1, day: 1)))
        let destination = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: source))
        XCTAssertGreaterThan(source, monday)
        XCTAssertLessThan(destination, calendar.date(byAdding: .day, value: 140, to: monday)!,
                          "This year-boundary fixture must fit the current seeded semester")

        // Both years are cached by the existing holiday seed. Add through the
        // real empty next-year page; its new range defaults to January 1.
        openScheduleSettings()
        let holiday = app.buttons["settings_holiday_entry"].firstMatch
        reveal(holiday)
        holiday.tap()
        let nextYearButton = app.buttons["Next year"].firstMatch
        reveal(nextYearButton)
        nextYearButton.tap()
        XCTAssertTrue(app.staticTexts[String(nextYear)].waitForExistence(timeout: 5))
        let dates = app.buttons["holiday_group_dates"].firstMatch
        reveal(dates)
        dates.tap()
        let add = app.buttons["holiday_add_entry"].firstMatch
        reveal(add)
        add.tap()
        let name = app.textFields["holiday_name_input"].firstMatch
        reveal(name)
        let fixtureName = "Approval Holiday " + String(UUID().uuidString.prefix(8))
        name.tap()
        name.typeText(fixtureName + "\n")
        XCTAssertEqual(name.value as? String, fixtureName)
        let saveHoliday = app.buttons["holiday_save"].firstMatch
        reveal(saveHoliday)
        saveHoliday.tap()
        XCTAssertTrue(waitUntil { !saveHoliday.exists })
        let group = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'holiday_group_transfer:' AND label CONTAINS %@", fixtureName)).firstMatch
        reveal(group)
        group.tap()
        let mappingID = String(format: "holiday_mapping_%04d-01-01", nextYear)
        let mapping = app.buttons[mappingID].firstMatch
        reveal(mapping)
        mapping.tap()
        let other = app.buttons["Other date…"].firstMatch
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.tap()
        let dateConfirm = app.buttons["holiday_date_confirm"].firstMatch
        XCTAssertTrue(dateConfirm.waitForExistence(timeout: 5))
        let wheels = app.pickerWheels.allElementsBoundByIndex
        XCTAssertEqual(wheels.count, 3)
        let dayWheel = try XCTUnwrap(wheels.first { ($0.value as? String) == "1" })
        XCTAssertTrue(wheels.contains { ($0.value as? String) == String(nextYear) })
        XCTAssertTrue(wheels.contains { ($0.value as? String) == "January" })
        dayWheel.adjust(toPickerWheelValue: "2")
        reveal(dateConfirm)
        dateConfirm.tap()
        XCTAssertTrue(waitUntil { !dateConfirm.exists && mapping.label.contains("1/2") })
        capture("secondary-holiday-approval-fixture-mapping")
        tapBack()
        tapBack()

        app.switchToPillTab("schedule")
        let course = app.collectionViews["schedule_week_pager"].buttons["gridcell_1"].firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 8))
        let originalCard = course.label
        course.tap()
        let actions = app.buttons["course_occurrence_actions"].firstMatch
        reveal(actions)
        actions.tap()
        let adjust = app.buttons["occurrence_adjust"].firstMatch
        XCTAssertTrue(adjust.waitForExistence(timeout: 5))
        adjust.tap()
        let date = app.buttons["occurrence_date"].firstMatch
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        let originalDateLabel = date.label
        let room = app.textFields["occurrence_room"].firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 5))
        let originalRoom = try XCTUnwrap(room.value as? String)
        selectOccurrenceDate(destination, from: monday)
        let save = app.buttons["occurrence_save"].firstMatch
        reveal(save)
        save.tap()
        let destinationPrompt = app.alerts["Choose how to schedule this class"].firstMatch
        XCTAssertTrue(destinationPrompt.waitForExistence(timeout: 5))
        XCTAssertTrue(destinationPrompt.staticTexts.matching(NSPredicate(
            format: "label CONTAINS '高等数学' AND label CONTAINS %@ AND label CONTAINS %@",
            String(format: "%04d-01-02", nextYear), String(format: "%04d-01-01", nextYear))).firstMatch.exists)
        XCTAssertTrue(destinationPrompt.buttons["Follow the holiday transfer"].isEnabled)
        XCTAssertTrue(destinationPrompt.buttons["Schedule directly on this day"].isEnabled)
        capture("secondary-holiday-occurrence-destination-confirmation")
        cancelOccurrencePrompt(destinationPrompt)
        XCTAssertTrue(waitUntil { !destinationPrompt.exists && date.label.contains(self.fullDate(destination)) })
        XCTAssertEqual(room.value as? String, originalRoom)

        reveal(save)
        save.tap()
        XCTAssertTrue(destinationPrompt.waitForExistence(timeout: 5))
        destinationPrompt.buttons["Schedule directly on this day"].tap()
        let hidden = app.alerts["This class will be hidden by the transfer"].firstMatch
        XCTAssertTrue(hidden.waitForExistence(timeout: 5))
        XCTAssertTrue(hidden.staticTexts.matching(NSPredicate(
            format: "label CONTAINS '高等数学' AND label CONTAINS %@ AND label CONTAINS %@",
            String(format: "%04d-01-02", nextYear), String(format: "%04d-01-01", nextYear))).firstMatch.exists)
        XCTAssertTrue(hidden.buttons["Schedule directly anyway"].isEnabled)
        capture("secondary-holiday-occurrence-direct-hidden-confirmation")
        cancelOccurrencePrompt(hidden)
        XCTAssertTrue(waitUntil { !hidden.exists && date.label.contains(self.fullDate(destination)) })
        XCTAssertEqual(room.value as? String, originalRoom)

        selectOccurrenceDate(source, from: destination)
        reveal(save)
        save.tap()
        let outgoing = app.alerts["This class will be transferred"].firstMatch
        XCTAssertTrue(outgoing.waitForExistence(timeout: 5))
        XCTAssertTrue(outgoing.staticTexts.matching(NSPredicate(
            format: "label CONTAINS '高等数学' AND label CONTAINS %@ AND label CONTAINS %@",
            String(format: "%04d-01-01", nextYear), String(format: "%04d-01-02", nextYear))).firstMatch.exists)
        XCTAssertTrue(outgoing.buttons["Continue"].isEnabled)
        capture("secondary-holiday-occurrence-outgoing-confirmation")
        cancelOccurrencePrompt(outgoing)
        XCTAssertTrue(waitUntil { !outgoing.exists && date.label.contains(self.fullDate(source)) })
        XCTAssertEqual(room.value as? String, originalRoom)
        capture("secondary-holiday-occurrence-cancel-keeps-date-draft")
        let cancel = app.buttons["occurrence_cancel"].firstMatch
        reveal(cancel)
        cancel.tap()
        XCTAssertTrue(waitUntil { !cancel.exists && actions.exists })
        reveal(actions)
        actions.tap()
        XCTAssertTrue(adjust.waitForExistence(timeout: 5))
        adjust.tap()
        XCTAssertTrue(date.waitForExistence(timeout: 5))
        XCTAssertEqual(date.label, originalDateLabel)
        XCTAssertEqual(room.value as? String, originalRoom)
        reveal(cancel)
        cancel.tap()
        let close = app.buttons["detail_close"].firstMatch
        reveal(close)
        close.tap()
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        XCTAssertEqual(course.label, originalCard)
        app.switchToPillTab("mine")
        XCTAssertEqual(courseCount.label, "5")
        XCTAssertEqual(savedTableRows(), originalTables)
        restartWithoutSeed()
        XCTAssertEqual(courseCount.label, "5")
        XCTAssertEqual(savedTableRows(), originalTables)
        app.switchToPillTab("schedule")
        XCTAssertTrue(course.waitForExistence(timeout: 8))
        XCTAssertEqual(course.label, originalCard, "Approval cancellation must not change the stored course")
        capture("secondary-holiday-occurrence-cancel-keeps-saved-course")
    }

    func testBackupRestoreModeCancelsAfterRealLocalExportWithoutChangingSchedulesCapture() throws {
        let originalTables = savedTableRows()
        let courseCount = app.staticTexts["mine_stat_courses_value"].firstMatch
        let periodCount = app.staticTexts["mine_stat_period_tables_value"].firstMatch
        XCTAssertEqual(courseCount.label, "5")
        let originalPeriods = periodCount.label
        let backup = app.buttons["mine_backup"].firstMatch
        reveal(backup)
        backup.tap()
        let export = app.buttons["settings_migration_export_row"].firstMatch
        reveal(export)
        export.tap()
        let fileName = app.textFields["DOCPicker.filenameTextField"].firstMatch
        XCTAssertTrue(fileName.waitForExistence(timeout: 15))
        let exportedName = try XCTUnwrap(fileName.value as? String)
        XCTAssertNotNil(exportedName.range(of: #"^sleepy-backup-\d{8}-\d{6}(\.[A-Za-z0-9]+)?$"#,
                                          options: .regularExpression),
                        "Select the exact exported file rather than a truncated display label")
        openLocalFilesRoot()
        let save = app.buttons.matching(NSPredicate(format: "label == 'Save'")).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(save.isEnabled)
        reveal(save)
        capture("secondary-backup-real-local-export")
        save.tap()
        XCTAssertTrue(waitUntil(timeout: 15) { !save.exists && export.isHittable })
        let toast = app.staticTexts["settings_migration_toast"].firstMatch
        XCTAssertTrue(waitUntil { toast.exists && toast.label == ".sleepybackup exported" })
        let restore = app.buttons["settings_migration_import_row"].firstMatch
        reveal(restore)
        restore.tap()
        XCTAssertTrue(app.collectionViews["File View"].firstMatch.waitForExistence(timeout: 10))
        openLocalFilesRoot()
        let file = app.collectionViews["File View"].cells.matching(NSPredicate(
            format: "label BEGINSWITH %@", exportedName)).firstMatch
        guard file.waitForExistence(timeout: 8) else {
            retainFailure("secondary-backup-exported-file-missing")
            return
        }
        reveal(file)
        capture("secondary-backup-select-real-export")
        file.tap()
        let mode = app.alerts["Import migration backup"].firstMatch
        XCTAssertTrue(mode.waitForExistence(timeout: 10))
        XCTAssertTrue(mode.buttons["Overwrite"].isEnabled)
        XCTAssertTrue(mode.buttons["Merge"].isEnabled)
        XCTAssertTrue(mode.staticTexts.matching(NSPredicate(
            format: "label == %@", "Overwrite clears all local timetables and settings, then restores from the backup. Merge keeps local data and only appends backup content.")).firstMatch.exists)
        let cancel = mode.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.isHittable)
        capture("secondary-backup-restore-mode-confirmation")
        cancel.tap()
        XCTAssertTrue(waitUntil { !mode.exists && export.isHittable && restore.isHittable })
        XCTAssertFalse(toast.exists && toast.label.hasPrefix("Imported"), "Cancel must not execute migration")
        capture("secondary-backup-restore-mode-cancelled")
        restore.tap()
        XCTAssertTrue(app.collectionViews["File View"].firstMatch.waitForExistence(timeout: 10),
                      "Cancelling the mode must release the import operation")
        cancelSystemFilesPanel()
        XCTAssertTrue(waitUntil { !mode.exists && export.isHittable && restore.isHittable })
        tapBack()
        XCTAssertEqual(courseCount.label, "5")
        XCTAssertEqual(periodCount.label, originalPeriods)
        XCTAssertEqual(savedTableRows(), originalTables)
        restartWithoutSeed()
        XCTAssertEqual(courseCount.label, "5")
        XCTAssertEqual(periodCount.label, originalPeriods)
        XCTAssertEqual(savedTableRows(), originalTables)
    }

    func testHolidayMappingOtherDateAndRangeEditorCapture() {
        openScheduleSettings()
        let entry = app.buttons["settings_holiday_entry"].firstMatch
        reveal(entry)
        entry.tap()
        XCTAssertTrue(app.buttons["holiday_group_dates"].waitForExistence(timeout: 8))

        let mappingGroup = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'holiday_group_transfer:'")).firstMatch
        reveal(mappingGroup)
        XCTAssertEqual(mappingGroup.value as? String, "collapsed")
        mappingGroup.tap()
        let mapping = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'holiday_mapping_'")).firstMatch
        reveal(mapping)
        XCTAssertEqual(mappingGroup.value as? String, "expanded")
        capture("secondary-holiday-mapping-expanded")
        mapping.tap()
        let otherDate = app.buttons["Other date…"].firstMatch
        XCTAssertTrue(otherDate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["None"].exists)
        capture("secondary-holiday-mapping-menu")
        otherDate.tap()
        let dateConfirm = app.buttons["holiday_date_confirm"].firstMatch
        XCTAssertTrue(dateConfirm.waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        reveal(dateConfirm)
        capture("secondary-holiday-other-date-picker")
        tapForegroundCancel()
        XCTAssertTrue(waitUntil { !dateConfirm.exists && mapping.isHittable })

        let dates = app.buttons["holiday_group_dates"].firstMatch
        reveal(dates)
        dates.tap()
        let range = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'holiday_date_edit_' AND label CONTAINS 'New Year'")).firstMatch
        reveal(range)
        range.tap()
        let name = app.textFields["holiday_name_input"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "New Year")
        XCTAssertTrue(app.staticTexts["Start date"].exists)
        XCTAssertTrue(app.staticTexts["End date"].exists)
        let save = app.buttons["holiday_save"].firstMatch
        reveal(save)
        capture("secondary-holiday-range-editor")
        tapForegroundCancel()
        XCTAssertTrue(waitUntil { !save.exists && range.isHittable })
        tapBack()
        XCTAssertTrue(app.descendants(matching: .any)["schedule_display_settings"].waitForExistence(timeout: 5))
        tapBack()
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5))
    }

    func testLanguageMenuAndVisibleWeekdaysCapture() {
        let general = app.buttons["mine_general"].firstMatch
        reveal(general)
        general.tap()
        let language = app.buttons["card_language"].firstMatch
        reveal(language)
        language.tap()
        let menu = app.collectionViews.containing(.button, identifier: "Español").firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        for label in ["简体中文", "繁體中文", "English", "日本語", "Español"] {
            XCTAssertTrue(menu.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch.exists)
        }
        capture("secondary-language-menu")
        let window = app.windows.firstMatch.frame
        let candidates = [CGPoint(x: window.minX + 24, y: window.minY + 100),
                          CGPoint(x: window.maxX - 24, y: window.minY + 100),
                          CGPoint(x: window.minX + 24, y: window.maxY - 80)]
        let outside = candidates.first { !menu.frame.insetBy(dx: -12, dy: -12).contains($0) }
        XCTAssertNotNil(outside, "The native menu must leave an outside dismissal target")
        if let outside {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: outside.x, dy: outside.y)).tap()
        }
        XCTAssertTrue(waitUntil { !menu.exists && language.isHittable })
        tapBack()
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5))

        openScheduleSettings()
        let days = app.descendants(matching: .any)["card_Visible Days"].firstMatch
        reveal(days, headerOnly: true)
        let monday = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Mon'")).firstMatch
        if !monday.exists {
            days.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: days.frame.width / 2, dy: 24)).tap()
        }
        XCTAssertTrue(monday.waitForExistence(timeout: 5))
        for day in ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", day)).firstMatch.exists)
        }
        reveal(monday)
        capture("secondary-visible-weekdays-upper")
        let sunday = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Sun'")).firstMatch
        reveal(sunday)
        capture("secondary-visible-weekdays-lower")
        tapBack()
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5))
    }

    func testReminderTimetableListCapture() {
        let reminder = app.buttons["mine_reminder"].firstMatch
        reveal(reminder)
        reminder.tap()
        let scope = app.buttons["reminder_table_reminder_entry"].firstMatch
        reveal(scope)
        scope.tap()
        let row = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'table_reminder_row_'" )).firstMatch
        reveal(row)
        XCTAssertTrue(app.staticTexts["Timetables to remind"].exists)
        XCTAssertTrue(app.staticTexts["我的课表"].exists)
        XCTAssertTrue(app.switches.firstMatch.exists)
        capture("secondary-reminder-timetable-list")
        tapBack()
        XCTAssertTrue(scope.waitForExistence(timeout: 5))
        tapBack()
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5))
    }

    func testBackupExportCancelAndAboutLicenseCapture() {
        let backup = app.buttons["mine_backup"].firstMatch
        reveal(backup)
        backup.tap()
        let export = app.buttons["settings_migration_export_row"].firstMatch
        let restore = app.buttons["settings_migration_import_row"].firstMatch
        reveal(export)
        reveal(restore)
        capture("secondary-backup-main")
        export.tap()

        // A Files subdirectory can show a navigation Back action instead of Cancel.
        // Its Save action and the backup filename establish that export has opened.
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel'")).firstMatch
        let fileName = app.textFields.matching(NSPredicate(
            format: "value BEGINSWITH 'sleepy-backup' OR label BEGINSWITH 'sleepy-backup'")).firstMatch
        let fileLabel = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'sleepy-backup'")).firstMatch
        let save = app.buttons.matching(NSPredicate(format: "label == 'Save'")).firstMatch
        XCTAssertTrue(waitUntil(timeout: 15) {
            save.exists && save.isHittable && (fileName.exists || fileLabel.exists)
        }, "Export must present the system file-saving panel")
        capture("secondary-backup-system-save-panel")
        cancelSystemFilesPanel()
        let dismissed = waitUntil { !cancel.exists && export.isHittable && restore.isHittable }
        capture("secondary-backup-after-system-cancel")
        XCTAssertTrue(dismissed, app.debugDescription)

        // These rows remain hittable while migrationBusy is true. Reopening the
        // real pickers proves that cancellation also releases the operation lock.
        export.tap()
        XCTAssertTrue(waitUntil(timeout: 15) {
            save.exists && save.isHittable && (fileName.exists || fileLabel.exists)
        }, "Canceling export must allow another backup export to present its filename and Save action.\n\(app.debugDescription)")
        capture("secondary-backup-export-reopened-after-cancel")
        cancelSystemFilesPanel()
        XCTAssertTrue(waitUntil {
            !cancel.exists && !fileName.exists && !fileLabel.exists && !save.exists
                && export.isHittable && restore.isHittable
        }, "The second export panel must close after cancellation.\n\(app.debugDescription)")

        restore.tap()
        let filesLocation = app.descendants(matching: .any).matching(NSPredicate(
            format: "label IN {'Locations', 'Browse', 'Recents', 'On My iPad', 'On My iPhone', 'iCloud Drive'}")).firstMatch
        XCTAssertTrue(waitUntil(timeout: 15) {
            cancel.exists && cancel.isHittable && filesLocation.exists
                && !fileName.exists && !fileLabel.exists && !save.exists
        }, "Canceling export must allow the system backup import picker to open.\n\(app.debugDescription)")
        capture("secondary-backup-system-import-panel-after-export-cancel")
        cancelSystemFilesPanel()
        XCTAssertTrue(waitUntil {
            !cancel.exists && !filesLocation.exists && export.isHittable && restore.isHittable
        }, "Canceling backup import must return to the backup controls.\n\(app.debugDescription)")
        capture("secondary-backup-after-system-import-cancel")
        tapBack()
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5))

        let about = app.buttons["mine_about"].firstMatch
        reveal(about)
        about.tap()
        let license = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Open Source License'")).firstMatch
        reveal(license)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == 'Privacy Policy'")).firstMatch.exists)
        capture("secondary-about-bottom")
        license.tap()
        XCTAssertTrue(app.staticTexts["License & Acknowledgements"].waitForExistence(timeout: 5))
        let licenseText = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS 'GNU General Public License v3.0'")).firstMatch
        reveal(licenseText)
        capture("secondary-open-source-license")
        tapBack()
        XCTAssertTrue(license.waitForExistence(timeout: 5))
        tapBack()
        XCTAssertTrue(app.buttons["mine_all_tables"].waitForExistence(timeout: 5))
    }

    func testNewBellScheduleManualAndAutoEditorCancelCapture() {
        app.switchToPillTab("manage")
        let entry = app.buttons["manage_period_tables"].firstMatch
        reveal(entry)
        entry.tap()
        let create = app.buttons["period_tables_new"].firstMatch
        reveal(create)
        let originalRows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'period_table_edit_'"))
            .allElementsBoundByIndex.map(\.identifier).sorted()
        create.tap()
        let name = app.textFields["field_Bell schedule name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 8))
        let manual = app.buttons["seg_Manual mode"].firstMatch
        let automatic = app.buttons["seg_Auto mode"].firstMatch
        XCTAssertTrue(manual.isSelected)
        let firstRow = app.descendants(matching: .any)["slot_row_1"].firstMatch
        reveal(firstRow)
        capture("secondary-new-bell-schedule-manual")
        reveal(automatic)
        automatic.tap()
        XCTAssertTrue(waitUntil { automatic.isSelected })
        let duration = app.textFields["number_Per-period duration"].firstMatch
        let total = app.textFields["number_Total periods"].firstMatch
        reveal(duration)
        reveal(total)
        capture("secondary-new-bell-schedule-auto-upper")
        let preview = app.staticTexts["Preview"].firstMatch
        reveal(preview)
        capture("secondary-new-bell-schedule-auto-lower")

        // The editor's production header uses the Back label. Returning without
        // saving discards the newly inserted draft row through handleBack().
        let back = app.buttons.matching(NSPredicate(format: "label == 'Back'"))
            .allElementsBoundByIndex.last { $0.isHittable }
        XCTAssertNotNil(back)
        back?.tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(waitUntil {
            !name.exists && originalRows == self.app.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH 'period_table_edit_'"))
                .allElementsBoundByIndex.map(\.identifier).sorted()
        }, "Cancel must return to the original bell-schedule list without a draft row")
    }
}
