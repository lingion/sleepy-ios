// NotificationScheduler.swift — ← CourseNotificationScheduler.kt
// 课程通知调度器 — 支持每日提醒 + 每节课前提醒。
//
// 每日提醒:在用户指定时间发送今日课程摘要。
// 课前提醒:每天凌晨调度当天每节课前 N 分钟的通知。
//
// 平台映射: AlarmManager+BroadcastReceiver → UNUserNotificationCenter+UNCalendarNotificationTrigger
// (iOS 无 exact alarm;日历触发器在锁屏也能到,精度分钟级 — 等价适配)
//
// OPPO Fluid Cloud(SDK≥26 前台服务 + ProgressStyle)整体跳过(平台差异表#3,
// iOS 无对应物);banner 通知完整移植。

import Foundation
import UserNotifications

final class NotificationScheduler {
    static let shared = NotificationScheduler()

    // ← companion object 常量
    static let CHANNEL_DAILY = "sleepy_daily"
    static let CHANNEL_BEFORE_CLASS = "sleepy_before_class"

    // Notification identifiers(= Android request codes 语义:按 id 撤销)
    static let NOTIFY_DAILY = "sleepy_daily_1001"
    static let NOTIFY_BEFORE_CLASS_PREFIX = "sleepy_bc_2000_"  // + courseId

    private let center = UNUserNotificationCenter.current()
    private let prefs = AppPrefs.shared

    var repositoryProvider: (() -> ScheduleRepository?)?

    // ==================== scheduleAll ← ====================

    func scheduleAll() {
        createChannels()
        Task {
            await cancelAll()

            guard prefs.isReminderEnabled() else { return }

            if prefs.isDailyReminderEnabled() {
                scheduleDaily()
            }
            if prefs.isBeforeClassEnabled() {
                scheduleBeforeClassDaily()
            }
        }
    }

    func cancelAll() async {
        // Android 逐 course id cancel;iOS removePendingNotificationRequests(withIdentifiers:)
        // 先枚举 pending 里属于本 app 的 id 全撤(含孤儿 — 删表级联后 Android 侧的孤儿问题
        // 在 iOS 由 removePendingNotificationRequests(全部自有前缀) 自然覆盖)
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// ★ 取消指定课程 id 的课前通知(ScheduleRepository.deleteTable 调 — 孤儿清理)
    func cancelCourseNotifications(_ courseIds: [Int64]) {
        let ids = courseIds.map { Self.NOTIFY_BEFORE_CLASS_PREFIX + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // ==================== Daily ====================

    private func scheduleDaily() {
        // ← "HH:mm" 解析 + 钳制(破损 pref 不崩)
        let timeStr = prefs.getDailyReminderTime()
        let parts = timeStr.split(separator: ":").map(String.init)
        let hour = min(max(Int(parts.count > 0 ? parts[0] : "") ?? 7, 0), 23)
        let minute = min(max(Int(parts.count > 1 ? parts[1] : "") ?? 0, 0), 59)

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        // ← setRepeatingAlarm INTERVAL_DAY: UNCalendarNotificationTrigger(dateMatching: time only, repeats: true)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)

        let content = UNMutableNotificationContent()
        // 实际文本在 willPresent 时由 provider 快照填充(锁屏快照只能静态 —
        // iOS 通知内容在排定时固化,故 title/body 用占位,发送前用 UNTextInput 无解 →
        // 改为:排定时即查当日课程快照。快照陈旧 ≤1 天,与 Android 语义一致(每日 0 点后重排)
        fillDailyContent(content)

        let req = UNNotificationRequest(identifier: Self.NOTIFY_DAILY, content: content, trigger: trigger)
        try? center.add(req)
    }

    // ==================== Before-class ====================

    private func scheduleBeforeClassDaily() {
        // Android: 00:05 排当天每节课的 alarm。iOS 等价:立即排今天剩余课的通知,
        // 并排一个 0:05 的重复触发器做"明天重排"(内容为重排动作本身 → 用 daily 静默通知
        // 会打扰;改为靠 WidgetKit timeline + app 启动重排,详见 README 平台差异#3)。
        // 精度权衡:UNCalendarNotificationTrigger per-course 直排到 expire,无需每日重排
        // —— 排 14 天滚动窗口(远期课表变更靠 scheduleAll() 幂等重排覆盖)。
        Task { await scheduleBeforeClassWindow() }
    }

    /// 排未来 14 天每天的课前通知(每课程一个 UNCalendarNotificationTrigger,精确到分)
    private func scheduleBeforeClassWindow() async {
        guard prefs.isBeforeClassEnabled() else { return }
        let minutes = prefs.getBeforeClassMinutes()
        guard let repo = repositoryProvider?() else { return }
        guard let table = WidgetTableResolver.resolveCurrentTable(repo) else { return }

        let cal = DateUtils.isoCalendar
        let now = Date()

        for dayOffset in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let dow = DateUtils.todayDayOfWeek(today: day)
            let week = DateUtils.currentWeek(startDate: table.startDate, today: day)
            let courses = ((try? repo.getCoursesByDay(table.id, day: dow)) ?? []).filter { $0.inWeek(week) }
            let nodes = TimeTableUtils.parseNodes(table.timeJson)

            for course in courses {
                // ← startTime: ownTime 优先,否则节次反查
                let startTimeStr: String?
                if course.ownTime && !course.startTime.isEmpty {
                    startTimeStr = course.startTime
                } else if let node = nodes.first(where: { $0.node == course.startNode }) {
                    startTimeStr = TimeTableUtils.formatTime(node.start)
                } else {
                    startTimeStr = nil
                }
                guard let startTimeStr else { continue }
                let parts = startTimeStr.split(separator: ":").map(String.init)
                guard let h = Int(parts.count > 0 ? parts[0] : ""),
                      let m = Int(parts.count > 1 ? parts[1] : ""),
                      (0...23).contains(h), (0...59).contains(m) else { continue }

                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = h
                comps.minute = m
                guard let classStart = cal.date(from: comps) else { continue }
                let notify = classStart.addingTimeInterval(-Double(minutes) * 60)
                if notify <= now { continue }  // ← skip past alarm

                var trigComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: notify)
                _ = trigComps
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: cal.dateComponents([.year, .month, .day, .hour, .minute], from: notify),
                    repeats: false
                )

                let content = UNMutableNotificationContent()
                let roomStr = course.room.isEmpty ? L10n.t("notif_room_unknown") : course.room
                if course.teacher.isEmpty {
                    content.title = L10n.t("notif_before_class_title")
                    content.body = L10n.format("notif_before_class_text", course.courseName, startTimeStr, roomStr)
                } else {
                    content.title = L10n.t("notif_before_class_title")
                    content.body = L10n.format("notif_before_class_text_with_teacher", course.courseName, startTimeStr, roomStr, course.teacher)
                }
                content.sound = .default

                let req = UNNotificationRequest(
                    identifier: Self.NOTIFY_BEFORE_CLASS_PREFIX + String(course.id),
                    content: content, trigger: trigger
                )
                try? await center.add(req)
            }
        }
    }

