// ClassDndScheduler.swift — ← widget/notification/ClassDndScheduler.kt
// 上课自动勿扰调度器 (参照 shiguang DndSchedulerWorker)。
//
// iOS 平台差异(适配而非省略):
//   - Android: 通知策略访问权限 + setInterruptionFilter(系统级 DND 切换)
//   - iOS: 无系统级勿扰写入 API(UNNotificationSettings 只读;
//     Focus 状态 NSSetUnabridged... 需要 Apple 授权的 Screen Time API)
//   - 等价适配: 上课区间内抑制本 app 自己的课前通知投放 — 投放闸即
//     shouldSuppressNotification(now:)。到货 delegate 已存在:
//     NotificationScheduler.swift 的 SleepyNotificationDelegate.willPresent,
//     其 sleepy_bc_* 分支现只查 beforeClassDeliveryAllowed, 尚未 AND 本闸 —
//     ⚠ 两处接线归集成者(共享文件, F128 issue#1):
//     (a) SleepyApp.swift didFinishLaunching:
//         UNUserNotificationCenter.current().delegate = SleepyNotificationDelegate.shared
//     (b) SleepyNotificationDelegate.willPresent 的 sleepy_bc_ 分支:
//         allowed = await beforeClassDeliveryAllowed(...) &&
//                   !(await ClassDndScheduler.shouldSuppressNotification())
//     接线落地前本闸无调用方 (对齐审计 F128 issue#1 记录此缺口)。
//     (iOS 通知即日历触发器, 无独立闹钟链可断 — 无需"两颗配对闹钟自续",
//     但保留纯函数边界计算供复用)
//
// 契约(保留):
//  - 枚举未来 WINDOW_DAYS 天的课程区间
//  - isCurrentlyInClass / nextBoundaries / courseInterval 纯函数, 可测
//  - DND 状态持久化(owned + savedFilter) — iOS 端 savedFilter 语义退化为
//    "用户之前是否被我们抑制"标记, 离开时自动恢复

import Foundation

final class ClassDndScheduler {
    static let shared = ClassDndScheduler()

    /// 下一次课程区间边界; nil = 窗口内无未来边界。
    struct Boundaries {
        let nextStart: Date?
        let nextEnd: Date?
    }

    static let WINDOW_DAYS = 7

    /// ← Android companion `savedFilter` 默认值 (NotificationManager.INTERRUPTION_FILTER_ALL)。
    /// iOS 无系统级 DND 可快照/恢复, 此常量只保留"离开时恢复到系统初始档"的契约语义,
    /// 供 SleepyTests/ClassDndSchedulerTests.swift 锁定默认值不变 (F128 issue#5)。
    static let savedFilterDefault = 1  // INTERRUPTION_FILTER_ALL

    /// 独立状态文件 — 与 Android DND_STATE_FILE 对齐。
    private static let DND_STATE_FILE = "sleepy_class_dnd_state"
    private static let KEY_DND_OWNED = "entered_by_app"

    /// ⚠ 必须在 AppDelegate.init 调用 (← Android SleepyApp 注入 classDndScheduler):
    ///   ClassDndScheduler.shared.configure(repositoryProvider: { [weak self] in self?.repository })
    /// 否则 repositoryProvider 恒 nil, rebuildState/shouldSuppressNotification 短路返回。
    /// (共享文件 SleepyApp.swift 接线, 集成者负责 — F128 issue#2)
    private var repositoryProvider: (() -> ScheduleRepository?)?

    func configure(repositoryProvider: (() -> ScheduleRepository?)?) {
        self.repositoryProvider = repositoryProvider
    }

    private var dndPrefs: UserDefaults? {
        UserDefaults(suiteName: Self.DND_STATE_FILE)
    }

    // ==================== 纯函数边界计算 (JVM 可测, ← companion object) ====================

    /// 当前时刻是否处于某节课区间 [start, end) 内。
    static func isCurrentlyInClass(_ intervals: [(Date, Date)], now: Date) -> Bool {
        return intervals.contains { s, e in now >= s && now < e }
    }

    /// 未来边界: 只取 still-future 的最早开始/最早结束。
    static func nextBoundaries(_ intervals: [(Date, Date)], now: Date) -> Boundaries {
        let starts = intervals.map { $0.0 }.filter { $0 > now }
        let ends = intervals.map { $0.1 }.filter { $0 > now }
        return Boundaries(
            nextStart: starts.min(),
            nextEnd: ends.min()
        )
    }

