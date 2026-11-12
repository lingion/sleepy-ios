import XCTest

/// Drive both production tabs and custom navigation while a simulator recording
/// captures the animated edges. Screenshots after tap() alone miss the exposed
/// window because XCTest waits for the transition to settle.
final class NavigationTransitionCanvasUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    func testNativeTabsAndSettingsRoundTrips() {
        launch(style: "liquid_glass", forcePill: false)
        exerciseNavigation(forcePill: false)
    }

    func testClassicTabsAndSettingsRoundTrips() {
        launch(style: "classic", forcePill: true)
        exerciseNavigation(forcePill: true)
    }

    func testClassicWeekButtonsAndStationaryLift() {
        launch(style: "classic", forcePill: true)
        let pager = app.scheduleWeekPager
        let week = app.buttons["week_label"]
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        for (button, expected) in [("week_next", 2), ("week_next", 3), ("week_prev", 2), ("week_prev", 1)] {
            app.buttons[button].firstMatch.tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Week \(expected)"), object: week)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
            capture("classic-week-button-\(expected)")
        }
        let original = pager.buttons["gridcell_1"].firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 10))
        original.press(forDuration: 0.8)
        let edit = app.buttons["course_float_edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "A stationary long press keeps the floating actions visible")
        XCTAssertTrue(app.buttons["course_float_delete"].exists)
        XCTAssertFalse(app.buttons["course_move_confirm"].exists)
        capture("classic-stationary-lift")
        app.buttons["week_label"].firstMatch.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: edit)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["course_move_confirm"].exists)
        XCTAssertFalse(app.buttons["undo_button"].exists)
    }

    func testClassicWeekJumpAndNativeSwipeStayInSync() {
        launch(style: "classic", forcePill: true)
        let pager = app.scheduleWeekPager
        XCTAssertTrue(pager.waitForExistence(timeout: 10))
        func expectWeek(_ number: Int) {
            let changed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", "Week \(number)"),
                object: app.buttons["week_label"].firstMatch)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
        }
        app.buttons["week_label"].firstMatch.tap()
        let destination = app.buttons["week_num_12"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10))
        destination.tap()
        expectWeek(12)
        capture("classic-far-week-jump")
        pager.swipeRight()
        expectWeek(11)
        pager.swipeLeft()
        expectWeek(12)
        app.buttons["week_prev"].firstMatch.tap()
        expectWeek(11)
        capture("classic-native-week-swipe")
        // Away from the actual week, the label returns directly to it.
        app.buttons["week_label"].firstMatch.tap()
        expectWeek(1)
        capture("classic-far-week-return")
    }

    func testClassicChildPagesAndManualTableRoundTrips() {
        launch(style: "classic", forcePill: true)
        XCTAssertTrue(app.switchToPillTab("mine"))
        app.buttons["mine_all_tables"].firstMatch.tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let originalIDs = Set(rows.allElementsBoundByIndex.map(\.identifier))

        let create = app.buttons["New Schedule"].firstMatch
        reveal(create)
        create.tap()
        let name = app.textFields["field_Schedule Name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["table_update_from_school"].exists,
                       "A new timetable must contain the same configuration sections as Android")
        XCTAssertFalse(app.buttons["edit_table_delete"].exists)
        capture("classic-all-tables-new-child")
        app.buttons["topbar_back"].firstMatch.tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(Set(rows.allElementsBoundByIndex.map(\.identifier)), originalIDs,
                       "Returning from an unsaved child must discard only that draft")
        XCTAssertFalse(name.exists)
        capture("classic-all-tables-child-return")
        app.buttons["topbar_back"].firstMatch.tap()

        XCTAssertTrue(app.switchToPillTab("manage"))
        app.buttons["manage_import"].firstMatch.tap()
        let textMethod = app.buttons["import_text"].firstMatch
        XCTAssertTrue(textMethod.waitForExistence(timeout: 10))
        XCTAssertLessThan(app.buttons["topbar_back"].firstMatch.frame.minY, app.frame.height * 0.2,
                          "Import methods must open as a full-screen navigation page")
        let manual = app.buttons["manage_new_table"].firstMatch
        reveal(manual)
        manual.tap()
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertLessThan(app.buttons["topbar_back"].firstMatch.frame.minY, app.frame.height * 0.2,
                          "The manual timetable editor must also use a full-screen child page")
        capture("classic-import-new-table-child")
        app.buttons["topbar_back"].firstMatch.tap()
        XCTAssertTrue(textMethod.waitForExistence(timeout: 10))
        XCTAssertFalse(name.exists)
        capture("classic-import-new-table-return")
        app.buttons["topbar_back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["manage_import"].firstMatch.waitForExistence(timeout: 10))
    }

    func testClassicGridGalleryShowsBothIndependentWideWidgets() {
        launch(style: "classic", forcePill: true)
        XCTAssertTrue(app.switchToPillTab("mine"))
        let widgets = app.buttons["mine_widget"].firstMatch
        reveal(widgets)
        widgets.tap()
        let management = app.buttons["settings_widget_manage_entry"].firstMatch
        reveal(management)
        management.tap()
        let add = app.buttons["widget_gallery_add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        let full = app.buttons["widget_gallery_card_WeekGridWidgetV19"].firstMatch
        XCTAssertTrue(full.waitForExistence(timeout: 10))
        full.tap()
        let wide = app.buttons["widget_gallery_card_WeekGridVerticalWidget"].firstMatch
        XCTAssertTrue(wide.waitForExistence(timeout: 10))
        XCTAssertTrue(wide.isHittable)
        XCTAssertGreaterThan(wide.frame.midX, full.frame.midX)
        XCTAssertEqual(wide.frame.minY, full.frame.minY, accuracy: 2,
                       "Both grid faces must appear in the first expanded row")
        let horizontal = app.buttons["widget_gallery_card_WeekGridHorizontalWidget"].firstMatch
        reveal(horizontal)
        XCTAssertTrue(horizontal.waitForExistence(timeout: 10))
        XCTAssertTrue(horizontal.isHittable)
        XCTAssertFalse(app.buttons["widget_gallery_card_WeekGridWideWidget"].exists)
        capture("classic-grid-gallery-independent-wide-widgets")
    }

    func testClassicWidgetSharedDisplayOpensAsFullScreenAndReturnsToSettings() {
        launch(style: "classic", forcePill: true)
        XCTAssertTrue(app.switchToPillTab("mine"))
        let widgets = app.buttons["mine_widget"].firstMatch
        reveal(widgets)
        widgets.tap()
        let shared = app.buttons["settings_widget_shared_display"].firstMatch
        reveal(shared)
        capture("classic-widget-settings")
        shared.tap()
        let display = app.descendants(matching: .any)["schedule_display_settings"].firstMatch
        XCTAssertTrue(display.waitForExistence(timeout: 10))
        let back = app.buttons.matching(identifier: "topbar_back").allElementsBoundByIndex
            .last { $0.isHittable } ?? app.buttons["topbar_back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertLessThan(back.frame.minY, app.frame.height * 0.2,
                          "Shared timetable display must open as a full-screen child page")
        capture("classic-widget-shared-display")
        back.tap()
        XCTAssertTrue(shared.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["settings_widget_manage_entry"].firstMatch.exists)
        capture("classic-widget-shared-display-return")
    }

    func testIndependentWidgetEditorsUseProductionSectionsWithoutAModePicker() {
        launch(style: "classic", forcePill: true, placedWidgets: true)
        XCTAssertTrue(app.switchToPillTab("mine"))
        let widgets = app.buttons["mine_widget"].firstMatch
        reveal(widgets)
        widgets.tap()
        let management = app.buttons["settings_widget_manage_entry"].firstMatch
        reveal(management)
        management.tap()
        for mode in ["Vertical", "Horizontal"] {
            let row = app.buttons["widget_manage_row_WeekGrid\(mode)Widget"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            let schedule = app.staticTexts["widget_edit_schedule_heading"].firstMatch
            let alias = app.staticTexts["widget_edit_alias_heading"].firstMatch
            let wide = app.staticTexts["widget_edit_wide_heading"].firstMatch
            XCTAssertTrue(schedule.waitForExistence(timeout: 10))
            XCTAssertTrue(alias.exists)
            XCTAssertTrue(wide.exists)
            XCTAssertLessThan(schedule.frame.minY, alias.frame.minY)
            XCTAssertLessThan(alias.frame.minY, wide.frame.minY)
            XCTAssertTrue(app.staticTexts["wide-preview-caption-\(mode.lowercased())"].firstMatch
                .waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["wide-shape-picker"].exists)
            XCTAssertFalse(app.pickers["wide-shape-picker"].exists)
            XCTAssertFalse(app.buttons["wide-shape-original"].exists)
            XCTAssertFalse(app.buttons["wide-shape-vertical"].exists)
            XCTAssertFalse(app.buttons["wide-shape-horizontal"].exists)
            let left = app.buttons["wide-label-left"].firstMatch
            let right = app.buttons["wide-label-right"].firstMatch
            if mode == "Horizontal" {
                reveal(right)
                XCTAssertTrue(left.exists)
                let previouslyRight = right.isSelected
                right.tap()
                let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: right)
                XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
                capture("classic-widget-editor-horizontal")
                if !previouslyRight { left.tap() }
            } else {
                XCTAssertFalse(left.exists)
                XCTAssertFalse(right.exists)
                capture("classic-widget-editor-vertical")
            }
            let back = app.buttons["topbar_back"].firstMatch
            XCTAssertLessThan(back.frame.minY, app.frame.height * 0.2)
            back.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 10))
        }
    }

    func testChineseSettingsNamesAndPopulatedFieldLabels() {
        launch(style: "classic", forcePill: true, language: "zh-Hans")
        XCTAssertTrue(app.switchToPillTab("mine"))
        let holiday = app.buttons["mine_holiday"].firstMatch
        XCTAssertTrue(holiday.waitForExistence(timeout: 10))
        XCTAssertTrue(holiday.label.contains("节假日与调休"))
        let appearance = app.buttons["mine_appearance"].firstMatch
        reveal(appearance)
        XCTAssertTrue(appearance.label.contains("外观与主题"))
        capture("chinese-settings-names")
        let tables = app.buttons["mine_all_tables"].firstMatch
        for _ in 0..<6 {
            if tables.isHittable { break }
            app.swipeDown()
        }
        reveal(tables)
        tables.tap()
        let create = app.buttons["新建课表"].firstMatch
        reveal(create)
        create.tap()
        let weeks = app.textFields["field_总周数"].firstMatch
        XCTAssertTrue(weeks.waitForExistence(timeout: 10))
        XCTAssertEqual(weeks.value as? String, "20")
        XCTAssertTrue(app.staticTexts["总周数"].exists,
                      "A populated semester-week field must retain its visible title")
        XCTAssertTrue(app.staticTexts["课表名称"].exists)
        capture("chinese-populated-table-labels")
        app.buttons["topbar_back"].firstMatch.tap()
    }

    private func launch(style: String, forcePill: Bool, language: String = "en", placedWidgets: Bool = false) {
        app.launchArguments = ["-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                               "-SLEEPY_UI_TEST_SEED", "-ui_style", style,
                               "-theme_mode", "light"]
        app.launchEnvironment["TZ"] = "Asia/Shanghai"
        if forcePill { app.launchArguments.append("-SLEEPY_FORCE_PILL_NAV") }
        if placedWidgets { app.launchArguments.append("-SLEEPY_UI_TEST_PLACED_WIDGETS") }
        // sleepyLaunch() deliberately forces pills, so native coverage must use
        // the production resolver through the ordinary launch entry point.
        app.launch()
        XCTAssertTrue(app.buttons["topbar_share"].firstMatch.waitForExistence(timeout: 15))
    }

    private func exerciseNavigation(forcePill: Bool) {
        for (id, title) in [("mine", "Me"), ("manage", "Manage"),
                            ("today", "Today"), ("schedule", "Schedule"),
                            ("mine", "Me")] {
            if forcePill {
                XCTAssertTrue(app.switchToPillTab(id))
            } else {
                let tab = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
                XCTAssertTrue(tab.waitForExistence(timeout: 10), "Native tab \(title) must exist")
                tab.tap()
            }
        }
        XCTAssertTrue(app.buttons["mine_all_tables"].firstMatch.waitForExistence(timeout: 10))
        for identifier in ["mine_general", "mine_appearance", "mine_reminder"] {
            let entry = app.buttons[identifier].firstMatch
            reveal(entry)
            entry.tap()
            let back = app.buttons["topbar_back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10), "\(identifier) must open")
            capture("\(forcePill ? "classic" : "native")-\(identifier)")
            back.tap()
            let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                                   object: back)
            XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 10), .completed)
            XCTAssertTrue(app.buttons["mine_all_tables"].firstMatch.waitForExistence(timeout: 10))
        }
    }

    private func reveal(_ entry: XCUIElement) {
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        for _ in 0..<6 {
            if entry.isHittable && entry.frame.maxY < app.frame.maxY - 110 { return }
            app.swipeUp()
        }
        XCTAssertTrue(entry.isHittable && entry.frame.maxY < app.frame.maxY - 110,
                      "Settings entry must be above the floating navigation")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
