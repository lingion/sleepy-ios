// HolidayReminderPolicy.swift — ← util/HolidayRange.kt (issue#44 调休映射部分) +
// util/HolidayReminderPolicy.kt 逐行翻译 (GPL-3.0)
// HolidayRange / HolidayRangeOps 已在 HolidayManager.swift 落地(v1.0.55 前);
// 本文件补齐 v1.0.60 尚缺的: HolidayTransferEntry / HolidayTransferOps / HolidayReminderPolicy。

import Foundation

// MARK: - HolidayTransferEntry (issue#44 调休映射)

/**
 * issue#44 调休映射: 放假日 → 该天的课调到哪个补班日去上。
 *
 * sourceDate = 被放假挪走课的那天(放假日, 通常有课)
 * targetDate = 补班日(国家安排的"上班"日, 该天上 sourceDate 星期几的课)
 * segmentId  = 所属节假日段(展示归属, 不参与判定)
 *
 * API 只给"哪天补班", 不给"补的谁的课"(各校自定), 因此映射由用户手选,
 * 默认空 = 不映射(该天按自然星期取课)。
 */
struct HolidayTransferEntry: Equatable {
    let sourceDate: Date
    let targetDate: Date
    let segmentId: String
}

// MARK: - HolidayTransferOps

/** 映射纯函数集(无系统依赖); 互斥写入由 AppPrefs 组合本对象完成 */
enum HolidayTransferOps {
    private static var fmt: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }

    private static func dayKey(_ d: Date) -> String { fmt.string(from: d) }
    private static func parseDay(_ s: String) -> Date? { fmt.date(from: s) }

    /// 星期几(1=周一 7=周日), 与 DateUtils.todayDayOfWeek 同语义
    private static func dayOfWeek(_ d: Date) -> Int {
        DateUtils.todayDayOfWeek(today: d)
    }

    /// 某放假日是否已有映射; 有 → 该 entry, 无 → nil ← transferFor
    /// (Android lastOrNull = 后选覆盖前选, 编解码侧已按 sourceDate 去重保尾)
    static func transferFor(_ date: Date, _ transfers: [HolidayTransferEntry]) -> HolidayTransferEntry? {
        transfers.last { dayKey($0.sourceDate) == dayKey(date) }
    }

    /**
     * 某天应"按星期几取课": 命中映射 → targetDate 的自然星期; 未命中 → 当天自然星期。
     * 补班日(如 1/4 周日)上的是被调走那天的课, 网格该列排 sourceDate 星期几的课。
     */
    static func effectiveDayOfWeek(_ date: Date, _ transfers: [HolidayTransferEntry]) -> Int {
        guard let hit = transferFor(date, transfers) else { return dayOfWeek(date) }
        return dayOfWeek(hit.targetDate)
    }

    /**
     * 互斥写(核心不变量): 一个 targetDate 一天只能上一次课 —
     * 写入 newEntry 前先移除同 targetDate 的既有条目(后选覆盖前选),
     * 同 sourceDate 的旧条目也一并替换。返回可直接落盘的新列表。
     */
    static func withTargetExclusivity(
        _ existing: [HolidayTransferEntry], _ newEntry: HolidayTransferEntry
    ) -> [HolidayTransferEntry] {
        (existing.filter {
            dayKey($0.targetDate) != dayKey(newEntry.targetDate) &&
            dayKey($0.sourceDate) != dayKey(newEntry.sourceDate)
        } + [newEntry]).sorted { dayKey($0.sourceDate) < dayKey($1.sourceDate) }
    }

    /**
     * 失效判定: sourceDate 不在当年放假日集合(段被数据源改掉/学校另行通知)。
     * 失效 entry 数据保留, UI 灰显提示, 用户手清。
     */
    static func isOrphanFor(_ entry: HolidayTransferEntry, _ yearHolidayDates: Set<Date>) -> Bool {
        !yearHolidayDates.contains { dayKey($0) == dayKey(entry.sourceDate) }
    }

    /// 映射列表 → JSON 数组 ← encodeTransfers
    static func encodeTransfers(_ transfers: [HolidayTransferEntry]) -> String {
        let arr: [[String: Any]] = transfers.map {
            ["sourceDate": dayKey($0.sourceDate), "targetDate": dayKey($0.targetDate), "segmentId": $0.segmentId]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// JSON → 映射列表(坏行跳过; 同 sourceDate 只留最后一条; 返回按 sourceDate 升序; 解析失败返回空) ← decodeTransfers
    static func decodeTransfers(_ json: String) -> [HolidayTransferEntry] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        var bySource: [String: HolidayTransferEntry] = [:]  // key = yyyy-MM-dd, 后者覆盖前者; 输出序与 JSON 插入序无关(下方按 sourceDate 排序)
        var order: [String] = []
        for obj in arr {
            guard let srcStr = obj["sourceDate"] as? String, let src = parseDay(srcStr) else { continue }
            guard let dstStr = obj["targetDate"] as? String, let dst = parseDay(dstStr) else { continue }
            let seg = obj["segmentId"] as? String ?? ""
            if bySource[srcStr] == nil { order.append(srcStr) }
            bySource[srcStr] = HolidayTransferEntry(sourceDate: src, targetDate: dst, segmentId: seg)
        }
        // Android: bySource.values.sortedBy { it.sourceDate } — 恒按 sourceDate 升序, 与 JSON 存储序无关
        return order.compactMap { bySource[$0] }.sorted { dayKey($0.sourceDate) < dayKey($1.sourceDate) }
    }
}

