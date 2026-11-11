// 实际 overlay 返回、边缘手势与课程详情→编辑→课表的导航回归。

import XCTest

final class SwipeBackGestureUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].firstMatch
                          .waitForExistence(timeout: 10),
                      "Schedule pill 必须存在")
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - 路径 A: 通用设置 overlay — 顶栏返回

    func testSettingsFullScreenDismissByBackButton() throws {
        // 进入 Mine tab
        XCTAssertTrue(app.descendants(matching: .any)["pill_mine"].firstMatch
                          .waitForExistence(timeout: 5))
        app.switchToPillTab("mine")
        XCTAssertTrue(app.descendants(matching: .any)["mine_all_tables"]
                          .waitForExistence(timeout: 5))

        // 点 mine_general 入口打开设置 overlay
        let generalEntry = app.descendants(matching: .any)["mine_general"].firstMatch
        XCTAssertTrue(generalEntry.waitForExistence(timeout: 5),
                      "mine_general 入口必须存在")
        XCTAssertTrue(scrollEntryIntoView(generalEntry),
                      "The complete General entry must be visible above navigation")
        generalEntry.tap()

        // Debug dump: 列出所有可识别的 accessibilityIdentifier + 顶层按钮
        let backButton = app.buttons["topbar_back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "SettingsTopBar ⬅️ 按钮 (topbar_back) 必须存在"
                      + "\n若失败: 检查 fullScreenCover overlay 内容是否包了 SettingsTopBar")

        // 顶栏 ⬅️ 按钮 → 关闭弹层
        backButton.tap()

        XCTAssertTrue(app.descendants(matching: .any)["mine_general"].firstMatch.waitForExistence(timeout: 3),
                      "⬅️ 按钮必须能关闭 fullScreenCover overlay 并回到 Mine"
                      + "\n(返回 Mine 后 mine_general 入口应重新可见)")
    }

    // MARK: - 路径 B: About overlay — 左边缘向右拖动返回

    func testFullScreenOverlaySwipeDismiss() throws {
        // 进入 Mine → About
        XCTAssertTrue(app.descendants(matching: .any)["pill_mine"].firstMatch
                          .waitForExistence(timeout: 5))
        app.switchToPillTab("mine")
        XCTAssertTrue(app.descendants(matching: .any)["mine_all_tables"]
                          .waitForExistence(timeout: 5))

        let aboutEntry = app.descendants(matching: .any)["mine_about"].firstMatch
        XCTAssertTrue(aboutEntry.waitForExistence(timeout: 5), "About entry must exist")
        // ★ mine_about 在 Mine 页下部, 部分可见时 tap 落点可能被 pill 导航栏拦截
        //   (2026-11-06 CI 实证: 无滚动直接 tap → overlay 不弹; A1 截图用例先
        //   swipeUp 再 tap 则稳定过)。滚出 pill bar 拦截区再点, 与
        //   MineSettingsUITests.scrollUntil 同口径(底部 110pt 拦截带)。
        XCTAssertTrue(scrollEntryIntoView(aboutEntry))
        XCTAssertTrue(aboutEntry.isHittable)
        aboutEntry.tap()

        // 等待 overlay 顶栏 ⬅️ 按钮
        let backButton = app.buttons["topbar_back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "About overlay 顶栏 ⬅️ 按钮必须存在")

        // 从屏幕左边缘拖向右侧，触发应用的 overlay 返回手势
        let leftEdge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
        let midRight = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        leftEdge.press(forDuration: 0.05, thenDragTo: midRight, withVelocity: .fast, thenHoldForDuration: 0.3)

        // 期望: overlay 消失且回到 Mine; 只检查底层入口不足以证明 dismiss 成功。
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: backButton)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed,
                       "左滑手势必须关闭 fullScreenCover overlay 并移除 overlay 顶栏")
        XCTAssertTrue(app.descendants(matching: .any)["mine_about"].firstMatch.waitForExistence(timeout: 3),
                      "左滑手势关闭后必须回到 Mine，mine_about 入口应重新可见")
    }

    // MARK: - 路径 C: 课程详情 → 编辑 → 课表

    func testCourseEditorBackRestoresSchedule() throws {
        let pager = app.collectionViews["schedule_week_pager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 5))
        let scheduleCell = pager.buttons["gridcell_1"]
        XCTAssertTrue(scheduleCell.waitForExistence(timeout: 5))
        XCTAssertTrue(scheduleCell.isHittable)
        XCTAssertTrue(scheduleCell.label.contains("高等数学"))
        scheduleCell.tap()
        let edit = app.buttons["detail_edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["detail_close"].exists)
        edit.tap()
        XCTAssertTrue(app.staticTexts["Edit Course"].waitForExistence(timeout: 5))
        let name = app.textFields["field_Course Name *"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "高等数学")
        let backButton = app.buttons["topbar_back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        XCTAssertTrue(backButton.isHittable)
        backButton.tap()
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"),
                                               object: backButton)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertFalse(name.exists)
        XCTAssertFalse(app.buttons["detail_edit"].exists)
        XCTAssertTrue(pager.isHittable)
        XCTAssertTrue(scheduleCell.label.contains("高等数学"))
        scheduleCell.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "The original course must still open after returning")
        XCTAssertTrue(app.buttons["detail_close"].exists)
    }

    // MARK: - 兜底: About overlay 顶栏 ⬅️ 按钮存在性

    func testAboutOverlayBackButtonExists() throws {
        XCTAssertTrue(app.descendants(matching: .any)["pill_mine"].firstMatch
                          .waitForExistence(timeout: 5))
        app.switchToPillTab("mine")

        let aboutEntry = app.descendants(matching: .any)["mine_about"].firstMatch
        XCTAssertTrue(aboutEntry.waitForExistence(timeout: 5), "About entry must exist")
        // ★ 同 testFullScreenOverlaySwipeDismiss: 先滚出 pill bar 拦截区再 tap。
        XCTAssertTrue(scrollEntryIntoView(aboutEntry))
        XCTAssertTrue(aboutEntry.isHittable)
        aboutEntry.tap()

        let backButton = app.buttons["topbar_back"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "SettingsTopBar ⬅️ 按钮 (topbar_back) 必须存在")
    }

    // MARK: - 滚动助手(与 MineSettingsUITests.scrollUntil 同口径)

    /// 把元素滚到 pill 导航栏拦截带之上; 最多 6 次上滑。
    /// 与 MineSettingsUITests.scrollUntil 的 110pt 底部拦截带同一经验值。
    @discardableResult
    private func scrollEntryIntoView(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        let screenH = app.windows.firstMatch.frame.height
        let usableBottom = screenH - 110
        func visible() -> Bool {
            guard element.exists else { return false }
            let f = element.frame
            return f.minY >= 0 && f.maxY <= usableBottom
        }
        for _ in 0...maxSwipes {
            if visible() { return true }
            app.swipeUp()
        }
        return visible()
    }
}
