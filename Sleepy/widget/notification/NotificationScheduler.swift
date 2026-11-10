// NotificationScheduler.swift — ← CourseNotificationScheduler.kt (v1.0.62)
// 课程通知调度器 — 支持每日提醒(当日/次日分闸) + 次日预告 + 每节课前提醒(7 天幂等重同步 + 账本)。
//
// 平台映射: AlarmManager+BroadcastReceiver → UNUserNotificationCenter+UNCalendarNotificationTrigger
// 日历触发器由系统投递；应用不承诺准点或绕过系统通知设置。
//
// v1.0.62 升级 (B5 每日议程):
//  - 摘要单条聚合: 多表扇出(sleepy_summary_*) → 单条通知, 跨表同名同刻的课经
//    buildDailyAgenda 合并(来源全保留); 正文 = 首课行 + 展开多行 (← sendScheduleSummary)
//  - 取课语义反向查: DataSource.effectiveDayOfWeek → courseDateForDate
//    (补班日=sourceDate 星期, 放假日=无课; ← HolidayTransferOps.courseDateForDate)
//  - 遗留扇出清理: DailySummaryNotificationMigration (sleepy_summary_ 前缀归属)
//  - 摘要点击 → 议程页 (userInfo.agendaDate 绝对日历日期; delegate didReceive 路由)
//  - 原版本 setTimeoutAfter(每日文案午夜过期) 无 iOS 等价物 — 平台缺口, 见
//    postDailySummaries 注释; dailyNotificationLifetime 纯函数保留供单测锁定
//
// v1.0.60 升级:
//  - 课前提醒: 未来 7 天全窗口幂等重同步(requestCode=NOTIFY_BEFORE_CLASS_PREFIX+courseId
//    同 id 重排原地替换; 上次排过这次不再需要的按账本精确撤销)
//  - 次日预告提醒 (TomorrowNotifyReceiver 语义)
//  - 节假日提醒策略门控 (HolidayReminderPolicyAdapter.decide.allowReminder)
//  - 调休映射 (effectiveDayOfWeek)
//
// v1.0.61 升级 (#143 每张课表独立提醒, 对齐 tag 012e657e):
//  - 每表独立提醒: 课前重同步改遍历 resolveReminderTables() = 所有 reminderEnabled 表
//    (含作息 hydrate), 不再只看当前表; 当前表 reminderEnabled=false 也生效
//  - 摘要多表扇出: 每日/次日摘要按开启提醒的表逐张贴, 多于一张活跃表时标题/正文加
//    "课表名 · " 前缀, id = sleepy_summary_{5000 + tableId*2 (+1 次日)}; 单表/无课摘要
//    沿用 1001/1002 号段 (iOS 加 sleepy_summary_ 前缀避免顶掉同 id 重复触发载体)
//  - 每日内容发送时重算: 旧 UNCalendarNotificationTrigger(repeats:true) 是排期时的一次性
//    快照；应用获得执行机会时由 refreshDailySummaries 重算。
//    BGAppRefreshTask 仅申请机会性刷新，不保证每日执行。
//  - 当日提醒独立闸: AppPrefs key "today_reminder" 默认 true (scheduleDaily 前置检查)
//  - banner 门控: ProdAlarmPort.setExact 落地前查 isBeforeClassBannerEnabled()
//    (原 `if (!banner && !fluid) return`; iOS 对应物 Live Activities 未实现 → banner 关 = 完全静默)
//  - 发送时重校验入口 beforeClassDeliveryAllowed(): 表被删/提醒被关/节假日豁免
//    → delegate willPresent 丢弃 (原版本 BeforeClassNotifyReceiver.onReceive 语义)
//
// OPPO Fluid Cloud(SDK≥26 前台服务 + ProgressStyle)整体跳过(OPPO 厂商 SDK 调用不可移植;
// iOS 对应物 = Live Activities/灵动岛(v1.0.64 已实现, 见 ClassDayActivityManager), 见 VendorCapabilityState.swift); banner 通知完整移植。

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

    /// 课前通知 userInfo 键 — delegate 发送时重校验用 (Intent extras)。
    static let KEY_USERINFO_RESYNC = "sleepy_resync"
    /// 节假日全豁免静默标记: 主 id 触发器是每日重算锚不能撤, 静默日贴空载荷 + 此标记,
    /// delegate willPresent 见标记即丢弃展示 (到货仍触发重算)。
    static let KEY_USERINFO_SUMMARY_SILENT = "sleepy_summary_silent"
    /// v1.0.62 摘要点击载荷: 绝对日历日期 "yyyy-MM-dd" (← DailyAgendaRoute.EXTRA_DATE) —
    /// delegate didReceive 据此路由到议程页, 旧通知点击不漂移到今天。
    static let KEY_USERINFO_AGENDA_DATE = "agenda_date"

    /// 课前提醒预排窗口: 今天起 7 个日历天(参照 shiguang WIDGET_SYNC_DAYS=7)
    static let BEFORE_CLASS_WINDOW_DAYS = 7

    private let prefs = AppPrefs.shared

    var repositoryProvider: (() -> ScheduleRepository?)?

    private let scheduleGate = NotificationScheduleGate()
    private let writeNotification: (UNNotificationRequest) async -> Void
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
        /// ← 原BeforeClassDataSource.resolveReminderTables(): 每张开启提醒的表
        /// 独立参与课前重排(含作息 hydrate), 不再只看当前表。
        func resolveReminderTables() throws -> [TimeTableEntity] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { throw CourseReminderLoadError.unavailable }
            let tables = try repo.getAllTables()
            return try tables.filter { $0.reminderEnabled }.map { t in
                var pt: PeriodTableEntity? = nil
                if let pid = t.periodTableId { pt = try repo.getPeriodTable(pid) }
                return t.hydratedWith(pt)
            }
        }
        func coursesForDay(tableId: Int64, dayOfWeek: Int) throws -> [CourseEntity] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { throw CourseReminderLoadError.unavailable }
            return try repo.getCoursesByDay(tableId, day: dayOfWeek)
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
            let content = UNMutableNotificationContent()
            let courseName = extras["courseName"] as? String ?? ""
            let room = (extras["room"] as? String) ?? ""
            let startTime = (extras["startTime"] as? String) ?? ""
            let roomStr = room.isEmpty ? L10n.t("notif_room_unknown") : room
            // v1.0.62 ← CourseNotificationScheduler.handle: 标准横幅统一 compact 文案 —
            //   title=课程名, 正文=「开始时间 · 教室」+ 多表来源标签〔…〕(教师不再进正文)。
            content.title = courseName
            var body = L10n.format(
                "notif_before_class_compact",
                startTime.trimmingCharacters(in: .whitespaces).isEmpty
                    ? L10n.t("agenda_time_unknown") : startTime,
                roomStr)
            // ← handle(context, intent, source): 来源标签 = 该表在「开启提醒的全部表」
            //   中的标注 (notificationSourceLabels; 单表/无标注 → 空表 → 无〔…〕后缀)。
            if let tableId = extras["tableId"] as? Int64,
               let repo = NotificationScheduler.shared.repositoryProvider?() {
                let enabled = ((try? repo.getAllTables()) ?? []).filter { $0.reminderEnabled }
                if let source = notificationSourceLabels(enabled, L10n.t("agenda_table_unknown"))[tableId] {
                    body += "\u{3014}\(source)\u{3015}"
                }
            }
            content.body = body
            content.sound = .default
            // 发送时重校验载荷 (Intent extras tableId/reminderDate):
            // delegate willPresent 用这两个键复查 表存在+reminderEnabled+节假日策略。
            var info: [String: Any] = [:]
            if let tableId = extras["tableId"] as? Int64 { info["tableId"] = tableId }
            if let reminderDate = extras["reminderDate"] as? String { info["reminderDate"] = reminderDate }
            content.userInfo = info
            let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
            let comps = CourseReminderOccurrence.notificationDateComponents(for: date)
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
        func availableSlots() async -> Int {
            let pending = await pendingIdentifiers()
            let other = pending.filter { !$0.hasPrefix(NotificationScheduler.NOTIFY_BEFORE_CLASS_PREFIX) }.count
            // App policy: leave four slots free; this is not an OS guarantee.
            return max(0, 60 - other)
        }
        func cancel(id: String) {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }
    }

    private let env: NotificationSchedulerBeforeClassEnv
    private let dataSource: NotificationSchedulerBeforeClassDataSource
    private let alarmPort: NotificationSchedulerBeforeClassAlarmPort

    init() {
        self.env = ProdEnv()
        self.dataSource = ProdDataSource()
        self.alarmPort = ProdAlarmPort()
        self.writeNotification = { request in _ = try? await UNUserNotificationCenter.current().add(request) }
        self.loadAgenda = nil
        self.cleanupLegacySummaries = { cleanupLegacyDailySummaryNotifications() }
        self.usesBackgroundTasks = true
    }

    /// 测试构造器 — 注入 fake 端口。
    init(env: NotificationSchedulerBeforeClassEnv, dataSource: NotificationSchedulerBeforeClassDataSource,
         alarmPort: NotificationSchedulerBeforeClassAlarmPort,
         writeNotification: @escaping (UNNotificationRequest) async -> Void = { request in _ = try? await UNUserNotificationCenter.current().add(request) },
         loadAgenda: ((Date) async throws -> LoadedDailyAgenda)? = nil) {
        self.env = env
        self.dataSource = dataSource
        self.alarmPort = alarmPort
        self.writeNotification = writeNotification
        self.loadAgenda = loadAgenda
        self.cleanupLegacySummaries = {}
        self.usesBackgroundTasks = false
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
        cancelRecurringLocked()

        guard env.isReminderEnabled() else {
            await cancelBeforeClassLocked()
            return
        }

        if env.isDailyReminderEnabled() {
            // v1.0.61: 当日摘要可独立关闭 (← AppPrefs.isTodayReminderEnabled, key "today_reminder")
            if isTodayReminderEnabled() {
                await scheduleDaily()
            }
            await scheduleTomorrowReminder()
        }
        guard env.isReminderEnabled(), env.isBeforeClassEnabled() else {
            await cancelBeforeClassLocked()
            return
        }
        scheduleBeforeClassDailyResync()
        await resyncBeforeClassLocked()
    }

    func cancelAll() async {
        await scheduleGate.perform {
            self.cancelRecurringLocked()
            await self.cancelBeforeClassLocked()
        }
    }

    private func cancelRecurringLocked() {
        alarmPort.cancel(id: Self.NOTIFY_DAILY)
        alarmPort.cancel(id: Self.NOTIFY_TOMORROW_DAILY)
        alarmPort.cancel(id: Self.NOTIFY_RESYNC)
        // v1.0.61: 扇出摘要与主 id 同属重复触发的每日通知, 一并撤销并清账本
        for tomorrow in [false, true] {
            for id in env.loadDailySummaryIds(isTomorrowPreview: tomorrow) {
                alarmPort.cancel(id: id)
            }
            env.saveDailySummaryIds([], isTomorrowPreview: tomorrow)
        }
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

    private func scheduleDaily() async {
        await postDailySummariesLocked(
            timeStr: env.dailyReminderTime(),
            fallbackHour: 7, fallbackMinute: 0,
            identifier: Self.NOTIFY_DAILY,
            isTomorrowPreview: false
        )
    }

    private func scheduleTomorrowReminder() async {
        guard env.isTomorrowReminderEnabled() else { return }
        await postDailySummariesLocked(
            timeStr: env.tomorrowReminderTime(),
            fallbackHour: 22, fallbackMinute: 0,
            identifier: Self.NOTIFY_TOMORROW_DAILY,
            isTomorrowPreview: true
        )
    }

    /// 摘要 id ← sendScheduleSummary 扇出号段: NOTIFY_TABLE_SUMMARY_BASE + tableId*2
    /// (+1 次日), iOS 字符串化 = "sleepy_summary_{n}"。单表/无课沿用主 id (1001/1002)。
    static func summaryIdentifier(tableId: Int64, isTomorrowPreview: Bool) -> String {
        let numeric = NOTIFY_TABLE_SUMMARY_BASE + Int(tableId * 2 + (isTomorrowPreview ? 1 : 0))
        return NOTIFY_SUMMARY_PREFIX + String(numeric)
    }

    /// 判定一个通知 id 属于次日预告链路 (1002 主 id 或扇出奇号) — delegate 到货子闸重查用。
    static func isTomorrowSummaryIdentifier(_ identifier: String) -> Bool {
        if identifier == NOTIFY_TOMORROW_DAILY { return true }
        guard identifier.hasPrefix(NOTIFY_SUMMARY_PREFIX),
              let n = Int(identifier.dropFirst(NOTIFY_SUMMARY_PREFIX.count)),
              n >= NOTIFY_TABLE_SUMMARY_BASE else { return false }
        return (n - NOTIFY_TABLE_SUMMARY_BASE) % 2 == 1
    }

    /// 判定一个通知 id 属于当日摘要链路 (1001 主 id 或扇出偶号)。
    static func isTodaySummaryIdentifier(_ identifier: String) -> Bool {
        if identifier == NOTIFY_DAILY { return true }
        guard identifier.hasPrefix(NOTIFY_SUMMARY_PREFIX),
              let n = Int(identifier.dropFirst(NOTIFY_SUMMARY_PREFIX.count)),
              n >= NOTIFY_TABLE_SUMMARY_BASE else { return false }
        return (n - NOTIFY_TABLE_SUMMARY_BASE) % 2 == 0
    }

    /// v1.0.62 (#143 → 单条聚合) 摘要重算+张贴 — 语义 ← sendScheduleSummary:
    /// 每次调用都按「当前库内实况」重算内容 (触发器 repeats:true 固定内容会陈旧, 因此
    /// scheduleAll / BGAppRefreshTask 获得执行机会时重贴同 id = 原地刷新)。
    /// targetDate 取触发器下一次到货日, 保证到货当天文案正确 («今天/明天» 不过期)。
    /// v1.0.62 变化: 多表扇出(sleepy_summary_*) → 单条聚合通知 — 跨表同名同刻的课
    /// 经 buildDailyAgenda 合并为一条, 来源全保留 (agenda.notificationSources);
    /// 正文首行 = 首课, 展开文本 = 来源课表数 + 前 6 条 + 「另有 N 次课」。
    /// 点击打开议程页 (userInfo.agendaDate = 绝对日历日期, 旧通知点击不漂移)。
    /// 原版本 setTimeoutAfter(dailyNotificationLifetime) 在 iOS 无等价物 (UNNotification
    /// 不支持自动过期) — 平台缺口, 相对文案过期由「每日重贴」覆盖, dailyNotificationLifetime
    /// 纯函数保留并由单测锁定 (DailyAgendaTests)。
    func postDailySummaries(timeStr: String, fallbackHour: Int, fallbackMinute: Int,
                            identifier: String, isTomorrowPreview: Bool) async {
        await scheduleGate.perform {
            await self.postDailySummariesLocked(timeStr: timeStr, fallbackHour: fallbackHour,
                fallbackMinute: fallbackMinute, identifier: identifier, isTomorrowPreview: isTomorrowPreview)
        }
    }

    private func postDailySummariesLocked(timeStr: String, fallbackHour: Int, fallbackMinute: Int,
                                         identifier: String, isTomorrowPreview: Bool) async {
        guard dailySummaryAllowed(isTomorrowPreview: isTomorrowPreview) else { return }
        let parts = timeStr.split(separator: ":").map(String.init)
        // 钳制到合法范围, 避免破损 pref 触发崩溃
        let hour = min(max(Int(parts.count > 0 ? parts[0] : "") ?? fallbackHour, 0), 23)
        let minute = min(max(Int(parts.count > 1 ? parts[1] : "") ?? fallbackMinute, 0), 59)

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        // 内容对应的到货日: 下一次触发日 (次日预告 = 触发日 +1)
        let nextFire = trigger.nextTriggerDate() ?? Date()
        let targetDate = isTomorrowPreview
            ? Calendar.current.date(byAdding: .day, value: 1, to: nextFire) ?? nextFire
            : nextFire

        // ← sendScheduleSummary: 先清 v1.0.61 扇出遗留, 再现读现算
        cleanupLegacySummaries()
        let loaded: LoadedDailyAgenda
        do {
            if let loadAgenda {
                loaded = try await loadAgenda(targetDate)
            } else {
                guard let repo = repositoryProvider?() else { throw AgendaLoadError.noRepository }
                loaded = try await loadDailyAgenda(repository: repo, targetDate: targetDate)
            }
        } catch {
            // ← 原 sendScheduleSummary 抛错即接收器协程静默不发; iOS 主 id 触发器
            //   是每日重算锚不能撤, 贴静默载荷保锚存活, 到货/BGTask 重算兜底。
            if dailySummaryAllowed(isTomorrowPreview: isTomorrowPreview) {
                await postSilentAnchor(identifier: identifier, trigger: trigger)
            }
            return
        }
        // Settings may change while holiday data is loading. Do not restore a
        // notification after its master or daily sub-switch was turned off.
        guard dailySummaryAllowed(isTomorrowPreview: isTomorrowPreview) else { return }
        // 上一轮扇出账本全撤 (单条聚合后不再有扇出 id; v1.0.61 升级残留在此收口)
        let previous = env.loadDailySummaryIds(isTomorrowPreview: isTomorrowPreview)
        for id in previous { alarmPort.cancel(id: id) }
        env.saveDailySummaryIds([], isTomorrowPreview: isTomorrowPreview)

        if loaded.suppressed {
            // 全部活跃表被节假日豁免 → 原版本 接收器直接 return 不发。iOS 主 id 触发器是
            // 每日重算锚, 不能撤(撤了锚就死); 改贴空载荷 + silent 标记, delegate 到货丢弃。
            await postSilentAnchor(identifier: identifier, trigger: trigger)
            return
        }
        let agenda = loaded.agenda

        // ← relativeDay: 通知到货日与目标日的相对天数 (0=今天 1=明天 其他=绝对日期文案)
        let today = DateUtils.isoCalendar.startOfDay(for: Date())
        let target = DateUtils.isoCalendar.startOfDay(for: targetDate)
        let relativeDay = DateUtils.isoCalendar.dateComponents([.day], from: today, to: target).day ?? 0

        let unknownTable = L10n.t("agenda_table_unknown")
        let unknownTime = L10n.t("agenda_time_unknown")
        let unknownRoom = L10n.t("notif_room_unknown")
        let sources = agenda.notificationSources(unknownTable: unknownTable)

        let title: String
        let text: String
        var expanded = ""
        if agenda.items.isEmpty {
            // ← 无课: 标题按相对日三分支, 正文沿用 no-course 文案
            switch relativeDay {
            case 0: title = L10n.t("notif_daily_title_no_course")
            case 1: title = L10n.t("notif_tomorrow_title_no_course")
            default: title = L10n.format("notif_date_no_course", DateUtils.fullDate(targetDate))
            }
            text = L10n.t(isTomorrowPreview ? "notif_tomorrow_text_no_course" : "notif_daily_text_no_course")
        } else {
            switch relativeDay {
            case 0: title = L10n.format("notif_daily_title", agenda.items.count)
            case 1: title = L10n.format("notif_tomorrow_title", agenda.items.count)
            default: title = L10n.format("notif_date_title", DateUtils.fullDate(targetDate), agenda.items.count)
            }
            // ← agenda_first + 首课单行; expanded = 来源数 + 可见行 + 「另有 N 次课」
            text = L10n.format("agenda_first",
                               agenda.items[0].notificationLine(unknownTime: unknownTime, unknownRoom: unknownRoom, sourceLabels: sources))
            let (visible, remaining) = agenda.preview()
            var lines: [String] = []
            if !sources.isEmpty {
                lines.append(L10n.format("agenda_source_count", agenda.tableCount))
            }
            lines.append(contentsOf: visible.map {
                $0.notificationLine(unknownTime: unknownTime, unknownRoom: unknownRoom, sourceLabels: sources)
            })
            if remaining > 0 {
                lines.append(L10n.format("agenda_more", remaining))
            }
            expanded = lines.joined(separator: "\n")
        }

        let content = UNMutableNotificationContent()
        content.title = title
        // ← BigTextStyle.bigText(expanded): iOS 无独立展开态, 长正文系统自带折叠;
        //   有展开内容时正文直接用多行聚合文本 (首课行已是第一行)。
        content.body = expanded.isEmpty ? text : expanded
        content.sound = .default
        // 点击 → 议程页 (绝对日历日期, ← DailyAgendaActivity.pendingIntent EXTRA_DATE)
        content.userInfo = [Self.KEY_USERINFO_AGENDA_DATE: DateUtils.fullDate(targetDate)]
        await writeNotification(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// 节假日全豁免/重算失败时的锚保活载体: 空载荷 + silent 标记, delegate 到货丢弃展示。
    private func postSilentAnchor(identifier: String, trigger: UNCalendarNotificationTrigger) async {
        let content = UNMutableNotificationContent()
        content.title = "Sleepy"
        content.body = ""
        content.userInfo = [Self.KEY_USERINFO_SUMMARY_SILENT: true]
        await writeNotification(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private enum AgendaLoadError: Error { case noRepository }

    /// 到货/后台唤醒重算入口: 按当前 prefs 重贴当日/次日摘要 (schedule 侧同款逻辑)。
    /// ← DailyNotifyReceiver/TomorrowNotifyReceiver.onReceive 的到货重查。
    func refreshDailySummaries(isTomorrowPreview: Bool) async {
        await scheduleGate.perform {
            await self.refreshDailySummariesLocked(isTomorrowPreview: isTomorrowPreview)
        }
    }

    private func refreshDailySummariesLocked(isTomorrowPreview: Bool) async {
        // 与 原版本 接收器同款到货重查: 总闸/日提醒闸/当日子闸
        guard dailySummaryAllowed(isTomorrowPreview: isTomorrowPreview) else { return }
        let identifier = isTomorrowPreview ? Self.NOTIFY_TOMORROW_DAILY : Self.NOTIFY_DAILY
        let timeStr = isTomorrowPreview ? env.tomorrowReminderTime() : env.dailyReminderTime()
        await postDailySummariesLocked(timeStr: timeStr, fallbackHour: isTomorrowPreview ? 22 : 7,
                                 fallbackMinute: 0, identifier: identifier,
                                 isTomorrowPreview: isTomorrowPreview)
    }

    private func dailySummaryAllowed(isTomorrowPreview: Bool) -> Bool {
        guard env.isReminderEnabled(), env.isDailyReminderEnabled() else { return false }
        return isTomorrowPreview ? env.isTomorrowReminderEnabled() : env.isTodayReminderEnabled()
    }

    /// 每日摘要到货闸 ← DailyNotifyReceiver/TomorrowNotifyReceiver 的三闸重查:
    /// isReminderEnabled && isDailyReminderEnabled && (当日? isTodayReminderEnabled : isTomorrowReminderEnabled)
    static func dailySummaryGateOpen(isTomorrowPreview: Bool) -> Bool {
        let prefs = AppPrefs.shared
        guard prefs.isReminderEnabled(), prefs.isDailyReminderEnabled() else { return false }
        return isTomorrowPreview ? prefs.isTomorrowReminderEnabled()
                                : NotificationScheduler.shared.isTodayReminderEnabled()
    }

    /// 当日摘要子闸 ← AppPrefs.isTodayReminderEnabled(ctx) (key "today_reminder", 默认 true)。
    /// AppPrefs 的 getter 已落地 (Sleepy/util/AppPrefs.swift), 直接走公开访问器 —— 与
    /// ReminderScreen 的开关节同一入口, 不再经 sharedBackedStore 直读。
    func isTodayReminderEnabled() -> Bool {
        env.isTodayReminderEnabled()
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
        try await CourseReminderLoader.load(tables: dataSource.resolveReminderTables(),
            dataSource: dataSource, from: env.todayDate(), days: Self.BEFORE_CLASS_WINDOW_DAYS)
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
        let occurrences: [CourseReminderOccurrence]
        do { occurrences = try await upcomingOccurrences() }
        catch { return } // Keep the system's existing requests on a read failure.
        let nowEpoch = env.nowEpochMs()
        let lead = env.beforeClassMinutes()
        let capacity = await alarmPort.availableSlots()
        let desired = occurrences.filter {
            Int64($0.reminderDate(leadMinutes: lead).timeIntervalSince1970 * 1000) > nowEpoch
        }.prefix(max(0, capacity))
        guard env.isReminderEnabled(), env.isBeforeClassEnabled() else {
            await cancelBeforeClassLocked()
            return
        }
        let desiredIDs = Set(desired.map(\.notificationIdentifier))
        var accepted = Set<String>()
        // Release obsolete slots first. Matching valid requests remain in place
        // while replacements are accepted, and retain their ledger on failure.
        for id in previous.union(owned) where !desiredIDs.contains(id) { alarmPort.cancel(id: id) }
        for item in desired {
            guard env.isReminderEnabled(), env.isBeforeClassEnabled() else { break }
            let fire = item.reminderDate(leadMinutes: lead)
            let extras: [String: Any?] = [
                "courseName": item.name, "room": item.room, "teacher": item.teacher,
                "startTime": TimeTableUtils.formatTime(item.start),
                "endTime": TimeTableUtils.formatTime(item.end),
                "startNode": item.startNode, "notifyEpoch": Int64(fire.timeIntervalSince1970 * 1000),
                "classEpoch": Int64(item.start.timeIntervalSince1970 * 1000),
                "tableId": item.tableId, "reminderDate": DateUtils.fullDate(item.start)
            ]
            if await alarmPort.setExact(id: item.notificationIdentifier,
                epochMs: Int64(fire.timeIntervalSince1970 * 1000), extras: extras) {
                accepted.insert(item.notificationIdentifier)
            } else if pending.contains(item.notificationIdentifier) {
                accepted.insert(item.notificationIdentifier)
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
        guard prefs.isReminderEnabled(), prefs.isBeforeClassEnabled(),
              prefs.isBeforeClassBannerEnabled() else { return false }
        let tableId = (userInfo["tableId"] as? Int64)
            ?? (userInfo["tableId"] as? NSNumber)?.int64Value
        let repo = repositoryProvider?()
        let resolvedTableId: Int64?
        if let tid = tableId {
            resolvedTableId = tid
        } else {
            resolvedTableId = repo.flatMap { WidgetTableResolver.resolveCurrentTable($0) }?.id
        }
        guard let tid = resolvedTableId, let repo = repo else { return false }
        let owner = ((try? repo.getAllTables()) ?? []).first { $0.id == tid }
        guard let owner = owner, owner.reminderEnabled else { return false }
        // reminderDate: "yyyy-MM-dd" (排期时写入); 解析失败回退今天 (原 runCatching 语义)
        let date = (userInfo["reminderDate"] as? String).flatMap { DateUtils.parseDate($0) } ?? Date()
        return await HolidayReminderPolicyAdapter.decide(date: date, tableId: tid).allowReminder
    }

    /// 到货/BGTask 每日窗口入口 — 等价 原版本 00:05 BeforeClassScheduleReceiver +
    /// 每日接收器每次现算语义: 课前链路开时重同步 7 天窗口, 每日链路开时重算摘要内容。
    /// delegate 收到 sleepy_resync / BGAppRefreshTask handler 都调此函数。
    func handleDailyResync() async {
        await scheduleGate.perform {
            guard self.env.isReminderEnabled() else { return }
            if self.env.isBeforeClassEnabled() {
                await self.resyncBeforeClassLocked()
            }
            if self.env.isDailyReminderEnabled() {
                await self.refreshDailySummariesLocked(isTomorrowPreview: false)
                await self.refreshDailySummariesLocked(isTomorrowPreview: true)
            }
        }
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
        let todays = DateUtils.isoCalendar.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime)
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
    func loadArmedIds() -> Set<String>
    func saveArmedIds(_ ids: Set<String>)
    /// v1.0.61 摘要扇出账本 — 上次贴出的多表摘要 id 集合, 分当日/次日两套。
    func loadDailySummaryIds(isTomorrowPreview: Bool) -> Set<String>
    func saveDailySummaryIds(_ ids: Set<String>, isTomorrowPreview: Bool)
}

/// 默认实现回退空账本 — 兼容未升级的旧测试替身 (接口默认方法同款兼容策略)。
extension NotificationSchedulerBeforeClassEnv {
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
    /// 每表独立提醒: 返回开启提醒的课表(含作息 hydrate)。默认实现回退到当前课表,
    /// 兼容旧测试替身 (BeforeClassDataSource.resolveReminderTables 默认分支)。
    func resolveReminderTables() throws -> [TimeTableEntity]
    func coursesForDay(tableId: Int64, dayOfWeek: Int) throws -> [CourseEntity]
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
}

/// 课前通知落地端口 — UNUserNotificationCenter 接缝。
protocol NotificationSchedulerBeforeClassAlarmPort {
    func setExact(id: String, epochMs: Int64, extras: [String: Any?]) async -> Bool
    func pendingIdentifiers() async -> Set<String>
    func availableSlots() async -> Int
    func cancel(id: String)
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
        // 每日/次日摘要 (含扇出 id): 子闸到货重查; 其他未知 id 走系统默认展示
        if NotificationScheduler.isTodaySummaryIdentifier(id) || NotificationScheduler.isTomorrowSummaryIdentifier(id) {
            let tomorrow = NotificationScheduler.isTomorrowSummaryIdentifier(id)
            let silent = notification.request.content.userInfo[NotificationScheduler.KEY_USERINFO_SUMMARY_SILENT] as? Bool ?? false
            Task {
                // 内容陈旧防御: 到货即按当前数据重算, 本轮仍展示已排内容;
                // 节假日全豁免的静默载体只触发重算、不展示 (豁免日接收器 return 不发)
                let gateOn = NotificationScheduler.dailySummaryGateOpen(isTomorrowPreview: tomorrow)
                if gateOn { await NotificationScheduler.shared.refreshDailySummaries(isTomorrowPreview: tomorrow) }
                completionHandler(gateOn && !silent ? [.banner, .sound] : [])
            }
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
