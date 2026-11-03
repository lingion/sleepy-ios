// BackgroundReliabilityProbe.swift — ← BackgroundReliabilityProbe.kt
// 单点读取 iOS 可观测的后台可靠性事实。注入式读取便于单测(与 原 probe 同思路)。
//
// 平台映射(禁止 silent skip):
// - notificationPermissionGranted ← POST_NOTIFICATIONS 检查 → UNUserNotificationCenter
//   .notificationSettings().authorizationStatus == .authorized
// - exactAlarmAllowed ← AlarmManager.canScheduleExactAlarms → timeSensitiveSetting == .enabled
// - batteryOptimizationIgnored ← PowerManager.isIgnoringBatteryOptimizations → !isLowPowerModeEnabled
// - vendor/liveCardState/widgetBound/promotedOngoingAllowed: 原版本-only 事实,
//   iOS 无对应物(no-analog), 见 BackgroundReliabilitySnapshot.swift 头部映射表;
//   "失败的私有厂商探测保持 UNKNOWN 且永不禁用标准通知"(原版本 注释)在 iOS 侧天然成立:
//   单厂商, 探测不存在, 标准通知路径不受本 probe 影响。

import Foundation
import UserNotifications

final class BackgroundReliabilityProbe {
    static let shared = BackgroundReliabilityProbe()

    /// 可注入的原始事实(测试用); nil = 运行时真实读取
    var factsOverride: RelayFacts?

    struct RelayFacts {
        let notificationPermissionGranted: Bool
        let timeSensitiveAllowed: Bool
        let lowPowerModeActive: Bool
    }

    /// ← snapshot(context): 异步聚合三 facts → snapshot
    func snapshot(
        center: UNUserNotificationCenter = .current(),
        processInfo: ProcessInfo = .processInfo
    ) async -> BackgroundReliabilitySnapshot {
        if let f = factsOverride {
            return BackgroundReliabilitySnapshot(
                notificationPermissionGranted: f.notificationPermissionGranted,
                timeSensitiveAllowed: f.timeSensitiveAllowed,
                lowPowerModeActive: f.lowPowerModeActive
            )
        }
        let settings = await center.notificationSettings()
        return BackgroundReliabilitySnapshot(
            notificationPermissionGranted: settings.authorizationStatus == .authorized,
            timeSensitiveAllowed: settings.timeSensitiveSetting == .enabled,
            lowPowerModeActive: processInfo.isLowPowerModeEnabled
        )
    }
}
