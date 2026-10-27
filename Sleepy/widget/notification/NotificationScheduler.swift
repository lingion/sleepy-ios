// NotificationScheduler.swift — ← CourseNotificationScheduler.kt (v1.0.61)
// 课程通知调度器 — 支持每日提醒(当日/次日分闸) + 次日预告 + 每节课前提醒(7 天幂等重同步 + 账本)。
//
// 平台映射: AlarmManager+BroadcastReceiver → UNUserNotificationCenter+UNCalendarNotificationTrigger
// (iOS 无 exact alarm;日历触发器在锁屏也能到,精度分钟级 — 等价适配)
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
//    快照, 数日不开 App 会一直推旧「今日 N 号」→ 载体到货 refreshDailySummaries 重算
//    (Android 接收器每次现算语义); BGAppRefreshTask handleDailyResync 兜底每日窗口
//  - 当日提醒独立闸: AppPrefs key "today_reminder" 默认 true (scheduleDaily 前置检查)
//  - banner 门控: ProdAlarmPort.setExact 落地前查 isBeforeClassBannerEnabled()
//    (Android `if (!banner && !fluid) return`; iOS 无流体云载体 → banner 关 = 完全静默)
//  - 发送时重校验入口 beforeClassDeliveryAllowed(): 表被删/提醒被关/节假日豁免
//    → delegate willPresent 丢弃 (Android BeforeClassNotifyReceiver.onReceive 语义)
//
// OPPO Fluid Cloud(SDK≥26 前台服务 + ProgressStyle)整体跳过(平台差异,iOS 无对应物,
// 见 VendorCapabilityState.swift); banner 通知完整移植。

import Foundation
import UserNotifications
import BackgroundTasks

final class NotificationScheduler {
    static let shared = NotificationScheduler()

    // ← companion object 常量
    static let CHANNEL_DAILY = "sleepy_daily"
    static let CHANNEL_BEFORE_CLASS = "sleepy_before_class"
    static let CHANNEL_FLUID = "sleepy_fluid_v2"

    // Notification identifiers(= Android request codes 语义:按 id 撤销)
    static let NOTIFY_DAILY = "sleepy_daily_1001"
    static let NOTIFY_TOMORROW_DAILY = "sleepy_daily_1002"
    static let NOTIFY_BEFORE_CLASS_PREFIX = "sleepy_bc_2000_"  // + courseId
    static let NOTIFY_RESYNC = "sleepy_resync_0002"            // 每日 00:05 全窗口重同步
    /// ← NOTIFY_TABLE_SUMMARY_BASE = 5000: 多表开启时每日/明日摘要按 tableId 分配独立 ID
    /// (base + tableId*2, 次日预告 +1), iOS 侧落为字符串 "sleepy_summary_{id}"。
    static let NOTIFY_TABLE_SUMMARY_BASE = 5000
    static let NOTIFY_SUMMARY_PREFIX = "sleepy_summary_"

    /// BGAppRefreshTask 标识 — 每日窗口重同步 + 摘要内容刷新的系统兜底。
    static let BG_RESYNC_TASK_ID = "sleepy.alarm.daily.resync"

    /// 课前通知 userInfo 键 — delegate 发送时重校验用 (← Android Intent extras)。
    static let KEY_USERINFO_RESYNC = "sleepy_resync"
    /// 节假日全豁免静默标记: 主 id 触发器是每日重算锚不能撤, 静默日贴空载荷 + 此标记,
    /// delegate willPresent 见标记即丢弃展示 (到货仍触发重算)。
    static let KEY_USERINFO_SUMMARY_SILENT = "sleepy_summary_silent"

    /// 课前提醒预排窗口: 今天起 7 个日历天(参照 shiguang WIDGET_SYNC_DAYS=7)
    static let BEFORE_CLASS_WINDOW_DAYS = 7

    private let center = UNUserNotificationCenter.current()
    private let prefs = AppPrefs.shared

