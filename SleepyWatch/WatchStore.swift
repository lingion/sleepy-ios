// WatchStore.swift — 手表镜像库视图态 (2026-10 watch 伴侣 App)
// 三视图 (今日/整周/设置) 共用: 收到新快照 apply 后 bump version 驱动 UI 重算。
// 查询全走共享层 ScheduleRepository/DateUtils/TimeTableUtils — 与 widget loader 同源
// (loader 文件在 watch target 排除, 手表直接按 repo 查询)。

import Foundation
import Combine
import UserNotifications
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchStore: ObservableObject {
    static let shared = WatchStore()

    /// 快照代数 — apply 一次 +1, 视图 onChange 重取数据
    @Published private(set) var version = 0
    /// 上次同步时刻 (来自快照 sentAt) — 设置页显示
    @Published private(set) var lastSyncDate: Date? = nil
    /// 手表已应用回执时刻 = 快照镜像的 ackSentAt (单源 iPhone, 手表不写本地键)
    @Published private(set) var ackDate: Date? = nil

    private let db = AppDatabase.getShared()
    /// 每次现造 — ScheduleRepository 是无状态包装 (同一 dbQueue), 零成本
    var repo: ScheduleRepository { ScheduleRepository(db) }

    /// App 启动接线 — 调度器 repo provider 指向镜像库 + 通知授权首启申请。
    /// 不等 applySnapshot: delegate 到货 (00:05 重同步/课前重校验) 冷启动即可能触发,
    /// 届时需已接好 provider, 否则 resolveCurrentTable 返 nil 撤错通知。
    func prepareScheduler() {
        NotificationScheduler.shared.repositoryProvider = { [weak self] in self?.repo }
        // 手表自有通知链路须本地授权批文才投递 (申请点唯一, 幂等)。
        // alert/sound 无需 Info.plist usage 文案 (仅 location/calendar 类才需)。
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - 数据查询

    /// 当前展示表: 默认表 (WidgetTableResolver 三级兜底策略, 含作息水合)
    func currentTable() -> TimeTableEntity? {
        WidgetTableResolver.resolveCurrentTable(repo)
    }

    /// 今日课 (调休换日 + 当前周过滤 + 节次排序, ← TodayWidgetLoader 同口径)
    func todayCourses(table: TimeTableEntity) -> [CourseEntity] {
        courses(on: Date(), table: table)
    }

    /// 当前表全部课 — 课程清单分组用 (← CourseListScreen 数据源
    /// viewModel.state.courses)。不按日/周过滤, 取整表。
    func allCourses(table: TimeTableEntity) -> [CourseEntity] {
        (try? repo.getCourses(table.id)) ?? []
    }

    /// 展示日语境 ← WidgetWeekDataLoader.resolve / ScheduleViewModel:259 逐参同口径:
    /// nearest_busy_day 镜像开时, 今日无剩余课 → 跳最近有课日。
    /// ⚠ 只作用于「周」语义 (手表周视图锚定周 = iOS 周页/WidgetWeekSource);
    /// iOS 今日页 (TodayScreen) 恒真实今天不跳日 — 手表今日页同口径, 不调本函数。
    /// (WeekDisplayResolver 已编入手表 target, 与手机同一决策核)。
    func displayContext(_ table: TimeTableEntity, now: Date = Date()) -> WeekDisplayContext {
        let courses = (try? repo.getCourses(table.id)) ?? []
        return WeekDisplayResolver.resolve(
            startDate: table.startDate, maxWeek: table.maxWeek, now: now,
            courses: courses, timeJson: table.timeJson,
            enabled: AppPrefs.shared.isNearestBusyDay(),
            transfers: HolidayTransferHelper.transfers(for: table.id))
    }

    /// 周视图锚定日 — NEAREST_BUSY_DAY 档取 targetDate, 其余为今天
    /// (← WidgetWeekSource.resolvedToday)
    func weekAnchorDate(_ table: TimeTableEntity) -> Date {
        let d = displayContext(table)
        return d.status == .nearestBusyDay ? d.targetDate : Date()
    }

    /// 某天课 — ← WidgetWeekDataLoader.coursesOn 全语义:
    /// 学期前「第 1 周课」预习照常显示 (previewBeforeStart)、学期后仅调休
    /// 补班日 (该日在 transfer 映射 sourceDate 集内) 显示映射到的周课, 否则空。
    func courses(on date: Date, table: TimeTableEntity) -> [CourseEntity] {
        let status = DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: date)
        let week: Int
        switch status {
        case .inRange:
            week = DateUtils.currentWeek(startDate: table.startDate, today: date)
        case .beforeStart:
            week = 1   // 预习周固定按第 1 周口径 (真源 previewBeforeStart=true)
        case .afterEnd:
            // 补班日 = 调休映射的 sourceDate (上班日→换日上课); 其余学期外日清空
            let sourceDays = Set(HolidayTransferHelper.transfers(for: table.id)
                .map { cal.startOfDay(for: $0.sourceDate) })
            guard sourceDays.contains(cal.startOfDay(for: date)) else { return [] }
            week = DateUtils.currentWeek(startDate: table.startDate, today: date)
        }
        let dow = HolidayTransferHelper.effectiveDayOfWeek(table.id, date)
        return ((try? repo.getCoursesByDay(table.id, day: dow)) ?? [])
            .filter { $0.inWeek(week) }
            .sorted { $0.startNode < $1.startNode }
    }

    // MARK: - 节假日/灰显 (同步决策核, 纯读磁盘镜像 — 零网络零 await)

    /// 该日灰显判定 — 与 iOS HolidayManager.shouldGrey 的决策核同源: 磁盘缓存
    /// (v2 快照灌入) + 用户覆盖段合并 → decideGrey。镜像未含当年数据返 false
    /// (手表无网络不兜底 — 宁不灰不联网)。iOS 侧磁盘读取是 private, 手表走
    /// 公开 diskEntries 重建同等输入。
    func shouldGrey(_ date: Date, tableId: Int64) -> Bool {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        let network = HolidayManager.diskEntries(year) ?? []
        let merged = HolidayRangeOps.mergeSegments(network, AppPrefs.shared.getHolidayRanges())
        let (holidays, networkWorkdays) = HolidayRangeOps.toSets(merged.active)
        let transfers = HolidayTransferHelper.transfers(for: tableId)
        // 补班日 = 网络法定补班 + 用户映射 targetDate; ignoreWorkday 开时豁免周末灰显
        // (← HolidayManager.shouldGrey 同口径)
        let customWorkdays = Set(transfers.map { cal.startOfDay(for: $0.targetDate) })
        let workdaysForWeekend = (AppPrefs.shared.isHolidayGreyWeekend() && AppPrefs.shared.isHolidayIgnoreWorkday())
            ? networkWorkdays.union(customWorkdays) : []
        let hasTransfer = transfers.contains { cal.isDate($0.sourceDate, inSameDayAs: date) }
        return HolidayManager.decideGrey(
            date: date, holidays: holidays, workdays: workdaysForWeekend,
            greyHoliday: AppPrefs.shared.isHolidayGreyHoliday(),
            greyWeekend: AppPrefs.shared.isHolidayGreyWeekend(),
            ignoreWorkday: AppPrefs.shared.isHolidayIgnoreWorkday(),
            dateHasTransfer: hasTransfer)
    }

    /// 该日是否调休映射的上班日 (sourceDate) — 周视图换日标记
    func isTransferSourceDay(_ date: Date, tableId: Int64) -> Bool {
        HolidayTransferHelper.transfers(for: tableId)
            .contains { cal.isDate($0.sourceDate, inSameDayAs: date) }
    }

    /// 节假日标注 — 「放假/补班 X」, 前缀复用 iOS 同源键 (holiday_list_holidays /
    /// holiday_workday_badge), 无条目 (纯周末/手动禁课日) → 「无课」(no_course)。
    /// 仅灰显日调用 — 是否灰显由 shouldGrey 决定, 标注只是其可视化。
    func greyAnnotation(_ date: Date, tableId: Int64) -> String {
        guard let entry = holidayEntry(on: date) else { return L10n.t("no_course") }
        let prefix = entry.type == HolidayManager.TYPE_PUBLIC_HOLIDAY
            ? L10n.t("holiday_list_holidays")
            : L10n.t("holiday_workday_badge")
        return entry.name.isEmpty ? prefix : "\(prefix) \(entry.name)"
    }

    /// 磁盘镜像中该日条目 (nil=无); 只认「非补班=休 / 补班=班」两型, 与 iOS 同源
    private func holidayEntry(on date: Date) -> HolidayEntry? {
        let year = cal.component(.year, from: date)
        return HolidayManager.diskEntries(year)?
            .first { cal.isDate($0.date, inSameDayAs: date) }
    }

    /// 行卡时段标签 ← 镜像 display_mode 二选一: time=「08:00–09:40」(默认),
    /// node=「1-2 节」节次。AppPrefs KEY_DISPLAY_MODE 字面量 (契约常量收口后
    /// watch 侧不反向依赖 sync 层)。
    func slotLabel(_ course: CourseEntity, table: TimeTableEntity) -> String {
        AppPrefs.shared.getDisplayMode() == "node"
            ? course.nodeString(isShort: true)
            : timeRange(course, table: table)
    }

    // MARK: - 显示口径 (v2 镜像 prefs 直读, 零独有开关)

    /// 别名口径对位 iOS 实况: 仅网格周视图套 grid_use_alias (WeekView);
    /// week_use_alias 属 iOS 纵向周页 (手表无该形态, 镜像落盘但不消费)。
    /// 今日行卡/详情恒原名 (← TodayScreen:303 / CourseDetailSheet:44 实况,
    /// 均不套别名)。
    var useGridAlias: Bool { AppPrefs.shared.isGridUseAlias() }
    /// 星期列显日期 ← show_date
    var showDate: Bool { AppPrefs.shared.isShowDate() }
    /// 周视图固定周一起 (iOS 无周起始设置, 手表=手机口径; 换日标记按日集合判定)
    /// 今日无课自动跳最近有课日 ← nearest_busy_day
    var nearestBusyDay: Bool { AppPrefs.shared.isNearestBusyDay() }
    /// 可见星期 (周一1..周日7) ← visible_days; 空集防御 = 全显 (同 iOS getter 兜底)
    var visibleDays: Set<Int> { AppPrefs.shared.getVisibleDays() }
    /// 无色模式 (镜像 course_colorless) — 色条降级 neutral
    var neutralColor: Bool { AppPrefs.shared.isCourseColorless() }

    private let cal = Calendar(identifier: .gregorian)

    /// 课程时刻 "HH:mm–HH:mm" (ownTime 直读 / 节次查表, 水合表优先)
    func timeRange(_ course: CourseEntity, table: TimeTableEntity) -> String {
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        let start: String
        let end: String
        if (course.ownTime || course.isIrregularTime), !course.startTime.isEmpty, !course.endTime.isEmpty {
            start = course.startTime; end = course.endTime
        } else if course.isIrregularNode {
            return course.nodeString()
        } else {
            guard let s = nodes.first(where: { $0.node == course.startNode }),
                  let e = nodes.first(where: { $0.node == course.startNode + course.step - 1 })
            else { return "" }
            start = TimeTableUtils.formatTime(s.start)
            end = TimeTableUtils.formatTime(e.end)
        }
        return "\(start)–\(end)"
    }

    /// 手表周天序列 (周一..周日) — iOS 无周起始设置, 固定周一起=手机口径。
    /// 过滤 (visible_days + 周末) 由视图做, 顺序/日期锚定在此。
    func weekDates(today: Date) -> [Date] {
        let monday = DateUtils.mondayOf(today)
        return (0..<7).map { cal.date(byAdding: .day, value: $0, to: monday)! }
    }

    // MARK: - 快照应用 (WatchSyncReceiver → 本方法)

    /// 全量重建镜像 + prefs 落盘 + 通知重排 + UI bump。
    /// apply 失败 (坏载荷/DB 异常) → 保留旧镜像, 不落半成品。
    func applySnapshot(_ body: WatchSyncSnapshot.Body) {
        do {
            try WatchSyncSnapshot.apply(db: db, body: body)
        } catch {
            WidgetArchiveLog.append(kind: "watch", family: "apply", result: "fail \(String(describing: error))")
            return
        }
        WatchSyncSnapshot.applyPrefs(body.prefs)
        // 镜像快照已落 course_colors → 重读本地快照, 手表课程色与手机一致。
        CourseHueStore.shared.invalidate(mode: AppPrefs.shared.getCourseColorMode(),
                                         dao: db.courseColorDao)
        lastSyncDate = body.sentAt > 0 ? Date(timeIntervalSince1970: Double(body.sentAt) / 1000) : Date()
        // 「已同步」回执时刻 = 镜像 ackSentAt (>0 才显)。外层括号强制 Optional flatMap
        // (无括号时 flatMap 绑到解包后的 Int64 → 编译错, swiftc 实测)。
        ackDate = (body.prefs?.ackSentAt).flatMap { $0 > 0 ? Date(timeIntervalSince1970: Double($0) / 1000) : nil }
        version += 1
        // prefs 落盘后立即重排手表本地通知 (BGTask 分支已被 WATCH_APP 守卫裁掉)。
        // master 关时 scheduleAll=撤净, 语义自洽。⚠ 前提=通知授权已批 (prepareScheduler)。
        NotificationScheduler.shared.scheduleAll()
        // 表盘复杂功能刷新 (PR#16): 镜像数据变 → 重算「下一节」timeline。
        // extension 进程独立读同 App Group 容器 GRDB, reload 触发其 getTimeline 重跑。
        WidgetCenter.shared.reloadAllTimelines()
        // 回执经 context[watchAck] 送 iPhone (Coordinator 消费存 AppPrefs → capture
        // 镜像回手表; 手机不在线时 context 由系统代存, 上线自动消费 — 「最近意图」语义)。
        sendAck(body.sentAt)
    }

    private func sendAck(_ sentAt: Int64) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated else { return }
        // sentAt<=0 的旧版载荷回本地时刻兜底 (回执语义「已应用」不失效)
        let ms = sentAt > 0 ? sentAt : Int64(Date().timeIntervalSince1970 * 1000)
        do {
            try s.updateApplicationContext([WatchSyncSnapshot.keyAckPayload: ms])
        } catch {
            WidgetArchiveLog.append(kind: "watch", family: "ack", result: "fail \(String(describing: error))")
        }
    }

    // MARK: - 冷启动补拉

    /// 手表端主动 requestContents (iPhone 在 didReceiveMessage 回全量)
    func requestSync() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        // 手表侧无 isPaired/isWatchAppInstalled (那是 iPhone 端 API); 可达性 =
        // iPhone App 正在跑, sendMessage 只对可达端有意义, 不可达静默跳过 —
        // applicationContext 代存兜底仍在 (receiver 激活回调会消费)。
        guard s.activationState == .activated, s.isReachable else { return }
        try? s.sendMessage([WatchSyncSnapshot.keyRequestContents: true], replyHandler: nil)
    }
}
