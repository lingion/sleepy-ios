// ReminderPermissionUITests.swift — 提醒权限与时间设置全路径
// ★ 通知权限跨测试持久(模拟器 per-app 状态, 卸载 app 才清), 测试按名排序即状态机:
//   01 首次 notDetermined → 点 Allow → granted 固化 → 02..04 全在 granted 下跑。
//   denied 路径单独 ReminderPermissionDeniedTests, 由专项脚本 uninstall 后单跑。
// ★ 开关一律用 identifier 定位(reminder_master_toggle/_daily_toggle/_before_class_toggle):
//   app.switches boundBy index 在多卡渲染时不可靠(实测同页 6 个 switch)。
// ★ 系统通知弹窗是 SBUserNotificationAlert: 必须经 springboard.alerts 层级 query。

import XCTest

final class ReminderPermissionUITests: XCTestCase {

    var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 30))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    private func openReminder() {
        app.switchToPillTab("mine")
        let entry = app.descendants(matching: .any)["mine_reminder"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "Mine 页应有提醒入口")
        entry.tap()
        XCTAssertTrue(app.staticTexts["Reminders"].waitForExistence(timeout: 5), "应进入提醒页")
    }

    private var masterSwitch: XCUIElement {
        app.descendants(matching: .any)["reminder_master_toggle"]
    }

    private var dailySwitch: XCUIElement {
        app.descendants(matching: .any)["reminder_daily_toggle"]
    }

    private func masterIsOn() -> Bool {
        switchIsOn(masterSwitch)
    }

    /// 允许系统通知弹窗(若出现)。返回是否处理了弹窗。
    @discardableResult
    private func allowPermissionAlertIfPresent() -> Bool {
        let alert = springboard.alerts.firstMatch
        let allowBtn = alert.buttons.matching(
            NSPredicate(format: "label IN {'Allow', '好', '允许', '允許'}")).firstMatch
        if allowBtn.waitForExistence(timeout: 6) {
            allowBtn.tap()
            return true
        }
        return false
    }

    private func ensureMasterOn() {
        if !masterIsOn() {
            masterSwitch.tap()
            allowPermissionAlertIfPresent()
        }
        XCTAssertTrue(masterSwitch.waitForExistence(timeout: 4), "master 开关应在")
        waitForSwitch(masterSwitch, isOn: true)
    }

    private func switchIsOn(_ element: XCUIElement) -> Bool {
        if let value = element.value as? String { return value == "1" }
        if let value = element.value as? NSNumber { return value.boolValue }
        XCTFail("Unreadable switch value: \(String(describing: element.value))")
        return false
    }

    private func waitForSwitch(_ element: XCUIElement, isOn: Bool) {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if switchIsOn(element) == isOn { return }
            usleep(100_000)
        }
        XCTAssertEqual(switchIsOn(element), isOn,
            "Expected switch \(element.identifier)=\(isOn), got \(String(describing: element.value))")
    }

    // MARK: 01 首次开 master → 弹权限 → Allow → 子卡渲染 + master 开

    func test01_MasterOnNotDeterminedThenAllow() throws {
        openReminder()
        // 幂等: 首跑 notDetermined(弹窗→Allow); 重跑时权限/开关已持久 → 直接验证开态
        if !masterIsOn() {
            masterSwitch.tap()
            let prompted = allowPermissionAlertIfPresent()
            if prompted {
                XCTAssertTrue(app.descendants(matching: .any).matching(
                    NSPredicate(format: "label CONTAINS 'Daily Reminder'")).firstMatch
                    .waitForExistence(timeout: 4), "授权后 Daily 子卡应渲染")
            }
        }
        if !masterIsOn() {
            masterSwitch.tap()  // master off 持久态(上轮测试遗留) → 再开
            allowPermissionAlertIfPresent()
        }
        XCTAssertTrue(masterIsOn(), "master 应为开")
        XCTAssertTrue(app.staticTexts["Reminders"].exists, "操作后不崩")
    }

    // MARK: 02 Daily 时间行 → 取消 → 值不变

    func test02_DailyTimeCancelKeepsValue() throws {
        openReminder()
        ensureMasterOn()
        XCTAssertTrue(dailySwitch.waitForExistence(timeout: 4), "Daily 子开关应渲染")
        if !switchIsOn(dailySwitch) { dailySwitch.tap() }
        let timeRow = app.descendants(matching: .any)["reminder_time_row"]
        XCTAssertTrue(timeRow.waitForExistence(timeout: 4), "开 Daily 后应显示时间行")
        let before = timeRow.label

        timeRow.tap()
        let cancel = app.descendants(matching: .any)["reminder_time_cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 4), "应弹时间选择 sheet")
        cancel.tap()

        let row = app.descendants(matching: .any)["reminder_time_row"]
        XCTAssertTrue(row.waitForExistence(timeout: 4), "取消后回提醒页")
        XCTAssertEqual(row.label, before, "取消后时间不应变")
    }

    // MARK: 03 Daily 时间行 → 确认 → sheet 收起 + 时间显示在

    func test03_DailyTimeConfirmUpdatesValue() throws {
        openReminder()
        ensureMasterOn()
        XCTAssertTrue(dailySwitch.waitForExistence(timeout: 4))
        if !switchIsOn(dailySwitch) { dailySwitch.tap() }
        let timeRow = app.descendants(matching: .any)["reminder_time_row"]
        XCTAssertTrue(timeRow.waitForExistence(timeout: 4))

        timeRow.tap()
        let confirm = app.descendants(matching: .any)["reminder_time_confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()

        let row = app.descendants(matching: .any)["reminder_time_row"]
        XCTAssertTrue(row.waitForExistence(timeout: 4), "确认后回提醒页")
        XCTAssertTrue(row.label.contains(":"), "时间格式应含冒号(HH:mm), 实际: \(row.label)")
    }

    // MARK: 04 master 关 → 子卡隐藏; 再开(granted) → 不弹窗直接开

    func test04_MasterOffHidesSubcardsAndReOn() throws {
        openReminder()
        ensureMasterOn()
        let dailyCard = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Daily Reminder'")).firstMatch
        XCTAssertTrue(dailyCard.waitForExistence(timeout: 4), "开态下子卡应在")

        masterSwitch.tap() // 关
        waitForSwitch(masterSwitch, isOn: false)
        XCTAssertTrue(dailyCard.waitForNonExistence(timeout: 5), "关 master 后子卡应隐藏")

        masterSwitch.tap() // 再开(已授权 → 不弹窗)
        XCTAssertFalse(allowPermissionAlertIfPresent(), "已授权再开不应再弹权限窗")
        waitForSwitch(masterSwitch, isOn: true)
        XCTAssertTrue(masterIsOn(), "再开后 master 应为开")
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Daily Reminder'")).firstMatch
            .waitForExistence(timeout: 3), "再开后子卡应回归")
    }

    func test05_NotificationAndLiveActivitySwitchesAreIndependentAndPersist() throws {
        openReminder()
        ensureMasterOn()
        let before = app.switches["reminder_before_class_toggle"]
        for _ in 0..<5 where !before.isHittable { app.swipeUp() }
        XCTAssertTrue(before.waitForExistence(timeout: 5))
        // A scroll can leave the switch partially clipped. Move the before-class
        // card into the centre before querying/tapping its state.
        if before.frame.midY > app.frame.height * 0.75 { app.swipeUp(velocity: .slow) }
        if !switchIsOn(before) { before.tap() }
        waitForSwitch(before, isOn: true)
        let live = app.switches["reminder_live_activity_toggle"]
        for _ in 0..<5 where !live.isHittable { app.swipeUp() }
        XCTAssertTrue(live.waitForExistence(timeout: 5))
        if (live.value as? String) != "1" { live.tap() }
        let notification = app.switches["reminder_notification_toggle"]
        XCTAssertTrue(notification.exists)
        if (notification.value as? String) != "1" { notification.tap() }
        XCTAssertEqual(live.value as? String, "1")
        notification.tap()
        XCTAssertEqual(live.value as? String, "1")
        live.tap()
        XCTAssertEqual(notification.value as? String, "0")
        live.tap()
        notification.tap()
        XCTAssertEqual(live.value as? String, "1")
        app.terminate()
        app.sleepyLaunch()
        openReminder()
        for _ in 0..<5 where !live.isHittable { app.swipeUp() }
        XCTAssertEqual(live.value as? String, "1")
        XCTAssertEqual(notification.value as? String, "1")
        if #available(iOS 26.0, *) {
            XCTAssertTrue(app.descendants(matching: .any)["reminder_live_activity_schedule_status"].exists)
        }
    }
}

