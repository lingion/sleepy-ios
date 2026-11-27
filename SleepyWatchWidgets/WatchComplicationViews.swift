// WatchComplicationViews.swift — 表盘复杂功能 4 形态视图 (2026-10 watch 伴侣 App)
// ← plan 阶段四: circular(下一节倒计时分钟角标) / rectangular(课名+时间+教室) /
//   inline(课名缩写) / corner 同矩形语义。无下一节时显示「无课」占位。
// 配色走系统 .widgetAccentable() (表盘规范), 不强套主题色 — extension 独立进程,
// 用最稳的系统着色避免跨进程主题解析。深链: widgetURL(sleepy://watch?tab=today)。

import WidgetKit
import SwiftUI

private let noCourseText = L10n.t("no_course")
private let deepLink = URL(string: "sleepy://watch?tab=today")!

/// circular — 下一节倒计时分钟数 (角标)。无课 → 「—」
struct WatchCircularView: View {
    let next: WatchNextClass?
    var body: some View {
        ZStack {
            WatchProgressRing(progress: 0)
            VStack(spacing: 0) {
                if let n = next {
                    Text("\(n.minutesUntil)")
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .widgetAccentable()
                    Text(L10n.t("unit_minutes"))
                        .font(.system(size: 8))
                } else {
                    Text("—").font(.system(size: 22, weight: .bold))
                }
            }
        }
        .widgetURL(deepLink)
    }
}

/// rectangular — 课名 + 时段 + 教室
struct WatchRectangularView: View {
    @Environment(\.watchMaterialPalette) private var palette
    let next: WatchNextClass?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let n = next {
                Text(n.courseName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(palette.primaryText)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(n.startLabel)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(palette.secondaryText)
                if !n.room.isEmpty {
                    Text(n.room)
                        .font(.system(size: 10))
                        .foregroundColor(palette.secondaryText)
                        .lineLimit(1)
                }
            } else {
                Text(noCourseText).font(.system(size: 12)).foregroundColor(palette.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(deepLink)
    }
}

/// inline — 单行: 「下一节 · 课名」/ 无课
struct WatchInlineView: View {
    let next: WatchNextClass?
    var body: some View {
        if let n = next {
            Text("\(L10n.t("watch_mark_next")) · \(n.courseName)")
        } else {
            Text(noCourseText)
        }
    }
}

/// corner — 圆角矩形语义同 rectangular (corner 形态系统自裁)
struct WatchCornerView: View {
    let next: WatchNextClass?
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let n = next {
                Text(n.courseName).font(.system(size: 11, weight: .semibold)).lineLimit(2)
                Text("\(n.minutesUntil)\(L10n.t("unit_minutes"))")
                    .font(.system(size: 10).monospacedDigit()).widgetAccentable()
            } else {
                Image(systemName: "tray").font(.system(size: 16))
            }
        }
        .widgetURL(deepLink)
    }
}
