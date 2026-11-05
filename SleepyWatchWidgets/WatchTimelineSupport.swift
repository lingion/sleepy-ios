// WatchTimelineSupport.swift — 表盘 5 个新 kind 的共享 Timeline 管线 (2026-11 watch 小组件扩展)
//
// 泛型 provider: 装载(load) 与边界(boundary) 两个闭包注入, 各 kind 只管自己的快照。
// 边界口径 ← 现有 WatchComplicationProvider: 课程起止时刻 +60s (防同刻竞态);
// 差异: 边界时刻内容可确定性预计算 → 前瞻 entry 带真实快照 (非 nil 占位), 上限 3 个,
// 末位兜底次日 00:05; policy .atEnd 到期续期。
// 快照同步 → WatchStore.applySnapshot 已调 reloadAllTimelines, 全 kind 自动受益。

import WidgetKit
import SwiftUI

/// 通用 entry: 时间 + 快照
struct WatchWidgetEntry<S>: TimelineEntry {
    let date: Date
    let snapshot: S
}

/// 泛型 TimelineProvider — 各 kind 注入 load / boundary
struct WatchSnapshotProvider<S>: TimelineProvider {
    typealias Entry = WatchWidgetEntry<S>

    let load: (Date) -> S
    /// entry.date 之后的下一个刷新边界; nil → 次日 00:05 兜底
    let boundary: (Date, S) -> Date?

    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: load(Date())) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: load(Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        var t = now
        var entries = [Entry(date: t, snapshot: load(t))]
        for _ in 0..<3 {
            if let b = boundary(t, entries.last!.snapshot), b > t {
                t = b
            } else {
                t = WatchTimelineSupport.nextMidnight(after: t)
            }
            entries.append(Entry(date: t, snapshot: load(t)))
            // 兜底(无更多边界)后不再续 — 交给 .atEnd 续期
            if boundary(t, entries.last!.snapshot) == nil { break }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

enum WatchTimelineSupport {

    /// 下一个课程边界 (开课/下课时刻) +60s; 无 → nil
    static func classBoundary(after t: Date, items: [WatchAgendaCore.ClassItem]) -> Date? {
        items.flatMap { [$0.startDate, $0.endDate] }
            .filter { $0 > t }
            .min()?
            .addingTimeInterval(60)
    }

    /// 次日 00:05 兜底 (← 现有 WatchComplicationProvider 跨日口径)
    static func nextMidnight(after t: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: t)) ?? t
        return cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
    }
}

/// 共享进度环 (circular 形态: 「正在上的课」课堂进度 / 「第 N 周」学期进度)
struct WatchProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().stroke(.foreground.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
    }
}
