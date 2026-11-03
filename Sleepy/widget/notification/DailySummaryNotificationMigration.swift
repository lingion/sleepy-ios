// DailySummaryNotificationMigration.swift — ← widget/notification/DailySummaryNotificationMigration.kt (v1.0.62 B5)
// v1.0.61 摘要多表扇出遗留通知的一次性清理: v1.0.62 起每日摘要改单条聚合
// (只贴主 id sleepy_daily_1001/1002), 旧扇出 id (sleepy_summary_*) 若不撤会与
// 新摘要同屏重复。iOS 无 NotificationChannel, 频道归属判定落为 identifier 前缀
// 归属: 只清自家 sleepy_summary_ 命名空间, 不碰课前/重同步/未知来源载体。
//
// 平台映射: NotificationManager.activeNotifications + cancel(tag, id) →
//   UNUserNotificationCenter getPendingNotificationRequests + getDeliveredNotifications
//   + removePendingNotificationRequests / removeDeliveredNotifications (双清单各清各的)。

import Foundation
import UserNotifications

/// ← DailySummaryNotificationIdentity: iOS 侧只有 identifier 一维
/// (原版本 的 channelId/id/tag 三元组在 iOS 由前缀命名空间承担归属判定)。
struct DailySummaryNotificationIdentity: Equatable {
    let identifier: String
}

/// ← legacyDailySummaryNotifications: 频道所有权是必需的 — 旧 id 可能与无关课程
/// 通知撞号 (原 channel == CHANNEL_DAILY 判定的 iOS 前缀等价物)。
/// 不做任何数字段位假设(负数/超大号一律按前缀归属处理)。
func legacyDailySummaryNotifications(
    _ notifications: [DailySummaryNotificationIdentity]
) -> [DailySummaryNotificationIdentity] {
    notifications.filter {
        $0.identifier.hasPrefix(NotificationScheduler.NOTIFY_SUMMARY_PREFIX)
    }
}

/// ← cleanupLegacyDailySummaryNotifications: pending 与 delivered 两清单分别清理;
/// 失败静默(原 runCatching + Log.w 同义 — 清理失败不影响本次摘要张贴)。
func cleanupLegacyDailySummaryNotifications(_ center: UNUserNotificationCenter = .current()) {
    Task {
        do {
            let pending = try await center.pendingNotificationRequests()
            let legacyPending = legacyDailySummaryNotifications(
                pending.map { DailySummaryNotificationIdentity(identifier: $0.identifier) })
            if !legacyPending.isEmpty {
                center.removePendingNotificationRequests(
                    withIdentifiers: legacyPending.map { $0.identifier })
            }
            let delivered = try await center.deliveredNotifications()
            let legacyDelivered = legacyDailySummaryNotifications(
                delivered.map { DailySummaryNotificationIdentity(identifier: $0.request.identifier) })
            if !legacyDelivered.isEmpty {
                center.removeDeliveredNotifications(
                    withIdentifiers: legacyDelivered.map { $0.identifier })
            }
        } catch {
            // ← Log.w("DailySummaryMigration", "Unable to remove legacy daily summaries")
        }
    }
}
