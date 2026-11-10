// ReminderModeAndTableReminderTests.swift — v1.0.62 B3 闸门单测 (矩阵 §5)
//
// 覆盖两块:
//   1) 课前提醒形态互斥单源 (← AppPrefs.kt:302-316 getBeforeClassMode):
//      未写过 mode 时由 legacy KEY_BEFORE_CLASS_FLUID 推导 (无损迁移),
//      写入只走 setBeforeClassMode; banner 桥仅 true 侧有信息量。
//   2) 每课表提醒开关 (← ScheduleRepository.kt:154-162 setTableReminderEnabled):
//      改值 → captureForUndo + UPDATE + onDataChanged (通知重排链);
//      同值/缺表 → no-op, 不抓 undo, 不触发 onDataChanged。

import XCTest
@testable import Sleepy

/// 课前提醒形态互斥 — banner|fluid 单源 + legacy 双开关迁移桥。
final class BeforeClassModePrefsTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var prefs: AppPrefs!

    override func setUp() {
        super.setUp()
        // suite 隔离 — AppPrefs 进程级语义, 测试间串扰需显式隔离 (LocaleAndL10nTests 同款)
        suiteName = "b3_mode_\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        prefs = AppPrefs(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testDefaultModeIsBanner() {
        XCTAssertEqual(AppPrefs.BEFORE_CLASS_MODE_BANNER, prefs.getBeforeClassMode())
        XCTAssertTrue(prefs.isBeforeClassBannerEnabled())
        XCTAssertFalse(prefs.isBeforeClassFluidEnabled())
    }

    func testLegacyFluidKeyMigratesToFluidMode() {
        // ← 原版本: legacyFluid ? FLUID : BANNER — 旧双开关用户无损迁移
        defaults.set(true, forKey: AppPrefs.KEY_BEFORE_CLASS_FLUID)
        XCTAssertEqual(AppPrefs.BEFORE_CLASS_MODE_FLUID, prefs.getBeforeClassMode())
        XCTAssertTrue(prefs.isBeforeClassFluidEnabled())
    }

    func testLegacyFluidKeyFalseMigratesToBannerMode() {
        defaults.set(false, forKey: AppPrefs.KEY_BEFORE_CLASS_FLUID)
        XCTAssertEqual(AppPrefs.BEFORE_CLASS_MODE_BANNER, prefs.getBeforeClassMode())
    }

    func testSetBeforeClassModeRoundTrip() {
        prefs.setBeforeClassMode(AppPrefs.BEFORE_CLASS_MODE_FLUID)
        XCTAssertEqual(AppPrefs.BEFORE_CLASS_MODE_FLUID, prefs.getBeforeClassMode())
        XCTAssertTrue(prefs.isBeforeClassFluidEnabled())
        XCTAssertFalse(prefs.isBeforeClassBannerEnabled())

        prefs.setBeforeClassMode(AppPrefs.BEFORE_CLASS_MODE_BANNER)
        XCTAssertEqual(AppPrefs.BEFORE_CLASS_MODE_BANNER, prefs.getBeforeClassMode())
        XCTAssertTrue(prefs.isBeforeClassBannerEnabled())
    }

    func testBannerSetterDoesNotDisableLiveActivities() {
        // watch 快照恢复侧兼容桥: banner=true ⇔ mode=banner;
        // false 侧无信息量, 不得覆盖既有 mode (AppPrefs.swift 桥注释口径)。
        prefs.setBeforeClassMode(AppPrefs.BEFORE_CLASS_MODE_FLUID)
        prefs.setBeforeClassBannerEnabled(false)
        XCTAssertEqual(AppPrefs.BEFORE_CLASS_MODE_FLUID, prefs.getBeforeClassMode(),
                       "false 侧不得把既有 fluid 模式覆盖回 banner")

        prefs.setBeforeClassBannerEnabled(true)
        XCTAssertTrue(prefs.isBeforeClassFluidEnabled())
        XCTAssertTrue(prefs.isBeforeClassBannerEnabled())
    }

    func testLegacyFluidSelectionKeepsDefaultNotificationFallback() {
        defaults.set(AppPrefs.BEFORE_CLASS_MODE_FLUID, forKey: AppPrefs.KEY_BEFORE_CLASS_MODE)
        XCTAssertTrue(prefs.isBeforeClassFluidEnabled())
        XCTAssertTrue(prefs.isBeforeClassBannerEnabled())
        defaults.set(false, forKey: AppPrefs.KEY_BEFORE_CLASS_BANNER)
        XCTAssertFalse(prefs.isBeforeClassBannerEnabled())
    }

    func testIndependentSwitchesRoundTripIncludingBothOff() {
        prefs.setBeforeClassFluidEnabled(true)
        XCTAssertTrue(prefs.isBeforeClassBannerEnabled())
        prefs.setBeforeClassBannerEnabled(false)
        XCTAssertTrue(prefs.isBeforeClassFluidEnabled())
        prefs.setBeforeClassFluidEnabled(false)
        let reloaded = AppPrefs(defaults: defaults)
        XCTAssertFalse(reloaded.isBeforeClassBannerEnabled())
        XCTAssertFalse(reloaded.isBeforeClassFluidEnabled())
    }

    func testFluidSetterMapsToMode() {
        prefs.setBeforeClassFluidEnabled(true)
        XCTAssertEqual(AppPrefs.BEFORE_CLASS_MODE_FLUID, prefs.getBeforeClassMode())
        prefs.setBeforeClassFluidEnabled(false)
        XCTAssertEqual(AppPrefs.BEFORE_CLASS_MODE_BANNER, prefs.getBeforeClassMode())
    }
}

