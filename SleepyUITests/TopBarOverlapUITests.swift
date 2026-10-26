// TopBarOverlapUITests.swift — 顶栏控件重叠复现探针
// 用户令 2026-10-26: 撤回胶囊与翻页三件套重叠(与 Android 不一致)。
// 手段: 种子数据 → 删一课(制造 undo 快照 → 胶囊出现)→ 量各控件 frame, 断言两区域不相交。
// 注: 语言只在冷启动时生效, 故英文/中文各一个测试类, 各自 setUp 单次 launch, 绝不中途重启。

import XCTest

extension XCUIApplication {
    fileprivate func frameOf(_ id: String) -> CGRect? {
        let el = descendants(matching: .any)[id].firstMatch
        guard el.waitForExistence(timeout: 4) else { return nil }
        return el.frame
    }

    /// 顶栏几何探针: 删课产生 undo 快照 → 打印各控件 frame → 断言左右两区不相交
    fileprivate func probeTopBarGeometry() {
        // 1. 切周视图(默认 cards 网格)→ 点一节有课的课 → 详情 sheet → 编辑 → 删除
        let enTab = descendants(matching: .any)["seg_Week"]
        let zhTab = descendants(matching: .any)["seg_周视图"]
        let weekTab = enTab.exists ? enTab : zhTab
        XCTAssertTrue(weekTab.waitForExistence(timeout: 8), "视图切换栏未出现"
        weekTab.tap()
        sleep(1)
        swipeUp()
        let lesson = descendants(matching: .any).matching(
            NSPredicate(format: "identifier CONTAINS 'lesson_'")).firstMatch
        XCTAssertTrue(lesson.waitForExistence(timeout: 10), "种子课表应有课"
        lesson.tap()

        let edit = descendants(matching: .any)["detail_edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "详情 sheet 未出现"
        edit.tap()

        let del = descendants(matching: .any)["course_delete"].firstMatch
        XCTAssertTrue(del.waitForExistence(timeout: 5)
        del.tap()
        // 二次确认 alert: en "Delete" / zh "删除"
        let enConfirm = buttons["Delete"].firstMatch
        let zhConfirm = buttons["删除"].firstMatch
        let confirm = enConfirm.exists ? enConfirm : zhConfirm
        if confirm.waitForExistence(timeout: 4) { confirm.tap() }
        // 回退到课表页(删除后 pop 或手动返回)
        let undo = descendants(matching: .any)["undo_button"].firstMatch
        if !undo.waitForExistence(timeout: 5) {
            navigationBars.firstMatch.buttons.firstMatch.tap()   // back
            XCTAssertTrue(undo.waitForExistence(timeout: 6), "删除后顶栏应出现撤回胶囊"
        }

        // 2. 打印顶栏全部控件 frame
        let ids = ["switch_table", "undo_button", "redo_button",
                   "week_prev", "week_label", "week_next", "topbar_add", "topbar_share"]
        var frames: [String: CGRect] = [:]
        for id in ids {
            if let f = frameOf(id) { frames[id] = f }
            print("TOPBAR[\(id)]: \(String(describing: frames[id]))")
        }

        // 3. 断言: 最左区(switch/undo/redo) 与 中区(week_prev/label/next) 不相交
        func assertDisjoint(_ a: String, _ b: String) {
            guard let fa = frames[a], let fb = frames[b] else {
                XCTFail("缺 frame: \(a) 或 \(b)"
                return
            }
            let overlap = fa.intersection(fb)
            if !overlap.isNull && overlap.width > 0.5 && overlap.height > 0.5 {
                // 注意: AX frame 可能含容器 padding, 交叠面积做阈值
                print("OVERLAP \(a) × \(b): \(overlap)")
                XCTFail("\(a) 与 \(b) 重叠 \(overlap.width)×\(overlap.height)"
            }
        }
        assertDisjoint("undo_button", "week_prev")
        assertDisjoint("switch_table", "week_prev")
        if frames["redo_button"] != nil { assertDisjoint("redo_button", "week_prev") }
        assertDisjoint("week_next", "topbar_add")
    }
}

final class TopBarOverlapUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-SLEEPY_UI_TEST_SEED", "1",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.sleepyLaunch()
    }

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testTopBarNoOverlapEnglish() throws {
        app.probeTopBarGeometry()
    }
}

/// 中文环境: 周标签"本学期第N周"/学期状态前缀更长 → 中央三件套更宽 → 重叠高危场景
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

    override func tearDown() {
        app.terminate()
        super.tearDown()
    }

    func testTopBarNoOverlapChineseLongLabel() throws {
        app.probeTopBarGeometry()
    }
}
