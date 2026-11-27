// DailyScheduleSummary.swift — ← widget/notification/DailyScheduleSummary.kt (v1.0.62 B5)
// 多课表合并「每日议程」的中间层: 每表当日课程 → 统一按真实开始时间排序的条目流。
// 纯 Foundation 逻辑(app/widget/watch 三 target 共源编译, 无 UIKit 依赖)。
//
// 调用契约(注释): 必须在 提醒开关/学期范围/节假日策略 过滤之后调用;
// 传入的 table.timeJson 必须已水合(hydratedWith)。

import Foundation

// MARK: - 时间小工具 (原版本 LocalTime 的 iOS 投影: 当日分钟数 + "HH:mm" 文本)

enum DailyAgendaTime {
    /// 分钟数 → "HH:mm" (← String.format("%02d:%02d", hour, minute))
    static func format(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// ← DailyTableCourses: 单表当日课程集
struct DailyTableCourses {
    let table: TimeTableEntity
    let courses: [CourseEntity]
}

/// ← DailyScheduleEntry
struct DailyScheduleEntry {
    let table: TimeTableEntity
    let course: CourseEntity
    /// Seconds from civil midnight. Keep seconds for ordering and merging even though labels show minutes.
    let startTimeSeconds: Int?
    let endTimeSeconds: Int?
    var startTimeMinutes: Int? { startTimeSeconds.map { $0 / 60 } }
    /// 展示文本 ← 原版本 startTimeText: 自定义时间原文 或 解析后的 "HH:mm"; 不可解析 = ""
    let startTimeText: String
}

/// ← DailyScheduleSummary
struct DailyScheduleSummary {
    let entries: [DailyScheduleEntry]
    let isMultiTable: Bool

    /// 逐行紧凑文本(多表时行首加 "[课表名] ") ← compactText
    func compactText(unknownRoom: String) -> String {
        entries.map { entry -> String in
            let source = isMultiTable ? "[\(entry.table.name)] " : ""
            let room = entry.course.room.isBlank ? unknownRoom : entry.course.room
            return "\(source)\(entry.startTimeText) \(entry.course.courseName) @ \(room)"
        }.joined(separator: "\n")
    }
}

/// ← buildDailyScheduleSummary: 提醒/学期/节假日过滤之后调用; 表必须已水合 timeJson。
/// 排序 = 无时间沉底 → 按开始时间升序(Swift 5 sort 稳定, 同键保持输入序 ← Kotlin sortedWith 稳定语义)。
/// 空表仍计入来源(明天的课可能来自另一张表) ← isMultiTable = tables.size > 1。
func buildDailyScheduleSummary(_ tables: [DailyTableCourses]) -> DailyScheduleSummary {
    let entries = tables.flatMap { tc -> [DailyScheduleEntry] in
        let table = tc.table
        let courses = tc.courses
        let bells = ReminderBellTimes(table.timeJson)
        return courses.filter { $0.tableId == table.id }.map { course -> DailyScheduleEntry in
            // ← customTime = startTime.takeIf { course.ownTime && isNotBlank }:
            // 自定义时间存在但畸形 → start=null(不回落节点时间, 原版本 同款语义)。
            // iOS 双旗适配: isIrregularTime 吞并旧 ownTime 语义(实体注释), 判定取或。
            let usesOwnTime = course.ownTime || course.isIrregularTime
            let customTime = usesOwnTime && !course.startTime.isBlank ? course.startTime : nil
            let times = bells.bounds(for: course)
            // Keep the legacy summary fallback when only the custom start is blank.
            let start = usesOwnTime && customTime == nil ? bells.nodeBounds(for: course).start : times.start
            let text = customTime ?? start.map { DailyAgendaTime.format($0 / 60) } ?? ""
            return DailyScheduleEntry(table: table, course: course,
                                      startTimeSeconds: start, endTimeSeconds: times.end, startTimeText: text)
        }
    }.sorted { a, b in
        switch (a.startTimeSeconds, b.startTimeSeconds) {
        case (nil, nil): return false        // 同 null 保持稳定序
        case (nil, _): return false          // null 沉底
        case (_, nil): return true
        case (let startA?, let startB?): return startA < startB
        }
    }
    return DailyScheduleSummary(entries: entries, isMultiTable: tables.count > 1)
}
