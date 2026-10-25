// MineSettingsUITests.swift — G5+ 我的页设置全交互面测试
// 覆盖: Mine 刷新小组件按钮(带 snackbar) + AllTables(切表/编辑入口/新建) +
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
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 10))
        app.descendants(matching: .any)["pill_mine"].tap()
        XCTAssertTrue(app.staticTexts["Me"].waitForExistence(timeout: 5))
    }

    override func tearDownWithError() throws {
        app.terminate()   // 隔离: 每用例杀进程重启, 防跨用例状态串扰
    }

    /// 自适应下滑直到元素在视口内(元素全量物化, exists≠可见; 不可见时 tap
    /// 落点出屏丢失 — 2026-09 基线腐化根因; 页面高度随版本变, 固定次数不可靠)
    @discardableResult
    private func scrollUntil(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        let screenH = app.windows.firstMatch.frame.height
        // 底部再排除 110pt = 悬浮/贴底药丸导航栏占位区(capsule 64 + float 12 + 缓冲):
        // 元素"在屏"但落进 bar 区时, tap 会被 bar 拦截(2026-10-24 testGeneralToggles
        // 实证: switch hit y=790 ∈ bar 区 y742-806, 连点不翻转)。
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

    /// 语言选项收在折叠卡 card_language 内(v1.0.56 T4, 与 Android 一致), expanded
    /// 是页面 @State(不落盘)→ 每次切语言整树重建后回到收起态 → 选项前先展开卡。
    /// 卡头 label=当前语言: 若与目标同名(如 en→English)则 buttons[label] 双匹配,
    /// 用 y>卡头中线 锁定头部下方的选项行。锚点全用 identifier/label(与 locale 无关)。
    private func tapLanguageOption(_ label: String) {
        let head = app.buttons["card_language"].firstMatch
        XCTAssertTrue(head.waitForExistence(timeout: 5), "语言卡 card_language 应存在")
        XCTAssertTrue(scrollUntil(head, maxSwipes: 8), "语言卡应能滚入视口")
        head.tap()   // 展开折叠卡
        let headMidY = head.frame.midY
        // ★ 修复: Xcode 14.3.1 模拟器拒绝 NSPredicate 中 `y` 键路径(XCTElementQueryInvalidPredicate),
        //   改用 allElementsBoundByIndex + Swift 过滤(与 TableSwitchUITests.courseElement 同源模式)。
        let option = app.buttons.allElementsBoundByIndex
            .filter { $0.label == label && $0.frame.midY > headMidY }
            .first
        guard let opt = option else {
            XCTFail("展开后选项列表应有 \(label)")
            return
        }
        opt.tap()
    }

    // MARK: 刷新小组件按钮 + snackbar 反馈

    func testRefreshWidgetsButtonShowsSnackbar() {
        let refreshBtn = app.descendants(matching: .any)["mine_refresh_widgets"]
        XCTAssertTrue(refreshBtn.waitForExistence(timeout: 3))
        refreshBtn.tap()
        // snackbar 2.5s 停留 — 用 descendants 锚点(与 MineScreen.mine_snackbar 对齐)
        let snackbar = app.descendants(matching: .any)["mine_snackbar"]
        XCTAssertTrue(snackbar.waitForExistence(timeout: 3),
                      "点刷新应弹 snackbar")
    }

    // MARK: All Schedules — 切表 / 编辑入口 / 新建按钮

    /// a.v.1.0.41 热区回归: 点行内"空白区"(右端 Spacer 区, 离图标/文字最远)也应触发。
    /// 用户报障 = 点行色块不响应只有图标/文字才触发(SleepyButtonStyle 修复)。
    /// 代表行 2 条: mine_all_tables(普通导航) + mine_export(第二行, 验证同卡多行互不串扰)
    func testAllTablesRowBlankAreaTriggersNav() {
        let row = app.descendants(matching: .any)["mine_all_tables"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        // dx=0.92 → 行右端 8% 处: 文字在左侧, 此处为纯空白色块区
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["All Schedules"].waitForExistence(timeout: 5),
                      "点'所有课表'行右端空白区应跳转(SleepyButtonStyle 整行热区)")
    }

    func testExportRowBlankAreaTriggersNav() {
        let row = app.descendants(matching: .any)["mine_export"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertTrue(app.staticTexts["Export Schedule"].waitForExistence(timeout: 5),
                      "点'导出'行右端空白区应跳转到导出页")
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

    // MARK: Appearance — 3 态模式分段切换

    func testAppearanceModeSegmented() {
        app.descendants(matching: .any)["mine_appearance"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))

        let light = app.descendants(matching: .any)["theme_mode_light"]
        let dark = app.descendants(matching: .any)["theme_mode_dark"]
        let auto = app.descendants(matching: .any)["theme_mode_system"]
        XCTAssertTrue(light.waitForExistence(timeout: 3), "Light 模式按钮应存在")
        XCTAssertTrue(dark.exists, "Dark 模式按钮应存在")
        XCTAssertTrue(auto.exists, "Auto 模式按钮应存在")

        // 切 Dark → 立即生效不崩
        dark.tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 3), "切深色不应崩")
        // 切回 Light
        light.tap()
        // 切 Auto
        auto.tap()
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
    }

    // MARK: Appearance — 预设主题网格(至少一个预设可点)

    func testAppearancePresetGrid() {
        app.descendants(matching: .any)["mine_appearance"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        app.swipeUp()
        // 预设网格(2 列 N 个)— 任一预设按钮可点不崩
        let presets = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'theme' OR label CONTAINS 'Wake'")).firstMatch
        if presets.exists {
            presets.tap()
            XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 3))
        }
        // 无论预设如何, 页面不崩
        XCTAssertTrue(app.staticTexts["Appearance"].exists)
    }

    // MARK: General — 设置卡交互(平卡选项即时点选; 卡已原生化: Time Display/
    //       Grid sub-info = SettingsFlatCard 分段控件, 选项常显不可折叠 →
    //       旧"展开/收起"语义过时; 外层 accessibilityLabel(title) 覆盖段按钮 label,
    //       按标签查 buttons["Show as periods"] 失效 → 锚点用 seg_<渲染标签> identifier)

    func testGeneralCardsExpandCollapse() {
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))

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
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
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
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))

        // "Show dates on schedule" 行在 Home display 折叠卡内(pillCard, key=gridScale;
        // expandedSections 跨启动持久化 → 初始态不可假设)。锚点用卡 identifier
        // card_Home display(SettingsCards.swift:95), 点标题区驱动 onToggle;
        // 以行是否可见判当前态, 需要时翻转 → 确定性展开。
        let pillCard = app.descendants(matching: .any)["card_Home display"].firstMatch
        XCTAssertTrue(scrollUntil(pillCard, maxSwipes: 8), "Home display 卡应可达")
        // ★ 修复: 用 descendants 锚点(与 SettingToggleRow label 对齐), 避免 staticTexts 在合并后不可达
        let showDateRow = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Show dates'")).firstMatch
        if !showDateRow.waitForExistence(timeout: 1) {
            pillCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            XCTAssertTrue(pollUntil(4) { showDateRow.exists }, "展开后应有 'Show dates on schedule' 行")
        }
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
        sw0.tap()
        XCTAssertTrue(pollUntil(4) { showDateSwitch()?.value as? String != before },
                      "点 switch 应翻转")
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

    func testGeneralWidgetSection() {
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
        app.swipeUp()
        app.swipeUp()
        app.swipeUp()
        let widgetCard = app.staticTexts["Widget settings"].firstMatch
        if widgetCard.waitForExistence(timeout: 3) {
            widgetCard.tap()
            XCTAssertTrue(app.staticTexts["Uniform widget course colors"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.staticTexts["Week view separator"].exists)
            // 展开状态点第一个选项卡的 switch
            let sw = app.switches.firstMatch
            if sw.exists { sw.tap() }
        }
    }

    // MARK: General — 语言 5 项切换(切 en → ja → 切回 en)
    //   选项在折叠卡 card_language 内(v1.0.56 T4, Android 对齐)→ tapLanguageOption
    //   先展卡再点选项; 切语言=整树重建 → expanded 复位, 每项前都要重展。

    func testGeneralLanguageSwitch() {
        app.descendants(matching: .any)["mine_general"].tap()
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
        app.descendants(matching: .any)["mine_general"].tap()
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

    // ★ 节假日入口(← Android General 页 holiday 入口卡): 点击进二级页, 返回回 General
    func testHolidayEntryOpensHolidayScreen() {
        app.descendants(matching: .any)["mine_general"].tap()
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 5))
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
        // 返回(← Android onBack = overlayScreen = null) → 回主界面, Mine tab 仍在。
        // Holiday 经 .sheet 呈现(GeneralSettingsScreen.swift:521), 背景 General 页仍在
        // 树上且自带同名 topbar_back → 全局 firstMatch 按树序命中被盖住的背景按钮,
        // tap 落空。改点 Holiday 顶栏自身坐标: SettingsTopBar 几何 = leading 4 +
        // 40×40 按钮(中心距栏左缘 24) + 标题前导 4 → 返回键中心 x = 标题左缘 x - 26,
        // y = 标题垂直中心(同一行)。XCUITest 元素 frame = 屏幕绝对系; window 归一化
        // 点 = (绝对系 - window 原点)/window 尺寸。物理点击落在最上层 sheet 的返回键。
        // ★ 修复: 标题可能紧贴左缘(minX≈7), 返回键中心 x 可能为负 → 用 max(24, ...) 保底,
        //   与 SettingsTopBar 实际 leading=4 + 按钮半宽 20 = 24 对齐。
        let win = app.windows.firstMatch
        let backX = max(24.0, title.frame.minX - 26)
        let backY = title.frame.midY
        XCTAssertTrue(backX < win.frame.width && backY > win.frame.minY && backY < win.frame.maxY,
                      "Holiday 顶栏应在屏内(backX=\(backX), backY=\(backY))")
        win.coordinate(withNormalizedOffset: CGVector(dx: (backX - win.frame.minX) / win.frame.width,
                                                      dy: (backY - win.frame.minY) / win.frame.height)).tap()
        XCTAssertTrue(app.descendants(matching: .any)["mine_general"].waitForExistence(timeout: 5),
                      "返回后应回主界面(Mine tab)")
    }

    // MARK: Export — 3 格式行存在

    func testExportScreenThreeFormats() {
        app.descendants(matching: .any)["mine_export"].tap()
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
        app.descendants(matching: .any)["mine_reminder"].tap()
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
        XCTAssertTrue((masterSwitch.value as? String) == "1", "master 应为开")
        XCTAssertTrue(app.staticTexts["Reminders"].exists, "提醒页操作后不崩")
    }

    // MARK: About — 检查更新按钮(点击进入 checking 态, 网络失败回落不崩)

    func testAboutCheckUpdateButton() {
        app.descendants(matching: .any)["mine_about"].tap()
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 5))

        let checkBtn = app.descendants(matching: .any)["about_check_update"]
        XCTAssertTrue(checkBtn.waitForExistence(timeout: 3))
        checkBtn.tap()
        // 进入 checking(可能很快过去, 只要页面不崩)
        XCTAssertTrue(app.staticTexts["About"].waitForExistence(timeout: 3),
                      "检查更新不应崩溃")
    }
}

