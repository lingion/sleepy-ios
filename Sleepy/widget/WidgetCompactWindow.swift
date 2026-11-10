// WidgetCompactWindow.swift — ← widget/WidgetCompactWindow.kt + WidgetCompactWindowCore.kt
//   + WidgetCompactWindowStore.kt (三文件合一, 职责分区注释保留)
//
// 最小档三天窗口数据构建 (2026-09-15 用户令) — 「本周课表（列表/周视图）· 小」专用。
//
// 窗口 = compactWindowDates 的三天真实日期; 列序与星期随展示日, 可跨上下周。
// 调休课程反向查来源日期与周次; 定日课仅跟随自己的自然日, 不参与调休。
// 普通学期前日期预习第 1 周常规课; 补班日按来源日期判定学期范围。
//
// ★ 平台差异 (WidgetBindingStore.swift 头注同源): 原版本 per-appWidgetId → iOS per-kind。
//   Core 的 key 形状按 kind 字符串 1:1 保留 (raw map 进出, 迁移语义逐条对齐);
//   Store 的持久层 = App Group 共享容器 JSON 文件 (等价 SharedPreferences 文件)。

import Foundation

// MARK: - WidgetCompactWindowCore (纯逻辑, 可单测)

/// Per-widget(=kind) 三天窗口档位纯逻辑 (2026-09-15 用户定稿: 设置从管理页外卡挪进
/// 「· 小」变体的二级编辑页, 每个实例各管各的)。
///
/// 与 WidgetScrollCore 同模式: raw prefs map 进出, 零平台依赖, 纯可测。
/// 迁移语义: 本实例从未显式设置过 → 继承旧全局值 (老用户升级后行为不变);
/// 编辑页一旦拨动即写显式值, 与旧全局彻底脱钩。
enum WidgetCompactWindowCore {

    /// ← PREFS_NAME("widget_compact_window_prefs") + ".json" 后缀 (JSON 文件持久层)
    static let storeFileName = "widget_compact_window_prefs.json"

    static func key(_ widgetId: String) -> String { "compact_today_first_\(widgetId)" }

    /// 显式值; nil = 从未设置 (调用方按迁移语义回退旧全局)。
    static func read(_ raw: [String: Bool], _ widgetId: String) -> Bool? { raw[key(widgetId)] }

    static func write(_ raw: inout [String: Bool], _ widgetId: String, _ todayFirst: Bool) {
        raw[key(widgetId)] = todayFirst
    }

    static func delete(_ raw: inout [String: Bool], _ widgetId: String) {
        raw.removeValue(forKey: key(widgetId))
    }

    /// 生效值 = 显式值 ?: 旧全局 (出厂默认 true = 今日居第一位)。
    static func resolve(_ explicit: Bool?, _ legacyGlobal: Bool) -> Bool {
        explicit ?? legacyGlobal
    }
}

// MARK: - WidgetCompactWindowStore (持久化 facade)

/// [WidgetCompactWindowCore] 的 JSON 文件读写壳 (等价 原版本 SharedPreferences)。
///
/// 控制「· 小」变体 compact 脸的三天窗口方向: true = 今日居第一位
/// (今天/明天/后天), false = 今日居第二位 (昨天/今天/明天)。
enum WidgetCompactWindowStore {

    /// 本实例生效值 = 显式设置 ?: 旧全局值 (升级老用户行为不变)。
    static func isTodayFirst(_ widgetId: String) -> Bool {
        WidgetCompactWindowCore.resolve(read(widgetId), AppPrefs.shared.isCompactWindowTodayFirst())
    }

    static func setTodayFirst(_ widgetId: String, _ todayFirst: Bool) {
        lock.lock(); defer { lock.unlock() }
        var raw = loadAll()
        WidgetCompactWindowCore.write(&raw, widgetId, todayFirst)
        saveAll(raw)
    }

    /// 实例删除时清位 — 回收的 widget 不得继承前任的窗口偏好。
    static func remove(_ widgetId: String) {
        lock.lock(); defer { lock.unlock() }
        var raw = loadAll()
        WidgetCompactWindowCore.delete(&raw, widgetId)
        saveAll(raw)
    }

    // 读改写互斥 (synchronized(writeLock): 读全量→改一条→重写全量非原子)
    private static let lock = NSLock()

    private static func storeURL() -> URL {
        AppGroupResolver.sharedDirectory().appendingPathComponent(WidgetCompactWindowCore.storeFileName)
    }

    private static func read(_ widgetId: String) -> Bool? {
        WidgetCompactWindowCore.read(loadAll(), widgetId)
    }

    private static func loadAll() -> [String: Bool] {
        guard let data = try? Data(contentsOf: storeURL()),
              let map = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return [:]
        }
        return map
    }

    private static func saveAll(_ data: [String: Bool]) {
        guard let data = try? JSONEncoder().encode(data) else { return }
        try? data.write(to: storeURL(), options: .atomic)
    }
}

// MARK: - WidgetCompactWindow (数据构建) ← WidgetCompactWindow.kt

/// 最小档三天窗口数据构建 — 原 suspend → Swift async, 语义逐行对齐。
enum WidgetCompactWindow {

    static func build(
        repo: ScheduleRepository,
        tableId: Int64,
        timeJson: String,
        startDate: String,
        maxWeek: Int,
        today: Date,
        todayFirst: Bool,
        displayDate: Date? = nil
    ) async -> [DayData] {
        let anchorDate = displayDate ?? today
        let dates = WidgetCompactHelpers.compactWindowDates(today, todayFirst, anchorDate)
        let rows = (try? repo.getCourses(tableId)) ?? []
        // ← dates.map 内 await HolidayManager → 闭包需 async; Sequence.map
        //   不接 async 闭包, 改 for 循环累加 (行为 1:1, 顺序保持, async 透传)
        var result: [DayData] = []
        for effectiveDate in dates {
            let dow = DateUtils.todayDayOfWeek(today: effectiveDate)
            let sourceDate = HolidayTransferHelper.courseDateForDate(tableId, effectiveDate)
            let week = DateUtils.currentWeek(startDate: startDate, today: sourceDate ?? effectiveDate)
            // Kotlin LocalDate equality compares civil days. Widget timelines
            // can carry a time of day, while persisted transfers are midnight.
            let isOriginalDay = sourceDate.map {
                HolidayTransferOps.dayKey($0) == HolidayTransferOps.dayKey(effectiveDate)
            } ?? false
            let visible: [CourseEntity]
            if isOriginalDay && DateUtils.semesterStatus(
                startDate: startDate, maxWeek: maxWeek, today: effectiveDate
            ) == .beforeStart {
                visible = rows.filter { $0.fixedDate == nil && $0.day == dow && $0.inWeek(week) }
                    .sorted { $0.startNode < $1.startNode }
            } else {
                visible = HolidayTransferOps.coursesForDate(
                    effectiveDate, startDate: startDate, maxWeek: maxWeek,
                    courses: rows, transfers: AppPrefs.shared.getHolidayTransfers(tableId)
                ).sorted { $0.startNode < $1.startNode }
            }
            result.append(DayData(
                date: effectiveDate,
                dayOfWeek: dow,
                courses: visible,
                timeJson: timeJson,
                isGrey: await HolidayManager.shouldGrey(effectiveDate, tableId: tableId)
            ))
        }
        return result
    }
}
