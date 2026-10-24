// SmartPeriodConfig.swift — ← data/entity/SmartPeriodConfig.kt (逐行翻译, GPL-3.0)

import Foundation

/// v1.0.16 智慧节次配置（自动模式）
///
/// 用户输入：
///  - periodMinutes (a)        每节时长
///  - totalPeriods  (N)        总节数
///  - startTime                第一节开始时间 "HH:mm"
///  - breaks                   break 模板列表（每项 = 一个分组）
///  - transitionAssignments    每个 transition 选哪个 break 索引
///                              null = 默认 0 分钟（连续）
///                              长度 = N - 1
///  - durations                课时时长模板列表（v1.0.61 混合课时，每项 = 一个分组）
///  - periodAssignments        每个 period 选哪个 duration 索引
///                              null = 使用主课程时长 periodMinutes
///                              长度 = N
///
/// 推导：
///  第 i 节开始时间 = startTime + Σ(period时长)_before_i + Σbreaks_before_i
///  transition i 表示第 i 节与第 i+1 节之间的课间
///
/// 解码：各字段缺省走默认值（对齐 Android @Serializable 默认值，旧 JSON 无
/// durations/periodAssignments 也能解码）。
struct SmartPeriodConfig: Codable, Equatable {
    var startTime: String = "08:00"
    var periodMinutes: Int = 45
    var totalPeriods: Int = 12
    var breaks: [BreakOption] = []
    var transitionAssignments: [Int?] = []
    var durations: [DurationOption] = []
    var periodAssignments: [Int?] = []

    enum CodingKeys: String, CodingKey {
        case startTime, periodMinutes, totalPeriods, breaks, transitionAssignments
        case durations, periodAssignments
    }

    init(startTime: String = "08:00",
         periodMinutes: Int = 45,
         totalPeriods: Int = 12,
         breaks: [BreakOption] = [],
         transitionAssignments: [Int?] = [],
         durations: [DurationOption] = [],
         periodAssignments: [Int?] = []) {
        self.startTime = startTime
        self.periodMinutes = periodMinutes
        self.totalPeriods = totalPeriods
        self.breaks = breaks
        self.transitionAssignments = transitionAssignments
        self.durations = durations
        self.periodAssignments = periodAssignments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime) ?? "08:00"
        periodMinutes = try c.decodeIfPresent(Int.self, forKey: .periodMinutes) ?? 45
        totalPeriods = try c.decodeIfPresent(Int.self, forKey: .totalPeriods) ?? 12
        breaks = try c.decodeIfPresent([BreakOption].self, forKey: .breaks) ?? []
        transitionAssignments = try c.decodeIfPresent([Int?].self, forKey: .transitionAssignments) ?? []
        durations = try c.decodeIfPresent([DurationOption].self, forKey: .durations) ?? []
        periodAssignments = try c.decodeIfPresent([Int?].self, forKey: .periodAssignments) ?? []
    }

    /// 取每个 period 的 duration 索引（带范围保护 + 默认填充）。
    /// null 或越界表示使用主课程时长 periodMinutes。
    /// 长度 = max(0, totalPeriods)
    func effectivePeriodAssignments() -> [Int?] {
        let n = max(totalPeriods, 0)
        let base = Array(periodAssignments.prefix(n))
        let mapped: [Int?] = base.map { value in
            (value != nil && value! >= 0 && value! < durations.count) ? value : nil
        }
        return mapped + [Int?](repeating: nil, count: max(n - base.count, 0))
    }

    /// 每个 period 的实际分钟数，未分配时使用主课程时长。
    func effectivePeriodMinutes() -> [Int] {
        return effectivePeriodAssignments().map { index in
            (index != nil && index! >= 0 && index! < durations.count) ? durations[index!].minutes : periodMinutes
        }
    }

    /// 取每个 transition 的 break 索引（带范围保护 + 默认填充）
    /// 长度 = max(0, totalPeriods - 1)
    /// 未填的位置默认 null（0 分钟连续）
    func effectiveAssignments() -> [Int?] {
        let n = max(totalPeriods - 1, 0)
        let base = Array(transitionAssignments.prefix(n))
        var result = base.map { v -> Int? in
            (v != nil && v! >= 0 && v! < breaks.count) ? v : nil
        }
        result += [Int?](repeating: nil, count: max(n - base.count, 0))
        return result
    }

    /// 推导所有 transition 的实际分钟数
    /// 默认（null 或越界）= 0 分钟
    func effectiveTransitionMinutes() -> [Int] {
        let n = max(totalPeriods - 1, 0)
        let assigns = effectiveAssignments()
        return (0..<n).map { i in
            let idx = assigns[i]
            return (idx != nil && idx! >= 0 && idx! < breaks.count) ? breaks[idx!].minutes : 0
        }
    }

    /// 推导节次（不含 transition，仅节本身）
    func derive() -> [TimeTableUtils.TimeSlotRow] {
        var rows: [TimeTableUtils.TimeSlotRow] = []
        let transMins = effectiveTransitionMinutes()
        let periodMins = effectivePeriodMinutes()
        let (h0, m0) = parseStart()
        var curH = h0
        var curM = m0
        // totalPeriods <= 0 时返回空列表（对齐 Kotlin "0 until n"，避免 Swift 半开区间崩溃）
        for i in 0..<max(totalPeriods, 0) {
            let startStr = String(format: "%02d:%02d", curH, curM)
            curM += periodMins[i]
            curH += curM / 60
            curM %= 60
            let endStr = String(format: "%02d:%02d", curH, curM)
            rows.append(TimeTableUtils.TimeSlotRow(node: i + 1, start: startStr, end: endStr))
            if i < transMins.count {
                curM += transMins[i]
                curH += curM / 60
                curM %= 60
            }
        }
        return rows
    }

    private func parseStart() -> (Int, Int) {
        let parts = startTime.split(separator: ":").map { Int($0) }
        return parts.count == 2 ? (parts[0] ?? 8, parts[1] ?? 0) : (8, 0)
    }
}

