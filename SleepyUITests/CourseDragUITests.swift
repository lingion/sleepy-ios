import XCTest

final class CourseDragUITests: XCTestCase {
    private var app: XCUIApplication!
    private let mathName = "高等数学"

    // 日志确认同一 identifier 同时出现在 Other 和 CollectionView；限定真实 pager 类型。
    private var pager: XCUIElement { app.collectionViews["schedule_week_pager"] }
    private var originalCard: XCUIElement { pager.buttons["gridcell_1"] }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-SLEEPY_UI_TEST_SEED",
                               "-ui_style", "classic"]
        app.sleepyLaunch()
        XCTAssertTrue(pager.waitForExistence(timeout: 15))
        waitForWeek(1)
        waitForHittable(originalCard)
        assertNoUndoOrRedo()
    }

    override func tearDown() { app.terminate() }

    // UIKit's lift must complete before releasing the synthetic touch. A long
    // stationary hold can cancel lift; use a normal one-second pickup followed
    // by a destination hold, retaining every move/undo/persistence assertion.
    private func waitForWeek(_ week: Int) {
        let label = app.buttons["week_label"]
        if label.exists && label.label == "Week \(week)" { return }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "Week \(week)"), object: label)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed,
                       "Expected week \(week), actual label: \(label.label)")
    }

    private func waitForHittable(_ element: XCUIElement) {
        if element.exists && element.isHittable { return }
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        waitForHittable(button)
        XCTAssertTrue(button.exists, "\(identifier) 必须存在")
        XCTAssertTrue(button.isEnabled, "\(identifier) 应可用")
        var previousFrame = button.frame
        var stableSince = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard button.exists && button.isHittable else { return false }
            let frame = button.frame
            if frame != previousFrame { stableSince = Date() }
            previousFrame = frame
            return self.app.frame.contains(frame) && Date().timeIntervalSince(stableSince) >= 0.3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func assertNoUndoOrRedo(file: StaticString = #filePath, line: UInt = #line) {
        // 两份快照都没有时整个胶囊不渲染；先判断 exists，不能向不存在的按钮读 isEnabled。
        for identifier in ["undo_button", "redo_button"] {
            let button = app.buttons[identifier]
            XCTAssertFalse(button.exists && button.isEnabled,
                           "无改动时 \(identifier) 应不存在或禁用", file: file, line: line)
        }
    }

    private func goToWeek(_ week: Int, from current: Int) {
        waitForWeek(current)
        var selected = current
        while selected != week {
            let next = selected + (week > selected ? 1 : -1)
            tap(week > selected ? "week_next" : "week_prev")
            waitForWeek(next)
            selected = next
        }
        waitForHittable(pager.buttons["gridcell_2"])
    }

    // TabView 可保留邻页：只数当前可交互卡片，不把邻周缓存当作目标存在。
    private func visibleMathCards(movedOnly: Bool = false) -> [XCUIElement] {
        let cards = pager.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "gridcell_", mathName))
        return cards.allElementsBoundByIndex.filter {
            $0.isHittable && (!movedOnly || $0.identifier != "gridcell_1")
        }
    }

    private func assertMathCount(_ count: Int, movedOnly: Bool = false) {
        if visibleMathCards(movedOnly: movedOnly).count == count { return }
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            visibleMathCards(movedOnly: movedOnly).count == count
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed,
                       "本周高数卡数量应为 \(count)，movedOnly=\(movedOnly)")
    }

    private func movedCard() -> XCUIElement {
        assertMathCount(1, movedOnly: true)
        // 上面严格断言唯一性后取值，不使用 firstMatch 掩盖重复目标。
        return visibleMathCards(movedOnly: true)[0]
    }

    /// 同页英语=周二3–4、数据结构=周四3–4、体育=周五1–2、物理=周三5–6。
    /// 用真实卡片作坐标标尺，避免滚动/缩放改变全局 Y 后误判课程被移动。
    private func expectedCenter(day: Int, startNode: Int) -> CGPoint {
        let english = pager.buttons["gridcell_2"]
        let data = pager.buttons["gridcell_5"]
        waitForHittable(english)
        waitForHittable(data)
        let pitch = (data.frame.midX - english.frame.midX) / 2
        XCTAssertGreaterThan(pitch, 0)
        let rowReference: XCUIElement
        switch startNode {
        case 1: rowReference = pager.buttons["gridcell_4"]
        case 3: rowReference = english
        case 5: rowReference = pager.buttons["gridcell_3"]
        default: preconditionFailure("测试只使用 seed 中有独立标尺的两节课")
        }
        waitForHittable(rowReference)
        return CGPoint(x: english.frame.midX + CGFloat(day - 2) * pitch,
                       y: rowReference.frame.midY)
    }

    private func assertOccurrence(_ card: XCUIElement, week: Int, day: Int, startNode: Int,
                                  firstWeek: Int, lastWeek: Int) {
        waitForWeek(week)
        waitForHittable(card)
        let expected = expectedCenter(day: day, startNode: startNode)
        XCTAssertEqual(card.frame.midX, expected.x, accuracy: 3, "课程星期列错误")
        XCTAssertEqual(card.frame.midY, expected.y, accuracy: 3, "课程节次位置错误")
        card.tap()
        waitForHittable(app.buttons["detail_close"])
        XCTAssertFalse(app.buttons["course_occurrence_actions"].exists,
                       "普通点击详情只显示课程资料与编辑课程入口")
        XCTAssertTrue(app.staticTexts["张老师"].exists)
        XCTAssertTrue(app.staticTexts["教 1-101"].exists)
        XCTAssertTrue(app.staticTexts["Period \(startNode)-\(startNode + 1)"].exists)
        XCTAssertTrue(app.staticTexts[
            "\(startNode)-\(startNode + 1) (Week \(firstWeek)-\(lastWeek))"].exists,
                      "详情必须匹配精确节次及周范围，不能只验证源卡消失")
        tap("detail_close")
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["detail_close"])
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }

    private func coordinate(at point: CGPoint) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y))
    }

    private func restartWithoutSeed() {
        app.terminate()
        app.launchArguments.removeAll { $0 == "-SLEEPY_UI_TEST_SEED" }
        app.sleepyLaunch()
        XCTAssertTrue(pager.waitForExistence(timeout: 15))
        // selectedWeek 是会话态；seed 的 startDate 是本周一，冷启动回到实际第1周。
        waitForWeek(1)
        waitForHittable(pager.buttons["gridcell_2"])
    }

    private func confirmMove() {
        let confirmation = app.buttons["course_move_confirm"]
        waitForHittable(confirmation)
        tap("course_move_confirm")
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: confirmation)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
    }

    func testNativeDragWithinGridPersistsAndUndoRestores() throws {
        let source = originalCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // 周二5–6为空，避免进入既有英语3–4的冲突卡分支。
        let destination = coordinate(at: expectedCenter(day: 2, startNode: 5))
        source.press(forDuration: 1, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.75)
        confirmMove()
        let moved = movedCard()
        assertMathCount(1)
        XCTAssertFalse(originalCard.exists && originalCard.isHittable)
        assertOccurrence(moved, week: 1, day: 2, startNode: 5, firstWeek: 1, lastWeek: 1)

        goToWeek(2, from: 1)
        assertMathCount(1)
        assertOccurrence(originalCard, week: 2, day: 1, startNode: 1, firstWeek: 2, lastWeek: 20)
        goToWeek(1, from: 2)
        tap("undo_button")
        assertMathCount(0, movedOnly: true)
        assertMathCount(1)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        tap("redo_button")
        assertMathCount(1)
        assertOccurrence(movedCard(), week: 1, day: 2, startNode: 5, firstWeek: 1, lastWeek: 1)

        // undo/redo 快照只在内存中；先验证，再冷启动验证真实落库。
        restartWithoutSeed()
        assertMathCount(1)
        XCTAssertFalse(originalCard.exists && originalCard.isHittable)
        assertOccurrence(movedCard(), week: 1, day: 2, startNode: 5, firstWeek: 1, lastWeek: 1)
        goToWeek(2, from: 1)
        assertMathCount(1)
        assertOccurrence(originalCard, week: 2, day: 1, startNode: 1, firstWeek: 2, lastWeek: 20)
    }

    func testNativeDragAcceptsHoveredDestination() throws {
        let source = originalCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = coordinate(at: expectedCenter(day: 2, startNode: 5))
        source.press(forDuration: 1, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.75)
        confirmMove()
        assertMathCount(1)
        assertOccurrence(movedCard(), week: 1, day: 2, startNode: 5, firstWeek: 1, lastWeek: 1)
        XCTAssertFalse(originalCard.exists && originalCard.isHittable)
    }

    func testStationaryRightEdgeContinuesPagingAndMovingOccurrence() throws {
        XCTAssertEqual(app.collectionViews.matching(identifier: "schedule_week_pager").count, 1)
        let source = originalCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = coordinate(at: CGPoint(x: pager.frame.maxX - 9, y: originalCard.frame.midY))
        // The recorded 0.85s hold left 0.472s from the first native edge sample
        // to performDrop. Budget two 500ms pages plus that measured native tail;
        // retain the exact Week 3/drop/undo/restart assertions below.
        source.press(forDuration: 1, thenDragTo: target, withVelocity: .fast, thenHoldForDuration: 1.5)
        confirmMove()
        waitForWeek(3)
        // 第3周原有周一课必须保留，并额外出现从第1周移来的周日单次课。
        assertMathCount(2)
        assertOccurrence(movedCard(), week: 3, day: 7, startNode: 1, firstWeek: 3, lastWeek: 3)
        assertOccurrence(originalCard, week: 3, day: 1, startNode: 1, firstWeek: 2, lastWeek: 20)
        goToWeek(2, from: 3)
        assertMathCount(1)
        assertOccurrence(originalCard, week: 2, day: 1, startNode: 1, firstWeek: 2, lastWeek: 20)
        goToWeek(1, from: 2)
        assertMathCount(0)
        tap("undo_button")
        assertMathCount(1)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        goToWeek(3, from: 1)
        assertMathCount(0, movedOnly: true)
        assertMathCount(1)
        assertOccurrence(originalCard, week: 3, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        tap("redo_button")
        assertMathCount(2)
        assertOccurrence(movedCard(), week: 3, day: 7, startNode: 1, firstWeek: 3, lastWeek: 3)
        goToWeek(1, from: 3)
        assertMathCount(0)

        restartWithoutSeed()
        assertMathCount(0)
        goToWeek(3, from: 1)
        assertMathCount(2)
        assertOccurrence(movedCard(), week: 3, day: 7, startNode: 1, firstWeek: 3, lastWeek: 3)
        goToWeek(4, from: 3)
        assertMathCount(1)
        assertOccurrence(originalCard, week: 4, day: 1, startNode: 1, firstWeek: 2, lastWeek: 20)
    }

    func testStationaryLeftEdgeContinuesPagingAndMovingOnlySourceOccurrence() throws {
        goToWeek(3, from: 1)
        let source = originalCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // 左边缘在时间轴外，落到首个星期列的5–6节，避免与第1周已有高数重叠。
        let target = coordinate(at: CGPoint(x: pager.frame.minX + 9,
                                           y: expectedCenter(day: 1, startNode: 5).y))
        // The recorded 1.2s destination hold leaves only 0.887s after UIKit's lift
        // enters the drop session. Allow two full 500ms pages; Week 1 is the boundary.
        source.press(forDuration: 1, thenDragTo: target, withVelocity: .fast, thenHoldForDuration: 1.7)
        confirmMove()
        waitForWeek(1)
        assertMathCount(2)
        assertOccurrence(movedCard(), week: 1, day: 1, startNode: 5, firstWeek: 1, lastWeek: 1)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 2)
        goToWeek(2, from: 1)
        assertMathCount(1)
        assertOccurrence(originalCard, week: 2, day: 1, startNode: 1, firstWeek: 1, lastWeek: 2)
        goToWeek(3, from: 2)
        assertMathCount(0)
        goToWeek(4, from: 3)
        assertMathCount(1)
        // 中间周移走后右侧区间有新 ID；按唯一可见课程查，不能假定仍是 gridcell_1。
        assertOccurrence(visibleMathCards()[0], week: 4, day: 1, startNode: 1, firstWeek: 4, lastWeek: 20)
        tap("undo_button")
        assertMathCount(1)
        assertOccurrence(originalCard, week: 4, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        goToWeek(3, from: 4)
        assertMathCount(1)
        assertOccurrence(originalCard, week: 3, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        goToWeek(1, from: 3)
        assertMathCount(1)
        assertMathCount(0, movedOnly: true)
        tap("redo_button")
        assertMathCount(2)
        assertOccurrence(movedCard(), week: 1, day: 1, startNode: 5, firstWeek: 1, lastWeek: 1)

        restartWithoutSeed()
        assertMathCount(2)
        assertOccurrence(movedCard(), week: 1, day: 1, startNode: 5, firstWeek: 1, lastWeek: 1)
        goToWeek(2, from: 1)
        assertMathCount(1)
        assertOccurrence(originalCard, week: 2, day: 1, startNode: 1, firstWeek: 1, lastWeek: 2)
        goToWeek(3, from: 2)
        assertMathCount(0)
        goToWeek(4, from: 3)
        assertMathCount(1)
        assertOccurrence(visibleMathCards()[0], week: 4, day: 1, startNode: 1, firstWeek: 4, lastWeek: 20)
    }

    func testMultiPeriodCenterLiftAndDropInPlaceDoesNotMoveOrCreateUndo() {
        let original = originalCard.frame
        let center = originalCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 1, thenDragTo: center, withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertTrue(app.buttons["course_float_edit"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["course_move_confirm"].exists)
        coordinate(at: CGPoint(x: pager.frame.maxX - 20, y: pager.frame.maxY - 20)).tap()
        assertMathCount(1)
        assertMathCount(0, movedOnly: true)
        XCTAssertEqual(originalCard.frame.minX, original.minX, accuracy: 3)
        XCTAssertEqual(originalCard.frame.minY, original.minY, accuracy: 3)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        assertNoUndoOrRedo()
    }

    func testMultiPeriodCenterHorizontalDragPreservesPeriods() throws {
        let source = originalCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = expectedCenter(day: 2, startNode: 1)
        // 明确纯横移，Y 固定为源卡中心；不能靠向上补偿掩盖抓取偏移缺陷。
        source.press(forDuration: 1, thenDragTo: coordinate(at:
            CGPoint(x: target.x, y: originalCard.frame.midY)),
            withVelocity: .slow, thenHoldForDuration: 0.75)
        confirmMove()
        let moved = movedCard()
        assertMathCount(1)
        XCTAssertFalse(originalCard.exists && originalCard.isHittable)
        assertOccurrence(moved, week: 1, day: 2, startNode: 1, firstWeek: 1, lastWeek: 1)
        tap("undo_button")
        assertMathCount(0, movedOnly: true)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        tap("redo_button")
        assertOccurrence(movedCard(), week: 1, day: 2, startNode: 1, firstWeek: 1, lastWeek: 1)
    }

    func testDropCancellationPreservesOriginalAndUndoAcrossRestart() {
        let source = originalCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = coordinate(at: expectedCenter(day: 2, startNode: 5))
        source.press(forDuration: 1, thenDragTo: destination, withVelocity: .slow, thenHoldForDuration: 0.75)
        capture("course-drop-before-confirmation")
        waitForHittable(app.buttons["course_move_cancel"])
        XCTAssertTrue(app.staticTexts["Move this class?"].exists)
        capture("course-move-confirmation")
        tap("course_move_cancel")
        assertMathCount(1)
        assertMathCount(0, movedOnly: true)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        assertNoUndoOrRedo()
        restartWithoutSeed()
        assertMathCount(1)
        assertMathCount(0, movedOnly: true)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        assertNoUndoOrRedo()
    }

    func testFloatingTopAndBottomHandlesResizeOnlyAfterConfirmation() {
        // Move this occurrence to periods 3–4 first so both edges can be stretched.
        let source = originalCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        source.press(forDuration: 1, thenDragTo: coordinate(at: expectedCenter(day: 1, startNode: 3)),
            withVelocity: .slow, thenHoldForDuration: 0.75)
        confirmMove()
        var card = movedCard()
        let movedFrame = card.frame
        let periodHeight = movedFrame.height / 2
        card.press(forDuration: 1)
        let top = app.descendants(matching: .any)["course_float_top"]
        XCTAssertTrue(top.waitForExistence(timeout: 5))
        capture("course-float-blur-and-handles")
        let topStart = top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        topStart.press(forDuration: 0.1, thenDragTo: topStart.withOffset(CGVector(dx: 0, dy: -periodHeight)),
            withVelocity: .slow, thenHoldForDuration: 0.1)
        waitForHittable(app.buttons["course_move_cancel"])
        XCTAssertTrue(app.staticTexts["Change this class's length?"].exists)
        tap("course_move_cancel")
        card = movedCard()
        XCTAssertEqual(card.frame.minY, movedFrame.minY, accuracy: 3)
        XCTAssertEqual(card.frame.height, movedFrame.height, accuracy: 3)

        card.press(forDuration: 1)
        let bottom = app.descendants(matching: .any)["course_float_bottom"]
        XCTAssertTrue(bottom.waitForExistence(timeout: 5))
        let bottomStart = bottom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        bottomStart.press(forDuration: 0.1,
            thenDragTo: bottomStart.withOffset(CGVector(dx: 0, dy: periodHeight)),
            withVelocity: .slow, thenHoldForDuration: 0.1)
        confirmMove()
        card = movedCard()
        XCTAssertEqual(card.frame.minY, movedFrame.minY, accuracy: 3)
        XCTAssertGreaterThan(card.frame.height, movedFrame.height + periodHeight / 2)
        card.tap()
        waitForHittable(app.buttons["detail_close"])
        XCTAssertTrue(app.staticTexts["Period 3-5"].exists)
        XCTAssertFalse(app.buttons["course_occurrence_actions"].exists)
        tap("detail_close")
        tap("undo_button")
        card = movedCard()
        XCTAssertEqual(card.frame.height, movedFrame.height, accuracy: 3)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDropOutsideGridLeavesOriginalAndWeekUnchanged() {
        let original = originalCard.frame
        let source = originalCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let target = app.buttons["week_label"].coordinate(withNormalizedOffset: .zero)
        source.press(forDuration: 1, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.75)
        assertMathCount(1)
        assertMathCount(0, movedOnly: true)
        // 保留屏幕坐标断言：不能将没有抬起课程、实际触发滚动的手势当作取消成功。
        XCTAssertEqual(originalCard.frame.minX, original.minX, accuracy: 3)
        XCTAssertEqual(originalCard.frame.minY, original.minY, accuracy: 3)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        assertNoUndoOrRedo()
        restartWithoutSeed()
        assertMathCount(1)
        assertMathCount(0, movedOnly: true)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        assertNoUndoOrRedo()
    }

    func testCreateCourseOverlayLongPressDoesNotMoveCoveredCourse() {
        let original = originalCard.frame
        let source = CGPoint(x: original.midX, y: original.midY)
        let target = CGPoint(x: expectedCenter(day: 2, startNode: 1).x, y: original.midY)

        func attachScreenshot(_ name: String) {
            XCTContext.runActivity(named: name) { activity in
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = name
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }

        attachScreenshot("Schedule before opening Create Course")
        // The schedule toolbar opens AddCourseScreen directly, preserving the
        // covered schedule tree and its previously measured course geometry.
        tap("topbar_add")
        let editor = app.staticTexts["Create Course"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        var previousEditorFrame = editor.frame
        var stableSince = Date()
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard editor.exists && editor.isHittable && self.app.buttons["topbar_back"].isHittable else {
                stableSince = Date()
                return false
            }
            let frame = editor.frame
            if frame != previousEditorFrame { stableSince = Date() }
            previousEditorFrame = frame
            return Date().timeIntervalSince(stableSince) >= 0.3
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        attachScreenshot("Create Course before covered-course gesture")

        // Send one real touch at the old course center, then move horizontally
        // to the old adjacent column. The root recognizer must ignore overlay touches.
        coordinate(at: source).press(forDuration: 1, thenDragTo: coordinate(at: target),
            withVelocity: .slow, thenHoldForDuration: 0.75)
        XCTAssertTrue(editor.exists && editor.isHittable, "The gesture must leave Create Course open")
        attachScreenshot("Create Course after covered-course gesture")
        tap("topbar_back")
        waitForHittable(pager)
        waitForWeek(1)
        attachScreenshot("Schedule after closing Create Course")

        assertMathCount(1)
        assertMathCount(0, movedOnly: true)
        waitForHittable(originalCard)
        XCTAssertEqual(originalCard.frame.minX, original.minX, accuracy: 3)
        XCTAssertEqual(originalCard.frame.minY, original.minY, accuracy: 3)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        assertNoUndoOrRedo()

        restartWithoutSeed()
        assertMathCount(1)
        assertMathCount(0, movedOnly: true)
        assertOccurrence(originalCard, week: 1, day: 1, startNode: 1, firstWeek: 1, lastWeek: 20)
        assertNoUndoOrRedo()
    }
}
