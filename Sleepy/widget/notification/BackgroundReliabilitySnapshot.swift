// BackgroundReliabilitySnapshot.swift — ← BackgroundReliabilitySnapshot.kt
// 后台可靠性事实快照: 从当前设备与 App 状态观察到的客观事实模型。
// 刻意不声称"厂商通道一定可用"(原版本 注释原文), iOS 侧对应: 不声称后台刷新一定存活。
//
// 平台映射(逐字段, 禁止 silent skip):
// - notificationPermissionGranted ← 同名: POST_NOTIFICATIONS → UNAuthorizationStatus.authorized
// - exactAlarmAllowed ← 同名: AlarmManager.canScheduleExactAlarms → iOS 无 exact alarm 概念,
//   等价事实 = 时效性通知可用(UserNotifications.timeSensitiveSetting == .enabled,
//   时效性是 iOS 唯一能突破摘要投递/专注模式的"精确通道")
// - batteryOptimizationIgnored ← PowerManager.isIgnoringBatteryOptimizations → iOS 无电池优化白名单,
//   等价替代事实 = 低电量模式未开启(ProcessInfo.isLowPowerModeEnabled == false;
//   低电量模式会推迟后台任务与通知聚合投递, 是 iOS 唯一的"系统级省电干预")
// - ActivityKit 权限独立于通知权限，由 ReminderScreen 读取 areActivitiesEnabled。
// - WidgetCenter.getCurrentConfigurations 可查询已配置的小组件；不代表准时刷新保证。

import Foundation

/// ← 原版本 ReminderTransportState: 提醒投递链路的就绪度
enum ReminderTransportState: String {
    case ready
    /// 原版本: exact alarm 未授权只能粗颗粒告警; iOS: 时效性通知不可用, 投退化为普通通道
    case degradedInexactAlarm
    /// 原版本/iOS 同语义: 通知权限未授权, 一切本地提醒不可达
    case blockedNotificationPermission
}

/// ← BackgroundReliabilitySnapshot.kt data class(字段名对齐, 3 项 no-analog 字段见文件头映射表)
struct BackgroundReliabilitySnapshot {
    let notificationPermissionGranted: Bool
    /// ≙ 原版本 exactAlarmAllowed
    let timeSensitiveAllowed: Bool
    /// ≙ 原版本 batteryOptimizationIgnored(取反)
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
