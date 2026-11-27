// Local course notifications, with independent before-class, daily and tomorrow gates.
// Dated deliveries carry the timetable scope and local civil date used to plan them.
// The system delivers the request without running the app; background refresh can
// refill the rolling window but is not guaranteed to execute on time.

import Foundation
import UserNotifications
// BackgroundTasks 仅 iOS 可用 (watchOS 无此 framework)。下方 BGTask 相关函数体已由
// `#if WIDGET_EXT || WATCH_APP` / `#if !WIDGET_EXT && !WATCH_APP` 守卫排除 watch 路径,
// 但 import 本身在 watchOS 编译期即失败 ("no such module 'BackgroundTasks'") → 必须同样守卫。
// CI macos-15 archive (含 #23 watch target) 实测复现并修复。
#if os(iOS)
import BackgroundTasks
#endif

/// Keep an entire scheduling operation exclusive while its I/O suspends. An
/// actor alone would allow another operation to enter during each await.
private actor NotificationScheduleGate {
    private var occupied = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func perform(_ operation: () async -> Void) async {
        if occupied {
            await withCheckedContinuation { waiters.append($0) }
        } else {
            occupied = true
        }
        await operation()
        if waiters.isEmpty {
            occupied = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

final class NotificationScheduler {
    static let shared = NotificationScheduler()

    // ← companion object 常量
    static let CHANNEL_DAILY = "sleepy_daily"
    static let CHANNEL_BEFORE_CLASS = "sleepy_before_class"
    static let CHANNEL_FLUID = "sleepy_fluid_v2"

    // Notification identifiers(= 原 request codes 语义:按 id 撤销)
    static let NOTIFY_DAILY = "sleepy_daily_1001"
    static let NOTIFY_TOMORROW_DAILY = "sleepy_daily_1002"
    static let NOTIFY_BEFORE_CLASS_PREFIX = "sleepy_bc_2000_"  // + tableId_courseId_startEpoch
    static let NOTIFY_RESYNC = "sleepy_resync_0002"            // legacy identifier, cleanup only
    /// ← NOTIFY_TABLE_SUMMARY_BASE = 5000: 多表开启时每日/明日摘要按 tableId 分配独立 ID
    /// (base + tableId*2, 次日预告 +1), iOS 侧落为字符串 "sleepy_summary_{id}"。
    static let NOTIFY_TABLE_SUMMARY_BASE = 5000
    static let NOTIFY_SUMMARY_PREFIX = "sleepy_summary_"

    /// BGAppRefreshTask 标识 — 每日窗口重同步 + 摘要内容刷新的系统兜底。
    static let BG_RESYNC_TASK_ID = "sleepy.alarm.daily.resync"

    /// v1.0.62 摘要点击载荷: 绝对日历日期 "yyyy-MM-dd" (← DailyAgendaRoute.EXTRA_DATE) —
    /// delegate didReceive 据此路由到议程页, 旧通知点击不漂移到今天。
    static let KEY_USERINFO_AGENDA_DATE = "agenda_date"
    static let KEY_USERINFO_SUMMARY_TABLES = "agenda_table_ids"

    /// 课前提醒预排窗口: 今天起 7 个日历天(参照 shiguang WIDGET_SYNC_DAYS=7)
    static let BEFORE_CLASS_WINDOW_DAYS = 7
    static let DAILY_SUMMARY_WINDOW_DAYS = 7

    var repositoryProvider: (() -> ScheduleRepository?)?

    private let scheduleGate = NotificationScheduleGate()
    private let writeNotification: (UNNotificationRequest) async -> Bool
    private let loadAgenda: ((Date) async throws -> LoadedDailyAgenda)?
    private let cleanupLegacySummaries: () -> Void
    private let usesBackgroundTasks: Bool

    /// Suppress a duplicate foreground banner only while its scheduled activity is active.
    var foregroundActivityIDs: (() async -> Set<String>)?

    // MARK: - 生产实现 (协议定义在文件底部顶层 — Swift 不允许协议嵌套在类内)

    /// prefs/时钟/独立账本文件(闹钟是本机状态, 不随 sleepy_prefs 云备份迁移)。
    private final class ProdEnv: NotificationSchedulerBeforeClassEnv {
        private let ledger = UserDefaults(suiteName: "sleepy_alarm_ledger")
        func isReminderEnabled() -> Bool { AppPrefs.shared.isReminderEnabled() }
        func isDailyReminderEnabled() -> Bool { AppPrefs.shared.isDailyReminderEnabled() }
        func isTodayReminderEnabled() -> Bool { AppPrefs.shared.isTodayReminderEnabled() }
        func isTomorrowReminderEnabled() -> Bool { AppPrefs.shared.isTomorrowReminderEnabled() }
        func dailyReminderTime() -> String { AppPrefs.shared.getDailyReminderTime() }
        func tomorrowReminderTime() -> String { AppPrefs.shared.getTomorrowReminderTime() }
        func isBeforeClassEnabled() -> Bool {
            AppPrefs.shared.isReminderEnabled() && AppPrefs.shared.isBeforeClassEnabled()
                && AppPrefs.shared.isBeforeClassBannerEnabled()
        }
        func beforeClassMinutes() -> Int { AppPrefs.shared.getBeforeClassMinutes() }
        func nowEpochMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
        func todayDate() -> Date { Date() }
        func notificationTimeZone() -> TimeZone { Calendar.autoupdatingCurrent.timeZone }
        func loadArmedIds() -> Set<String> {
            guard let raw = ledger?.stringArray(forKey: "before_class_armed_ids") else { return [] }
            return Set(raw)
        }
        func saveArmedIds(_ ids: Set<String>) {
            ledger?.set(Array(ids), forKey: "before_class_armed_ids")
        }
        func loadDailySummaryIds(isTomorrowPreview: Bool) -> Set<String> {
            guard let raw = ledger?.stringArray(forKey: Self.dailySummaryKey(isTomorrowPreview: isTomorrowPreview)) else { return [] }
            return Set(raw)
        }
        func saveDailySummaryIds(_ ids: Set<String>, isTomorrowPreview: Bool) {
            ledger?.set(Array(ids), forKey: Self.dailySummaryKey(isTomorrowPreview: isTomorrowPreview))
        }
        private static func dailySummaryKey(isTomorrowPreview: Bool) -> String {
            isTomorrowPreview ? "daily_summary_ids_tomorrow" : "daily_summary_ids_today"
        }
    }

    private final class ProdDataSource: NotificationSchedulerBeforeClassDataSource {
        func resolveCurrentTable() -> TimeTableEntity? {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { return nil }
            return WidgetTableResolver.resolveCurrentTable(repo)
        }
        func resolveReminderTables() throws -> [TimeTableEntity] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { throw CourseReminderLoadError.unavailable }
            return try repo.getReminderTables().filter(\.reminderEnabled)
        }
        func boundPeriodTable(for table: TimeTableEntity) throws -> PeriodTableEntity? {
            guard let id = table.periodTableId else { return nil }
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { throw CourseReminderLoadError.unavailable }
            return try repo.getPeriodTable(id)
        }
        func coursesForDay(tableId: Int64, dayOfWeek: Int) throws -> [CourseEntity] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { throw CourseReminderLoadError.unavailable }
            return try repo.getCoursesByDay(tableId, day: dayOfWeek)
        }
        func coursesOn(table: TimeTableEntity, date: Date) throws -> [CourseEntity] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { throw CourseReminderLoadError.unavailable }
            return CourseOccurrences.coursesForDate(date, startDate: table.startDate, maxWeek: table.maxWeek,
                courses: try repo.getCourses(table.id), transfers: HolidayTransferHelper.transfers(for: table.id))
        }
        func allCourseIds() -> [Int64] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { return [] }
            let tables = (try? repo.getAllTables()) ?? []
            var ids: [Int64] = []
            for t in tables {
                ids += ((try? repo.getCourses(t.id)) ?? []).map { $0.id }
            }
            return ids
        }
        /// v1.0.62: effectiveDayOfWeek(正向查遗留) → courseDateForDate(反向查取课语义)
        func courseDateForDate(tableId: Int64?, date: Date) -> Date? {
            return HolidayTransferHelper.courseDateForDate(tableId, date)
        }
        func allowsReminder(tableId: Int64, date: Date) async -> Bool {
            return await HolidayReminderPolicyAdapter.decide(date: date, tableId: tableId).allowReminder
        }
    }

    private final class ProdAlarmPort: NotificationSchedulerBeforeClassAlarmPort {
        private let timeZoneProvider: () -> TimeZone

        init(timeZoneProvider: @escaping () -> TimeZone = { Calendar.autoupdatingCurrent.timeZone }) {
            self.timeZoneProvider = timeZoneProvider
        }

        private static func makeContent(extras: [String: Any?]) -> (content: UNMutableNotificationContent, tableId: Int64?, reminderDate: String?) {
            let content = UNMutableNotificationContent()
            let courseName = extras["courseName"] as? String ?? ""
            let room = (extras["room"] as? String) ?? ""
            let startTime = (extras["startTime"] as? String) ?? ""
            let roomStr = room.isEmpty ? L10n.t("notif_room_unknown") : room
            content.title = courseName
            var body = L10n.format(
                "notif_before_class_compact",
                startTime.trimmingCharacters(in: .whitespaces).isEmpty
                    ? L10n.t("agenda_time_unknown") : startTime,
                roomStr)
            if let source = extras["sourceLabel"] as? String {
                body += "\u{3014}\(source)\u{3015}"
            }
            content.body = body
            content.sound = .default
            let tableId = extras["tableId"] as? Int64
            let reminderDate = extras["reminderDate"] as? String
            var info: [String: Any] = [:]
            if let tableId { info["tableId"] = tableId }
            if let reminderDate { info["reminderDate"] = reminderDate }
            content.userInfo = info
            return (content, tableId, reminderDate)
        }

        func setExact(id: String, epochMs: Int64, extras: [String: Any?]) async -> Bool {
            // Notification and ActivityKit permission are independent. Only
            // schedule this channel when explicitly enabled and authorized.
            guard AppPrefs.shared.isBeforeClassBannerEnabled() else { return false }
            let permission = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
            #if os(watchOS)
            guard permission == .authorized || permission == .provisional else { return false }
            #else
            guard permission == .authorized || permission == .provisional || permission == .ephemeral else { return false }
            #endif
            let content = Self.makeContent(extras: extras).content
            let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
            let comps = CourseReminderOccurrence.notificationDateComponents(for: date, timeZone: timeZoneProvider())
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
            do {
                try await UNUserNotificationCenter.current().add(req)
                return true
            } catch { return false }
        }
        func pendingIdentifiers() async -> Set<String> {
            Set(await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier))
        }
        func pendingRequestMatches(id: String, fireEpochMs: Int64, timeZone: TimeZone, extras: [String: Any?]) async -> Bool {
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            guard let existing = pending.first(where: { $0.identifier == id }),
                  let trigger = existing.trigger as? UNCalendarNotificationTrigger,
                  !trigger.repeats else { return false }
            let expected = Self.makeContent(extras: extras)
            let existingTable = (existing.content.userInfo["tableId"] as? Int64)
                ?? (existing.content.userInfo["tableId"] as? NSNumber)?.int64Value
            let existingDate = existing.content.userInfo["reminderDate"] as? String
            guard existing.content.title == expected.content.title,
                  existing.content.body == expected.content.body,
                  existingTable == expected.tableId,
                  existingDate == expected.reminderDate else { return false }
            let expectedComps = CourseReminderOccurrence.notificationDateComponents(
                for: Date(timeIntervalSince1970: TimeInterval(fireEpochMs) / 1000),
                timeZone: timeZone
            )
            let existingZone = trigger.dateComponents.timeZone?.identifier ?? trigger.dateComponents.calendar?.timeZone.identifier
            return existingZone == timeZone.identifier
                && trigger.dateComponents.year == expectedComps.year
                && trigger.dateComponents.month == expectedComps.month
                && trigger.dateComponents.day == expectedComps.day
                && trigger.dateComponents.hour == expectedComps.hour
                && trigger.dateComponents.minute == expectedComps.minute
                && trigger.dateComponents.second == expectedComps.second
        }
        func availableSlots() async -> Int {
            let pending = await pendingIdentifiers()
            let summaries = pending.filter {
                NotificationScheduler.isTodaySummaryIdentifier($0) || NotificationScheduler.isTomorrowSummaryIdentifier($0)
            }.count
            let other = pending.filter { !$0.hasPrefix(NotificationScheduler.NOTIFY_BEFORE_CLASS_PREFIX) }.count - summaries
            let prefs = AppPrefs.shared
            let summaryChannels = prefs.isReminderEnabled() && prefs.isDailyReminderEnabled()
                ? [prefs.isTodayReminderEnabled(), prefs.isTomorrowReminderEnabled()].filter { $0 }.count : 0
            let reservedSummaries = max(summaries, summaryChannels * NotificationScheduler.DAILY_SUMMARY_WINDOW_DAYS)
            // App policy: leave four slots free; this is not an OS guarantee.
            return max(0, 60 - other - reservedSummaries)
        }
        func cancel(id: String) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
    }

    private let env: NotificationSchedulerBeforeClassEnv
    private let dataSource: NotificationSchedulerBeforeClassDataSource
    private let alarmPort: NotificationSchedulerBeforeClassAlarmPort

    init() {
        let env = ProdEnv()
        self.env = env
        self.dataSource = ProdDataSource()
        self.alarmPort = ProdAlarmPort { env.notificationTimeZone() }
        self.writeNotification = Self.addNotification
        self.loadAgenda = nil
        self.cleanupLegacySummaries = { cleanupLegacyDailySummaryNotifications() }
        self.usesBackgroundTasks = true
    }

    /// 测试构造器 — 注入 fake 端口。
    init(env: NotificationSchedulerBeforeClassEnv, dataSource: NotificationSchedulerBeforeClassDataSource,
         alarmPort: NotificationSchedulerBeforeClassAlarmPort,
         writeNotification: ((UNNotificationRequest) async -> Bool)? = nil,
         loadAgenda: ((Date) async throws -> LoadedDailyAgenda)? = nil) {
        self.env = env
        self.dataSource = dataSource
        self.alarmPort = alarmPort
        self.writeNotification = writeNotification ?? Self.addNotification
        self.loadAgenda = loadAgenda
        self.cleanupLegacySummaries = {}
        self.usesBackgroundTasks = false
    }

    private static func addNotification(_ request: UNNotificationRequest) async -> Bool {
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch { return false }
    }

    // ==================== scheduleAll ← ====================

    @discardableResult
    func scheduleAll() -> Task<Void, Never> {
        // iOS 无 NotificationChannel; 原 createChannels 在此处的隐式
        // requestAuthorization 已按权限政策摘除 —— 全 app 唯一申请点 =
        // ReminderScreen master 开关(用户显式操作), denied 后走系统设置引导。
        if usesBackgroundTasks {
            Self.registerDailyResyncTask()
            submitDailyResyncTask()
        }
        return Task {
            await scheduleGate.perform { await self.scheduleAllLocked() }
        }
    }

    private func scheduleAllLocked() async {
        // Remove the date-less repeating requests before any async data load.
        alarmPort.cancel(id: Self.NOTIFY_DAILY)
        alarmPort.cancel(id: Self.NOTIFY_TOMORROW_DAILY)
        guard env.isReminderEnabled() else {
            await cancelDailySummariesLocked()
            await cancelBeforeClassLocked()
            return
        }

        if env.isBeforeClassEnabled() {
            if usesBackgroundTasks { scheduleBeforeClassDailyResync() }
            // Release any course slots needed by the date-bound summaries.
            await resyncBeforeClassLocked()
        } else {
            await cancelBeforeClassLocked()
        }
        await refreshDailySummariesLocked(isTomorrowPreview: false)
        await refreshDailySummariesLocked(isTomorrowPreview: true)
    }

    func cancelAll() async {
        await scheduleGate.perform {
            await self.cancelDailySummariesLocked()
            await self.cancelBeforeClassLocked()
        }
    }

    private func cancelDailySummariesLocked() async {
        let pending = await alarmPort.pendingIdentifiers()
        for tomorrow in [false, true] {
            for id in summaryIdentifiersToReconcile(pending: pending, isTomorrowPreview: tomorrow) { alarmPort.cancel(id: id) }
            env.saveDailySummaryIds([], isTomorrowPreview: tomorrow)
        }
        cleanupLegacySummaries()
    }

    private func cancelBeforeClassLocked() async {
        alarmPort.cancel(id: Self.NOTIFY_RESYNC)
        await cancelBeforeClassCourseAlarmsLocked()
    }

    private func cancelBeforeClassCourseAlarmsLocked() async {
        // 账本覆盖已删课程/已换掉的课表; 现存课程 id 覆盖账本上线前旧版本排下的闹钟
        let courseIds = dataSource.allCourseIds()
        let armed = env.loadArmedIds()
        var all = armed.union(await alarmPort.pendingIdentifiers().filter { $0.hasPrefix(Self.NOTIFY_BEFORE_CLASS_PREFIX) })
        for id in courseIds {
            all.insert(Self.NOTIFY_BEFORE_CLASS_PREFIX + String(id))
        }
        for id in all {
            alarmPort.cancel(id: id)
        }
        env.saveArmedIds([])
    }

    /// 取消指定课程 id 的课前通知(ScheduleRepository.deleteTable 调 — 孤儿清理)。
    func cancelCourseAlarms(courseIds: [Int64]) {
        Task {
            await scheduleGate.perform {
                let courseIDs = Set(courseIds)
                let owned = self.env.loadArmedIds().union(await self.alarmPort.pendingIdentifiers())
                    .filter { $0.hasPrefix(Self.NOTIFY_BEFORE_CLASS_PREFIX) }
                var cancelled = Set<String>()
                for id in owned {
                    let parts = id.dropFirst(Self.NOTIFY_BEFORE_CLASS_PREFIX.count).split(separator: "_")
                    let course = parts.count == 1 ? Int64(parts[0]) : parts.count == 3 ? Int64(parts[1]) : nil
                    if let course, courseIDs.contains(course) {
                        self.alarmPort.cancel(id: id)
                        cancelled.insert(id)
                    }
                }
                self.env.saveArmedIds(self.env.loadArmedIds().subtracting(cancelled))
            }
        }
    }

    // ==================== Daily ====================

    /// 摘要 id ← sendScheduleSummary 扇出号段: NOTIFY_TABLE_SUMMARY_BASE + tableId*2
    /// (+1 次日), iOS 字符串化 = "sleepy_summary_{n}"。单表/无课沿用主 id (1001/1002)。
    static func summaryIdentifier(tableId: Int64, isTomorrowPreview: Bool) -> String {
        let numeric = NOTIFY_TABLE_SUMMARY_BASE + Int(tableId * 2 + (isTomorrowPreview ? 1 : 0))
        return NOTIFY_SUMMARY_PREFIX + String(numeric)
    }

    /// 判定一个通知 id 属于次日预告链路 (1002 主 id 或扇出奇号) — delegate 到货子闸重查用。
    static func isTomorrowSummaryIdentifier(_ identifier: String) -> Bool {
        if identifier == NOTIFY_TOMORROW_DAILY || identifier.hasPrefix(NOTIFY_TOMORROW_DAILY + "_") { return true }
        guard identifier.hasPrefix(NOTIFY_SUMMARY_PREFIX),
              let n = Int(identifier.dropFirst(NOTIFY_SUMMARY_PREFIX.count)),
              n >= NOTIFY_TABLE_SUMMARY_BASE else { return false }
        return (n - NOTIFY_TABLE_SUMMARY_BASE) % 2 == 1
    }

    /// 判定一个通知 id 属于当日摘要链路 (1001 主 id 或扇出偶号)。
    static func isTodaySummaryIdentifier(_ identifier: String) -> Bool {
        if identifier == NOTIFY_DAILY || identifier.hasPrefix(NOTIFY_DAILY + "_") { return true }
        guard identifier.hasPrefix(NOTIFY_SUMMARY_PREFIX),
              let n = Int(identifier.dropFirst(NOTIFY_SUMMARY_PREFIX.count)),
              n >= NOTIFY_TABLE_SUMMARY_BASE else { return false }
        return (n - NOTIFY_TABLE_SUMMARY_BASE) % 2 == 0
    }

    /// Remove old repeating requests and reconcile the now date-specific set.
    /// A local notification cannot wake an inactive app to replace its content.
    func refreshDailySummaries(isTomorrowPreview: Bool) async {
        await scheduleGate.perform {
            await self.refreshDailySummariesLocked(isTomorrowPreview: isTomorrowPreview)
        }
    }

    private func summaryIdentifiersToReconcile(pending: Set<String>, isTomorrowPreview: Bool) -> Set<String> {
        let predicate = isTomorrowPreview ? Self.isTomorrowSummaryIdentifier : Self.isTodaySummaryIdentifier
        let legacyID = isTomorrowPreview ? Self.NOTIFY_TOMORROW_DAILY : Self.NOTIFY_DAILY
        var ids = pending.filter(predicate).union(env.loadDailySummaryIds(isTomorrowPreview: isTomorrowPreview))
        ids.insert(legacyID)
        return ids
    }

    private var now: Date { Date(timeIntervalSince1970: Double(env.nowEpochMs()) / 1000) }

    private func refreshDailySummariesLocked(isTomorrowPreview: Bool) async {
        let pending = await alarmPort.pendingIdentifiers()
        let previous = summaryIdentifiersToReconcile(pending: pending, isTomorrowPreview: isTomorrowPreview)
        guard dailySummaryAllowed(isTomorrowPreview: isTomorrowPreview) else {
            for id in previous { alarmPort.cancel(id: id) }
            env.saveDailySummaryIds([], isTomorrowPreview: isTomorrowPreview)
            return
        }
        cleanupLegacySummaries()
        let prefix = isTomorrowPreview ? Self.NOTIFY_TOMORROW_DAILY : Self.NOTIFY_DAILY
        let time = isTomorrowPreview ? env.tomorrowReminderTime() : env.dailyReminderTime()
        let parts = time.split(separator: ":", omittingEmptySubsequences: false)
        let hour = min(max(parts.first.flatMap { Int($0) } ?? (isTomorrowPreview ? 22 : 7), 0), 23)
        let minute = min(max(parts.dropFirst().first.flatMap { Int($0) } ?? 0, 0), 59)
        let zone = env.notificationTimeZone()
        let clock = CourseReminderCalendar(timeZone: zone)
        let now = self.now
        let slots = clock.days(startingAt: now, count: Self.DAILY_SUMMARY_WINDOW_DAYS).compactMap { day
            -> (id: String, fire: Date, target: Date)? in
            guard let fire = clock.instant(on: day, wallSeconds: hour * 3600 + minute * 60), fire > now else { return nil }
            guard let target = CourseOccurrences.calendar.date(byAdding: .day, value: isTomorrowPreview ? 1 : 0,
                                                                to: day) else { return nil }
            return (prefix + "_" + HolidayTransferOps.dayKey(day), fire, target)
        }
        let desired = Set(slots.map(\.id))
        for id in previous.subtracting(desired) { alarmPort.cancel(id: id) }

        var scheduledIds = Set<String>()
        for slot in slots {
            guard dailySummaryAllowed(isTomorrowPreview: isTomorrowPreview) else { break }
            let loaded: LoadedDailyAgenda
            do {
                if let loadAgenda {
                    loaded = try await loadAgenda(slot.target)
                } else if let repo = repositoryProvider?() {
                    loaded = try await loadDailyAgenda(repository: repo, targetDate: slot.target)
                } else {
                    throw CourseReminderLoadError.unavailable
                }
            } catch {
                // A failed lookup must not turn a stale snapshot or a placeholder into a banner.
                if pending.contains(slot.id) { alarmPort.cancel(id: slot.id) }
                continue
            }
            guard dailySummaryAllowed(isTomorrowPreview: isTomorrowPreview) else { break }
            if loaded.suppressed || slot.fire <= self.now {
                if pending.contains(slot.id) { alarmPort.cancel(id: slot.id) }
                continue
            }
            let written = await writeNotification(Self.summaryRequest(agenda: loaded.agenda, identifier: slot.id,
                fireDate: slot.fire, targetDate: slot.target, isTomorrowPreview: isTomorrowPreview, timeZone: zone))
            if written {
                scheduledIds.insert(slot.id)
            } else if pending.contains(slot.id) {
                alarmPort.cancel(id: slot.id)
            }
        }
        // An alarm write can suspend while the user turns off a reminder.
        if !dailySummaryAllowed(isTomorrowPreview: isTomorrowPreview) {
            for id in desired { alarmPort.cancel(id: id) }
            env.saveDailySummaryIds([], isTomorrowPreview: isTomorrowPreview)
        } else {
            env.saveDailySummaryIds(scheduledIds, isTomorrowPreview: isTomorrowPreview)
        }
    }

    private static func summaryRequest(agenda: DailyAgenda, identifier: String, fireDate: Date,
                                       targetDate: Date, isTomorrowPreview: Bool,
                                       timeZone: TimeZone = Calendar.autoupdatingCurrent.timeZone) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        if agenda.items.isEmpty {
            content.title = L10n.t(isTomorrowPreview ? "notif_tomorrow_title_no_course" : "notif_daily_title_no_course")
            content.body = L10n.t(isTomorrowPreview ? "notif_tomorrow_text_no_course" : "notif_daily_text_no_course")
        } else {
            content.title = L10n.format(isTomorrowPreview ? "notif_tomorrow_title" : "notif_daily_title", agenda.items.count)
            let sources = agenda.notificationSources(unknownTable: L10n.t("agenda_table_unknown"))
            let unknownTime = L10n.t("agenda_time_unknown")
            let unknownRoom = L10n.t("notif_room_unknown")
            let (visible, remaining) = agenda.preview()
            var lines: [String] = []
            if !sources.isEmpty { lines.append(L10n.format("agenda_source_count", agenda.tableCount)) }
            lines += visible.map {
                $0.notificationLine(unknownTime: unknownTime, unknownRoom: unknownRoom, sourceLabels: sources)
            }
            if remaining > 0 { lines.append(L10n.format("agenda_more", remaining)) }
            content.body = lines.joined(separator: "\n")
        }
        content.sound = .default
        content.userInfo = [Self.KEY_USERINFO_AGENDA_DATE: HolidayTransferOps.dayKey(targetDate),
                            Self.KEY_USERINFO_SUMMARY_TABLES: agenda.sourceTables.map(\.id)]
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: CourseReminderOccurrence.notificationDateComponents(for: fireDate, timeZone: timeZone), repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func dailySummaryAllowed(isTomorrowPreview: Bool) -> Bool {
        guard env.isReminderEnabled(), env.isDailyReminderEnabled() else { return false }
        return isTomorrowPreview ? env.isTomorrowReminderEnabled() : env.isTodayReminderEnabled()
    }

    func dailySummaryDeliveryAllowed(_ request: UNNotificationRequest, isTomorrowPreview: Bool) -> Bool {
        let prefix = isTomorrowPreview ? Self.NOTIFY_TOMORROW_DAILY : Self.NOTIFY_DAILY
        guard dailySummaryAllowed(isTomorrowPreview: isTomorrowPreview), request.identifier.hasPrefix(prefix + "_"),
              let trigger = request.trigger as? UNCalendarNotificationTrigger, !trigger.repeats,
              let fire = trigger.dateComponents.date,
              let day = CourseReminderCalendar(timeZone: env.notificationTimeZone()).civilDay(containing: fire),
              let target = CourseOccurrences.calendar.date(byAdding: .day, value: isTomorrowPreview ? 1 : 0, to: day),
              request.identifier == prefix + "_" + HolidayTransferOps.dayKey(day),
              request.content.userInfo[Self.KEY_USERINFO_AGENDA_DATE] as? String == HolidayTransferOps.dayKey(target),
              let scope = request.content.userInfo[Self.KEY_USERINFO_SUMMARY_TABLES] as? [Int64],
              let tables = try? dataSource.resolveReminderTables() else { return false }
        return Set(scope) == Set(tables.filter(\.reminderEnabled).map(\.id))
    }

    // ==================== Before-class 7 天幂等重同步 ====================

    /// Local notifications do not wake a suspended app to run a delegate.
    /// Remove the obsolete midnight anchor; BG refresh is only opportunistic.
    private func scheduleBeforeClassDailyResync() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.NOTIFY_RESYNC])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.NOTIFY_RESYNC])
    }

    /// 兼容入口 — 语义已升级为「未来 7 天全窗口重同步」(幂等)。
    func scheduleTodayBeforeClassAlarms() async {
        await scheduleNext7DaysExactAlarms()
    }

    /// 预排未来 7 个日历天(含今天)的课前通知, 幂等重同步。
    /// 每个课次的 id 包含课表、课程与开始时刻；同课次由系统原地替换。
    /// 账本只记录接受成功或仍在系统队列中的请求。
    /// 学期范围外的天跳过(防呆: currentWeek 钳制会误匹配第 1 周的课)。
    func scheduleNext7DaysExactAlarms() async {
        await scheduleGate.perform { await self.resyncBeforeClassLocked() }
    }

    /// Shared dated input for both reminder channels. Propagate database failures
    /// so a temporary read error never cancels already accepted reminders.
    func upcomingOccurrences() async throws -> [CourseReminderOccurrence] {
        try await upcomingOccurrences(tables: dataSource.resolveReminderTables(),
            calendar: CourseReminderCalendar(timeZone: env.notificationTimeZone()))
    }

    private func upcomingOccurrences(tables: [TimeTableEntity], calendar: CourseReminderCalendar) async throws -> [CourseReminderOccurrence] {
        try await CourseReminderLoader.load(tables: tables, dataSource: dataSource, from: env.todayDate(),
            days: Self.BEFORE_CLASS_WINDOW_DAYS, calendar: calendar)
    }

    private func resyncBeforeClassLocked() async {
        let previous = env.loadArmedIds()
        let pending = await alarmPort.pendingIdentifiers()
        let owned = pending.filter { $0.hasPrefix(Self.NOTIFY_BEFORE_CLASS_PREFIX) }
        guard env.isReminderEnabled(), env.isBeforeClassEnabled() else {
            for id in previous.union(owned) { alarmPort.cancel(id: id) }
            env.saveArmedIds([])
            return
        }
        let calendar = CourseReminderCalendar(timeZone: env.notificationTimeZone())
        let tables: [TimeTableEntity]
        let occurrences: [CourseReminderOccurrence]
        do {
            tables = try dataSource.resolveReminderTables().filter(\.reminderEnabled)
            occurrences = try await upcomingOccurrences(tables: tables, calendar: calendar)
        } catch { return } // Keep the system's existing requests on a read failure.
        let labels = notificationSourceLabels(tables, L10n.t("agenda_table_unknown"))
        let nowEpoch = env.nowEpochMs()
        let lead = env.beforeClassMinutes()
        let futureCandidates = occurrences.filter {
            Int64($0.reminderDate(leadMinutes: lead).timeIntervalSince1970 * 1000) > nowEpoch
        }
        let candidateIDs = Set(futureCandidates.map(\.notificationIdentifier))
        // Release obsolete slots before counting capacity.
        for id in previous.union(owned) where !candidateIDs.contains(id) { alarmPort.cancel(id: id) }
        let capacity = await alarmPort.availableSlots()
        let desired = futureCandidates.prefix(max(0, capacity))
        guard env.isReminderEnabled(), env.isBeforeClassEnabled() else {
            await cancelBeforeClassLocked()
            return
        }
        let desiredIDs = Set(desired.map(\.notificationIdentifier))
        var accepted = Set<String>()
        // Release any candidate overflow slots while keeping active desired slots intact.
        for id in previous.union(owned) where candidateIDs.contains(id) && !desiredIDs.contains(id) {
            alarmPort.cancel(id: id)
        }
        for item in desired {
            guard env.isReminderEnabled(), env.isBeforeClassEnabled() else { break }
            guard let courseDay = calendar.civilDay(containing: item.start) else { continue }
            let fire = item.reminderDate(leadMinutes: lead)
            let fireEpoch = Int64(fire.timeIntervalSince1970 * 1000)
            guard fireEpoch > env.nowEpochMs() else {
                if owned.contains(item.notificationIdentifier) { alarmPort.cancel(id: item.notificationIdentifier) }
                continue
            }
            let extras: [String: Any?] = [
                "courseName": item.name, "room": item.room, "teacher": item.teacher,
                "startTime": calendar.timeText(for: item.start),
                "endTime": calendar.timeText(for: item.end),
                "startNode": item.startNode, "notifyEpoch": fireEpoch,
                "classEpoch": Int64(item.start.timeIntervalSince1970 * 1000),
                "tableId": item.tableId, "reminderDate": HolidayTransferOps.dayKey(courseDay),
                "sourceLabel": labels[item.tableId]
            ]
            if await alarmPort.setExact(id: item.notificationIdentifier, epochMs: fireEpoch, extras: extras) {
                accepted.insert(item.notificationIdentifier)
            } else if pending.contains(item.notificationIdentifier) {
                if await alarmPort.pendingRequestMatches(
                    id: item.notificationIdentifier, fireEpochMs: fireEpoch,
                    timeZone: env.notificationTimeZone(), extras: extras
                ) {
                    accepted.insert(item.notificationIdentifier)
                } else {
                    alarmPort.cancel(id: item.notificationIdentifier)
                }
            }
        }
        guard env.isReminderEnabled(), env.isBeforeClassEnabled() else {
            for id in desiredIDs { alarmPort.cancel(id: id) }
            env.saveArmedIds([])
            return
        }
        env.saveArmedIds(accepted)
    }

    // v1.0.62: semesterInRange(table:date:) 已删 — 学期判定并入 collectTableSlots
    // 的反向查分支(改用 sourceDate 判定, ← 原 collectTableSlots 同款内联)。
    // v1.0.62: courseStartTime(course:table:) 已删 — 摘要改单条聚合后无消费方
    // (原版本 v1.0.62 同步删除 getCourseStartTime)。

    // ==================== Channels / 权限 ====================
    // iOS 无 NotificationChannel。原 createChannels 携带的隐式
    // POST_NOTIFICATIONS 申请(requestAuthorization)不再随调度触发 ——
    // 权限申请唯一入口 = ReminderScreen master 开关(用户显式操作),
    // denied 后由 UI 引导手动去系统设置; 本调度器只消费已授权结果。

    // ==================== 到货重校验 / 每日窗口兜底 ====================

    /// 课前通知发送时重校验 ← BeforeClassNotifyReceiver.onReceive (v1.0.61):
    /// 排期后到到货前可能 表被删 / 该表提醒被关 / 提醒Date落在新加的放假日 → 丢弃。
    /// v1.0.61 已删除「必须是当前课表」规则, 只要求该表仍存在且 reminderEnabled。
    /// 同时复查 banner 闸 (排期后才关 banner 的残留通知走这里)。
    func beforeClassDeliveryAllowed(userInfo: [AnyHashable: Any]) async -> Bool {
        guard env.isReminderEnabled(), env.isBeforeClassEnabled(),
              let tableId = (userInfo["tableId"] as? Int64) ?? (userInfo["tableId"] as? NSNumber)?.int64Value,
              let dayKey = userInfo["reminderDate"] as? String,
              let day = CourseOccurrences.parseDate(dayKey),
              let tables = try? dataSource.resolveReminderTables(),
              tables.contains(where: { $0.id == tableId && $0.reminderEnabled }) else { return false }
        // No fallback to a widget's table or the date when the banner arrives.
        let allowed = await dataSource.allowsReminder(tableId: tableId, date: day)
        return allowed && env.isReminderEnabled() && env.isBeforeClassEnabled()
    }

    /// 到货/BGTask 每日窗口入口 — 等价 原版本 00:05 BeforeClassScheduleReceiver +
    /// 每日接收器每次现算语义: 课前链路开时重同步 7 天窗口, 每日链路开时重算摘要内容。
    /// delegate 收到 sleepy_resync / BGAppRefreshTask handler 都调此函数。
    func handleDailyResync() async {
        await scheduleGate.perform { await self.scheduleAllLocked() }
    }

    /// Register opportunistic BG refresh. Local notifications do not wake the app.
    /// 必须在 willFinishLaunching 早期调用 (BGTaskScheduler 注册窗口限制), 归集成者接线。
    private static var bgTaskRegistered = false
    static func registerDailyResyncTask() {
        // BGTaskScheduler.register 在 app extension 内不可用(系统只允许主 App 注册
        // launch handler); widget 进程不接 BGTask, 注册归 app 侧 willFinishLaunching。
        // watchOS 进程同理不接 (BGTaskScheduler API 在 watchOS 不可用);
        // 通知载体不能提供静默唤醒；同步依赖应用执行机会。
        #if WIDGET_EXT || WATCH_APP
        return
        #else
        guard #available(iOS 15.0, *), !bgTaskRegistered else { return }
        bgTaskRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BG_RESYNC_TASK_ID, using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            NotificationScheduler.handleDailyResyncBackground(refreshTask)
        }
        #endif
    }

    #if !WIDGET_EXT && !WATCH_APP
    private static func handleDailyResyncBackground(_ task: BGAppRefreshTask) {
        NotificationScheduler.shared.submitDailyResyncTask()
        let work = Task {
            await NotificationScheduler.shared.handleDailyResync()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
    #endif

    /// Request opportunistic refresh no earlier than the next 00:05; no execution deadline is promised.
    func submitDailyResyncTask() {
        // watchOS/widget 进程无 BGTask 通道 (见 registerDailyResyncTask 注释)
        #if WIDGET_EXT || WATCH_APP
        return
        #else
        guard #available(iOS 15.0, *) else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.BG_RESYNC_TASK_ID)
        var comps = DateComponents()
        comps.hour = 0
        comps.minute = 5
        let todays = Calendar.autoupdatingCurrent.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
        request.earliestBeginDate = todays
        try? BGTaskScheduler.shared.submit(request)
        #endif
    }
}

// MARK: - 可注入端口(JVM 单测接缝, 顶层 — Swift 不允许协议嵌套在类内)

/// 课前通知环境值 — prefs/时钟/账本读取接缝。
protocol NotificationSchedulerBeforeClassEnv {
    func isReminderEnabled() -> Bool
    func isDailyReminderEnabled() -> Bool
    func isTodayReminderEnabled() -> Bool
    func isTomorrowReminderEnabled() -> Bool
    func dailyReminderTime() -> String
    func tomorrowReminderTime() -> String
    func isBeforeClassEnabled() -> Bool
    func beforeClassMinutes() -> Int
    func nowEpochMs() -> Int64
    func todayDate() -> Date
    func notificationTimeZone() -> TimeZone
    func loadArmedIds() -> Set<String>
    func saveArmedIds(_ ids: Set<String>)
    /// v1.0.61 摘要扇出账本 — 上次贴出的多表摘要 id 集合, 分当日/次日两套。
    func loadDailySummaryIds(isTomorrowPreview: Bool) -> Set<String>
    func saveDailySummaryIds(_ ids: Set<String>, isTomorrowPreview: Bool)
}

/// 默认实现回退空账本 — 兼容未升级的旧测试替身 (接口默认方法同款兼容策略)。
extension NotificationSchedulerBeforeClassEnv {
    func notificationTimeZone() -> TimeZone { .current }
    func isReminderEnabled() -> Bool { true }
    func isDailyReminderEnabled() -> Bool { false }
    func isTodayReminderEnabled() -> Bool { true }
    func isTomorrowReminderEnabled() -> Bool { true }
    func dailyReminderTime() -> String { "07:00" }
    func tomorrowReminderTime() -> String { "22:00" }
    func loadDailySummaryIds(isTomorrowPreview: Bool) -> Set<String> { [] }
    func saveDailySummaryIds(_ ids: Set<String>, isTomorrowPreview: Bool) {}
}

/// 课前通知数据源 — 课表/课程查询接缝。
protocol NotificationSchedulerBeforeClassDataSource {
    func resolveCurrentTable() -> TimeTableEntity?
    /// 每表独立提醒: 返回开启提醒的课表。默认实现回退到当前课表,
    /// 兼容旧测试替身 (BeforeClassDataSource.resolveReminderTables 默认分支)。
    func resolveReminderTables() throws -> [TimeTableEntity]
    func boundPeriodTable(for table: TimeTableEntity) throws -> PeriodTableEntity?
    func coursesForDay(tableId: Int64, dayOfWeek: Int) throws -> [CourseEntity]
    func coursesOn(table: TimeTableEntity, date: Date) throws -> [CourseEntity]
    func allCourseIds() -> [Int64]
    /// v1.0.62 取课语义反向查 (← BeforeClassDataSource.courseDateForDate):
    /// 补班日=sourceDate(上被挪走那天的课), 放假日=nil(无课), 未映射=原日期。
    /// (替换 v1.0.60 的 effectiveDayOfWeek 正向查遗留语义 — 实际取课一律走反向查,
    /// 保留来源周次; 列映射兼容口径归 HolidayTransferHelper.effectiveDayOfWeek)
    func courseDateForDate(tableId: Int64?, date: Date) -> Date?
    func allowsReminder(tableId: Int64, date: Date) async -> Bool
}

extension NotificationSchedulerBeforeClassDataSource {
    func resolveReminderTables() -> [TimeTableEntity] {
        guard let t = resolveCurrentTable() else { return [] }
        return t.reminderEnabled ? [t] : []
    }

    func boundPeriodTable(for table: TimeTableEntity) throws -> PeriodTableEntity? { nil }

    func coursesOn(table: TimeTableEntity, date: Date) throws -> [CourseEntity] {
        let key = HolidayTransferOps.dayKey(date)
        let fixed = try coursesForDay(tableId: table.id, dayOfWeek: CourseOccurrences.day(date))
            .filter { $0.fixedDate == key }
        guard let source = courseDateForDate(tableId: table.id, date: date),
              let week = CourseOccurrences.week(startDate: table.startDate, date: source), week <= table.maxWeek else {
            return fixed
        }
        let recurring = try coursesForDay(tableId: table.id, dayOfWeek: CourseOccurrences.day(source))
            .filter { $0.fixedDate == nil && $0.inWeek(week) }
        return fixed + recurring
    }
}

/// 课前通知落地端口 — UNUserNotificationCenter 接缝。
protocol NotificationSchedulerBeforeClassAlarmPort {
    func setExact(id: String, epochMs: Int64, extras: [String: Any?]) async -> Bool
    func pendingIdentifiers() async -> Set<String>
    func availableSlots() async -> Int
    func cancel(id: String)
    func pendingRequestMatches(id: String, fireEpochMs: Int64, timeZone: TimeZone, extras: [String: Any?]) async -> Bool
}

extension NotificationSchedulerBeforeClassAlarmPort {
    func pendingRequestMatches(id: String, fireEpochMs: Int64, timeZone: TimeZone, extras: [String: Any?]) async -> Bool {
        true
    }
}

extension NotificationSchedulerBeforeClassAlarmPort {
    func pendingIdentifiers() async -> Set<String> { [] }
    func availableSlots() async -> Int { 60 }
}

// MARK: - 到货 delegate (原版本 Receiver 的 iOS 对位; 赋值归集成者, 见 SleepyApp 接线)

/// UNUserNotificationCenterDelegate 实现 ← 三个 Receiver 的到货语义:
///  - sleepy_resync_0002 (00:05 载体) → handleDailyResync 全窗口重同步 + 摘要重算, 不展示;
///  - sleepy_bc_* (课前) → beforeClassDeliveryAllowed 重校验后决定是否展示
///    (← BeforeClassNotifyReceiver.onReceive: 表存在 + reminderEnabled + 节假日策略 + banner 闸);
///  - sleepy_daily_1001 / sleepy_summary_* → 当日/次日子闸重查 (← DailyNotifyReceiver /
///    TomorrowNotifyReceiver 的 isTodayReminderEnabled / isTomorrowReminderEnabled 重查);
///    v1.0.62: 点击(userInfo.agendaDate)路由到议程页 ← DailyAgendaActivity.pendingIntent。
/// 注册点: SleepyApp 启动时 `UNUserNotificationCenter.current().delegate = SleepyNotificationDelegate.shared`
/// (共享文件, 集成者统一接线)。
final class SleepyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SleepyNotificationDelegate()

    /// 通知点击 → 议程页的内部广播 (AppRoot onReceive 订阅; userInfo["agendaDate"] =
    /// raw "yyyy-MM-dd" 原文, 议程页侧经 DailyAgendaRoute 严格解析)。
    static let agendaOpenNotification = Notification.Name("sleepy.agenda.open")

    /// 点击议程页的待消费日期原文 (raw "yyyy-MM-dd") — Foundation 级静态:
    /// delegate 三 target 共源编译不能引用 app-only 的 DailyAgendaRoute/PendingAgendaDate;
    /// 冷启竞态兜底(系统投递 didReceive 可能早于 SwiftUI 订阅), AppRoot 消费后清空。
    static var pendingAgendaDateRaw: String? = nil

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               willPresent notification: UNNotification,
                               withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id = notification.request.identifier
        if id == NotificationScheduler.NOTIFY_RESYNC {
            // 00:05 重同步载体: 前台到货同样不展示, 立刻重同步
            Task { await NotificationScheduler.shared.handleDailyResync() }
            completionHandler([])
            return
        }
        if id.hasPrefix(NotificationScheduler.NOTIFY_BEFORE_CLASS_PREFIX) {
            Task {
                // F128 issue#1: 课前投放闸 AND 上课勿扰抑制闸 — 后者让
                // ClassDndScheduler.shouldSuppressNotification 真正有调用方。
                // watchOS: ClassDndScheduler 为 Foundation-only 已随 watch 编入;
                // isClassDndEnabled 未镜像 (手表 prefs 默认 false) = 抑制闸恒开闸,
                // Focus 真抑制只在 iPhone 生效。2026-10 watch 伴侣 App。
                let delivery = await NotificationScheduler.shared.beforeClassDeliveryAllowed(
                    userInfo: notification.request.content.userInfo)
                // F128 issue#1: `&&` 的 RHS 是 @autoclosure, 不支持嵌入 await —
                // 拆开两次 await 再组合, 否则 widget target 独立编译报
                // "'async' call in an autoclosure that does not support concurrency"。
                let suppressed = await ClassDndScheduler.shouldSuppressNotification()
                let activities = await NotificationScheduler.shared.foregroundActivityIDs?() ?? []
                completionHandler((delivery && !suppressed && !activities.contains(id)) ? [.banner, .sound] : [])
            }
            return
        }
        // Undelivered legacy repeating summaries cannot be trusted. Dated
        // summaries can present immediately; refresh the window separately.
        if NotificationScheduler.isTodaySummaryIdentifier(id) || NotificationScheduler.isTomorrowSummaryIdentifier(id) {
            let tomorrow = NotificationScheduler.isTomorrowSummaryIdentifier(id)
            let allowed = NotificationScheduler.shared.dailySummaryDeliveryAllowed(notification.request, isTomorrowPreview: tomorrow)
            completionHandler(allowed ? [.banner, .sound] : [])
            Task { await NotificationScheduler.shared.refreshDailySummaries(isTomorrowPreview: tomorrow) }
            return
        }
        completionHandler([.banner, .sound])
        return
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                               didReceive response: UNNotificationResponse,
                               withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        if id == NotificationScheduler.NOTIFY_RESYNC {
            Task { await NotificationScheduler.shared.handleDailyResync(); completionHandler() }
            return
        }
        // v1.0.62: 摘要点击 → 议程页 (← DailyAgendaActivity.pendingIntent EXTRA_DATE)。
        // agendaDate 是排期时写入的绝对日历日期; 缺省(旧版本排下的残留)不路由。
        // 双通道: pendingAgendaDateRaw 兜冷启竞态, NotificationCenter 通知驱动前台即时打开。
        if NotificationScheduler.isTodaySummaryIdentifier(id) || NotificationScheduler.isTomorrowSummaryIdentifier(id),
           let raw = response.notification.request.content.userInfo[NotificationScheduler.KEY_USERINFO_AGENDA_DATE] as? String {
            Self.pendingAgendaDateRaw = raw
            NotificationCenter.default.post(
                name: Self.agendaOpenNotification, object: nil,
                userInfo: [NotificationScheduler.KEY_USERINFO_AGENDA_DATE: raw])
        }
        completionHandler()
    }
}
