// WidgetContent.swift — ← WidgetContent.kt
// 小组件数据模型 + 配色派生 — 5 个 WidgetKit 视图共用。
//
// 平台差异表#5: 原版本 RemoteViews+Canvas bitmap → WidgetKit SwiftUI;
// 布局/配色计算逻辑保留,bitmap 管道不移植。
// Glance 层在 原版本 侧已删(v1.0.29 决策 D5-11),5 个生产入口全走 RemoteViews;
// iOS 侧全部 5 个 widget 走 SwiftUI TimelineProvider,共享本文件的数据模型。

import Foundation
import SwiftUI
import UIKit

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
    /// 主题跟随模式(light/dark/system); system 时渲染端用环境色域覆盖 isDark
    var themeMode: String? = nil
    /// ★ 学期状态(学期外时 Today 渲染状态文案不渲染课程)
    var semesterStatus: DateUtils.SemesterStatus = .inRange
    /// 是否「今天」— false = 导航态/跳转态 (← v1.0.60 WidgetData.isToday; 标题与
    /// 时间窗语义都依赖它: 非今天走 HEAD 模式从头部截断)
    var isToday: Bool = true
    /// 节假日/周末灰显 (← v1.0.60 WidgetData.isGrey)
    var isGrey: Bool = false
    /// 自动跳最近有课日状态 (← v1.0.60 WidgetData.weekDisplayStatus)
    var weekDisplayStatus: WeekDisplayStatus = .normal

    var dayName: String { DateUtils.localizedDay(DateUtils.todayDayOfWeek(today: date)) }
    var dateLabel: String { DateUtils.shortDateSlash(date) }
}

/// 4 元组:背景 / 主题强调色 / 正文色 / 次要色
/// 跟 app M3 scheme 派生方式相同:surface / primary / onSurface / onSurfaceVariant ← WidgetScheme
///
/// [intentional custom] 小组件渲染层拿不到 MaterialTheme.colorScheme,故维护一份
/// 「与 app M3 scheme 同源派生」的扁平值类型。全部由 resolveWidgetScheme 构造,
/// 不允许默认值 — 历史默认值(#FDFCFF/#FFFBFE/#6750A4 等)已被 ThemePresets
/// LightScheme 取代(#FEF7FF/同/#6750A4),默认值即漂移源,故全部删默认,强制派生。
/// (← WidgetContent.kt:64-70, v1.0.61 对齐)
struct WidgetScheme {
    let bg: Color
    let surface: Color
    let primary: Color
    let primaryContainer: Color
    /// colorless 灰底基准色 (← WidgetContent.kt:76; 原版本 渲染层
    /// CourseColorUtil.pickCourseColorIntWithGroupRows(..., scheme.secondaryContainer,
    /// colorless) 用它当「刷新所有小组件」同色灰底,WidgetBitmapRenderers.kt:87)
    let secondaryContainer: Color
    let onPrimaryContainer: Color
    let onSurface: Color
    let onSurfaceVariant: Color
    let surfaceContainer: Color
    let surfaceContainerLow: Color
    let surfaceContainerLowest: Color
    let surfaceVariant: Color
    let isDark: Bool
    /// iOS 26 主屏「透明/着色」样式 (accented/vibrant 渲染态) — 玻璃档配色标志,
    /// 渲染层据此跳过课程色/灰显覆盖 (整组已是白 alpha 层级, ← WidgetGlassCompat)
    let isGlass: Bool
}

/// 按 themeKey + isDark 派生小组件配色。 ← resolveWidgetScheme
///
/// ★ themeKey == "system" 走 iOS 语义色(等价适配:原版本 Material You 动态取色
///   在 iOS 无对应 API,降级为系统语义色),与 SleepyThemeProvider 的处理对齐。
/// ★ "custom:<id>" 走 CustomThemeStore + CustomSchemeDeriver —— 与 App 内
///   SleepyThemeProvider 同一个派生函数,保证小组件与界面配色同源;id 读不到
///   (已删)回落 ThemePresets.byKey(null) 默认套(原版本 同语义)。
/// system 模式 → 渲染期取系统深浅(WidgetKit \.colorScheme, 对齐原实现
/// isSystemInDarkTheme 渲染期取值); 锁定 light/dark 用快照 isDark。
/// 旧快照无 themeMode 字段(nil)沿用原行为。
func effectiveWidgetIsDark(themeMode: String?, snapshotIsDark: Bool, envScheme: ColorScheme) -> Bool {
    guard let mode = themeMode else { return snapshotIsDark }
    return mode == AppPrefs.THEME_MODE_SYSTEM ? envScheme == .dark : snapshotIsDark
}

