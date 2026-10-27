// WatchStore.swift — 手表镜像库视图态 (2026-10 watch 伴侣 App)
// 三视图 (今日/整周/设置) 共用: 收到新快照 apply 后 bump version 驱动 UI 重算。
// 查询全走共享层 ScheduleRepository/DateUtils/TimeTableUtils — 与 widget loader 同源
// (loader 文件在 watch target 排除, 手表直接按 repo 查询)。

import Foundation
import Combine
import UserNotifications
import WatchConnectivity

@MainActor
final class WatchStore: ObservableObject {
    static let shared = WatchStore()

    /// 快照代数 — apply 一次 +1, 视图 onChange 重取数据
    @Published private(set) var version = 0
    /// 上次同步时刻 (来自快照 sentAt) — 设置页显示
    @Published private(set) var lastSyncDate: Date? = nil

    private let db = AppDatabase.getShared()
    /// 每次现造 — ScheduleRepository 是无状态包装 (同一 dbQueue), 零成本
    var repo: ScheduleRepository { ScheduleRepository(db) }

    /// App 启动接线 — 调度器 repo provider 指向镜像库 + 通知授权首启申请。
    /// 不等 applySnapshot: delegate 到货 (00:05 重同步/课前重校验) 冷启动即可能触发,
    /// 届时需已接好 provider, 否则 resolveCurrentTable 返 nil 撤错通知。
    func prepareScheduler() {
        NotificationScheduler.shared.repositoryProvider = { [weak self] in self?.repo }
        // ← iPhone 侧唯一申请点 = ReminderScreen master 开关 (该 UI 不在手表),
        // 手表自有通知链路须本地授权批文才投递。2026-10 watch 伴侣 App:
        // 首启前台申请一次 (幂等, 批文后不再弹)。alert/sound 无需 Info.plist
        // usage 文案 (仅 location/calendar 类才需), 故 watch Info.plist 不加键。
        // 拒批 = 展示链路静默 (scheduleAll 的 UN add 仍入队但不投递), 与 iPhone
        // denied 后引导系统设置的语义对齐 —— 手表无引导 UI, 后续如需可加提示行。
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - 数据查询

    /// 当前展示表: 默认表 (WidgetTableResolver 三级兜底策略, 含作息水合)
    func currentTable() -> TimeTableEntity? {
        WidgetTableResolver.resolveCurrentTable(repo)
    }

    /// 今日课 (当前周过滤 + 节次排序, ← TodayWidgetLoader 同口径)
    func todayCourses(table: TimeTableEntity) -> [CourseEntity] {
        let today = Date()
        let dow = HolidayTransferHelper.effectiveDayOfWeek(table.id, today)
        let week = DateUtils.currentWeek(startDate: table.startDate, today: today)
        let status = DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: today)
        guard status == .inRange else { return [] }
        return ((try? repo.getCoursesByDay(table.id, day: dow)) ?? [])
            .filter { $0.inWeek(week) }
            .sorted { $0.startNode < $1.startNode }
    }

    /// 某天课 (周视图列) — 学期外/调休日口径与 todayCourses 同源
    func courses(on date: Date, table: TimeTableEntity) -> [CourseEntity] {
        let status = DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: date)
        guard status == .inRange else { return [] }
        let dow = HolidayTransferHelper.effectiveDayOfWeek(table.id, date)
        let week = DateUtils.currentWeek(startDate: table.startDate, today: date)
        return ((try? repo.getCoursesByDay(table.id, day: dow)) ?? [])
            .filter { $0.inWeek(week) }
            .sorted { $0.startNode < $1.startNode }
    }

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
        lastSyncDate = body.sentAt > 0 ? Date(timeIntervalSince1970: Double(body.sentAt) / 1000) : Date()
        version += 1
        // prefs 落盘后立即重排手表本地通知 (scheduleAll 全链路 UN 调用, watch 可用;
        // BGTask 分支已被 WATCH_APP 守卫裁掉)。master 关时 scheduleAll=撤净, 语义自洽。
        // ⚠ 前提 = 通知授权已批 (AppEntry 首次请求); watchOS 在批文到达前不投递。
        rescheduleNotifications()
    }

    private func rescheduleNotifications() {
        // provider 已在 prepareScheduler 接好; 此处只重排
        NotificationScheduler.shared.scheduleAll()
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