    var repositoryProvider: (() -> ScheduleRepository?)?

    // 进程级锁 — Mutex 不可重入, 持锁路径只调 *Locked
    private let scheduleLock = NSLock()

    // MARK: - 生产实现 (协议定义在文件底部顶层 — Swift 不允许协议嵌套在类内)

    /// prefs/时钟/独立账本文件(闹钟是本机状态, 不随 sleepy_prefs 云备份迁移)。
    private final class ProdEnv: NotificationSchedulerBeforeClassEnv {
        private let ledger = UserDefaults(suiteName: "sleepy_alarm_ledger")
        func isBeforeClassEnabled() -> Bool { AppPrefs.shared.isBeforeClassEnabled() }
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
        /// ← AndroidBeforeClassDataSource.resolveReminderTables(): 每张开启提醒的表
        /// 独立参与课前重排(含作息 hydrate), 不再只看当前表。
        func resolveReminderTables() -> [TimeTableEntity] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { return [] }
            let tables = (try? repo.getAllTables()) ?? []
            return tables.filter { $0.reminderEnabled }.map { t in
                var pt: PeriodTableEntity? = nil
                if let pid = t.periodTableId { pt = (try? repo.getPeriodTable(pid)) ?? nil }
                return t.hydratedWith(pt)
            }
        }
        func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity] {
            guard let repo = NotificationScheduler.shared.repositoryProvider?() else { return [] }
            return (try? repo.getCoursesByDay(tableId, day: dayOfWeek)) ?? []
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
        func effectiveDayOfWeek(tableId: Int64?, date: Date) -> Int {
            return HolidayTransferHelper.effectiveDayOfWeek(tableId, date)
        }
        func allowsReminder(tableId: Int64, date: Date) async -> Bool {
            return await HolidayReminderPolicyAdapter.decide(date: date, tableId: tableId).allowReminder
        }
    }

    private final class ProdAlarmPort: NotificationSchedulerBeforeClassAlarmPort {
        func setExact(id: String, epochMs: Int64, extras: [String: Any?]) {
            // v1.0.61 banner 门控 (← BeforeClassNotifyReceiver.handle 的 `if (!banner && !fluid) return`):
            // iOS 无流体云载体, banner 关 = 课前通知完全静默。排期时拦截;
            // 排期后才关 banner 的残留由 delegate willPresent 二次拦截 (见 beforeClassDeliveryAllowed)。
            guard AppPrefs.shared.isBeforeClassBannerEnabled() else { return }
            Task {
                let content = UNMutableNotificationContent()
                let courseName = extras["courseName"] as? String ?? ""
                let room = (extras["room"] as? String) ?? ""
                let teacher = (extras["teacher"] as? String) ?? ""
                let startTime = (extras["startTime"] as? String) ?? ""
                let roomStr = room.isEmpty ? L10n.t("notif_room_unknown") : room
                if teacher.isEmpty {
                    content.title = L10n.t("notif_before_class_title")
                    content.body = L10n.format("notif_before_class_text", courseName, startTime, roomStr)
                } else {
                    content.title = L10n.t("notif_before_class_title")
                    content.body = L10n.format("notif_before_class_text_with_teacher", courseName, startTime, roomStr, teacher)
                }
                content.sound = .default
                // 发送时重校验载荷 (← Android Intent extras tableId/reminderDate):
                // delegate willPresent 用这两个键复查 表存在+reminderEnabled+节假日策略。
                var info: [String: Any] = [:]
                if let tableId = extras["tableId"] as? Int64 { info["tableId"] = tableId }
                if let reminderDate = extras["reminderDate"] as? String { info["reminderDate"] = reminderDate }
                content.userInfo = info
                let date = Date(timeIntervalSince1970: TimeInterval(epochMs) / 1000)
                let comps = DateUtils.isoCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
                try? await UNUserNotificationCenter.current().add(req)
            }
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
    }

    /// 测试构造器 — 注入 fake 端口。
    init(env: NotificationSchedulerBeforeClassEnv, dataSource: NotificationSchedulerBeforeClassDataSource, alarmPort: NotificationSchedulerBeforeClassAlarmPort) {
        self.env = env
        self.dataSource = dataSource
        self.alarmPort = alarmPort
    }

    // ==================== scheduleAll ← ====================

    func scheduleAll() {
        // iOS 无 NotificationChannel; Android createChannels 在此处的隐式
        // requestAuthorization 已按权限政策摘除 —— 全 app 唯一申请点 =
        // ReminderScreen master 开关(用户显式操作), denied 后走系统设置引导。
        Self.registerDailyResyncTask()
        submitDailyResyncTask()
        Task {
            scheduleLock.lock(); defer { scheduleLock.unlock() }
            cancelRecurringLocked()

            guard prefs.isReminderEnabled() else {
                await cancelBeforeClassLocked()
                return
            }

            if prefs.isDailyReminderEnabled() {
                // v1.0.61: 当日摘要可独立关闭 (← AppPrefs.isTodayReminderEnabled, key "today_reminder")
                if isTodayReminderEnabled() {
                    scheduleDaily()
                }
                scheduleTomorrowReminder()
            }
            guard prefs.isBeforeClassEnabled() else {
                await cancelBeforeClassLocked()
                return
            }
            scheduleBeforeClassDailyResync()
            await resyncBeforeClassLocked()
        }
    }

    func cancelAll() async {
        scheduleLock.lock(); defer { scheduleLock.unlock() }
        cancelRecurringLocked()
        await cancelBeforeClassLocked()
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
        var all = armed
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
        for id in courseIds {
            alarmPort.cancel(id: Self.NOTIFY_BEFORE_CLASS_PREFIX + String(id))
        }
    }

    // ==================== Daily ====================

    private func scheduleDaily() {
        scheduleDailyAlarm(
            timeStr: prefs.getDailyReminderTime(),
            fallbackHour: 7, fallbackMinute: 0,
            identifier: Self.NOTIFY_DAILY,
            isTomorrowPreview: false
        )
    }

    private func scheduleTomorrowReminder() {
        guard prefs.isTomorrowReminderEnabled() else { return }
        scheduleDailyAlarm(
            timeStr: prefs.getTomorrowReminderTime(),
            fallbackHour: 22, fallbackMinute: 0,
            identifier: Self.NOTIFY_TOMORROW_DAILY,
            isTomorrowPreview: true
        )
    }

    private func scheduleDailyAlarm(
        timeStr: String, fallbackHour: Int, fallbackMinute: Int,
        identifier: String, isTomorrowPreview: Bool
    ) {
        Task {
            await postDailySummaries(timeStr: timeStr, fallbackHour: fallbackHour, fallbackMinute: fallbackMinute,
                                     identifier: identifier, isTomorrowPreview: isTomorrowPreview)
        }
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

    /// v1.0.61 (#143) 摘要重算+张贴 — 语义 ← DailyNotifyReceiver → sendScheduleSummary:
    /// 每次调用都按「当前库内实况」重算内容 (触发器 repeats:true 固定内容会陈旧, 因此
    /// scheduleAll / 00:05 载体到货 / BGAppRefreshTask 每条唤醒路径都重贴同 id = 原地刷新)。
    /// targetDate 取触发器下一次到货日, 保证到货当天文案正确 («今日 N 号» 不过期)。
    /// 多张有课表时逐表贴 sleepy_summary_* (活跃表 >1 时标题/正文加 "课表名 · " 前缀),
    /// 上一轮扇出本轮不再需要的 id 按账本精确撤销。
    func postDailySummaries(timeStr: String, fallbackHour: Int, fallbackMinute: Int,
                            identifier: String, isTomorrowPreview: Bool) async {
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

        let result = await computeSummaryPosts(targetDate: targetDate, isTomorrowPreview: isTomorrowPreview)
        let previous = env.loadDailySummaryIds(isTomorrowPreview: isTomorrowPreview)
        var armedIds = Set<String>()

        if result.posts.isEmpty {
            if result.silent {
                // 全部活跃表被节假日豁免 → Android 接收器直接 return 不发。iOS 主 id 触发器是
                // 每日重算锚, 不能撤(撤了锚就死); 改贴空载荷 + silent 标记, delegate 到货丢弃。
                let content = UNMutableNotificationContent()
                content.title = "Sleepy"
                content.body = ""
                content.userInfo = [Self.KEY_USERINFO_SUMMARY_SILENT: true]
                try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            } else {
                // 无课摘要贴主 id (← Android notify(1001/1002, no-course 文案))
                let content = UNMutableNotificationContent()
                content.title = result.noCourseTitle
                content.body = result.noCourseBody
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }
            for id in previous { alarmPort.cancel(id: id) }
            env.saveDailySummaryIds([], isTomorrowPreview: isTomorrowPreview)
            return
        }

        let multiTable = result.activeCount > 1
        for (index, post) in result.posts.enumerated() {
            var title = post.title
            var text = post.body
            if multiTable {
                title = "\(post.tableName) · \(title)"
                text = "\(post.tableName) · \(text)"
            }
            // baseId 判定 ← Android posts==1 && activeTables<=1 → 主 id, 否则扇出号段。
            // 平台适配: 扇出模式下第 0 张贴主 id — iOS 主 id 的 repeats:true 触发器是
            // 每日重算链的锚(无 fire-time 代码执行), 不能让旧内容空转; Android 侧锚是
            // PendingIntent 闹钟与 notify id 解耦, 第 0 张用哪个 id 对用户不可见。
            let id: String
            if result.posts.count == 1 && result.activeCount <= 1 {
                id = identifier
            } else if index == 0 {
                id = identifier
            } else {
                id = Self.summaryIdentifier(tableId: post.tableId, isTomorrowPreview: isTomorrowPreview)
                armedIds.insert(id)
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = text
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        // 单表场景主 id 内容原地刷新, 扇出账本里的多余 id 撤销
        for id in previous where !armedIds.contains(id) {
            alarmPort.cancel(id: id)
        }
        env.saveDailySummaryIds(armedIds, isTomorrowPreview: isTomorrowPreview)
    }

    /// ← sendScheduleSummary 的数据聚合部分。
    /// silent = 有开启提醒的表但全部被节假日策略豁免 → 不发任何摘要 (Android 语义)。
    private func computeSummaryPosts(targetDate: Date, isTomorrowPreview: Bool) async
        -> (posts: [(tableId: Int64, tableName: String, title: String, body: String)],
            activeCount: Int, noCourseTitle: String, noCourseBody: String, silent: Bool) {
        let dayOfMonth = DateUtils.isoCalendar.component(.day, from: targetDate)
        let noCourseTitle = L10n.format(isTomorrowPreview ? "notif_tomorrow_title_no_course" : "notif_daily_title_no_course", dayOfMonth)
        let noCourseBody = L10n.t(isTomorrowPreview ? "notif_tomorrow_text_no_course" : "notif_daily_text_no_course")

        guard let repo = repositoryProvider?() else {
            return ([], 0, noCourseTitle, noCourseBody, false)
        }
        let tables = ((try? repo.getAllTables()) ?? []).map { t -> TimeTableEntity in
            var pt: PeriodTableEntity? = nil
            if let pid = t.periodTableId { pt = (try? repo.getPeriodTable(pid)) ?? nil }
            return t.hydratedWith(pt)
        }
        let enabledTables = tables.filter { $0.reminderEnabled }
        var activeTables: [TimeTableEntity] = []
        for t in enabledTables {
            if await HolidayReminderPolicyAdapter.decide(date: targetDate, tableId: t.id).allowReminder {
                activeTables.append(t)
            }
        }
        if !enabledTables.isEmpty && activeTables.isEmpty {
            return ([], 0, noCourseTitle, noCourseBody, true)
        }

        struct Row { let table: TimeTableEntity; let courses: [CourseEntity] }
        let rows: [Row] = activeTables.map { table in
            let effDow = HolidayTransferHelper.effectiveDayOfWeek(table.id, targetDate)
            let week = DateUtils.currentWeek(startDate: table.startDate, today: targetDate)
            let inSemester = DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: targetDate) == .inRange
            let courses: [CourseEntity] = inSemester
                ? ((try? repo.getCoursesByDay(table.id, day: effDow)) ?? []).filter { $0.inWeek(week) }.sorted { $0.startNode < $1.startNode }
                : []
            return Row(table: table, courses: courses)
        }
        let posts: [(tableId: Int64, tableName: String, title: String, body: String)] = rows.compactMap { row in
            guard !row.courses.isEmpty else { return nil }
            let title = L10n.format(isTomorrowPreview ? "notif_tomorrow_title" : "notif_daily_title", dayOfMonth, row.courses.count)
            let first = row.courses[0]
            let firstTime = Self.courseStartTime(first, row.table)
            let firstRoom = first.room.isEmpty ? L10n.t("notif_room_unknown") : first.room
            let body = L10n.format("notif_daily_text_first", first.courseName, firstTime, firstRoom)
            return (row.table.id, row.table.name, title, body)
        }
        return (posts, activeTables.count, noCourseTitle, noCourseBody, false)
    }

    /// 到货/后台唤醒重算入口: 按当前 prefs 重贴当日/次日摘要 (schedule 侧同款逻辑)。
    /// ← DailyNotifyReceiver/TomorrowNotifyReceiver.onReceive 的到货重查。
    func refreshDailySummaries(isTomorrowPreview: Bool) async {
        // 与 Android 接收器同款到货重查: 总闸/日提醒闸/当日子闸
        guard Self.dailySummaryGateOpen(isTomorrowPreview: isTomorrowPreview) else { return }
        let identifier = isTomorrowPreview ? Self.NOTIFY_TOMORROW_DAILY : Self.NOTIFY_DAILY
        let timeStr = isTomorrowPreview ? prefs.getTomorrowReminderTime() : prefs.getDailyReminderTime()
        await postDailySummaries(timeStr: timeStr, fallbackHour: isTomorrowPreview ? 22 : 7,
                                 fallbackMinute: 0, identifier: identifier,
                                 isTomorrowPreview: isTomorrowPreview)
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
        AppPrefs.shared.isTodayReminderEnabled()
    }

    // ==================== Before-class 7 天幂等重同步 ====================

    /// 每日 00:05 的全窗口重同步载体 — 静默通知, 到货由 delegate
    /// SleepyNotificationDelegate 调 handleDailyResync (v1.0.61: 此前注释宣称的 delegate
    /// 从未注册 = 死接线; 现在 delegate 实现 + BGAppRefreshTask 双通路都已落地)。
    private func scheduleBeforeClassDailyResync() {
        var comps = DateComponents()
        comps.hour = 0
        comps.minute = 5
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let content = UNMutableNotificationContent()
        content.title = "Sleepy"
        content.body = ""   // 静默 — delegate 侧 handleDailyResync
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .passive   // 后台到货也不点亮屏幕/发声, 仅静默入通知中心
        }
        content.userInfo = [Self.KEY_USERINFO_RESYNC: true]
        let req = UNNotificationRequest(identifier: Self.NOTIFY_RESYNC, content: content, trigger: trigger)
        try? center.add(req)
    }

    /// 兼容入口 — 语义已升级为「未来 7 天全窗口重同步」(幂等)。
    func scheduleTodayBeforeClassAlarms() async {
        await scheduleNext7DaysExactAlarms()
    }

    /// 预排未来 7 个日历天(含今天)的课前通知, 幂等重同步。
    /// id = NOTIFY_BEFORE_CLASS_PREFIX + course.id, 同 id 重排由 iOS 原地替换,
    /// 只需撤销"上次排过、这次不再需要"的 id。上次排过的集合持久化在账本里。
    /// 学期范围外的天跳过(防呆: currentWeek 钳制会误匹配第 1 周的课)。
    func scheduleNext7DaysExactAlarms() async {
        scheduleLock.lock(); defer { scheduleLock.unlock() }
        await resyncBeforeClassLocked()
    }

    private func resyncBeforeClassLocked() async {
        let previous = env.loadArmedIds()
        let tables = env.isBeforeClassEnabled() ? dataSource.resolveReminderTables() : []
        if tables.isEmpty {
            for id in previous { alarmPort.cancel(id: id) }
            env.saveArmedIds([])
            return
        }
        let minutes = env.beforeClassMinutes()
        let nowEpoch = env.nowEpochMs()
        let today = env.todayDate()

        // v1.0.61 每表独立提醒 (← resyncBeforeClassLocked): 逐张开启提醒的表收集未来
        // 槽位; courseId 全局唯一, 跨表 id 不冲突。
        var desired: [(String, Int64, [String: Any?])] = []
        var desiredIds = Set<String>()
        var windowCourseIds = Set<String>()
        for table in tables {
            await collectTableSlots(table: table, today: today, minutes: minutes, nowEpoch: nowEpoch,
                                    desired: &desired, desiredIds: &desiredIds,
                                    windowCourseIds: &windowCourseIds)
        }

        // 撤销不再需要的: 账本里的 + 窗口内出现过的(覆盖账本上线前旧版本排下的)
        var toCancel = previous
        for id in windowCourseIds { toCancel.insert(id) }
        for id in toCancel where !desiredIds.contains(id) {
            alarmPort.cancel(id: id)
        }
        for (id, epoch, extras) in desired {
            alarmPort.setExact(id: id, epochMs: epoch, extras: extras)
        }
        env.saveArmedIds(desiredIds)
    }

    /// ← collectTableSlots(): 收集单张课表窗口内需要的课前槽位;
    /// 同 courseId 保留最早的未来触发(先到先得)。
    private func collectTableSlots(table: TimeTableEntity, today: Date, minutes: Int, nowEpoch: Int64,
                                   desired: inout [(String, Int64, [String: Any?])],
                                   desiredIds: inout Set<String>,
                                   windowCourseIds: inout Set<String>) async {
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        let cal = DateUtils.isoCalendar

        // 1) 枚举窗口内的天, 收集课程行(仅学期内且允许提醒的天)
        var days: [(Date, [CourseEntity])] = []
        for offset in 0..<Self.BEFORE_CLASS_WINDOW_DAYS {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            if !semesterInRange(table: table, date: date) {
                days.append((date, []))
                continue
            }
            if !(await dataSource.allowsReminder(tableId: table.id, date: date)) {
                days.append((date, []))
                continue
            }
            let week = DateUtils.currentWeek(startDate: table.startDate, today: date)
            let dow = dataSource.effectiveDayOfWeek(tableId: table.id, date: date)
            let courses = dataSource.coursesForDay(tableId: table.id, dayOfWeek: dow).filter { $0.inWeek(week) }
            days.append((date, courses))
        }

        // 2) 逐天收集未来槽位; 同 courseId 保留最早的未来触发(先到先得)
        for (date, courses) in days {
            for course in courses {
                let startTimeStr: String?
                if course.ownTime && !course.startTime.isEmpty {
                    startTimeStr = course.startTime
                } else if let node = nodes.first(where: { $0.node == course.startNode }) {
                    startTimeStr = TimeTableUtils.formatTime(node.start)
                } else {
                    startTimeStr = nil
                }
                guard let startStr = startTimeStr else { continue }
                let parts = startStr.split(separator: ":").map(String.init)
                guard let h = Int(parts.count > 0 ? parts[0] : ""),
                      let m = Int(parts.count > 1 ? parts[1] : ""),
                      (0...23).contains(h), (0...59).contains(m) else { continue }

                var comps = cal.dateComponents([.year, .month, .day], from: date)
                comps.hour = h; comps.minute = m
                guard let classStart = cal.date(from: comps) else { continue }
                let notifyTime = classStart.addingTimeInterval(-Double(minutes) * 60)
                let epoch = Int64(notifyTime.timeIntervalSince1970 * 1000)
                if epoch <= nowEpoch { continue }   // 已过触发点

                let id = Self.NOTIFY_BEFORE_CLASS_PREFIX + String(course.id)
                if desiredIds.contains(id) { continue }
                desiredIds.insert(id)

                let endTimeStr: String = {
                    if course.ownTime && !course.endTime.isEmpty { return course.endTime }
                    guard let node = nodes.first(where: { $0.node == course.startNode + course.step - 1 }) else { return "" }
                    return TimeTableUtils.formatTime(node.end)
                }()
                desired.append((id, epoch, [
                    "courseName": course.courseName,
                    "room": course.room,
                    "teacher": course.teacher,
                    "startTime": String(format: "%02d:%02d", h, m),
                    "endTime": endTimeStr,
                    "startNode": course.startNode,
                    "notifyEpoch": epoch,
                    "classEpoch": Int64(classStart.timeIntervalSince1970 * 1000),
                    "tableId": table.id,
                    "reminderDate": DateUtils.fullDate(date)
                ]))
            }
            for c in courses {
                windowCourseIds.insert(Self.NOTIFY_BEFORE_CLASS_PREFIX + String(c.id))
            }
        }
    }

    private func semesterInRange(table: TimeTableEntity, date: Date) -> Bool {
        return DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: date) == .inRange
    }

    // ==================== Channels / 权限 ====================
    // iOS 无 NotificationChannel。Android createChannels 携带的隐式
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
        // reminderDate: "yyyy-MM-dd" (排期时写入); 解析失败回退今天 (Android runCatching 语义)
        let date = (userInfo["reminderDate"] as? String).flatMap { DateUtils.parseDate($0) } ?? Date()
        return await HolidayReminderPolicyAdapter.decide(date: date, tableId: tid).allowReminder
    }

    /// 到货/BGTask 每日窗口入口 — 等价 Android 00:05 BeforeClassScheduleReceiver +
    /// 每日接收器每次现算语义: 课前链路开时重同步 7 天窗口, 每日链路开时重算摘要内容。
    /// delegate 收到 sleepy_resync / BGAppRefreshTask handler 都调此函数。
    func handleDailyResync() async {
        guard prefs.isReminderEnabled() else { return }
        if prefs.isBeforeClassEnabled() {
            await scheduleNext7DaysExactAlarms()
        }
        if prefs.isDailyReminderEnabled() {
            await refreshDailySummaries(isTomorrowPreview: false)
            await refreshDailySummaries(isTomorrowPreview: true)
        }
    }

    /// BGAppRefreshTask 注册 ← iOS 无 AlarmManager, 00:05 窗口与到货重算的系统兜底。
    /// 必须在 willFinishLaunching 早期调用 (BGTaskScheduler 注册窗口限制), 归集成者接线。
    private static var bgTaskRegistered = false
    static func registerDailyResyncTask() {
        // BGTaskScheduler.register 在 app extension 内不可用(系统只允许主 App 注册
        // launch handler); widget 进程不接 BGTask, 注册归 app 侧 willFinishLaunching。
        // watchOS 进程同理不接 (BGTaskScheduler API 在 watchOS 不可用);
        // 手表每日窗口兜底 = 00:05 静默通知载体 (scheduleBeforeClassDailyResync 已排)。
        #if WIDGET_EXT || WATCH_APP
        return
        #else
        guard #available(iOS 15.0, *), !bgTaskRegistered else { return }
        bgTaskRegistered = true
        try? BGTaskScheduler.shared.register(
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
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
    #endif

    /// 提交下一次每日窗口兜底唤醒 (00:05~00:35 时段, 系统择机; 重复调用同 id 合并)。
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

    /// ← getCourseStartTime(course, table)
    static func courseStartTime(_ course: CourseEntity, _ table: TimeTableEntity) -> String {
        if course.ownTime && !course.startTime.isEmpty { return course.startTime }
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        guard let node = nodes.first(where: { $0.node == course.startNode }) else { return "" }
        return TimeTableUtils.formatTime(node.start)
    }
}

// MARK: - 可注入端口(JVM 单测接缝, 顶层 — Swift 不允许协议嵌套在类内)

/// 课前通知环境值 — prefs/时钟/账本读取接缝。
protocol NotificationSchedulerBeforeClassEnv {
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

/// 默认实现回退空账本 — 兼容未升级的旧测试替身 (← Android 接口默认方法同款兼容策略)。
extension NotificationSchedulerBeforeClassEnv {
    func loadDailySummaryIds(isTomorrowPreview: Bool) -> Set<String> { [] }
    func saveDailySummaryIds(_ ids: Set<String>, isTomorrowPreview: Bool) {}
}

/// 课前通知数据源 — 课表/课程查询接缝。
protocol NotificationSchedulerBeforeClassDataSource {
    func resolveCurrentTable() -> TimeTableEntity?
    /// 每表独立提醒: 返回开启提醒的课表(含作息 hydrate)。默认实现回退到当前课表,
    /// 兼容旧测试替身 (← Android BeforeClassDataSource.resolveReminderTables 默认分支)。
    func resolveReminderTables() -> [TimeTableEntity]
    func coursesForDay(tableId: Int64, dayOfWeek: Int) -> [CourseEntity]
    func allCourseIds() -> [Int64]
    func effectiveDayOfWeek(tableId: Int64?, date: Date) -> Int
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
    func setExact(id: String, epochMs: Int64, extras: [String: Any?])
    func cancel(id: String)
}

// MARK: - 到货 delegate (Android Receiver 的 iOS 对位; 赋值归集成者, 见 SleepyApp 接线)

/// UNUserNotificationCenterDelegate 实现 ← 三个 Receiver 的到货语义:
///  - sleepy_resync_0002 (00:05 载体) → handleDailyResync 全窗口重同步 + 摘要重算, 不展示;
///  - sleepy_bc_* (课前) → beforeClassDeliveryAllowed 重校验后决定是否展示
///    (← BeforeClassNotifyReceiver.onReceive: 表存在 + reminderEnabled + 节假日策略 + banner 闸);
///  - sleepy_daily_1001 / sleepy_summary_* → 当日/次日子闸重查 (← DailyNotifyReceiver /
///    TomorrowNotifyReceiver 的 isTodayReminderEnabled / isTomorrowReminderEnabled 重查)。
/// 注册点: SleepyApp 启动时 `UNUserNotificationCenter.current().delegate = SleepyNotificationDelegate.shared`
/// (共享文件, 集成者统一接线)。
final class SleepyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = SleepyNotificationDelegate()

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
                completionHandler((delivery && !suppressed) ? [.banner, .sound] : [])
            }
            return
        }
        // 每日/次日摘要 (含扇出 id): 子闸到货重查; 其他未知 id 走系统默认展示
        if NotificationScheduler.isTodaySummaryIdentifier(id) || NotificationScheduler.isTomorrowSummaryIdentifier(id) {
            let tomorrow = NotificationScheduler.isTomorrowSummaryIdentifier(id)
            let silent = notification.request.content.userInfo[NotificationScheduler.KEY_USERINFO_SUMMARY_SILENT] as? Bool ?? false
            Task {
                // 内容陈旧防御: 到货即按当前数据重算, 本轮仍展示已排内容;
                // 节假日全豁免的静默载体只触发重算、不展示 (← Android 豁免日接收器 return 不发)
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
        completionHandler()
    }
}