func resolveWidgetScheme(themeKey: String, isDark: Bool, isGlass: Bool = false) -> WidgetScheme {
    // iOS 26 主屏「透明/着色」样式 → accented/vibrant 渲染: 系统把不透明内容整组
    // 染白(仅保 alpha)+背景换玻璃。预设/自定义色全被判白 → 层级消失。
    // 玻璃档直接给「白 @ alpha 阶梯」配色 (← WidgetGlassCompat), 与系统染色语义自洽。
    if isGlass { return glassWidgetScheme() }
    let s: WakeUpColorScheme
    if themeKey.hasPrefix(ThemePresets.CUSTOM_KEY_PREFIX) {
        let id = String(themeKey.dropFirst(ThemePresets.CUSTOM_KEY_PREFIX.count))
        if let theme = CustomThemeStore.getById(id) {
            s = CustomSchemeDeriver.derive(theme: theme, isDark: isDark)
        } else {
            let preset = ThemePresets.byKey(ThemePresets.KEY_DEFAULT)
            s = isDark ? preset.dark : preset.light
        }
    } else if themeKey == ThemePresets.KEY_SYSTEM {
        s = opaqueWidgetSystemScheme(dark: isDark)
    } else {
        let preset = ThemePresets.byKey(themeKey)
        s = isDark ? preset.dark : preset.light
    }
    return WidgetScheme(
        bg: s.surface,
        surface: s.surface,
        primary: s.primary,
        primaryContainer: s.primaryContainer,
        secondaryContainer: s.secondaryContainer,
        onPrimaryContainer: s.onPrimaryContainer,
        onSurface: s.onSurface,
        onSurfaceVariant: s.onSurfaceVariant,
        surfaceContainer: s.surfaceContainer,
        surfaceContainerLow: s.surfaceContainerLow,
        surfaceContainerLowest: s.surfaceContainerLowest,
        surfaceVariant: s.surfaceVariant,
        isDark: isDark,
        isGlass: false
    )
}

/// "system" 主题的 widget 专用配色 — App 视图层的 dynamicSystemScheme 走 UIKit 动态
/// 语义色 (label/secondarySystemBackground/tertiarySystemFill…), 由视图所在窗口的
/// trait 解析。widget 扩展进程 + StandBy/锁屏场景下:
///   1) trait 深浅可能与 entry 快照 isDark (锁定 light/dark 时) 劈叉 → 白字配浅底;
///   2) tertiarySystemFill 等本身带 alpha → 背景被剥离后胶囊溶解。
/// 原版本 Material You 动态色恒为不透明且恒匹配深色标志, 无此二坑。
/// 修法: 按 entry 的 isDark 显式给 trait 解析成**不透明静态色** (无硬编码色值,
/// 系统升级自动跟随), 半透明填充先合成到 systemBackground 再取色。
func opaqueWidgetSystemScheme(dark: Bool) -> WakeUpColorScheme {
    let base = SleepyThemeProvider.dynamicSystemScheme(dark: dark)
    #if os(watchOS)
    // watchOS 无 iOS 语义色族 (dynamicSystemScheme 已回落默认预设) → 无需烘焙
    return base
    #else
    let traits = UITraitCollection(traitsFrom: [
        UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
        UITraitCollection(displayScale: 2.0),
    ])
    let bg = UIColor.systemBackground.resolvedColor(with: traits)
    func bake(_ c: UIColor) -> Color {
        let r = c.resolvedColor(with: traits)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        guard r.getRed(&rr, green: &gg, blue: &bb, alpha: &aa) else { return base.surface }
        if aa >= 1 { return Color(.sRGB, red: Double(rr), green: Double(gg), blue: Double(bb), opacity: 1) }
        // 半透明色 (systemFill 系): 合成到 systemBackground 取不透明等价色
        var br: CGFloat = 0, bgg: CGFloat = 0, bgb: CGFloat = 0, ba: CGFloat = 0
        bg.getRed(&br, green: &bgg, blue: &bgb, alpha: &ba)
        return Color(.sRGB, red: Double(br * (1 - aa) + rr * aa),
                     green: Double(bgg * (1 - aa) + gg * aa),
                     blue: Double(bgb * (1 - aa) + bb * aa), opacity: 1)
    }
    return base.replacing(
        primary: bake(UIColor.systemPurple),
        onSurface: bake(UIColor.label),
        onSurfaceVariant: bake(UIColor.secondaryLabel),
        surface: bake(UIColor.secondarySystemBackground),
        surfaceVariant: bake(UIColor.tertiarySystemFill))
    #endif
}