/// 每课表提醒开关 — repo 写语义 (读现值→no-op→capture+UPDATE→onDataChanged)。
final class TableReminderEnabledRepoTests: XCTestCase {

    private func makeRepo() throws -> (ScheduleRepository, AppDatabase) {
        let appdb = try AppDatabase.inMemory()
        return (ScheduleRepository(appdb), appdb)
    }

    func testFlipPersistsAndCapturesUndoAndFiresHook() throws {
        let (repo, appdb) = try makeRepo()
        var fired = 0
        repo.onDataChangedHook = { fired += 1 }

        let id = try repo.insertTable(TimeTableEntity(name: "T1", startDate: "2026-09-01"))
        // insertTable 自带 captureForUndo — 先清槽, 让下方断言只归 setTableReminderEnabled
        UndoManager.shared.clear()
        XCTAssertTrue(try appdb.timeTableDao.getById(id)!.reminderEnabled, "v11 旧行默认参与提醒")

        try repo.setTableReminderEnabled(id: id, enabled: false)
        XCTAssertFalse(try appdb.timeTableDao.getById(id)!.reminderEnabled)
        XCTAssertTrue(UndoManager.shared.hasSnapshot, "真变化必须抓 undo (撤回按钮亮)")
        XCTAssertEqual(1, fired, "有变化才 onDataChanged (widget 刷新 + 通知重排)")
    }

    func testSameValueIsNoOpWithoutUndoOrHook() throws {
        let (repo, appdb) = try makeRepo()
        var fired = 0
        repo.onDataChangedHook = { fired += 1 }

        let id = try repo.insertTable(TimeTableEntity(name: "T2", startDate: "2026-09-01"))
        // 同上: 清掉 insert 自带快照, 断言只归 setTableReminderEnabled
        UndoManager.shared.clear()
        try repo.setTableReminderEnabled(id: id, enabled: true) // 与默认值相同
        XCTAssertTrue(try appdb.timeTableDao.getById(id)!.reminderEnabled)
        XCTAssertFalse(UndoManager.shared.hasSnapshot, "同值 no-op 不得抓 undo (原 return@withTransaction false)")
        XCTAssertEqual(0, fired, "同值 no-op 不得触发 onDataChanged")
    }

    func testMissingTableIsNoOp() throws {
        let (repo, _) = try makeRepo()
        var fired = 0
        repo.onDataChangedHook = { fired += 1 }
        // 无 insert — 全新 inMemory 库 + clear 后槽为空
        UndoManager.shared.clear()

        try repo.setTableReminderEnabled(id: 424_242, enabled: false)
        XCTAssertFalse(UndoManager.shared.hasSnapshot)
        XCTAssertEqual(0, fired)
    }
}
