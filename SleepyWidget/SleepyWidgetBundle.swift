// SleepyWidgetBundle.swift — WidgetBundle 入口
// ← widget/{TodayWidget,TwoDayWidget,WeekListWidget,WeekViewWidget,WeekGridWidgetProvider}.kt
// 5 类 widget 于 D7 批次逐个落地;D0 为可编译占位。

import WidgetKit
import SwiftUI

@main
struct SleepyWidgetBundle: WidgetBundle {
    var body: some Widget {
        // D7: TodayWidget(), TwoDayWidget(), WeekListWidget(), WeekViewWidget(), WeekGridWidget()
        EmptyWidget()
    }
}

struct EmptyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SleepyPlaceholder", provider: PlaceholderProvider()) { _ in
            Text("D0")
        }
        .configurationDisplayName("Sleepy")
        .supportedFamilies([.systemSmall])
    }
}

struct PlaceholderEntry: TimelineEntry { let date = Date() }

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry() }
    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry()], policy: .atEnd))
    }
}