    /// Kotlin `isNotBlank()` 等价 (← CourseEntity.isNotBlank 同语义):
    /// 纯空白串视为空 → ownTime 课程回落节点表, 而非直接判破损跳过 (Android 同行为)。
    private static func isNotBlank(_ s: String) -> Bool {
        return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 单门课 → (start, end) 区间; 时间不可解析/非法 → nil 跳过。
    static func courseInterval(
        date: Date,
        course: CourseEntity,
        nodes: [TimeTableUtils.NodeTime]
    ) -> (Date, Date)? {
        let cal = DateUtils.isoCalendar
        let startStr: String
        if course.ownTime && isNotBlank(course.startTime) {
            startStr = course.startTime
        } else if let node = nodes.first(where: { $0.node == course.startNode }) {
            startStr = TimeTableUtils.formatTime(node.start)
        } else {
            return nil
        }
        let endNode = course.startNode + course.step - 1
        let endStr: String
        if course.ownTime && isNotBlank(course.endTime) {
            endStr = course.endTime
        } else if let node = nodes.first(where: { $0.node == endNode }) {
            endStr = TimeTableUtils.formatTime(node.end)
        } else {
            return nil
        }
        let sp = startStr.split(separator: ":").map(String.init)
        let ep = endStr.split(separator: ":").map(String.init)
        guard let sh = Int(sp.count > 0 ? sp[0] : ""), let sm = Int(sp.count > 1 ? sp[1] : ""),
              let eh = Int(ep.count > 0 ? ep[0] : ""), let em = Int(ep.count > 1 ? ep[1] : ""),
              (0...23).contains(sh), (0...59).contains(sm),
              (0...23).contains(eh), (0...59).contains(em) else { return nil }
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = sh; comps.minute = sm
        guard let start = cal.date(from: comps) else { return nil }
        comps.hour = eh; comps.minute = em
        guard let end = cal.date(from: comps) else { return nil }
        if end <= start { return nil }   // 跨天课罕见, 保守跳过
        return (start, end)
    }

    // ==================== 区间构建 (异步 — 节假日策略查缓存) ====================

    /// 枚举未来 WINDOW_DAYS 天的课程区间。
    func buildIntervals(table: TimeTableEntity) async -> [(Date, Date)] {
        let cal = DateUtils.isoCalendar
        let today = cal.startOfDay(for: Date())
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        var result: [(Date, Date)] = []
        guard let repo = repositoryProvider?() else { return result }
        for offset in 0..<Self.WINDOW_DAYS {
            guard let date = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            if DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: date) != .inRange {
                continue
            }
            // 与课前通知同一日期语义 — 节假日策略门控
            if !(await HolidayReminderPolicyAdapter.decide(date: date, tableId: table.id)).allowReminder {
                continue
            }
            let week = DateUtils.currentWeek(startDate: table.startDate, today: date)
            let dow = HolidayTransferHelper.effectiveDayOfWeek(table.id, date)
            let courses = ((try? repo.getCoursesByDay(table.id, day: dow)) ?? []).filter { $0.inWeek(week) }
            for course in courses {
                if let interval = Self.courseInterval(date: date, course: course, nodes: nodes) {
                    result.append(interval)
                }
            }
        }
        return result
    }

    // ==================== 开关同步 ← syncFromPrefs ====================

    /// 开关入口 (ReminderScreen 调): 开 → 标记 active; 关 → 清除抑制状态。
    func syncFromPrefs() {
        if AppPrefs.shared.isClassDndEnabled() {
            // iOS: 无闹钟链可排 — 状态在 willPresent 投放时实时查询
            Task { await rebuildState() }
        } else {
            disableAndRestore()
        }
    }

    func reconcileReminderRules() {
        syncFromPrefs()
    }

    /// 校准当下抑制状态。
    private func rebuildState() async {
        guard AppPrefs.shared.isClassDndEnabled() else {
            clearOwnership()
            return
        }
        guard let repo = repositoryProvider?(),
              let table = WidgetTableResolver.resolveCurrentTable(repo) else {
            clearOwnership()
            return
        }
        let intervals = await buildIntervals(table: table)
        let inClass = Self.isCurrentlyInClass(intervals, now: Date())
        setDndOwned(inClass)
    }

    /// 关闭开关: 清除抑制现场。
    func disableAndRestore() {
        clearOwnership()
    }

    // ==================== 投放闸 (delegate willPresent 调) ====================

    /// 课前通知投放前查询: 上课勿扰开启且正处于课中 → true(抑制)。
    static func shouldSuppressNotification(now: Date = Date()) async -> Bool {
        guard AppPrefs.shared.isClassDndEnabled() else { return false }
        guard let repo = ClassDndScheduler.shared.repositoryProvider?(),
              let table = WidgetTableResolver.resolveCurrentTable(repo) else { return false }
        let intervals = await ClassDndScheduler.shared.buildIntervals(table: table)
        return isCurrentlyInClass(intervals, now: now)
    }

    // ==================== 状态持久化 ====================

    private func isDndOwned() -> Bool {
        return dndPrefs?.bool(forKey: Self.KEY_DND_OWNED) ?? false
    }

    private func setDndOwned(_ owned: Bool) {
        dndPrefs?.set(owned, forKey: Self.KEY_DND_OWNED)
    }

    private func clearOwnership() {
        setDndOwned(false)
    }
}
