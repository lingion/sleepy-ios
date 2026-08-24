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
///
/// 推导：
///  第 i 节开始时间 = startTime + i × periodMinutes + Σbreaks_before_i
///  transition i 表示第 i 节与第 i+1 节之间的课间
struct SmartPeriodConfig: Codable, Equatable {
    var startTime: String = "08:00"
    var periodMinutes: Int = 45
    var totalPeriods: Int = 12
    var breaks: [BreakOption] = []
    var transitionAssignments: [Int?] = []

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
        let (h0, m0) = parseStart()
        var curH = h0
        var curM = m0
        for i in 0..<totalPeriods {
            let startStr = String(format: "%02d:%02d", curH, curM)
            curM += periodMinutes
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

    func displayLabel(index: Int) -> String {
        if let l = label, !l.isEmpty { return l }
        let prefix = isLong ? "大课间" : "小课间"
        return "\(prefix) \(minutes) 分钟"
    }
}
