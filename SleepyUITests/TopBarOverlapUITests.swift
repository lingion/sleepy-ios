// TopBarOverlapUITests.swift — 顶栏「撤回胶囊 × 翻页三件套」重叠探针
// 语言独立成类 + 单次冷启动(AppleLanguages 只在首启生效, 绝不中途重启)。
// 语义: 种子数据 → 删一课(产生 undo 快照 → 胶囊出现)→ 量顶栏各控件 frame → 断言左/中区不相交。

import XCTest

extension XCUIApplication {
    fileprivate func frameOf(_ id: String) -> CGRect? {
        let el = descendants(matching: .any)[id].firstMatch
        guard el.waitForExistence(timeout: 4) else { return nil }
        return el.frame
    }

    fileprivate func probeTopBarGeometry() {
        let enTab = descendants(matching: .any)["seg_Week"]
        let zhTab = descendants(matching: .any)["seg_周视图"]
        let weekTab = enTab.exists ? enTab : zhTab
        XCTAssertTrue(weekTab.waitForExistence(timeout: 8), "视图切换栏未出现")
        weekTab.tap()
        sleep(1)
        swipeUp()
        let lesson = descendants(matching: .any).matching(
            NSPredicate(format: "identifier CONTAINS 'lesson_'")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 10), "种子课表应有课")
        lesson.tap()

        let edit = descendants(matching: .any)["detail_edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "详情 sheet 未出现")
        edit.tap()

        let del = descendants(matching: .any)["course_delete"].firstMatch
        XCTAssertTrue(del.waitForExistence(timeout: 5))
        // XCTest's implicit scroll-to-tap can release while the editor is still
        // moving. Reveal the complete button before sending the actual action.
        let viewport = frame.insetBy(dx: 4, dy: 8)
        for _ in 0..<8 {
            if del.isHittable && viewport.contains(del.frame) { break }
            let foreground = scrollViews.allElementsBoundByIndex.reversed().first { $0.isHittable }
            XCTAssertNotNil(foreground, "The course editor must expose its scroll container")
            foreground?.swipeUp()
        }
        XCTAssertTrue(del.isHittable && viewport.contains(del.frame), "The complete delete action must be visible")
        var previousFrame = del.frame
        var stableSince = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = del.frame
            if current != previousFrame { stableSince = Date() }
            previousFrame = current
            return Date().timeIntervalSince(stableSince) >= 0.3
                && del.isHittable && viewport.contains(current)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        del.tap()
        let alert = alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Deleting must present its confirmation")
        let confirm = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Delete", "删除"])).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        let undo = descendants(matching: .any)["undo_button"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 8), "Confirmed deletion must expose undo on the schedule")

        let ids = ["switch_table", "undo_button", "redo_button",
                   "week_prev", "week_label", "week_next", "topbar_add", "topbar_share"]
        var frames: [String: CGRect] = [:]
        for id in ids {
            if let f = frameOf(id) { frames[id] = f }
            print("TOPBAR[\(id)]: \(String(describing: frames[id]))")
        }
        for id in ["switch_table", "topbar_add", "topbar_share"] {
            guard let frame = frames[id] else { XCTFail("Missing icon action: \(id)"); continue }
            XCTAssertEqual(frame.width, frame.height, accuracy: 1,
                           "Independent icon actions keep square slots for circular controls: \(id)")
            XCTAssertLessThanOrEqual(frame.width, 48.5,
                                    "Native padding must not grow an icon beyond the toolbar slot: \(id)")
        }
        XCTContext.runActivity(named: "Schedule toolbar after undo appears") { activity in
            let attachment = XCTAttachment(screenshot: screenshot())
            attachment.name = "schedule-toolbar-with-undo"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }

        func assertDisjoint(_ a: String, _ b: String) {
            guard let fa = frames[a], let fb = frames[b] else {
                XCTFail("缺 frame: \(a) 或 \(b)")
                return
            }
            let overlap = fa.intersection(fb)
            if !overlap.isNull && overlap.width > 0.5 && overlap.height > 0.5 {
                print("OVERLAP \(a) × \(b): \(overlap)")
                XCTFail("\(a) 与 \(b) 重叠 \(overlap.width)×\(overlap.height)")
            }
        }
        assertDisjoint("undo_button", "week_prev")
        assertDisjoint("switch_table", "week_prev")
        if frames["redo_button"] != nil { assertDisjoint("redo_button", "week_prev") }
        assertDisjoint("week_next", "topbar_add")
        if let previous = frames["week_prev"], let next = frames["week_next"] {
            XCTAssertEqual((previous.minX + next.maxX) / 2, descendants(matching: .any)["schedule_toolbar"].firstMatch.frame.midX, accuracy: 1,
                           "Week navigation remains centered on the full toolbar")
            for id in ids {
                guard let frame = frames[id] else { continue }
                XCTAssertEqual(frame.midY, previous.midY, accuracy: 1, "All toolbar controls remain on one row: \(id)")
            }
        }
    }
}

final class TopBarOverlapEnUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-SLEEPY_UI_TEST_SEED", "1",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.sleepyLaunch()
    }
    override func tearDown() { app.terminate(); super.tearDown() }
    func testTopBarNoOverlapEnglish() throws { app.probeTopBarGeometry() }
}

/// 中文长标签: 周标签/学期状态文案比英文更长 → 三件套更宽 → 重叠高危场景
final class TopBarOverlapZhUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-SLEEPY_UI_TEST_SEED", "1",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh-Hans-CN"]
        app.sleepyLaunch()
    }
    override func tearDown() { app.terminate(); super.tearDown() }
    func testTopBarNoOverlapChineseLongLabel() throws { app.probeTopBarGeometry() }
}

final class TopBarOverlapGlassUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-SLEEPY_UI_TEST_SEED", "1", "-ui_style", "liquid_glass",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.sleepyLaunch()
    }
    override func tearDown() { app.terminate(); super.tearDown() }
    func testNativeGlassTopBarKeepsOneCenteredRow() { app.probeTopBarGeometry() }

    func testNativeGlassRetainsFullWeekLabelAcrossTwoDigitWeeksAndRotation() {
        let week = app.buttons["week_label"]
        XCTAssertTrue(week.waitForExistence(timeout: 15))
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any)["schedule_toolbar"].firstMatch.frame.width, 360)

        func assertFullWeek(_ number: Int) {
            let updated = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", "Week \(number)"), object: week)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
            XCTAssertFalse(app.descendants(matching: .any)["week_group"].firstMatch.exists,
                           "Keep the full week wording until margin and side-action fallbacks are exhausted")
            XCTAssertEqual(app.buttons.matching(identifier: "week_label").count, 1,
                           "Hidden measurement candidates must not expose duplicate controls")
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "glass-toolbar-full-week-\(number)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        assertFullWeek(1)
        for _ in 1..<10 { app.buttons["week_next"].tap() }
        assertFullWeek(10)
        let toolbar = app.descendants(matching: .any)["schedule_toolbar"].firstMatch
        let portraitWidth = toolbar.frame.width
        XCUIDevice.shared.orientation = .landscapeLeft
        let wider = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            toolbar.frame.width > portraitWidth + 100
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [wider], timeout: 10), .completed)
        assertFullWeek(10)
        XCUIDevice.shared.orientation = .portrait
        let narrower = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(toolbar.frame.width - portraitWidth) < 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [narrower], timeout: 10), .completed)
        assertFullWeek(10)
    }
}
