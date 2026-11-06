// BackgroundReliabilitySnapshot.swift — ← BackgroundReliabilitySnapshot.kt
// 后台可靠性事实快照: 从当前设备与 App 状态观察到的客观事实模型。
// 刻意不声称"厂商通道一定可用"(Android 注释原文), iOS 侧对应: 不声称后台刷新一定存活。
//
// 平台映射(逐字段, 禁止 silent skip):
// - notificationPermissionGranted ← 同名: POST_NOTIFICATIONS → UNAuthorizationStatus.authorized
// - exactAlarmAllowed ← 同名: AlarmManager.canScheduleExactAlarms → iOS 无 exact alarm 概念,
//   等价事实 = 时效性通知可用(UserNotifications.timeSensitiveSetting == .enabled,
//   时效性是 iOS 唯一能突破摘要投递/专注模式的"精确通道")
// - batteryOptimizationIgnored ← PowerManager.isIgnoringBatteryOptimizations → iOS 无电池优化白名单,
//   等价替代事实 = 低电量模式未开启(ProcessInfo.isLowPowerModeEnabled == false;
//   低电量模式会推迟后台任务与通知聚合投递, 是 iOS 唯一的"系统级省电干预")
// - vendor / liveCardState ← LiveCardVendor + VendorCapabilityState: Android 厂商 ROM 探测,
//   iOS 单一厂商无多厂商探测维度(no-analog, 本结构不设字段); iOS 对应物 = ActivityKit
//   实况活动/灵动岛, 本 app 未实现(属 reminder-live 切片)
// - widgetBound ← AppWidgetManager.getAppWidgetIds → WidgetKit 无"已在桌面添加"公开 API(no-analog)
// - promotedOngoingAllowed ← Android 16 promoted notifications → iOS 无同名机制;近似探针 =
//   ActivityAuthorizationInfo().areLiveActivitiesEnabled(iOS 16.2+), 随 ActivityKit 切片一并未实现

import Foundation

/// ← Android ReminderTransportState: 提醒投递链路的就绪度
enum ReminderTransportState: String {
    case ready
    /// Android: exact alarm 未授权只能粗颗粒告警; iOS: 时效性通知不可用, 投退化为普通通道
    case degradedInexactAlarm
    /// Android/iOS 同语义: 通知权限未授权, 一切本地提醒不可达
    case blockedNotificationPermission
}

/// ← BackgroundReliabilitySnapshot.kt data class(字段名对齐, 3 项 no-analog 字段见文件头映射表)
struct BackgroundReliabilitySnapshot {
    let notificationPermissionGranted: Bool
    /// ≙ Android exactAlarmAllowed
    let timeSensitiveAllowed: Bool
    /// ≙ Android batteryOptimizationIgnored(取反)
    let lowPowerModeActive: Bool

    /// ← reminderTransportState(): 权限 > 精确通道, 短路判定
    func reminderTransportState() -> ReminderTransportState {
        if !notificationPermissionGranted { return .blockedNotificationPermission }
        if !timeSensitiveAllowed { return .degradedInexactAlarm }
        return .ready
    }

    /// ← standardNotificationAllowed()
    func standardNotificationAllowed() -> Bool { notificationPermissionGranted }

    /// ← backgroundPermissionFactsSatisfied()
    func backgroundPermissionFactsSatisfied() -> Bool {
        notificationPermissionGranted && timeSensitiveAllowed && !lowPowerModeActive
    }
}
