// WidgetBoundaryScheduler.swift — ← widget/WidgetBoundaryScheduler.kt (含 WidgetBoundaryReceiver)
//
// 课程边界刷新调度器 (设计文稿 widget-redesign-2026-09 §5)。
//
// FIXED 窗口的锚点/页脚在「一行结束」的瞬间变化(进行中→下一节 / 全结束→ALL_DONE),
// iOS 等价实现已在 TodayWidgetView.getTimeline 内联 (← f7e80c84 把"下一节下课的下一分钟"
// 作为 timeline entry,到点自动换页; 原版本 用 AlarmManager 重推)。
// 本文件 = 纯函数 / 文档契约层, 写 Schedule 入口时复用。
//
// 原版本 备注: 收集行 end 分钟排一颗单次闹钟, 15-min 周期兜底;
// 权限降级 (评审 #12): S+ 无精确闹钟 → setAndAllowWhileIdle 静默不精确。
// 链自续: 边界到点 → WidgetBoundaryReceiver → notifyDataChanged → armNext 重排。
// iOS 差异: WidgetKit timeline policy = .after(...) + boundaryDates 自动驱动, 详见
// TodayWidgetView.swift / TwoDayWidgetView.swift 注释。

import Foundation

/// 窗口锚点随课程边界变化的族 (WeekList/WeekView 为 HEAD 列式, 无边界语义)。
/// ← BOUNDARY_FAMILIES: Today / TodaySmall / TwoDay / TwoDaySmall / WeekGridSmall
enum WidgetBoundaryFamily: String, CaseIterable {
    case todayWidgetRV = "TodayWidgetRV"
    case twoDayWidgetRV = "TwoDayWidgetRV"
    case weekGridWidgetV19 = "WeekGridWidgetV19"
}

enum WidgetBoundaryScheduler {

    /// Keep the periodic fallback, but reload date/week-dependent data at the next civil midnight.
    static func nextRefresh(after date: Date, calendar: Calendar = .current) -> Date {
        let periodic = date.addingTimeInterval(6 * 3600)
        guard let midnight = calendar.date(byAdding: .day, value: 1,
                                           to: calendar.startOfDay(for: date)) else { return periodic }
        return min(periodic, midnight)
    }

    /// 纯函数: 下一边界分钟 = min(end+1) 且 > nowMin; 无未来边界 → nil。
    /// ← nextBoundaryMin
    static func nextBoundaryMin(_ endMins: [Int], nowMin: Int) -> Int? {
        endMins.map { $0 + 1 }.filter { $0 > nowMin }.min()
    }

    /// 行 end 分钟 — 与 FIXED 锚点同一契约 (effectiveCourseTime 真实分钟, 行取 max)。
    /// ← rowEndMins; 提供占位 height 38f (与原实现一致, 值未参与判定)
    static func rowEndMins(courses: [CourseEntity], timeJson: String?) -> [Int] {
        let rows = ConflictLayoutEngine.weekLaneRows(courses, timeJson: timeJson)
        return WidgetWindowCore.entriesOf(rows: rows, timeJson: timeJson) { _ in 38 }
            .compactMap { $0.endMin }
    }
}
