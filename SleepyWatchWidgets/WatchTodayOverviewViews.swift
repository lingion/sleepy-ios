// WatchTodayOverviewViews.swift — 「今日概览」4 形态视图 (2026-11 watch 小组件扩展)
//
// 语义矩阵 (设计文档 §5):
//   circular    = 今日总节数大数字; 无课 → 无课; 学期外 → 假期中
//   corner      = N 节 / 假期中
//   rectangular = 第 N 周 / 今日 N 节 / 首末时间
//   inline      = 第 N 周 · 今日 N 节
//
// 周次/首末用恒时钟时间 (formatTime), 与节次显示模式解耦 — 概览语义=「今天整体」。

import WidgetKit
import SwiftUI

struct WatchTodayOverviewEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchWidgetEntry<WatchOverviewSnapshot>

    var body: some View {
        switch family {
        case .accessoryCircular: WatchOverviewCircular(snap: entry.snapshot)
        case .accessoryCorner: WatchOverviewCorner(snap: entry.snapshot)
        case .accessoryInline: WatchOverviewInline(snap: entry.snapshot)
        default: WatchOverviewRectangular(snap: entry.snapshot)
        }
    }
}

/// circular — 今日总节数 / 无课 / 假期中
private struct WatchOverviewCircular: View {
    let snap: WatchOverviewSnapshot
    var body: some View {
        ZStack {
            Circle().stroke(.foreground.opacity(0.3), lineWidth: 2)
            if !snap.inSemester {
                Text(L10n.t("watch_holiday")).font(.system(size: 11))
            } else if snap.totalCount > 0 {
                VStack(spacing: 0) {
                    Text("\(snap.totalCount)")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .widgetAccentable()
                    Text(L10n.t("unit_periods")).font(.system(size: 8))
                }
            } else {
                Text(L10n.t("no_course")).font(.system(size: 11))
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=today")!)
    }
}

/// corner — N 节 / 假期中
private struct WatchOverviewCorner: View {
    let snap: WatchOverviewSnapshot
    var body: some View {
        Group {
            if !snap.inSemester {
                Text(L10n.t("watch_holiday")).font(.system(size: 12))
            } else if snap.totalCount > 0 {
                Text("\(snap.totalCount)\(L10n.t("unit_periods"))")
                    .font(.system(size: 16).monospacedDigit())
                    .widgetAccentable()
            } else {
                Text(L10n.t("no_course")).font(.system(size: 12))
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=today")!)
    }
}

/// rectangular — 第 N 周 / 今日 N 节 / 首末时间
private struct WatchOverviewRectangular: View {
    let snap: WatchOverviewSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !snap.inSemester {
                Text(L10n.t("watch_holiday")).font(.system(size: 12)).foregroundColor(.secondary)
            } else {
                Text(L10n.format("schedule_week_prefix", snap.week))
                    .font(.system(size: 13, weight: .semibold))
                    .widgetAccentable()
                Text("\(L10n.t("tab_today")) \(snap.totalCount)\(L10n.t("unit_periods"))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                if let f = snap.first, let l = snap.last {
                    Text("\(TimeTableUtils.formatTime(f.startDate))–\(TimeTableUtils.formatTime(l.endDate))")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.secondary)
                } else {
                    Text(L10n.t("no_course"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "sleepy://watch?tab=today")!)
    }
}

/// inline — 第 N 周 · 今日 N 节 / 假期中
private struct WatchOverviewInline: View {
    let snap: WatchOverviewSnapshot
    var body: some View {
        if !snap.inSemester {
            Text(L10n.t("watch_holiday"))
        } else {
            Text("\(L10n.format("schedule_week_prefix", snap.week)) · \(L10n.t("tab_today")) \(snap.totalCount)\(L10n.t("unit_periods"))")
        }
    }
}
