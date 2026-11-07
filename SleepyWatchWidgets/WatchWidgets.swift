// WatchWidgets.swift — 表盘复杂功能入口 (2026-10 watch 伴侣 App)
// ← plan 阶段四: 圆形角标 / 矩形 / inline / corner 同语义; 智能栈 glance 由系统
//   自动收录本 Widget 的 rectangular/inline 形态。
//
// Control Center (ControlWidget) 说明: 实测本 Xcode 的 watchOS SDK 将其门控在
// watchOS 26.0+ (非 plan 早先假设的 11+), 且需 AppIntents/OpenIntent 一整套接线。
// 部署目标保持 watchOS 10.0 (Series 4/SE 一代以上全覆盖, 刻意定的覆盖面) →
// Control Center 项留待后续单独评估「是否值得为它把部署目标提到 26.0」, 本 PR
// 不纳入, 避免为极小众能力牺牲老设备支持。
//
// 2026-11 小组件扩展 (docs/watch-widgets-design.md): bundle 1→6 —
// 下一节(现有, 不动) + 正在上的课 / 今日课程一览 / 今日概览 / 明日课程 / 第 N 周。
// 新 kind 共用 WatchSnapshotProvider(load/boundary 注入) + WatchAgendaCore 口径;
// 边界 = 课程起止+60s (课程类) 或 次日 00:05 (日/周类), policy .atEnd。

import WidgetKit
import SwiftUI

/// 主复杂功能 — 支持 circular/rectangular/inline/corner 四形态 (watchOS 10+)
struct WatchNextClassWidget: Widget {
    let kind = "WatchNextClassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
            WatchComplicationEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.t("watch_complication_display_name"))
        .description(L10n.t("watch_complication_description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular,
                            .accessoryInline, .accessoryCorner])
    }
}

/// 「正在上的课」— 当前课程进度/剩余; 课间退化为下一节
struct WatchCurrentClassWidget: Widget {
    let kind = "WatchCurrentClassWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WatchSnapshotProvider(
                load: { WatchAgendaData.loadCurrentClass(now: $0) },
                boundary: { t, snap in WatchTimelineSupport.classBoundary(after: t, items: snap.items) })
        ) { entry in
            WatchCurrentClassEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.t("watch_current_display_name"))
        .description(L10n.t("watch_current_description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular,
                            .accessoryInline, .accessoryCorner])
    }
}

/// 「今日课程一览」— 剩余列表 / 剩余节数
struct WatchTodayListWidget: Widget {
    let kind = "WatchTodayListWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WatchSnapshotProvider(
                load: { WatchAgendaData.loadTodayList(now: $0) },
                boundary: { t, snap in WatchTimelineSupport.classBoundary(after: t, items: snap.items) })
        ) { entry in
            WatchTodayListEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.t("watch_todaylist_display_name"))
        .description(L10n.t("watch_todaylist_description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

/// 「今日概览」— 第 N 周 + 今日节数 + 首末时间
struct WatchTodayOverviewWidget: Widget {
    let kind = "WatchTodayOverviewWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WatchSnapshotProvider(
                load: { WatchAgendaData.loadOverview(now: $0) },
                boundary: { _, _ in nil })
        ) { entry in
            WatchTodayOverviewEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.t("watch_overview_display_name"))
        .description(L10n.t("watch_overview_description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

/// 「明日课程」— 明日列表 / 节数 (晚间场景)
struct WatchTomorrowWidget: Widget {
    let kind = "WatchTomorrowWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WatchSnapshotProvider(
                load: { WatchAgendaData.loadTomorrow(now: $0) },
                boundary: { _, _ in nil })
        ) { entry in
            WatchTomorrowEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.t("watch_tomorrow_display_name"))
        .description(L10n.t("watch_tomorrow_description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

/// 「第 N 周」— 周数 + 学期进度
struct WatchWeekWidget: Widget {
    let kind = "WatchWeekWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: kind,
            provider: WatchSnapshotProvider(
                load: { WatchAgendaData.loadWeek(now: $0) },
                boundary: { _, _ in nil })
        ) { entry in
            WatchWeekEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.t("watch_week_display_name"))
        .description(L10n.t("watch_week_description"))
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

/// 按当前 family 选视图 (watchOS 用 accessory* 族)
struct WatchComplicationEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular: WatchCircularView(next: entry.next)
        case .accessoryInline:   WatchInlineView(next: entry.next)
        case .accessoryCorner:   WatchCornerView(next: entry.next)
        default:                 WatchRectangularView(next: entry.next)
        }
    }
}

struct WatchTimeStripWidget: Widget {
    let kind = "WatchTimeStripWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchTimeStripProvider()) { entry in
            WatchTimeStripView(entry: entry)
        }
        .configurationDisplayName(localized("watch_time_strip_display_name"))
        .description(localized("watch_time_strip_description"))
        .supportedFamilies([.accessoryRectangular])
    }

    private func localized(_ key: String) -> String {
        let language = WatchTimeStripPreferencesStore.shared.load().language
        return NSLocalizedString(key, bundle: LocaleHelper.bundle(for: language), comment: "")
    }
}

@main
struct SleepyWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WatchNextClassWidget()
        WatchCurrentClassWidget()
        WatchTodayListWidget()
        WatchTodayOverviewWidget()
        WatchTomorrowWidget()
        WatchWeekWidget()
        WatchTimeStripWidget()
    }
}
