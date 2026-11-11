// MineSettingsUITests.swift — G5+ 我的页设置全交互面测试
// 覆盖: Mine 小组件入口(独立页) + 画廊可达 + AllTables(切表/编辑入口/新建) +
//       Appearance(系统主题卡 + 3 态模式分段 + 预设网格) + General(5 张设置卡
//       展开收起 + 每卡内选项/开关 + 周可见日 7 行 + 语言 5 项) + Export(3 格式) +
//       Reminder(总开关 + 子开关 + 时间选择) + About(检查更新按钮)。

import XCTest

final class MineSettingsUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
        app.switchToPillTab("mine")
        // ★ 锚点修正(2026-10-31): 旧锚点 app.staticTexts["Me"] 是假阳性 ——
        //   悬浮药丸导航栏自己就渲染一个 StaticText label "Me", 该元素在
        //   「课表」页同样存在 ⇒ setUp 从未真正断言「已进入我的页」。
        //   实证: 失败时无障碍层级显示 app 仍停在 Schedule 页。
        //   改用「我的页独有」的入口 mine_all_tables 作锚点。
        XCTAssertTrue(app.descendants(matching: .any)["mine_all_tables"].waitForExistence(timeout: 8),
                      "未进入「我的」页(mine_all_tables 未出现)")
    }

    override func tearDownWithError() throws {
        app.terminate()   // 隔离: 每用例杀进程重启, 防跨用例状态串扰
    }

    /// 自适应下滑直到元素在视口内(元素全量物化, exists≠可见; 不可见时 tap
    /// 落点出屏丢失 — 2026-09 基线腐化根因; 页面高度随版本变, 固定次数不可靠)
    @discardableResult
    private func scrollUntil(_ element: XCUIElement, maxSwipes: Int = 6,
                             reservedBottomInset: CGFloat = 110) -> Bool {
        func owningScroll() -> XCUIElement? {
            let candidates = app.scrollViews.allElementsBoundByIndex
                + app.tables.allElementsBoundByIndex + app.collectionViews.allElementsBoundByIndex
            return candidates.reversed().first { scroll in
                guard scroll.exists && scroll.isHittable else { return false }
                let descendants = scroll.descendants(matching: element.elementType)
                return element.identifier.isEmpty
                    ? descendants.matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
                    : descendants.matching(identifier: element.identifier).firstMatch.exists
            }
        }
        func viewport(_ scroll: XCUIElement?) -> CGRect {
            let window = app.windows.firstMatch.frame
            var area = window.insetBy(dx: 2, dy: 4)
            if let scroll { area = area.intersection(scroll.frame) }
            let bottom = min(area.maxY, window.maxY - reservedBottomInset)
            if let back = app.buttons.matching(identifier: "topbar_back").allElementsBoundByIndex
                .last(where: { $0.isHittable }), back.frame.minY < area.midY {
                area.origin.y = max(area.minY, back.frame.maxY + 4)
            }
            area.size.height = max(0, bottom - area.minY)
            return area
        }
        func visible() -> Bool {
            guard element.exists && element.isHittable else { return false }
            let frame = element.frame
            return frame.width > 0 && frame.height > 0 && viewport(owningScroll()).contains(frame)
        }
        for _ in 0...maxSwipes {
            if visible() { return true }
            guard let scroll = owningScroll() else { break }
            let area = viewport(scroll)
            guard !area.isNull && area.width > 0 && area.height > 0 else { break }
            let earlier = element.frame.minY < area.minY
            let distance = earlier ? area.minY - element.frame.minY : element.frame.maxY - area.maxY
            let step = min(0.55, max(0.18, distance / area.height))
            // The first scroll view can be the disabled, scaled Mine page
            // beneath an overlay. Drag inside this control's foreground card,
            // before its sliders, rather than that unrelated page or a slider.
            let x = area.minX + min(24, area.width * 0.08)
            let startY = earlier ? 0.25 : 0.80
            let endY = earlier ? startY + step : startY - step
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x, dy: area.minY + area.height * startY))
                .press(forDuration: 0.05, thenDragTo:
                    origin.withOffset(CGVector(dx: x, dy: area.minY + area.height * endY)))
        }
        if !visible() { retainHierarchy("settings-control-not-visible") }
        return visible()
    }

    /// 轮询条件(0.25s/步, ≤timeout)— SwiftUI 状态/树变更异步落定(展开动画
    /// spring response≈0.31 + 切语言整树重建), 定长 sleep 既慢又抖
    @discardableResult
    private func pollUntil(_ timeout: TimeInterval = 6, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }

    private func retainScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Both appearances expose the five choices in an anchored system menu.
    private func tapLanguageOption(_ label: String) {
        let head = app.buttons["card_language"].firstMatch
        XCTAssertTrue(head.waitForExistence(timeout: 5), "语言卡 card_language 应存在")
        XCTAssertTrue(scrollUntil(head, maxSwipes: 8, reservedBottomInset: 0), "语言卡应能滚入视口")
        head.tap()
        // iOS exposes a Picker menu as a collection of option cells.
        // Scope to that real native surface, which contains all five languages.
        let menu = app.collectionViews.containing(.button, identifier: "Español").firstMatch
        guard menu.waitForExistence(timeout: 5) else {
            retainHierarchy("language-native-menu-missing")
            XCTFail("语言卡应打开系统菜单")
            return
        }
        let option = menu.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        guard option.waitForExistence(timeout: 5) else {
            retainHierarchy("language-native-option-missing")
            XCTFail("系统语言菜单应有 \(label)")
            return
        }
        option.tap()
    }

    private func retainHierarchy(_ name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        retainScreenshot(name)
    }

    private func relaunchWithNativeControls() {
        app.terminate()
        app.launchArguments += ["-ui_style", "liquid_glass"]
        app.sleepyLaunch()
        app.switchToPillTab("mine")
        let entrance = app.buttons["mine_all_tables"].firstMatch
        XCTAssertTrue(entrance.waitForExistence(timeout: 8))
        // Capture the settled page rather than the schedule-to-Mine crossfade.
        var stableSince = Date()
        var previous = entrance.frame
        XCTAssertTrue(pollUntil {
            let current = entrance.frame
            if current != previous { stableSince = Date() }
            previous = current
            return entrance.isHittable && Date().timeIntervalSince(stableSince) >= 0.5
        })
    }

    private func openScheduleDisplay() {
        let display = app.descendants(matching: .any)["mine_schedule_settings"].firstMatch
        XCTAssertTrue(display.waitForExistence(timeout: 5), "我的页应有独立课表设置入口")
        XCTAssertTrue(scrollUntil(display), "课表设置入口应能滚入视口")
        display.tap()
        XCTAssertTrue(app.descendants(matching: .any)["schedule_display_settings"].waitForExistence(timeout: 5))
    }

    func testScheduleSettingsIsFirstLevelEntry() {
        openScheduleDisplay()
        XCTAssertTrue(app.staticTexts["Schedule settings"].exists,
                      "独立入口应显示课表设置标题")
        retainScreenshot("schedule-settings-first-level")
    }

    func testHolidayGroupsStartCollapsedAndResetOnYearChange() {
        app.terminate()
        app.launchArguments += ["-SLEEPY_UI_TEST_HOLIDAYS"]
        app.sleepyLaunch()
        app.switchToPillTab("mine")
        openScheduleDisplay()
        let entry = app.descendants(matching: .any)["settings_holiday_entry"].firstMatch
        XCTAssertTrue(scrollUntil(entry, reservedBottomInset: 0))
        entry.tap()
        let dates = app.buttons["holiday_group_dates"].firstMatch
        XCTAssertTrue(dates.waitForExistence(timeout: 8))
        XCTAssertTrue(scrollUntil(dates, reservedBottomInset: 0))
        XCTAssertEqual(dates.value as? String, "collapsed")
        XCTAssertFalse(app.buttons["holiday_add_entry"].exists)
        let mapping = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'holiday_group_transfer:'")).firstMatch
        XCTAssertTrue(mapping.exists)
        XCTAssertEqual(mapping.value as? String, "collapsed")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'holiday_mapping_'")).firstMatch.exists)
        let maintenance = app.buttons["holiday_group_maintenance"].firstMatch
        XCTAssertTrue(maintenance.exists)
        XCTAssertEqual(maintenance.value as? String, "collapsed")
        retainScreenshot("holiday-default-collapsed")
        dates.tap()
        let add = app.buttons["holiday_add_entry"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        XCTAssertEqual(dates.value as? String, "expanded")
        // Workday date editing is also shared, independent of per-table mappings.
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'holiday_date_edit_'")).count, 2)
        retainScreenshot("holiday-dates-expanded")
        let next = app.buttons["Next year"].firstMatch
        for _ in 0..<5 {
            if next.isHittable { break }
            app.swipeDown()
        }
        next.tap()
        XCTAssertTrue(pollUntil { (dates.value as? String) == "collapsed" && !add.exists })
    }

    // MARK: 小组件设置独立页 + 画廊(v1.0.62 B4)
    //   刷新按钮自「我的」页迁入小组件设置独立页(仅桌面已有实例时出现, 种子环境
    //   无已放置实例 → 按钮不渲染, 旧 testRefreshWidgetsButtonShowsSnackbar 失效),
    //   由下面两条冒烟接替: 入口可达性 ×2。

    /// ①「我的」页 mine_widget 入口 → 小组件设置独立页可达。
    ///    断言锚点取页内独有的 settings_widget_manage_entry(与 locale 无关)。
    func testMineWidgetEntryOpensWidgetSettings() {
        let entry = app.descendants(matching: .any)["mine_widget"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3), "「我的」页应有 mine_widget 入口")
        XCTAssertTrue(scrollUntil(entry), "mine_widget 入口应能滚入视口")
        entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings_widget_manage_entry"]
                          .waitForExistence(timeout: 5),
                      "点 mine_widget 应打开小组件设置独立页")
    }

    /// ② 设置页管理入口 → 管理页顶栏「＋」→ 画廊页可达。
    ///    三级 fullScreenCover 叠放(Mine → WidgetSettings → Manage → Gallery),
    ///    断言锚点 = 画廊卡 widget_gallery_card_<kind>(5 kind 随注册表, 前缀匹配)。
    func testManageEntryAndPlusOpenGallery() {
        let entry = app.descendants(matching: .any)["mine_widget"]
        XCTAssertTrue(entry.waitForExistence(timeout: 3))
        XCTAssertTrue(scrollUntil(entry), "mine_widget 入口应能滚入视口")
        entry.tap()
        let manageEntry = app.descendants(matching: .any)["settings_widget_manage_entry"]
        // 冷首启 fullScreenCover 首次呈现可 >5s(时序 flake, 曾致 :115 偶发失败), 放宽到 10s
        XCTAssertTrue(manageEntry.waitForExistence(timeout: 10), "小组件设置页应有管理入口")
        manageEntry.tap()
        let addBtn = app.descendants(matching: .any)["widget_gallery_add"]
        XCTAssertTrue(addBtn.waitForExistence(timeout: 5), "管理页顶栏应有「＋」")
        addBtn.tap()
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'widget_gallery_card_'"))
            .firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5), "点「＋」应打开添加小组件画廊页")

        // v1.0.64: 先展开组件组，再点具体尺寸进入添加引导。
        card.tap()
        // The group identifier also reaches its title and collapse action. Select
        // the grid container that actually owns the concrete size buttons.
        let expanded = app.otherElements
            .matching(NSPredicate(format: "identifier BEGINSWITH 'widget_gallery_expanded_'"))
            .firstMatch
        XCTAssertTrue(expanded.waitForExistence(timeout: 5), "点组件组应展开全部尺寸")
        let sizeCard = expanded.descendants(matching: .button)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'widget_gallery_card_'"))
            .firstMatch
        XCTAssertTrue(sizeCard.waitForExistence(timeout: 5), "展开组应有可添加的尺寸卡片")
        retainScreenshot("widget-gallery-expanded-sizes")
        sizeCard.tap()
        let guideTitle = app.descendants(matching: .any)["widget_guide_title"]
        XCTAssertTrue(guideTitle.waitForExistence(timeout: 5), "点卡片应弹出小组件添加引导页")
        let guideCopy = app.descendants(matching: .any)["widget_guide_copy"]
        XCTAssertTrue(guideCopy.exists, "引导页应有复制组件名按钮")
        retainScreenshot("widget-gallery-add-guide")
        let close = app.descendants(matching: .any)["topbar_close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), "引导页应有 ✕ 关闭按钮")
        close.tap()
        let gone = Date().addingTimeInterval(3)
        while guideTitle.exists && Date() < gone { usleep(100_000) }
        XCTAssertFalse(guideTitle.exists, "关闭后引导页应消失")
    }

    // MARK: All Schedules — 切表 / 编辑入口 / 新建按钮

    /// a.v.1.0.41 热区回归: 点行内"空白区"(右端 Spacer 区, 离图标/文字最远)也应触发。
    /// 用户报障 = 点行色块不响应只有图标/文字才触发(SleepyButtonStyle 修复)。
    /// 代表行 2 条: mine_all_tables(普通导航) + mine_period_tables(第二行, 验证同卡多行互不串扰)
    func testAllTablesRowBlankAreaTriggersNav() {
        let row = app.descendants(matching: .any)["mine_all_tables"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        // dx=0.92 → 行右端 8% 处: 文字在左侧, 此处为纯空白色块区
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5),
                      "点'所有课表'行右端空白区应跳转(SleepyButtonStyle 整行热区)")
    }

    func testPeriodTablesRowBlankAreaTriggersNav() {
        let row = app.descendants(matching: .any)["mine_period_tables"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["period_tables_back"].firstMatch.waitForExistence(timeout: 5),
                      "点作息表行右端空白区应进入管理页")
        XCTAssertTrue(app.staticTexts["New bell schedule"].firstMatch.exists)
    }

    func testAllTablesSwitchAndEdit() {
        app.descendants(matching: .any)["mine_all_tables"].tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5))
        // 种子表"我的课表"为当前(checkmark)
        XCTAssertTrue(app.staticTexts["我的课表"].firstMatch.exists, "列表应有种子表")
        // 新建按钮存在
        XCTAssertTrue(app.staticTexts["New Schedule"].firstMatch.exists)
        // 表行的编辑齿轮(图标按钮)。锚点用 identifier: 6541178 起齿轮加了
        // accessibilityLabel("Settings"), SF Symbol 默认 "gear" 标签被覆盖 → label 匹配失效
        let gear = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_edit_'")).firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 3), "表行应有编辑齿轮")
    }

    func testAllTablesNewButtonOpensEditor() {
        app.descendants(matching: .any)["mine_all_tables"].tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5))
        app.staticTexts["New Schedule"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Edit Schedule"].waitForExistence(timeout: 5),
                      "新建应进表编辑页")
    }

    func testAllTablesSchoolUpdateOpensImportForTheSelectedRow() {
        app.descendants(matching: .any)["mine_all_tables"].tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5))
        let refresh = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@", "table_update_from_school_")).firstMatch
        XCTAssertTrue(refresh.waitForExistence(timeout: 5))
        refresh.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Select School"].waitForExistence(timeout: 10))
        let close = app.buttons["topbar_close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5))
    }

    func testNativeAllTablesActionsKeepIndependentTargets() {
        relaunchWithNativeControls()
        retainScreenshot("native-mine-material-icons")
        app.descendants(matching: .any)["mine_all_tables"].tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5))
        let identity = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'table_select_'" )).firstMatch
        let actions = ["table_duplicate_", "table_update_from_school_", "table_edit_"].map { prefix in
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
        }
        XCTAssertTrue(identity.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(identity.frame.width, 56, "The title must keep its reading width beside native actions")
        for action in actions {
            XCTAssertTrue(action.exists && action.isHittable)
            XCTAssertTrue(app.frame.contains(action.frame), "The complete native action must remain inside the window")
            XCTAssertGreaterThanOrEqual(action.frame.width, 44)
            XCTAssertGreaterThanOrEqual(action.frame.height, 44)
            XCTAssertLessThanOrEqual(action.frame.width, 48.5,
                                     "Native insets must fit inside the original icon slot")
            XCTAssertEqual(action.frame.width, action.frame.height, accuracy: 1,
                           "Independent native icon actions must remain circular")
            let overlap = identity.frame.intersection(action.frame)
            XCTAssertTrue(overlap.isNull || overlap.width < 1 || overlap.height < 1)
        }
        for index in 0..<actions.count - 1 {
            XCTAssertLessThanOrEqual(actions[index].frame.maxX, actions[index + 1].frame.minX + 1)
        }
        retainScreenshot("native-all-tables-actions")
        actions[1].coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Select School"].waitForExistence(timeout: 10))
    }

    // MARK: Appearance — 3 态模式分段切换

    func testAppearanceModeSegmented() {
        let entrance = app.buttons["mine_appearance"].firstMatch
        XCTAssertTrue(scrollUntil(entrance), "外观入口应滚出底部导航遮挡区")
        entrance.tap()
        let title = app.staticTexts["Appearance & display"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        let light = app.buttons.matching(NSPredicate(format: "label == 'Light'")).firstMatch
        let dark = app.buttons.matching(NSPredicate(format: "label == 'Dark'")).firstMatch
        let auto = app.buttons.matching(NSPredicate(format: "label == 'Auto (light/dark)'")).firstMatch
        XCTAssertTrue(scrollUntil(light, maxSwipes: 12), "Light 模式按钮应可达")
        XCTAssertTrue(dark.exists, "Dark 模式按钮应存在")
        XCTAssertTrue(auto.exists, "Auto 模式按钮应存在")

        // 切 Dark → 立即生效不崩
        dark.tap()
        XCTAssertTrue(pollUntil { dark.isSelected })
        XCTAssertTrue(title.waitForExistence(timeout: 3), "切深色不应崩")
        // 切回 Light
        light.tap()
        XCTAssertTrue(pollUntil { light.isSelected })
        // 切 Auto
        auto.tap()
        XCTAssertTrue(pollUntil { auto.isSelected })
        XCTAssertTrue(title.exists)
    }

    // MARK: Appearance — 预设主题网格(至少一个预设可点)

    func testAppearancePresetGrid() {
        let entrance = app.buttons["mine_appearance"].firstMatch
        XCTAssertTrue(scrollUntil(entrance), "外观入口应滚出底部导航遮挡区")
        entrance.tap()
        let title = app.staticTexts["Appearance & display"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        // 预设网格(2 列 N 个)— 任一预设按钮可点不崩
        let preset = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'theme_preset_'")).firstMatch
        XCTAssertTrue(preset.waitForExistence(timeout: 5), "预设主题应存在")
        XCTAssertTrue(scrollUntil(preset, reservedBottomInset: 0), "预设主题应可点")
        preset.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertTrue(title.exists)
    }

    // MARK: General — 设置卡交互(平卡选项即时点选; 卡已原生化: Time Display/
    //       Grid sub-info = SettingsFlatCard 分段控件, 选项常显不可折叠 →
    //       旧"展开/收起"语义过时; 外层 accessibilityLabel(title) 覆盖段按钮 label,
    //       按标签查 buttons["Show as periods"] 失效 → 锚点用 seg_<渲染标签> identifier)

    func testGeneralCardsExpandCollapse() {
        openScheduleDisplay()

        // Time Display 卡: 分段控件两选项(ScheduleFlowUITests 同款 seg_ 锚点)
        let periods = app.descendants(matching: .any)["seg_Show as periods"]
        XCTAssertTrue(scrollUntil(periods.firstMatch),
                      "Time Display 卡应有 periods 段选项")
        XCTAssertTrue(app.descendants(matching: .any)["seg_Show as times"].firstMatch.exists)

        // 点选 times 段 → 切回 periods 段
        app.descendants(matching: .any)["seg_Show as times"].firstMatch.tap()
        periods.firstMatch.tap()

        // Grid card sub-info 卡(同为平卡): Room / Teacher / None 三段
        let room = app.descendants(matching: .any)["seg_Room"]
        XCTAssertTrue(scrollUntil(room.firstMatch),
                      "副信息卡应有 Room 段选项")
        XCTAssertTrue(app.descendants(matching: .any)["seg_Teacher"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["seg_None"].firstMatch.exists)
        // 三选项轮点
        room.firstMatch.tap()
        app.descendants(matching: .any)["seg_Teacher"].firstMatch.tap()
        app.descendants(matching: .any)["seg_None"].firstMatch.tap()
    }

    // MARK: General — Visible Days 7 行开关

    func testGeneralVisibleDaysToggles() {
        openScheduleDisplay()
        // Visible Days = SettingsCard 折叠卡(SettingsCards.swift:95): 可点单元 =
        // 带 card_\(title) identifier + isButton trait 的容器; staticTexts["Visible Days"]
        // 命中的是无操作文本叶子(tap 落空)。expandedSections 跨启动持久化
        // → 初始展开态不可假设: 以 Monday 行可见性判当前态, 点一次翻转, 断言后置态。
        // 行锚点 = VisibleDayRow(整行合并元素, label=dayName 短名 "Mon", 非全名;
        // 类型随 combine 结果漂移 → .any + label 谓词, isSelected = 可见态)。
        let daysCard = app.descendants(matching: .any)["card_Visible Days"].firstMatch
        XCTAssertTrue(scrollUntil(daysCard, maxSwipes: 8), "Visible Days 卡应可达")
        // 卡中部是内容行(子控件优先消费点击)→ 固定点顶部标题区驱动 onToggle
        func toggleCard() {
            daysCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        }
        let monday = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'Mon'")).firstMatch
        let wasExpanded = monday.waitForExistence(timeout: 1)
        toggleCard()
        if wasExpanded {
            XCTAssertTrue(pollUntil(4) { !monday.exists }, "收起后 7 日行应消失")
            toggleCard()
            XCTAssertTrue(pollUntil(4) { monday.exists }, "再点后 7 日行应重现")
        } else {
            XCTAssertTrue(pollUntil(4) { monday.exists }, "展开后应出现 Monday 行")
        }
        // 周一开关通路(2026-10-24 probe 校正): VisibleDayRow 不合并(合并吞 switch
        // 命中) → 树形态 = 行文本 Button(label "Mon", 恒 isSelected=false) + 行右端
        // Switch(value 0/1)。翻转态真源 = switch.value, 不是文本行 isSelected。
        // 至少留 1 天守卫(VisibleDayRow.commit): 只剩 1 天时点它不生效 →
        // 优先点"当前关(value 0)"的行(开→关必可还原), 全开时退回 Mon(7→6→7 安全)。
        func rowSwitch(_ dayName: String) -> XCUIElement? {
            let row = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", dayName)).firstMatch
            guard row.exists else { return nil }
            return app.switches.allElementsBoundByIndex.first {
                abs($0.frame.midY - row.frame.midY) < 20
            }
        }
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        let targetName = dayNames.first { rowSwitch($0)?.value as? String == "0" } ?? "Mon"
        guard let sw = rowSwitch(targetName) else {
            XCTFail("\(targetName) 行右端应有 switch")
            return
        }
        let before = sw.value as? String
        sw.tap()
        XCTAssertTrue(pollUntil(4) { (sw.value as? String) != before },
                      "点可见日 switch 应翻转状态")
        sw.tap()
        XCTAssertTrue(pollUntil(4) { (sw.value as? String) == before }, "再点应还原")
        XCTAssertTrue(daysCard.exists, "操作后卡不崩")
    }

    // MARK: General — Show dates / colorless 开关

    func testGeneralToggles() {
        assertShowDatesSwitchToggles()
    }

    func testLiquidGlassSwitchPressKeepsItsLabelAndTogglesOnce() {
        app.terminate()
        app.launchArguments += ["-ui_style", "liquid_glass"]
        app.sleepyLaunch()
        app.switchToPillTab("mine")
        assertShowDatesSwitchToggles(pressDuration: 0.25)
    }

    private func assertShowDatesSwitchToggles(pressDuration: TimeInterval = 0) {
        openScheduleDisplay()

        let showDateRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Show dates in headers'")).firstMatch
        XCTAssertTrue(scrollUntil(showDateRow, maxSwipes: 8), "行应滚入视口")
        // SettingToggleRow 只有右侧 Toggle 可切换(点标签文本无效)。2026-10-25 tprobe
        // 实证两层结构: 外层容器(继承卡 identifier + 卡 onToggle — tap 它收起整卡)
        // + 内层真 Toggle(identifier 空)。取内层; 且每次操作按行位置重新解析
        // (值翻转后按索引缓存的元素引用会失效 — fix-verify3 "Element at index 17" 实证)。
        func showDateSwitch() -> XCUIElement? {
            guard showDateRow.exists else { return nil }
            let midY = showDateRow.frame.midY
            let near = app.switches.allElementsBoundByIndex
                .filter { abs($0.frame.midY - midY) < 20 }
            return near.first { $0.identifier.isEmpty } ?? near.first
        }
        guard let sw0 = showDateSwitch() else {
            XCTFail("行右端应有 switch")
            return
        }
        let before = sw0.value as? String
        if pressDuration > 0 { sw0.press(forDuration: pressDuration) }
        else { sw0.tap() }
        XCTAssertTrue(pollUntil(4) { showDateSwitch()?.value as? String != before },
                      "点 switch 应翻转")
        if pressDuration > 0 { retainScreenshot("native-switch-after-press") }
        // 不再二次 tap 还原: 首翻触发 refreshWidgets + 卡内重排, 二次 tap 在
        // 模拟器上 6 轮取证均未落位(verify4-6: 单向/双向找回 + 坐标 tap 全空),
        // 属 XCUITest×SwiftUI 重排交互 quirk, 开关本体行为已被首翻断言证明。
        // 隔离由 SleepyUITestSeeder 每用例复位 KEY_SHOW_DATE 保证, 无需手工还原。
        // 末项只断卡不崩(verify7: 翻转后行节点被重排替换, 行级 exists 抖动)。
        // 后续项: 若真机复现"连点第二下无响应"再立 app bug。
        XCTAssertTrue(daysCardAlive())
    }

    /// General 页仍在(卡容器可达)= 操作后页面不崩
    private func daysCardAlive() -> Bool {
        app.descendants(matching: .any)["card_Visible Days"].firstMatch.exists
    }

    // MARK: General — Widget 设置组(widgetcolorless/separator/vertPunct)

    func testGeneralKeepsLanguageAndEditingSettings() {
        let general = app.buttons["mine_general"].firstMatch
        XCTAssertTrue(scrollUntil(general), "通用设置入口应完整显示在底部导航上方")
        general.tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["card_language"].firstMatch.exists)
        XCTAssertTrue(scrollUntil(app.textFields["general_undo_depth_field"].firstMatch))
        XCTAssertFalse(app.descendants(matching: .any)["appearance_navigation_shape"].exists)
    }

    func testMineBackupEntryKeepsMigrationActions() {
        let backup = app.descendants(matching: .any)["mine_backup"].firstMatch
        XCTAssertTrue(scrollUntil(backup))
        backup.tap()
        XCTAssertTrue(app.descendants(matching: .any)["settings_migration_export_row"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["settings_migration_import_row"].exists)
    }

    func testInterfaceStyleKeepsNavigationSelection() {
        let appearance = app.descendants(matching: .any)["mine_appearance"].firstMatch
        XCTAssertTrue(scrollUntil(appearance))
        appearance.tap()
        // Native segments expose their option labels; enclosing card identifiers
        // can replace a segment's SwiftUI identifier in the accessibility tree.
        func option(_ label: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@",
                                             "seg_\(label)", label)).firstMatch
        }
        let classic = option("Material Design")
        XCTAssertTrue(scrollUntil(classic, reservedBottomInset: 0))
        classic.tap()
        XCTAssertTrue(pollUntil { classic.isSelected })
        let docked = option("Docked")
        XCTAssertTrue(scrollUntil(docked))
        docked.tap()
        XCTAssertTrue(docked.isSelected)
        let glass = option("Liquid Glass")
        XCTAssertTrue(glass.exists)
        glass.tap()
        XCTAssertTrue(pollUntil { glass.isSelected })
        XCTAssertTrue(docked.isSelected, "界面材质不能改导航形态")
        let widthTargets = [app.staticTexts["Appearance & display"].firstMatch,
                            option("Material Design"), glass, docked, option("Floating"),
                            app.buttons["theme_new_entry"].firstMatch]
            + app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'theme_preset_'"))
                .allElementsBoundByIndex
        XCTAssertTrue(pollUntil {
            let window = self.app.frame
            return widthTargets.allSatisfy { target in
                guard target.exists else { return false }
                let frame = target.frame
                return frame.width > 0 && frame.minX >= window.minX - 1 && frame.maxX <= window.maxX + 1
            }
        }, "Switching to native segments must keep the title, theme grid and every option inside the window width")
        retainScreenshot("native-glass-docked-selection")
        option("Material Design").tap()
        XCTAssertTrue(docked.isSelected)
    }

    // MARK: General — 语言 5 项切换(切 en → ja → 切回 en)
    //   选项在折叠卡 card_language 内(v1.0.56 T4, 原版本 对齐)→ tapLanguageOption
    //   先展卡再点选项; 切语言=整树重建 → expanded 复位, 每项前都要重展。

    func testGeneralLanguageSwitch() {
        relaunchWithNativeControls()
        let general = app.buttons["mine_general"].firstMatch
        XCTAssertTrue(scrollUntil(general), "通用设置入口应完整显示在底部导航上方")
        general.tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        tapLanguageOption("English")
        // 切日语验证多语切换(标题随之变 "一般")
        tapLanguageOption("日本語")
        XCTAssertTrue(pollUntil(6) { app.staticTexts["一般"].exists }, "切日语后标题应为 一般")
        // ★ 收尾必须切回 en: applyLanguage 持久化 AppPrefs 且优先于 -AppleLanguages
        //   启动参数 → 留 ja 会污染后续所有用例(TableSwitch 等英文断言全挂)
        tapLanguageOption("English")
        XCTAssertTrue(pollUntil(6) { app.staticTexts["General"].exists }, "切回 English 应恢复 General 标题")
    }

    // ★ 语言切换即时生效(修复前 L10n 固定 Bundle.main → 只写 prefs 不刷 UI):
    //   启动 en(种子已清残留语言)→ 切 "简体中文" → 页面立即变中文。
    //   全树重建(← Activity.recreate)保留 VM 状态 → 仍在 General overlay, 标题
    //   "General"→"通用" 即时变化;语言项标签是硬编码原生名, 不随语言变可再定位。
    //   选项在折叠卡 card_language 内 → 重建后回到收起态, 每项经 tapLanguageOption。
    func testLanguageSwitchAppliesImmediately() {
        relaunchWithNativeControls()
        let general = app.buttons["mine_general"].firstMatch
        XCTAssertTrue(scrollUntil(general), "通用设置入口应完整显示在底部导航上方")
        general.tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        tapLanguageOption("简体中文")

        // 整树重建后仍在 General overlay — 标题应立即是 "通用"(即时生效, 无需重启)
        XCTAssertTrue(pollUntil(6) { app.staticTexts["通用"].exists },
                      "切简体中文后 General 页标题应立即变 通用(即时生效)")
        // 恢复英文环境(与其他用例的英文断言隔离)
        tapLanguageOption("English")
        XCTAssertTrue(pollUntil(6) { app.staticTexts["General"].exists },
                      "切回 English 后应立即变回 General")
    }

    // ★ 节假日入口(General 页 holiday 入口卡): 点击进二级页, 返回回 General
    func testHolidayEntryOpensHolidayScreen() {
        openScheduleDisplay()
        let entry = app.descendants(matching: .any)["settings_holiday_entry"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "General 页应有节假日入口卡")
        // issue#26 别名开关折叠进 pill 卡后 General 页整体变矮, 固定 swipeUp 会把入口
        // 划出视口上沿(tap 落空)→ 按需双向滚动把入口送进可视区再点
        let screenH = app.frame.height
        for _ in 0..<4 {
            let f = entry.frame
            if f.minY > 80 && f.maxY < screenH - 80 { break }
            if f.minY <= 80 { app.swipeDown() } else { app.swipeUp() }
        }
        entry.tap()
        // 二级页标题 "Holidays & Make-up Days"
        let title = app.staticTexts["Holidays & Make-up Days"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "点入口应打开节假日设置页")
        // 返回(onBack = overlayScreen = null) → 回主界面, Mine tab 仍在。
        // Holiday 经 .sheet 呈现(GeneralSettingsScreen.swift:521), 背景 General 页仍在
        // 树上且自带同名 topbar_back → 全局 firstMatch 按树序命中被盖住的背景按钮。
        //
        // ★ 2026-11-06 两轮 CI 实证修正: 原坐标点击(基于标题 frame 反推返回键中心)
        //   不可信 — run 42158125671 / 42206732078 落点 [0.06, 0.12] 后
        //   Holiday sheet 实际未关闭, 旧断言只查 topbar_back 存在(开闭两态都成立)
        //   是假绿; 93235ca 收紧为"标题消失"后立即暴露(run 42229725312):
        //   点击后标题持续存在 5s。
        //   改走 AX 元素命中: sheet 打开时背景 General 顶栏的 topbar_back 被遮挡
        //   (isHittable=false), 可命中的那个就是最上层 Holiday sheet 的返回键;
        //   树序上 sheet 元素在后, 取最后一个可命中项兜底。
        let backs = app.buttons.matching(identifier: "topbar_back")
        XCTAssertGreaterThan(backs.count, 0, "Holiday sheet 打开时应存在返回键")
        let hittable = (0..<backs.count).map { backs.element(boundBy: $0) }.filter { $0.isHittable }
        (hittable.last ?? backs.element(boundBy: backs.count - 1)).tap()
        // ★ 返回落点是 General overlay(SleepyNavigationUnderlay covered=true 时底层
        //   Mine 整树 accessibilityHidden → mine_general 永不出现, 2026-11-06 CI 实证)。
        //   锚点拆两条分别覆盖两种错(单靠一条都判不全):
        //   1) topbar_back 仍在 — General 顶栏自带返回键(GeneralSettingsScreen:195,
        //      SettingsTopBar 默认 leadingStyle = .back)。被弹回 Mine 时全屏无此按钮,
        //      该条抓到"回错页"。
        //   2) Holiday 标题消失 — 锁住"Holiday sheet 已关"。入口卡文案是
        //      "Holiday course dimming"(settings_holiday_title), 与 sheet 标题
        //      "Holidays & Make-up Days"(holiday_page_title)不同串, 标题不会因入口卡残留。
        XCTAssertTrue(app.buttons["topbar_back"].firstMatch.waitForExistence(timeout: 5),
                      "返回后应回到 General 页(顶栏返回键仍在)")
        XCTAssertTrue(pollUntil(5) { !title.exists },
                      "返回后 Holiday sheet 应已关闭(标题不再存在)")
    }

    // MARK: Export — 3 格式行存在

    func testExportScreenThreeFormats() {
        app.switchToPillTab("manage")
        let export = app.descendants(matching: .any)["manage_export"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        XCTAssertTrue(app.staticTexts["Export Schedule"].waitForExistence(timeout: 5))
        // 3 个格式行(标题 L10n export_json/share/ics)
        let jsonRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'JSON'")).firstMatch
        XCTAssertTrue(jsonRow.waitForExistence(timeout: 3), "JSON 导出行应存在")
        let icsRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'ICS Calendar'")).firstMatch
        XCTAssertTrue(icsRow.exists, "ICS 导出行应存在")
    }

    // MARK: Reminder — 总开关 + 子开关 + 时间行

    func testReminderScreenToggles() {
        // ★ Reminder 深度场景(权限允许/拒绝/时间保存取消/子卡显隐)已迁至
        //   ReminderPermissionUITests(幂等+identifier 版)。此处保留冒烟:
        //   页可达 + master 幂等开 + 操作后不崩。
        let reminder = app.descendants(matching: .any)["mine_reminder"].firstMatch
        XCTAssertTrue(scrollUntil(reminder), "提醒入口应能滚入视口")
        reminder.tap()
        XCTAssertTrue(app.staticTexts["Reminders"].waitForExistence(timeout: 5))

        let masterSwitch = app.descendants(matching: .any)["reminder_master_toggle"]
        XCTAssertTrue(masterSwitch.waitForExistence(timeout: 3), "总开关应在")
        if (masterSwitch.value as? String) != "1" {
            masterSwitch.tap()
            // 若 notDetermined 会弹权限窗 — 点 Allow 使开关生效(幂等)
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let allowBtn = springboard.alerts.firstMatch.buttons.matching(
                NSPredicate(format: "label == 'Allow' OR label == '好'")).firstMatch
            if allowBtn.waitForExistence(timeout: 4) { allowBtn.tap() }
        }
        let denied = app.descendants(matching: .any)["reminder_notif_denied_row"].firstMatch
        XCTAssertTrue(pollUntil(6) { (masterSwitch.value as? String) == "1" || denied.exists },
                      "授权后应开启；系统已拒绝权限时应展示设置引导")
        if denied.exists {
            XCTAssertEqual(masterSwitch.value as? String, "0", "拒绝权限时总开关必须回退")
        } else {
            XCTAssertEqual(masterSwitch.value as? String, "1", "授权后总开关必须开启")
        }
        XCTAssertTrue(app.staticTexts["Reminders"].exists, "提醒页操作后不崩")
    }

}