    // ==================== Channels ====================

    private func createChannels() {
        // iOS 无 channel;权限请求对齐 Android 13 POST_NOTIFICATIONS
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // ==================== Daily content 快照 ====================

    private func fillDailyContent(_ content: UNMutableNotificationContent) {
        // ← DailyNotifyReceiver.sendDailyNotification 的文本构造
        let today = Date()
        let dow = DateUtils.todayDayOfWeek(today: today)
        let dayOfMonth = DateUtils.isoCalendar.component(.day, from: today)

        guard let repo = repositoryProvider?(),
              let table = WidgetTableResolver.resolveCurrentTable(repo) else {
            content.title = L10n.format("notif_daily_title_no_course", dayOfMonth)
            content.body = L10n.t("notif_daily_text_no_course")
            return
        }
        let week = DateUtils.currentWeek(startDate: table.startDate, today: today)
        let courses = ((try? repo.getCoursesByDay(table.id, day: dow)) ?? [])
            .filter { $0.inWeek(week) }
            .sorted { $0.startNode < $1.startNode }

        if courses.isEmpty {
            content.title = L10n.format("notif_daily_title_no_course", dayOfMonth)
            content.body = L10n.t("notif_daily_text_no_course")
            return
        }
        content.title = L10n.format("notif_daily_title", dayOfMonth, courses.count)
        let first = courses[0]
        let firstTime = Self.courseStartTime(first, table)
        let firstRoom = first.room.isEmpty ? L10n.t("notif_room_unknown") : first.room
        content.body = L10n.format("notif_daily_text_first", first.courseName, firstTime, firstRoom)
        content.sound = .default
    }

    /// ← getCourseStartTime(course, table)
    static func courseStartTime(_ course: CourseEntity, _ table: TimeTableEntity) -> String {
        if course.ownTime && !course.startTime.isEmpty { return course.startTime }
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        guard let node = nodes.first(where: { $0.node == course.startNode }) else { return "" }
        return TimeTableUtils.formatTime(node.start)
    }
}