// denied 路径: 需要 notDetermined 前提(权限被系统记住, 无法在 granted 会话内重演)。
// 专项批跑: xcrun simctl uninstall <udid> com.lingion.sleepy 后立即单跑本类。
final class ReminderPermissionDeniedTests: XCTestCase {

    var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-SLEEPY_UI_TEST_SEED"]
        app.sleepyLaunch()
        XCTAssertTrue(app.descendants(matching: .any)["pill_schedule"].waitForExistence(timeout: 30))
    }

    func testMasterOnWithNotificationPermissionDeniedKeepsIndependentActivitySettings() throws {
        app.switchToPillTab("mine")
        app.descendants(matching: .any)["mine_reminder"].tap()
        XCTAssertTrue(app.staticTexts["Reminders"].waitForExistence(timeout: 5))

        app.descendants(matching: .any)["reminder_master_toggle"].tap()
        let alert = springboard.alerts.firstMatch
        let denyBtn = alert.buttons.matching(
            NSPredicate(format: "label CONTAINS 'Don' OR label CONTAINS '不允'")).firstMatch
        if !denyBtn.waitForExistence(timeout: 6) {
            // 权限已被固化(granted/denied), 弹窗不会出现 → skip 而非 fail。
            // 完整重演: xcrun simctl uninstall <udid> com.lingion.sleepy 后单跑本类。
            throw XCTSkip("权限非 notDetermined, 弹窗不出现(专项批另行重演)")
        }
        denyBtn.tap()

        let master = app.descendants(matching: .any)["reminder_master_toggle"]
        XCTAssertEqual((master.value as? String) == "1", true,
                       "通知权限不能禁用独立的实况活动设置")
        XCTAssertTrue(app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS 'Daily Reminder'")).firstMatch.exists,
            "拒绝通知后仍可配置各提醒渠道")
    }
}
