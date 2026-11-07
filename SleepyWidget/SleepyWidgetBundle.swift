// SleepyWidgetBundle.swift — WidgetBundle 入口
// ← widget/{TodayWidget,TwoDayWidget,WeekListWidget,WeekViewWidget,WeekGridWidgetProvider}.kt
//
// 原版本 5 个 AppWidgetProvider(RemoteViews+Canvas) → WidgetKit SwiftUI
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
        // v1.0.64 课程实况活动(灵动岛/锁屏) — ActivityConfiguration 属 WidgetKit,
        // 与主屏小组件同扩展并列注册; iOS 16.1+ 门控(BundleBuilder 支持 #available)
        if #available(iOS 16.1, *) {
            SleepyClassLiveActivity()
        }
    }
}
