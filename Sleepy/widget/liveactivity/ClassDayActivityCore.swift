// ClassDayActivityCore.swift — 实况活动分段纯逻辑 (v1.0.64)
//
// 纯 Foundation(不 import ActivityKit) — Sleepy 主 target 单测 +
// SleepyWidget 扩展共源编译。分段规则:
//   相邻课间隔 > 60min 断段 → 规避 Live Activity「单条最长 8h / 4h 无更新腐坏」
//   的平台上限, 每段内一次前台刷新即可覆盖一整段。

import Foundation

enum ClassDayActivityCore {

    /// 断段阈值(分钟): 相邻课之间的空闲超过它 → 拆成两条活动。
    static let gapThresholdMin = 60

    /// 当日课程 → 活动段。输入按 startMin 升序(WatchAgendaCore.dayItems 保证)。
    static func segments(from items: [WatchAgendaCore.ClassItem]) -> [[WatchAgendaCore.ClassItem]] {
        var result: [[WatchAgendaCore.ClassItem]] = []
        var current: [WatchAgendaCore.ClassItem] = []
        for item in items {
            if let last = current.last, item.startMin - last.endMin > gapThresholdMin {
                result.append(current)
                current = []
            }
            current.append(item)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// 当前该呈现的段: 含 now 的进行段优先; 否则最近一节未来课所在的段(课前展示);
    /// 全部已过去 → nil(调用方据此结束活动)。
    static func activeSegment(from items: [WatchAgendaCore.ClassItem],
                              now: Date) -> [WatchAgendaCore.ClassItem]? {
        let all = segments(from: items)
        guard !all.isEmpty else { return nil }
        let nowMin = minutesOfDay(now)
        if let running = all.first(where: { seg in
            seg.contains { $0.startMin <= nowMin && nowMin < $0.endMin }
        }) {
            return running
        }
        return all.first { seg in
            guard let first = seg.first else { return false }
            return first.startMin > nowMin
        }
    }

    static func minutesOfDay(_ date: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        return cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
    }
}
