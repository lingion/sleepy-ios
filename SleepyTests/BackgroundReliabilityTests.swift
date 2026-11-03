// BackgroundReliabilityTests.swift — ← BackgroundReliabilityProbeTest.kt + BackgroundReliabilitySnapshotTest.kt
// 覆盖: transport state 三分支短路 / factsSatisfied 组合 / probe 注入读取 / settings deep-link 返回语义

import XCTest
@testable import Sleepy

final class BackgroundReliabilityTests: XCTestCase {

    // MARK: - ← BackgroundReliabilitySnapshotTest: reminderTransportState 短路判定

    func testTransportStateBlockedWhenNotificationPermissionMissing() {
        let s = BackgroundReliabilitySnapshot(
            notificationPermissionGranted: false, timeSensitiveAllowed: true, lowPowerModeActive: false)
        XCTAssertEqual(s.reminderTransportState(), .blockedNotificationPermission)
    }

    func testTransportStateDegradedWhenTimeSensitiveUnavailable() {
        // ≙ 原版本: exact alarm 未授权 → DEGRADED_INEXACT_ALARM
        let s = BackgroundReliabilitySnapshot(
            notificationPermissionGranted: true, timeSensitiveAllowed: false, lowPowerModeActive: false)
        XCTAssertEqual(s.reminderTransportState(), .degradedInexactAlarm)
    }

    func testTransportStateReadyWhenAllGranted() {
        let s = BackgroundReliabilitySnapshot(
            notificationPermissionGranted: true, timeSensitiveAllowed: true, lowPowerModeActive: false)
        XCTAssertEqual(s.reminderTransportState(), .ready)
    }

    // MARK: - ← BackgroundReliabilitySnapshotTest: 组合事实

    func testStandardNotificationAllowedFollowsPermissionOnly() {
        let s = BackgroundReliabilitySnapshot(
            notificationPermissionGranted: true, timeSensitiveAllowed: false, lowPowerModeActive: true)
        XCTAssertTrue(s.standardNotificationAllowed())
        XCTAssertFalse(s.backgroundPermissionFactsSatisfied())
    }

    func testBackgroundFactsSatisfiedRequiresAllThree() {
        XCTAssertTrue(BackgroundReliabilitySnapshot(
            notificationPermissionGranted: true, timeSensitiveAllowed: true, lowPowerModeActive: false)
            .backgroundPermissionFactsSatisfied())
        // 低电量模式开启 = ≙ 原版本 电池优化未忽略
        XCTAssertFalse(BackgroundReliabilitySnapshot(
            notificationPermissionGranted: true, timeSensitiveAllowed: true, lowPowerModeActive: true)
            .backgroundPermissionFactsSatisfied())
    }

    // MARK: - ← BackgroundReliabilityProbeTest: 注入式读取

    func testProbeSnapshotUsesOverriddenFacts() async {
        let probe = BackgroundReliabilityProbe()
        probe.factsOverride = .init(
            notificationPermissionGranted: false, timeSensitiveAllowed: false, lowPowerModeActive: true)
        let s = await probe.snapshot()
        XCTAssertEqual(s.reminderTransportState(), .blockedNotificationPermission)
        XCTAssertFalse(s.timeSensitiveAllowed)
        XCTAssertTrue(s.lowPowerModeActive)
    }

    // MARK: - ← BatteryOptimizationIntentsTest: Boolean 返回语义(全败落空)

    func testOpenSettingsReturnsTrueWhenOpenerInvoked() {
        var opened: URL?
        let ok = BatteryOptimizationIntents.openAppSettings(opener: { opened = $0 })
        XCTAssertTrue(ok)
        XCTAssertEqual(opened?.absoluteString, UIApplication.openSettingsURLString)
    }
}
