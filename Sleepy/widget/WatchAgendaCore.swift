// WatchAgendaCore.swift — 表盘小组件共享议程核 (2026-11 watch 小组件扩展)
//
// 纯 Foundation — 禁 UIKit/WidgetKit/app-only API: 三 target 共源编译
//   Sleepy (iOS, 供 SleepyTests 单测) / SleepyWatch (手表 App) /
//   SleepyWatchWidgets (extension)。
//
// 口径真源 (与手表主 App 完全同源):
//   - 今日课过滤 ← WatchStore.courses(on:) (semesterStatus + AFTER_END 补班日例外 +
//     effectiveDayOfWeek + inWeek) — 本文件把该过滤口径收口为可单测的纯函数
//   - 时间反解 ← TimeTableUtils.effectiveCourseTime (ownTime/isIrregularTime 直读时钟,
//     否则 timeJson 反解) + slotLabel(display_mode node/time)
//     = 原 WatchComplicationData 私有副本的迁移终点 (不留第三份副本)
//   - 课名恒原名 (今日页口径, 不套别名)
//
// 刻意差异 (设计文档 docs/watch-widgets-design.md §5): BEFORE_START (未开学) 全空 →
// 「假期中」兜底; 表盘不做手表 App 的预习周预览 (WatchStore 预习口径仅服务 App 内周视图)。

import Foundation

enum WatchAgendaCore {

    // MARK: - 视图模型

    /// 单节课快照 — 6 个表盘 kind 共用的最小字段集
    struct ClassItem: Equatable {
        let courseName: String
        let room: String
        /// 节次短串(node 模式) 或 时间区间(time 模式) ← slotLabel
        let startLabel: String
        let startMin: Int   // 当日分钟
        let endMin: Int
        let startDate: Date // 当日 00:00 + startMin
        let endDate: Date

        /// 距开课分钟 (≥0) — 现有「下一节」口径
        func minutesUntil(from now: Date) -> Int {
            max(0, Int(startDate.timeIntervalSince(now) / 60))
        }

        /// 进行中进度 0...1 (课外钳制) — 「正在上的课」进度环/条
        func progress(at now: Date) -> Double {
            let total = endDate.timeIntervalSince(startDate)
            guard total > 0 else { return 0 }
            return min(1, max(0, now.timeIntervalSince(startDate) / total))
        }
    }

    // MARK: - 某日议程

    /// 目标日全量议程: 有效星期 + 周次过滤 → 按开课时刻排序。
    /// - date: 目标日任意时刻 (内部取当日 00:00 为基准) — 明日 = +1 day
    /// - 未开学 / 学期外非补班日 / 当日无课 → [] (调用方用 semesterStatus 区分「假期中」兜底)
    static func dayItems(table: TimeTableEntity, courses: [CourseEntity], date: Date) -> [ClassItem] {
        dayItems(table: table, courses: courses, date: date,
                 displayMode: AppPrefs.shared.getDisplayMode(),
                 transfers: HolidayTransferHelper.transfers(for: table.id))
    }

    // Widget extensions have separate standard defaults; callers can supply the shared snapshot.
    static func dayItems(table: TimeTableEntity, courses: [CourseEntity], date: Date,
                         displayMode: String, transfers: [HolidayTransferEntry]) -> [ClassItem] {
        guard let week = activeWeek(table: table, date: date, transfers: transfers) else { return [] }
        let day = HolidayTransferOps.effectiveDayOfWeek(date, transfers)
        let dayStart = Calendar(identifier: .gregorian).startOfDay(for: date)
        return courses
            .filter { $0.day == day && $0.inWeek(week) }
            .compactMap { makeItem($0, table: table, displayMode: displayMode, dayStart: dayStart) }
            .sorted { $0.startMin < $1.startMin }
    }

    /// 「下一节」= startMin > nowMin 的最早一门 (← WatchComplicationData.computeNext 口径)
    static func nextClass(in items: [ClassItem], now: Date) -> ClassItem? {
        let nowMin = minutesOfDay(now)
        return items.first { $0.startMin > nowMin }
    }

    /// 「正在上的课」= startMin ≤ nowMin < endMin (半开区间, 下课瞬间即离开)
    static func currentClass(in items: [ClassItem], now: Date) -> ClassItem? {
        let nowMin = minutesOfDay(now)
        return items.first { $0.startMin <= nowMin && nowMin < $0.endMin }
    }

    // MARK: - 学期 / 周信息

