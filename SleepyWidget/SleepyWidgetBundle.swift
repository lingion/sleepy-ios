// SleepyWidgetBundle.swift — WidgetBundle 入口
// ← widget/{TodayWidget,TwoDayWidget,WeekListWidget,WeekViewWidget,WeekGridWidgetProvider}.kt
//
// Android 5 个 AppWidgetProvider(RemoteViews+Canvas) → WidgetKit SwiftUI
// (平台差异表#5: bitmap 管道不移植,布局/配色逻辑保留)。

import WidgetKit
import SwiftUI

@main
struct SleepyWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        TwoDayWidget()
        WeekListWidget()
        WeekViewWidget()
        WeekGridWidget()
    }
}
