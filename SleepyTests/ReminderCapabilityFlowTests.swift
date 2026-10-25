// ReminderCapabilityFlowTests.swift — ← ReminderCapabilityFlowTest.kt
// 覆盖: 检查顺序两阶段 / 兜底 action 三级候选与 null 分支 /
//       standardNotificationAllowed 五态判定 / capabilityStatusText 六分支文案

import XCTest
@testable import Sleepy

final class ReminderCapabilityFlowTests: XCTestCase {

    // MARK: - ← `notification permission is checked before vendor settings`

    func testNotificationPermissionIsCheckedBeforeVendorSettings() {
        XCTAssertEqual(capabilityInspectionOrder(notificationPermissionGranted: false), ["notification"])
        // Android 单测只断言 false 分支; true 分支同样来自源码, 一并锁定。
        XCTAssertEqual(capabilityInspectionOrder(notificationPermissionGranted: true), ["notification", "vendor"])
    }

    // MARK: - ← `vendor settings failure falls through to application notification settings`

    func testVendorSettingsFailureFallsThroughToApplicationNotificationSettings() {
        XCTAssertEqual(
            lastResolvableActionFor(unavailableActions: [
                "com.vendor.notification.SETTINGS",
                "android.settings.CHANNEL_NOTIFICATION_SETTINGS"
            ]),
            "android.settings.APP_NOTIFICATION_SETTINGS"
        )
    }

    // MARK: - ← `missing vendor settings has no fallback action`

    func testMissingVendorSettingsHasNoFallbackAction() {
        XCTAssertNil(
            lastResolvableActionFor(unavailableActions: [
                "com.vendor.notification.SETTINGS",
                "android.settings.CHANNEL_NOTIFICATION_SETTINGS",
                "android.settings.APP_NOTIFICATION_SETTINGS"
            ])
        )
    }

    // MARK: - ← `unknown vendor state keeps standard notification allowed`

    func testUnknownVendorStateKeepsStandardNotificationAllowed() {
        XCTAssertTrue(standardNotificationAllowed(.unknown))
    }

    // MARK: - ← `vendor capability states do not disable standard notification`

    func testVendorCapabilityStatesDoNotDisableStandardNotification() {
        XCTAssertTrue(standardNotificationAllowed(.disabled))
        XCTAssertTrue(standardNotificationAllowed(.settingsRequired))
        XCTAssertTrue(standardNotificationAllowed(.notSupported))
        // ← Android NOTIFICATION_PERMISSION_REQUIRED → iOS .notApplicable
        XCTAssertFalse(standardNotificationAllowed(.notApplicable))
    }

    // MARK: - ← capabilityStatusText 六分支映射 (Android 侧同名函数, 单测镜像补齐文案锁定)

    func testCapabilityStatusTextCoversAllSixStates() {
        XCTAssertEqual(capabilityStatusText(state: .enabled), "enabled")
        XCTAssertEqual(capabilityStatusText(state: .disabled), "disabled")
        XCTAssertEqual(capabilityStatusText(state: .notApplicable), "notification_permission_required")
        XCTAssertEqual(capabilityStatusText(state: .settingsRequired), "settings_required")
        XCTAssertEqual(capabilityStatusText(state: .notSupported), "not_supported")
        XCTAssertEqual(capabilityStatusText(state: .unknown), "unknown")
    }
}