    static func semesterStatus(table: TimeTableEntity, date: Date) -> DateUtils.SemesterStatus {
        DateUtils.semesterStatus(startDate: table.startDate, maxWeek: table.maxWeek, today: date)
    }

    /// 周信息: week 1-based; ratio = week/maxWeek clamp 0...1 (maxWeek ≤ 0 → 0)
    static func weekInfo(table: TimeTableEntity, date: Date) -> (week: Int, maxWeek: Int, ratio: Double) {
        let week = DateUtils.currentWeek(startDate: table.startDate, today: date)
        let maxWeek = table.maxWeek
        let ratio = maxWeek > 0 ? min(1, max(0, Double(week) / Double(maxWeek))) : 0
        return (week, maxWeek, ratio)
    }

    // MARK: - 内部

    /// 生效周次 — nil = 该日无课语境。
    /// ← WatchStore.courses(on:) 逐分支同源; BEFORE_START 刻意 nil (见文件头注释)。
    private static func activeWeek(table: TimeTableEntity, date: Date,
                                   transfers: [HolidayTransferEntry]) -> Int? {
        switch semesterStatus(table: table, date: date) {
        case .inRange:
            return DateUtils.currentWeek(startDate: table.startDate, today: date)
        case .beforeStart:
            return nil
        case .afterEnd:
            // 补班日 = 调休映射的 sourceDate (上班日→换日上课); 其余学期外日清空 ← WatchStore 同款
            let cal = Calendar(identifier: .gregorian)
            let sourceDays = Set(transfers.map { cal.startOfDay(for: $0.sourceDate) })
            guard sourceDays.contains(cal.startOfDay(for: date)) else { return nil }
            return DateUtils.currentWeek(startDate: table.startDate, today: date)
        }
    }

    private static func minutesOfDay(_ date: Date) -> Int {
        let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// 单课 → ClassItem; 时间反解失败 → nil (跳过, ← 原 computeNext 的 continue 口径)
    private static func makeItem(_ c: CourseEntity, table: TimeTableEntity,
                                 displayMode: String, dayStart: Date) -> ClassItem? {
        guard let se = courseStartEndMin(c, table.timeJson) else { return nil }
        return ClassItem(
            courseName: c.courseName,
            room: c.room,
            startLabel: slotLabel(c, table: table, displayMode: displayMode),
            startMin: se.start,
            endMin: se.end,
            startDate: dayStart.addingTimeInterval(TimeInterval(se.start * 60)),
            endDate: dayStart.addingTimeInterval(TimeInterval(se.end * 60)))
    }

    /// ← WatchComplicationData.courseStartEndMin 迁移 (ownTime/irregular 直读时钟, 否则 timeJson)
    private static func courseStartEndMin(_ c: CourseEntity, _ timeJson: String) -> (start: Int, end: Int)? {
        guard let eff = TimeTableUtils.effectiveCourseTime(
            isIrregularTime: c.isIrregularTime || c.ownTime,
            startTime: c.startTime, endTime: c.endTime,
            startNode: c.startNode, step: c.step, timeJson: timeJson),
              let s = TimeTableUtils.hmMinutes(eff.0),
              let e = TimeTableUtils.hmMinutes(eff.1) else { return nil }
        return (s, e)
    }

    /// ← WatchComplicationData.slotLabel 迁移: display_mode node → 节次短串, 否则时间区间
    private static func slotLabel(_ c: CourseEntity, table: TimeTableEntity, displayMode: String) -> String {
        displayMode == "node" ? c.nodeString(isShort: true) : timeRange(c, table: table)
    }

    /// ← WatchComplicationData.timeRange 迁移 (ownTime·irregular 直读, irregularNode 走节次, 否则 timeJson)
    private static func timeRange(_ c: CourseEntity, table: TimeTableEntity) -> String {
        let nodes = TimeTableUtils.parseNodes(table.timeJson)
        let start: String, end: String
        if (c.ownTime || c.isIrregularTime), !c.startTime.isEmpty, !c.endTime.isEmpty {
            start = c.startTime
            end = c.endTime
        } else if c.isIrregularNode {
            return c.nodeString()
        } else {
            guard let s = nodes.first(where: { $0.node == c.startNode }),
                  let e = nodes.first(where: { $0.node == c.startNode + c.step - 1 })
            else { return "" }
            start = TimeTableUtils.formatTime(s.start)
            end = TimeTableUtils.formatTime(e.end)
        }
        return "\(start)–\(end)"
    }
}
