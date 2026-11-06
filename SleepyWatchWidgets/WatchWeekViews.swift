// WatchWeekViews.swift — 「第 N 周 · 学期进度」4 形态视图 (2026-11 watch 小组件扩展)
//
// 语义矩阵 (设计文档 §5):
//   circular    = 大号周数 + 学期进度环; 学期外 → 假期中
//   corner      = N周 / 假期中
//   rectangular = 第 N 周 / 共 M 周 / 进度条
//   inline      = 第 N 周 / 共 M 周
//
// ratio = week/maxWeek clamp 0...1 ← WatchAgendaCore.weekInfo。

import WidgetKit
import SwiftUI

struct WatchWeekEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchWidgetEntry<WatchWeekSnapshot>

    var body: some View {
        switch family {
        case .accessoryCircular: WatchWeekCircular(snap: entry.snapshot)
        case .accessoryCorner: WatchWeekCorner(snap: entry.snapshot)
        case .accessoryInline: WatchWeekInline(snap: entry.snapshot)
        default: WatchWeekRectangular(snap: entry.snapshot)
        }
    }
}

/// circular — 学期进度环 + 大号周数
private struct WatchWeekCircular: View {
    let snap: WatchWeekSnapshot
    var body: some View {
        ZStack {
            WatchProgressRing(progress: snap.ratio)
            if !snap.inSemester {
                Text(L10n.t("watch_holiday")).font(.system(size: 11))
            } else {
                VStack(spacing: 0) {
                    Text("\(snap.week)")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .widgetAccentable()
                    Text(L10n.t("watch_week_unit")).font(.system(size: 8))
                }
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=schedule")!)
    }
}

/// corner — N周 / 假期中
private struct WatchWeekCorner: View {
    let snap: WatchWeekSnapshot
    var body: some View {
        Group {
            if !snap.inSemester {
                Text(L10n.t("watch_holiday")).font(.system(size: 12))
            } else {
                Text("\(snap.week)\(L10n.t("watch_week_unit"))")
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .widgetAccentable()
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=schedule")!)
    }
}

/// rectangular — 第 N 周 / 共 M 周 / 进度条
private struct WatchWeekRectangular: View {
    let snap: WatchWeekSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !snap.inSemester {
                Text(L10n.t("watch_holiday")).font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                Text(L10n.format("schedule_week_prefix", snap.week))
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text(L10n.format("watch_week_total", snap.maxWeek))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                ProgressView(value: snap.ratio)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "sleepy://watch?tab=schedule")!)
    }
}

/// inline — 第 N 周 / 共 M 周 / 假期中
private struct WatchWeekInline: View {
    let snap: WatchWeekSnapshot
    var body: some View {
        if !snap.inSemester {
            Text(L10n.t("watch_holiday"))
        } else {
            Text("\(L10n.format("schedule_week_prefix", snap.week)) / \(L10n.format("watch_week_total", snap.maxWeek))")
        }
    }
}
