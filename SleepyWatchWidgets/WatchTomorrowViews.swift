// WatchTomorrowViews.swift — 「明日课程」4 形态视图 (2026-11 watch 小组件扩展)
//
// 语义矩阵 (设计文档 §5):
//   circular    = 明日 N 节大数字; 明日无课 → 无课; 学期外 → 假期中
//   corner      = N 节 / 假期中
//   rectangular = 明日前 3 节列表 (时间 + 课名)
//   inline      = 明日 N 节 · 首节时间
//
// 学期状态按**明日**判定 (semesterStatus(tomorrow)), 不能只看今天。

import WidgetKit
import SwiftUI

struct WatchTomorrowEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchWidgetEntry<WatchTomorrowSnapshot>

    var body: some View {
        switch family {
        case .accessoryCircular: WatchTomorrowCircular(snap: entry.snapshot)
        case .accessoryCorner: WatchTomorrowCorner(snap: entry.snapshot)
        case .accessoryInline: WatchTomorrowInline(snap: entry.snapshot)
        default: WatchTomorrowRectangular(snap: entry.snapshot)
        }
    }
}

/// circular — 明日 N 节 / 无课 / 假期中
private struct WatchTomorrowCircular: View {
    let snap: WatchTomorrowSnapshot
    var body: some View {
        ZStack {
            Circle().stroke(.foreground.opacity(0.3), lineWidth: 2)
            if !snap.inSemester {
                Text(L10n.t("watch_holiday")).font(.system(size: 11))
            } else if !snap.items.isEmpty {
                VStack(spacing: 0) {
                    Text("\(snap.items.count)")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .widgetAccentable()
                    Text(L10n.t("unit_periods")).font(.system(size: 8))
                }
            } else {
                Text(L10n.t("no_course")).font(.system(size: 11))
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=schedule")!)
    }
}

/// corner — N 节 / 假期中
private struct WatchTomorrowCorner: View {
    let snap: WatchTomorrowSnapshot
    var body: some View {
        Group {
            if !snap.inSemester {
                Text(L10n.t("watch_holiday")).font(.system(size: 12))
            } else if !snap.items.isEmpty {
                Text("\(snap.items.count)\(L10n.t("unit_periods"))")
                    .font(.system(size: 16).monospacedDigit())
                    .widgetAccentable()
            } else {
                Text(L10n.t("no_course")).font(.system(size: 12))
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=schedule")!)
    }
}

/// rectangular — 明日前 3 节 (时间 + 课名)
private struct WatchTomorrowRectangular: View {
    let snap: WatchTomorrowSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !snap.inSemester {
                Text(L10n.t("watch_holiday")).font(.system(size: 12)).foregroundColor(.secondary)
            } else if snap.items.isEmpty {
                Text(L10n.t("watch_tomorrow_no_class"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(snap.items.prefix(3).enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 6) {
                        Text(TimeTableUtils.formatTime(item.startDate))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(.secondary)
                        Text(item.courseName)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "sleepy://watch?tab=schedule")!)
    }
}

/// inline — 明日 N 节 · 首节时间 / 明日无课 / 假期中
private struct WatchTomorrowInline: View {
    let snap: WatchTomorrowSnapshot
    var body: some View {
        if !snap.inSemester {
            Text(L10n.t("watch_holiday"))
        } else if snap.items.isEmpty {
            Text(L10n.t("watch_tomorrow_no_class"))
        } else if let first = snap.items.first {
            Text("\(L10n.t("watch_tomorrow_mark")) \(snap.items.count)\(L10n.t("unit_periods")) · \(TimeTableUtils.formatTime(first.startDate))")
        }
    }
}
