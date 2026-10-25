// ScheduleFlowUITests.swift — G5+ 课表 Tab 全交互面测试
// 覆盖: 周导航(左/右箭头/跳周菜单/越界) + 视图切换(seg_week/seg_grid) +
//       课程卡点击 → 详情 Sheet(detail_close/detail_edit) + 左右滑翻周。
// 锚点: accessibilityIdentifier(week_prev/week_next/week_label/seg_*/detail_*)。

import XCTest

final class ScheduleFlowUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
        // 种子后课表非空 → 等周标签就绪
        XCTAssertTrue(app.descendants(matching: .any)["week_label"].waitForExistence(timeout: 8),
                      "课表顶栏周标签未出现(种子失败?)")
        sleep(2)   // 首屏渲染稳定(种子注入后 pager 布局动画)
    }

    /// 周标签文本(week_label 是 Button, 文本在 label 里)
    private func weekLabelText() -> String {
        app.descendants(matching: .any)["week_label"].label
    }
    private func waitWeekLabel(_ contains: String, timeout: TimeInterval = 4) -> Bool {
        let el = app.descendants(matching: .any)["week_label"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if el.exists && el.label.contains(contains) { return true }
            usleep(300_000)
        }
        return el.exists && el.label.contains(contains)
    }

    /// 稳定 tap: 等 hittable 再点(布局动画期间 tap 会落空)
    private func stableTap(_ el: XCUIElement, timeout: TimeInterval = 5) {
        let _ = el.waitForExistence(timeout: timeout)
        var waited = 0.0
        while !el.isHittable && waited < timeout {
            sleep(1); waited += 1
        }
        el.tap()
    }

    override func tearDownWithError() throws {
        app.terminate()   // 隔离: 每用例杀进程重启, 防跨用例状态串扰
    }

    // MARK: 周导航 — 左箭头(第1周 → 第0周越界不崩)

    func testWeekNavPrevAtWeek1ShowsOutOfRange() {
        let prev = app.descendants(matching: .any)["week_prev"]
        XCTAssertTrue(prev.waitForExistence(timeout: 5))
        stableTap(prev)
        // 越界态: 周标签变为 out-of-range 文案, 底栏仍在
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 3),
                      "第0周不应崩溃")
        // 越界时点标签 = 跳回实际周
        stableTap(app.descendants(matching: .any)["week_label"])
        XCTAssertTrue(waitWeekLabel("Week 1"),
                      "越界后点标签应跳回 Week 1, 实际=\(weekLabelText())")
    }

    // MARK: 周导航 — 右箭头(1 → 2)

    func testWeekNavNextIncrementsWeek() {
        let next = app.descendants(matching: .any)["week_next"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        stableTap(next)
        XCTAssertTrue(waitWeekLabel("Week 2"), "点右箭头后应显示 Week 2, 实际=\(weekLabelText())")
        // 再点右 → 3;点左回 2(双向)
        stableTap(next)
        XCTAssertTrue(waitWeekLabel("Week 3"))
        stableTap(app.descendants(matching: .any)["week_prev"])
        XCTAssertTrue(waitWeekLabel("Week 2"))
    }

    // MARK: 跳周菜单(week_label → 菜单 → 选第 5 周)

    func testWeekMenuJumpToWeek5() {
        stableTap(app.descendants(matching: .any)["week_label"])
        XCTAssertTrue(app.staticTexts["Jump to week"].waitForExistence(timeout: 4),
                      "跳周 sheet 未弹出")
        let week5 = app.descendants(matching: .any)["week_num_5"]
        XCTAssertTrue(week5.waitForExistence(timeout: 3), "sheet 里应有第 5 周按钮")
        stableTap(week5)
        XCTAssertTrue(waitWeekLabel("Week 5"), "应跳到第 5 周, 实际=\(weekLabelText())")
    }

    // MARK: 视图切换 — seg_Week ↔ seg_Grid(SegmentedSwitcher)
    // 出厂默认启动视图 = cards(网格, ← Android AppPrefs "cards"), 种子复位保证
    // 起步即在网格 → 先断网格态, 切 Week 断周视图, 再切回网格。

    func testViewModeSwitchCardsToWeekAndBack() {
        let grid = app.descendants(matching: .any)["seg_Grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5), "网格切换按钮应存在")
        // 起步 = 网格模式(默认 cards): 种子课"高等数学"应有 gridcell_ 卡
        let startCell = app.descendants(matching: .any)["gridcell_1"]
        XCTAssertTrue(startCell.waitForExistence(timeout: 5), "默认启动视图=网格, 应有课程卡")
        // 切 Week(周视图)
        let week = app.descendants(matching: .any)["seg_Week"]
        XCTAssertTrue(week.exists)
        week.tap()
        // 周视图 DetailPanel 行锚点 lesson_1(种子固定 id)
        XCTAssertTrue(app.descendants(matching: .any)["lesson_1"].waitForExistence(timeout: 5),
                      "周视图应显示课程行")
        // 切回网格
        grid.tap()
        XCTAssertTrue(app.descendants(matching: .any)["gridcell_1"].waitForExistence(timeout: 5),
                      "切回网格应显示课程卡")
    }

    // MARK: 课程卡点击 → 详情 Sheet + 关闭(detail_close)

    /// DetailPanel 的 LessonRow 按钮(label = "1-2, 高等数学, 张老师 · 教1-101")
    private func lessonButton(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
    }

    /// 默认启动视图=网格(← Android "cards"), DetailPanel 只在周视图存在 →
    /// 用到 lesson_ 锚点的用例先切 seg_Week(幂等: 已在周视图则空操作)。
    private func switchToWeekMode() {
        let week = app.descendants(matching: .any)["seg_Week"]
        XCTAssertTrue(week.waitForExistence(timeout: 5))
        week.tap()
        sleep(1)
    }

    func testCourseTapOpensDetailSheetAndClose() {
        switchToWeekMode()
        // DetailPanel 在屏幕下半 — 先上滑
        app.swipeUp()
        let course = lessonButton("高等数学")
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        course.tap()
        XCTAssertTrue(app.staticTexts["Teacher"].waitForExistence(timeout: 5),
                      "详情 Sheet 未弹出")
        XCTAssertTrue(app.staticTexts["张老师"].exists)
        let close = app.descendants(matching: .any)["detail_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertFalse(app.staticTexts["Teacher"].waitForExistence(timeout: 2),
                       "关闭后详情应消失")
    }

    // MARK: 详情 Sheet → 编辑入口(detail_edit → AddCourseScreen 编辑模式)

    func testDetailSheetEditButtonOpensEditor() {
        switchToWeekMode()
        app.swipeUp()
        let course = lessonButton("高等数学")
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        course.tap()
        let edit = app.descendants(matching: .any)["detail_edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "编辑按钮未出现")
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit Course"].waitForExistence(timeout: 5),
                      "编辑页未打开")
        // 顶栏返回(SettingsTopBar chevron.left 按钮 label=Back)
        let back = app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3), "返回按钮未出现")
        back.tap()
        // overlay 关闭 → 底栏恢复
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 4),
                      "返回后底栏应恢复")
    }

    // MARK: 左右滑翻周(TabView pager 手势)

    func testSwipeChangesWeek() {
        XCTAssertTrue(waitWeekLabel("Week 1"))
        let window = app.windows.firstMatch
        window.swipeLeft()
        var w2ok = waitWeekLabel("Week 2")
        if !w2ok {   // 第一次滑动可能被 pager 惯性吞掉 — 重试
            window.swipeLeft()
            w2ok = waitWeekLabel("Week 2")
        }
        XCTAssertTrue(w2ok, "左滑应翻到第 2 周")
        window.swipeRight()
        XCTAssertTrue(waitWeekLabel("Week 1"), "右滑应翻回第 1 周")
    }

    // MARK: 网格模式课程卡可点(切网格 → 点卡 → 详情)

    func testGridCardTapOpensDetail() {
        app.descendants(matching: .any)["seg_Grid"].tap()
        let course = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '大学英语'")).firstMatch
        XCTAssertTrue(course.waitForExistence(timeout: 5))
        course.tap()
        XCTAssertTrue(app.staticTexts["Teacher"].waitForExistence(timeout: 5),
                      "网格模式课程卡点击应弹详情")
        app.descendants(matching: .any)["detail_close"].tap()
    }

    // MARK: ★ 今天页课程卡点击 → 详情 Sheet(对齐 Android TodayScreen 点击交互;
    //       修复前 iOS 今天页课卡不可点、无详情 Sheet)

    func testTodayCourseTapOpensDetailSheet() {
        app.descendants(matching: .any)["pill_today"].tap()
        // 种子: 周一高数/周二英语/周三物理/周五体育 — 今天落哪天不定,
        // 用 today_course_ 标识符匹配任意课卡(旧版只认"高等数学", 非周一有课时两断言全挂)
        let course = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'today_course_'")).firstMatch
        guard course.waitForExistence(timeout: 4) else {
            // 今天无课(空态; 学期外文案不同, 两种都算通过)
            let empty = app.staticTexts.matching(NSPredicate(
                format: "label CONTAINS 'classes' OR label CONTAINS 'semester'")).firstMatch
            XCTAssertTrue(empty.waitForExistence(timeout: 3), "无课应显示空态")
            return
        }
        let isMath = course.label.contains("高等数学")
        course.tap()
        XCTAssertTrue(app.staticTexts["Teacher"].waitForExistence(timeout: 5),
                      "今天页课程卡点击应弹详情 Sheet(对齐 Android)")
        if isMath {
            XCTAssertTrue(app.staticTexts["张老师"].exists, "高数详情应含张老师")
        }
        let edit = app.descendants(matching: .any)["detail_edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3), "详情应含编辑入口")
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit Course"].waitForExistence(timeout: 5),
                      "详情编辑应打开课程编辑页")
        let back = app.buttons.matching(NSPredicate(format: "label == 'Back'")).firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        back.tap()
    }
}
