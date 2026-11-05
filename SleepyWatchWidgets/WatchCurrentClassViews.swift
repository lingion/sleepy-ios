// WatchCurrentClassViews.swift — 「正在上的课」4 形态视图 (2026-11 watch 小组件扩展)
//
// 语义矩阵 (设计文档 §5):
//   circular    = 进行中: 进度环 + 剩余倒计时 (系统 timer 文本, 表盘上自动走字)
//               / 课间: 退化为「下一节」分钟数; 无课: —
//   corner      = 剩余时间 / 下一节分钟数
//   rectangular = 课名 / 教室 · 剩余 / 进度条; 课间退化同「下一节」三行
//   inline      = 进行中 · 课名 / 下一节 · 课名 / 无课
//
// 兜底顺序: 内容优先 (补班日 inSemester=false 但有课 → 显示课), 全空 → 无课。
// 剩余时间用 Text(timerInterval:countsDown:) — 真机验证项: 表盘走字不达预期则退回
// 静态值+边界刷新 (设计 §6)。timerInterval 下限 clamp 防 stale entry 越界 (now > end)。

import WidgetKit
import SwiftUI

struct WatchCurrentClassEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchWidgetEntry<WatchCurrentSnapshot>

    var body: some View {
        switch family {
        case .accessoryCircular: WatchCurrentCircular(snap: entry.snapshot, now: entry.date)
        case .accessoryCorner: WatchCurrentCorner(snap: entry.snapshot, now: entry.date)
        case .accessoryInline: WatchCurrentInline(snap: entry.snapshot)
        default: WatchCurrentRectangular(snap: entry.snapshot, now: entry.date)
        }
    }
}

/// circular — 进行中: 进度环+倒计时; 课间: 下一节分钟数; 无课: —
private struct WatchCurrentCircular: View {
    let snap: WatchCurrentSnapshot
    let now: Date
    var body: some View {
        ZStack {
            if let c = snap.current {
                WatchProgressRing(progress: c.progress(at: now))
                Text(timerInterval: min(now, c.endDate)...c.endDate, countsDown: true)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .minimumScaleFactor(0.6)
            } else if let n = snap.next {
                WatchProgressRing(progress: 0)
                VStack(spacing: 0) {
                    Text("\(n.minutesUntil(from: now))")
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .widgetAccentable()
                    Text(L10n.t("unit_minutes")).font(.system(size: 8))
                }
            } else {
                WatchProgressRing(progress: 0)
                Text("—").font(.system(size: 20, weight: .bold))
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=today")!)
    }
}

/// corner — 剩余 / 距下一节分钟
private struct WatchCurrentCorner: View {
    let snap: WatchCurrentSnapshot
    let now: Date
    var body: some View {
        Group {
            if let c = snap.current {
                Text(timerInterval: min(now, c.endDate)...c.endDate, countsDown: true)
                    .font(.system(size: 16, weight: .semibold).monospacedDigit())
                    .widgetAccentable()
            } else if let n = snap.next {
                Text("\(n.minutesUntil(from: now))\(L10n.t("unit_minutes"))")
                    .font(.system(size: 16).monospacedDigit())
                    .widgetAccentable()
            } else {
                Image(systemName: "tray").font(.system(size: 16))
            }
        }
        .widgetURL(URL(string: "sleepy://watch?tab=today")!)
    }
}

/// rectangular — 课名 / 教室·剩余 / 进度条; 课间退化三行
private struct WatchCurrentRectangular: View {
    let snap: WatchCurrentSnapshot
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let c = snap.current {
                Text(c.courseName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .widgetAccentable()
                HStack(spacing: 6) {
                    if !c.room.isEmpty {
                        Text(c.room)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Text(timerInterval: min(now, c.endDate)...c.endDate, countsDown: true)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(.secondary)
                }
                ProgressView(value: c.progress(at: now))
            } else if let n = snap.next {
                Text(n.courseName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .widgetAccentable()
                Text(n.startLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
                if !n.room.isEmpty {
                    Text(n.room)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(L10n.t("no_course"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "sleepy://watch?tab=today")!)
    }
}

/// inline — 进行中 · 课名 / 下一节 · 课名 / 无课
private struct WatchCurrentInline: View {
    let snap: WatchCurrentSnapshot
    var body: some View {
        if let c = snap.current {
            Text("\(L10n.t("watch_mark_now")) · \(c.courseName)")
        } else if let n = snap.next {
            Text("\(L10n.t("watch_mark_next")) · \(n.courseName)")
        } else {
            Text(L10n.t("no_course"))
        }
    }
}
