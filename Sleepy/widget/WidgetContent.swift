// WidgetContent.swift — ← WidgetContent.kt
// 小组件数据模型 + 配色派生 — 5 个 WidgetKit 视图共用。
//
// 平台差异表#5: Android RemoteViews+Canvas bitmap → WidgetKit SwiftUI;
// 布局/配色计算逻辑保留,bitmap 管道不移植。
// Glance 层在 Android 侧已删(v1.0.29 决策 D5-11),5 个生产入口全走 RemoteViews;
// iOS 侧全部 5 个 widget 走 SwiftUI TimelineProvider,共享本文件的数据模型。

import Foundation
import SwiftUI

/// 小组件渲染数据 — 让渲染端单纯绘制,不读 DB。
/// TimelineProvider 在后台拉数据,组装成这个 model 喂给 SwiftUI 视图。 ← WidgetData
struct WidgetData {
    /// 今日日期
    let date: Date
    /// 今日课程(已按当前周次过滤 + 排序)
    let courses: [CourseEntity]
    /// timeJson(用于查开始/结束时间)
    let timeJson: String
    /// 是否有课表
    let hasTable: Bool
    /// 跟 app 主题保持一致:true=深色小组件
    var isDark: Bool = false
    /// 跟 app 主题色(ThemePresets key)
    var themeKey: String = ThemePresets.KEY_DEFAULT

    var dayName: String { DateUtils.localizedDay(DateUtils.todayDayOfWeek(today: date)) }
    var dateLabel: String { DateUtils.shortDateSlash(date) }
}

/// 4 元组:背景 / 主题强调色 / 正文色 / 次要色
/// 跟 app M3 scheme 派生方式相同:surface / primary / onSurface / onSurfaceVariant ← WidgetScheme
struct WidgetScheme {
    var bg: Color = Color(0xFFFDFCFF)
    var surface: Color = Color(0xFFFFFBFE)
    var primary: Color = Color(0xFF6750A4)
    var primaryContainer: Color = Color(0xFFEADDFF)
    var onPrimaryContainer: Color = Color(0xFF1C1B1F)
    var onSurface: Color = Color(0xFF1C1B1F)
    var onSurfaceVariant: Color = Color(0xFF79747E)
    var surfaceContainer: Color = Color(0xFFF3EDF7)
    var surfaceVariant: Color = Color(0xFFE7E0EC)
    var isDark: Bool = false
}

/// 按 themeKey + isDark 派生小组件配色。 ← resolveSchemePublic
///
/// ★ themeKey == "system" 走 iOS 语义色(等价适配:Android Material You 动态取色
///   在 iOS 无对应 API,降级为系统语义色),与 SleepyThemeProvider 的处理对齐。
func resolveWidgetScheme(themeKey: String, isDark: Bool) -> WidgetScheme {
    let s: WakeUpColorScheme = themeKey == ThemePresets.KEY_SYSTEM
        ? SleepyThemeProvider.dynamicSystemScheme(dark: isDark)
        : {
            let preset = ThemePresets.byKey(themeKey)
            return isDark ? preset.dark : preset.light
        }()
    return WidgetScheme(
        bg: s.surface,
        surface: s.surface,
        primary: s.primary,
        primaryContainer: s.primaryContainer,
        onPrimaryContainer: s.onPrimaryContainer,
        onSurface: s.onSurface,
        onSurfaceVariant: s.onSurfaceVariant,
        surfaceContainer: s.surfaceContainer,
        surfaceVariant: s.surfaceVariant,
        isDark: isDark
    )
}

// ═══════════════════════════════════════════════════════
// Multi-day widget data
// ═══════════════════════════════════════════════════════

/// 单天数据 ← DayData
struct DayData {
    let date: Date
    let dayOfWeek: Int
    let courses: [CourseEntity]
    let timeJson: String

    var dayLabel: String { DateUtils.shortDate(date) }
    var dayName: String { DateUtils.localizedDay(dayOfWeek) }
    var isToday: Bool { Calendar.current.isDateInToday(date) }
    var isTomorrow: Bool { Calendar.current.isDateInTomorrow(date) }
}

/// 周视图数据 ← WeekData
struct WeekData {
    var days: [DayData]
    var hasTable: Bool
    var isDark: Bool = false
    var themeKey: String = ThemePresets.KEY_DEFAULT
    // displayMode 死字段已删(Android 侧 renderer 各自直读 AppPrefs)
    var showDate: Bool = false
    var visibleDays: Set<Int> = Set(1...7)
}

/// 两天视图数据 ← TwoDayData
struct TwoDayData {
    var days: [DayData]
    var hasTable: Bool
    var isDark: Bool = false
    var themeKey: String = ThemePresets.KEY_DEFAULT
}