/// Break 模板（用于"智慧节次"自动模式 UI）
/// - minutes: 该 break 的分钟数
/// - isLong: true=大课间, false=小课间（仅用于颜色/标签展示）
/// - label: 用户自定义名称（可选），默认"小课间 X"/"大课间 X"
struct BreakOption: Codable, Equatable {
    var minutes: Int
    var isLong: Bool = false
    var label: String? = nil

    enum CodingKeys: String, CodingKey {
        case minutes, isLong, label
    }

    init(minutes: Int, isLong: Bool = false, label: String? = nil) {
        self.minutes = minutes
        self.isLong = isLong
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minutes = try c.decode(Int.self, forKey: .minutes)
        isLong = try c.decodeIfPresent(Bool.self, forKey: .isLong) ?? false
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? nil
    }

    func displayLabel(index: Int) -> String {
        if let l = label, !l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return l }
        let prefix = isLong ? "大课间" : "小课间"
        return "\(prefix) \(minutes) 分钟"
    }
}

/// 课时时长模板（v1.0.61 混合课时，用于"智慧节次"自动模式 UI）
/// - minutes: 该课时分组的分钟数
/// - isLong: true=长课时, false=短课时（仅用于颜色/标签展示）
/// - label: 用户自定义名称（可选），默认"短课时 X"/"长课时 X"
struct DurationOption: Codable, Equatable {
    var minutes: Int
    var isLong: Bool = false
    var label: String? = nil

    enum CodingKeys: String, CodingKey {
        case minutes, isLong, label
    }

    init(minutes: Int, isLong: Bool = false, label: String? = nil) {
        self.minutes = minutes
        self.isLong = isLong
        self.label = label
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minutes = try c.decode(Int.self, forKey: .minutes)
        isLong = try c.decodeIfPresent(Bool.self, forKey: .isLong) ?? false
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? nil
    }

    func displayLabel(index: Int) -> String {
        if let l = label, !l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return l }
        let prefix = isLong ? "长课时" : "短课时"
        return "\(prefix) \(minutes) 分钟"
    }
}

/// Remap assignments after removing one duration group.
func remapDurationAssignmentsAfterDeletion(assignments: [Int?], deletedIndex: Int) -> [Int?] {
    return assignments.map { value in
        if value == deletedIndex {
            return nil
        } else if let v = value, v > deletedIndex {
            return v - 1
        }
        return value
    }
}
