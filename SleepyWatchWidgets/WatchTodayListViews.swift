// WatchTodayListViews.swift — 「今日课程一览」4 形态视图 (2026-11 watch 小组件扩展)
//
// 语义矩阵 (设计文档 §5):
//   circular    = 剩余 N 节大数字; 已上完 → ✓; 无课 → 无课
//   corner      = 剩余 N 节 / ✓ / 无课
//   rectangular = 进行中(置顶, 粗体) + 未开始课, 最多 3 行 (时间 + 课名)
//   inline      = 今日还有 N 节 / 今日已结束 / 无课
//
// 行内时间恒为时钟 (formatTime(startDate)), 不用 startLabel — 列表纵向对齐可比性。

import WidgetKit
import SwiftUI

struct WatchTodayListEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchWidgetEntry<WatchTodaySnapshot>

    var body: some View {
        switch family {
        case .accessoryCircular: WatchTodayListCircular(snap: entry.snapshot)
        case .accessoryCorner: WatchTodayListCorner(snap: entry.snapshot)
        case .accessoryInline: WatchTodayListInline(snap: entry.snapshot)
        default: WatchTodayListRectangular(snap: entry.snapshot)
        }
    }
}

/// circular — 剩余 N 节 / ✓ / 无课
private struct WatchTodayListCircular: View {
    let snap: WatchTodaySnapshot
    var body: some View {
        ZStack {
            Circle().stroke(.foreground.opacity(0.3), lineWidth: 2)
            if !snap.remaining.isEmpty {
                VStack(spacing: 0) {
                    Text("\(snap.remaining.count)")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .widgetAccentable()
                    Text(L10n.t("unit_periods")).font(.system(size: 8))
                }
            } else if snap.hasAnyClass {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .widgetAccentable()
            } else {
                Text(L10n.t("no_course")).font(.system(size: 11))
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=today")!)
    }
}

/// corner — 剩余 N 节 / ✓ / 无课
private struct WatchTodayListCorner: View {
    let snap: WatchTodaySnapshot
    var body: some View {
        Group {
            if !snap.remaining.isEmpty {
                Text("\(snap.remaining.count)\(L10n.t("unit_periods"))")
                    .font(.system(size: 16).monospacedDigit())
                    .widgetAccentable()
            } else if snap.hasAnyClass {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 16))
            } else {
                Text(L10n.t("no_course")).font(.system(size: 12))
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=today")!)
    }
}

/// rectangular — 进行中置顶 + 未开始, 最多 3 行 (时间 + 课名)
private struct WatchTodayListRectangular: View {
    let snap: WatchTodaySnapshot

    /// 进行中置顶, 其后未开始, 总 3 行
    private var rows: [(item: WatchAgendaCore.ClassItem, inProgress: Bool)] {
        var out: [(WatchAgendaCore.ClassItem, Bool)] = snap.current.map { [($0, true)] } ?? []
        for r in snap.remaining { out.append((r, false)) }
        return Array(out.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if rows.isEmpty {
                Text(snap.hasAnyClass ? L10n.t("watch_countdown_done") : L10n.t("no_course"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        Text(TimeTableUtils.formatTime(row.0.startDate))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundColor(row.1 ? .primary : .secondary)
                        Text(row.0.courseName)
                            .font(.system(size: 12, weight: row.1 ? .semibold : .regular))
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "sleepy://watch?tab=today")!)
    }
}

/// inline — 今日还有 N 节 / 今日已结束 / 无课
private struct WatchTodayListInline: View {
    let snap: WatchTodaySnapshot
    var body: some View {
        if !snap.remaining.isEmpty {
            Text(L10n.format("watch_today_remaining_count", snap.remaining.count))
        } else if snap.hasAnyClass {
            Text(L10n.t("watch_countdown_done"))
        } else {
            Text(L10n.t("no_course"))
        }
    }
}