// MARK: - HolidayReminderPolicy

/// 节假日提醒的纯日期分类与门控。← object HolidayReminderPolicy
enum HolidayReminderPolicy {
    enum Category: Equatable {
        case normalWeekday
        case publicHoliday
        case transferHoliday
        case makeupWorkday
        case ordinaryWeekend
        case dataUnavailable
    }

    struct Result: Equatable {
        let category: Category
        let allowReminder: Bool
    }

    static func decide(
        date: Date,
        publicHolidays: Set<Date>,
        transferWorkdays: Set<Date>,
        transfers: [HolidayTransferEntry],
        rulesEnabled: Bool,
        publicHolidayReminder: Bool,
        transferHolidayReminder: Bool,
        makeupWorkdayReminder: Bool,
        ordinaryWeekendReminder: Bool,
        dataAvailable: Bool
    ) -> Result {
        if !rulesEnabled {
            return Result(category: classify(date: date, publicHolidays: publicHolidays,
                                             transferWorkdays: transferWorkdays, transfers: transfers),
                          allowReminder: true)
        }
        if !dataAvailable {
            return Result(category: .dataUnavailable, allowReminder: true)
        }

        let category = classify(date: date, publicHolidays: publicHolidays,
                                transferWorkdays: transferWorkdays, transfers: transfers)
        let allowReminder: Bool
        switch category {
        case .normalWeekday: allowReminder = true
        case .publicHoliday: allowReminder = publicHolidayReminder
        case .transferHoliday: allowReminder = transferHolidayReminder
        case .makeupWorkday: allowReminder = makeupWorkdayReminder
        case .ordinaryWeekend: allowReminder = ordinaryWeekendReminder
        case .dataUnavailable: allowReminder = true
        }
        return Result(category: category, allowReminder: allowReminder)
    }

    private static func classify(
        date: Date,
        publicHolidays: Set<Date>,
        transferWorkdays: Set<Date>,
        transfers: [HolidayTransferEntry]
    ) -> Category {
        let day = Calendar.gregorianCST.startOfDay(for: date)
        let isHoliday = publicHolidays.contains { Calendar.gregorianCST.startOfDay(for: $0) == day }
        let isWorkday = transferWorkdays.contains { Calendar.gregorianCST.startOfDay(for: $0) == day }
        let dow = DateUtils.todayDayOfWeek(today: date)
        if isWorkday { return .makeupWorkday }
        if isHoliday && transfers.contains(where: { Calendar.gregorianCST.startOfDay(for: $0.sourceDate) == day }) {
            return .transferHoliday
        }
        if isHoliday { return .publicHoliday }
        if dow >= 6 { return .ordinaryWeekend }  // DayOfWeek.SATURDAY = 6
        return .normalWeekday
    }
}
