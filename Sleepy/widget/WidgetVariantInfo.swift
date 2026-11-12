// WidgetVariantInfo.swift — ← widget/WidgetVariantInfo.kt (ALL_WIDGET_VARIANTS)
//
// Metadata describing one widget variant (base or small).
//
// The list [allWidgetVariants] is the single source of truth for both the
// refresh broadcast dispatched by WidgetCenter.shared.reloadAllTimelines
// and the management screen UI. Adding a new widget must add exactly one
// entry here; the refresh call is derived automatically.
//
// ★ 平台差异:
//   - 原版本: ALL_WIDGET_VARIANTS 包含 13 个 receiver (4 个主类 × base/small/wide)。
//   - iOS: StaticConfiguration 不支持 widget 间的 base/small 实例化(同一 kind 三档
//     family 在配置里指定), 现有 5 个 widget 每个支持 [.systemSmall/Medium/Large],
//     即 5 档。WidgetManagementScreen.swift 的 PlacedWidgetItem.displayName 逐字
//     比对 kind → 本枚举是配置/管理两端一致的基础。

import Foundation

struct WidgetVariantInfo {
    let kind: String
    let displayNameKey: String
}

let allWidgetVariants: [WidgetVariantInfo] = [
    WidgetVariantInfo(kind: "WeekGridWidgetV19", displayNameKey: "widget_week_grid_label"),
    WidgetVariantInfo(kind: WeekGridWideMode.vertical.widgetKind, displayNameKey: WeekGridWideMode.vertical.displayNameKey),
    WidgetVariantInfo(kind: WeekGridWideMode.horizontal.widgetKind, displayNameKey: WeekGridWideMode.horizontal.displayNameKey),
    WidgetVariantInfo(kind: "TodayWidgetRV", displayNameKey: "widget_today_label"),
    WidgetVariantInfo(kind: "WeekListWidgetRV", displayNameKey: "widget_week_list_label"),
    WidgetVariantInfo(kind: "WeekViewWidgetRV", displayNameKey: "widget_week_view_label"),
    WidgetVariantInfo(kind: "TwoDayWidgetRV", displayNameKey: "widget_twoday_label")
]
