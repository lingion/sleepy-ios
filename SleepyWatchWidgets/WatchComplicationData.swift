// WatchComplicationData.swift — 「下一节」表盘复杂功能数据装载 (2026-10 watch 伴侣 App)
// ← plan 阶段四: Timeline 在课程边界刷新; 数据源 = 手表本地 GRDB。
// applySnapshot 后主 app 调 WidgetCenter.shared.reloadAllTimelines() 触发重算
// (SleepyWatch/WatchStore.swift 末尾)。
//
// 2026-11 小组件扩展: 业务口径迁移至 WatchAgendaCore (学期过滤/调休换日/周次/
// 时间反解/startLabel — 原私有副本的迁移终点, 不留第三份副本), 本文件只剩
// GRDB 装载 + WatchNextClass 视图模型映射。
// 行为差异(刻意, 与手表 App 今日页对齐): afterEnd 补班日由「无课」改为出课;
// 同日多课排序由节次改为实际开课时刻 (ownTime 重叠课的更准确次序)。

import Foundation

/// 表盘用的「下一节」快照。nil = 今天无未开始课 (semester 外 / 全上完 / 无表)。
struct WatchNextClass {
    let courseName: String
    let room: String
    let startLabel: String   // slotLabel 同口径 (节次 or 时间)
    let minutesUntil: Int    // 距开课分钟 (≥0)
    let startDate: Date      // 开课绝对时刻 (Timeline 刷新锚点)
}

enum WatchComplicationData {
    /// 装载当前表 + 今天 + 下一节。任一环节缺失 → (table: nil, next: nil)。
    static func load(now: Date = Date()) -> (table: TimeTableEntity?, next: WatchNextClass?) {
        let repo = ScheduleRepository(AppDatabase.getShared())
        guard let table = WidgetTableResolver.resolveCurrentTable(repo) else {
            return (nil, nil)
        }
        let courses = (try? repo.getCourses(table.id)) ?? []
        let items = WatchAgendaCore.dayItems(table: table, courses: courses, date: now)
        guard let next = WatchAgendaCore.nextClass(in: items, now: now) else {
            return (table, nil)
        }
        return (table, WatchNextClass(
            courseName: next.courseName,
            room: next.room,
            startLabel: next.startLabel,
            minutesUntil: next.minutesUntil(from: now),
            startDate: next.startDate))
    }
}
