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
        del.tap()
        let enConfirm = buttons["Delete"].firstMatch
        let zhConfirm = buttons["删除"].firstMatch
        let confirm = enConfirm.exists ? enConfirm : zhConfirm
        if confirm.waitForExistence(timeout: 4) { confirm.tap() }
        let undo = descendants(matching: .any)["undo_button"].firstMatch
        if !undo.waitForExistence(timeout: 5) {
            navigationBars.firstMatch.buttons.firstMatch.tap()
            XCTAssertTrue(undo.waitForExistence(timeout: 6), "删除后顶栏应出现撤回胶囊")
        }

        let ids = ["switch_table", "undo_button", "redo_button",
                   "week_prev", "week_label", "week_next", "topbar_add", "topbar_share"]
        var frames: [String: CGRect] = [:]
        for id in ids {
            if let f = frameOf(id) { frames[id] = f }
            print("TOPBAR[\(id)]: \(String(describing: frames[id]))")
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