/// iOS 26 主屏「透明/着色」小组件样式下的玻璃档配色 — 白 @ alpha 层级 (← WidgetGlassCompat)。
/// 依据 Apple "Optimizing your widget for accented rendering mode and Liquid Glass":
/// accented/vibrant 渲染中系统把所有不透明内容整组染白、仅保留 alpha, 背景移除换玻璃 —
/// 与其被染色打乱, 不如自身就以 alpha 阶梯表达层级: 文字 100%/72%、课程卡底 30%、
/// 表头容器 20%、chip/surfaceVariant 36%、页脚胶囊 24%; bg 全透明由玻璃材质托底。
func glassWidgetScheme() -> WidgetScheme {
    let w: (Double) -> Color = { Color.white.opacity($0) }
    return WidgetScheme(
        bg: .clear,
        surface: w(0),
        primary: w(1),
        primaryContainer: w(0.30),
        secondaryContainer: w(0.30),
        onPrimaryContainer: w(1),
        onSurface: w(1),
        onSurfaceVariant: w(0.72),
        surfaceContainer: w(0.20),
        surfaceContainerLow: w(0.20),
        surfaceContainerLowest: w(0.14),
        surfaceVariant: w(0.36),
        isDark: false,
        isGlass: true
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
    /// 节假日/周末灰显 (← v1.0.60 DayData.isGrey; compact 窗口列/WeekList 列渲染用)
    var isGrey: Bool = false

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
    /// 主题跟随模式(light/dark/system); system 时渲染端用环境色域覆盖 isDark
    var themeMode: String? = nil
    // displayMode 死字段已删(原版本 侧 renderer 各自直读 AppPrefs)
    var showDate: Bool = false
    var visibleDays: Set<Int> = Set(1...7)
    /// ★ 学期状态(学期外时列头加状态行)
    var semesterStatus: DateUtils.SemesterStatus = .inRange
    /// 最小档三天窗口 (← v1.0.60 WeekData.compactWindow): 真实日期的 ≤3 列,
    /// 「列表/周视图 · 小」compact 脸用 (compactShownDays 优先口径, 可跨上下周)
    var compactWindow: [DayData] = []
    /// 当前展示周状态 (← v1.0.60 WeekData.weekDisplayStatus)
    var weekDisplayStatus: WeekDisplayStatus = .normal
    /// NEAREST_BUSY_DAY 档时被自动跳到的那一天 (WeekData.nearestBusyTargetDate,
    /// 周网格 SMALL 最小档 weekGridMinimumTodayData 定位单日; nil 回退旧口径)
    var nearestBusyTargetDate: Date? = nil
}

/// 两天视图数据 ← TwoDayData
struct TwoDayData {
    var days: [DayData]
    var hasTable: Bool
    var isDark: Bool = false
    var themeKey: String = ThemePresets.KEY_DEFAULT
    /// 主题跟随模式(light/dark/system); system 时渲染端用环境色域覆盖 isDark
    var themeMode: String? = nil
    /// ★ 学期状态(学期外时渲染状态文案不渲染课程)
    var semesterStatus: DateUtils.SemesterStatus = .inRange
    /// 当前展示周状态 (← WidgetContent.kt:199 TwoDayData.weekDisplayStatus;
    /// 原版本 TwoDayWidget.kt:229 以 source.display.status 填充,.nearestBusyDay
    /// 时渲染/装载端走 findNearestBusyDays(count=2) 的「最近两个未来有课日」窗口,
    /// 用户 2026-09-23 定稿, 不再是 targetDate+1 日历相邻日)
    var weekDisplayStatus: WeekDisplayStatus = .normal
}
