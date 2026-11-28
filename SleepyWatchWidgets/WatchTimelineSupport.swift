// WatchTimelineSupport.swift — 表盘 5 个新 kind 的共享 Timeline 管线 (2026-11 watch 小组件扩展)
//
// 泛型 provider: 装载(load) 与边界(boundary) 两个闭包注入, 各 kind 只管自己的快照。
// 边界口径 ← 现有 WatchComplicationProvider: 课程起止时刻 +60s (防同刻竞态);
// 差异: 边界时刻内容可确定性预计算 → 前瞻 entry 带真实快照 (非 nil 占位), 上限 3 个,
// 末位兜底次日 00:05; policy .atEnd 到期续期。
// 快照同步 → WatchStore.applySnapshot 已调 reloadAllTimelines, 全 kind 自动受益。

import WidgetKit
import SwiftUI

/// 通用 entry: 时间 + 快照
struct WatchWidgetEntry<S>: TimelineEntry {
    let date: Date
    let snapshot: S
}

/// 泛型 TimelineProvider — 各 kind 注入 load / boundary
struct WatchSnapshotProvider<S>: TimelineProvider {
    typealias Entry = WatchWidgetEntry<S>

    let load: (Date) -> S
    /// entry.date 之后的下一个刷新边界; nil → 次日 00:05 兜底
    let boundary: (Date, S) -> Date?

    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: load(Date())) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: load(Date())))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        var t = now
        var entries = [Entry(date: t, snapshot: load(t))]
        for _ in 0..<3 {
            if let b = boundary(t, entries.last!.snapshot), b > t {
                t = b
            } else {
                t = WatchTimelineSupport.nextMidnight(after: t)
            }
            entries.append(Entry(date: t, snapshot: load(t)))
            // 兜底(无更多边界)后不再续 — 交给 .atEnd 续期
            if boundary(t, entries.last!.snapshot) == nil { break }
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

enum WatchTimelineSupport {

    /// 下一个课程边界 (开课/下课时刻) +60s; 无 → nil
    static func classBoundary(after t: Date, items: [WatchAgendaCore.ClassItem]) -> Date? {
        items.flatMap { [$0.startDate, $0.endDate] }
            .filter { $0 > t }
            .min()?
            .addingTimeInterval(60)
    }

    /// 次日 00:05 兜底 (← 现有 WatchComplicationProvider 跨日口径)
    static func nextMidnight(after t: Date) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: t)) ?? t
        return cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
    }
}

/// 共享进度环 (circular 形态: 「正在上的课」课堂进度 / 「第 N 周」学期进度)
struct WatchProgressRing: View {
    let progress: Double
    var body: some View {
        ZStack {
            Circle().strokeBorder(.foreground.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
    }
}


struct WatchMaterialPalette: Equatable {
    let usesMaterial: Bool
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let inProgressStart: Color
    let stripCourseFill: Color
    let stripCourseStroke: Color
    let stripFreeStroke: Color
    let stripActiveText: Color

    static let systemDefault = WatchMaterialPalette(
        usesMaterial: false,
        primaryText: .primary,
        secondaryText: .secondary,
        accent: .primary,
        inProgressStart: .primary,
        stripCourseFill: Color.primary.opacity(0.18),
        stripCourseStroke: .primary,
        stripFreeStroke: .secondary,
        stripActiveText: .primary
    )

    static func resolve(family: WidgetFamily, isFullColor: Bool, showsBackground: Bool,
                        scheme: WidgetScheme) -> WatchMaterialPalette {
        let material = family == .accessoryRectangular && isFullColor && showsBackground
        guard material else { return .systemDefault }
        return WatchMaterialPalette(
            usesMaterial: true,
            primaryText: scheme.onSurface,
            secondaryText: scheme.onSurfaceVariant,
            accent: scheme.primary,
            inProgressStart: scheme.primary,
            stripCourseFill: scheme.primaryContainer,
            stripCourseStroke: scheme.primary,
            stripFreeStroke: scheme.onSurfaceVariant.opacity(0.45),
            stripActiveText: scheme.onPrimaryContainer
        )
    }
}

private struct WatchMaterialPaletteKey: EnvironmentKey {
    static let defaultValue = WatchMaterialPalette.systemDefault
}

extension EnvironmentValues {
    var watchMaterialPalette: WatchMaterialPalette {
        get { self[WatchMaterialPaletteKey.self] }
        set { self[WatchMaterialPaletteKey.self] = newValue }
    }
}

// Material color roles are used only on full-color surfaces. Face tinting and
// monochrome rendering keep the system's foreground and accent groups.
struct WatchMaterialSurface: ViewModifier {
    let family: WidgetFamily

    @ViewBuilder func body(content: Content) -> some View {
        #if compiler(>=5.9)
        if #available(watchOS 10.0, *) {
            content.modifier(WatchMaterialSurfaceWatchOS10(family: family))
        } else {
            content.modifier(WatchMaterialSurfaceWatchOS9(family: family))
        }
        #else
        content.modifier(WatchMaterialSurfaceWatchOS9(family: family))
        #endif
    }
}

#if compiler(>=5.9)
@available(watchOS 10.0, *)
private struct WatchMaterialSurfaceWatchOS10: ViewModifier {
    @Environment(\.widgetRenderingMode) private var rendering
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    @Environment(\.colorScheme) private var colorScheme

    let family: WidgetFamily

    func body(content: Content) -> some View {
        let prefs = AppPrefs.shared
        let isDark = prefs.isDarkMode(isSystemDark: colorScheme == .dark)
        let scheme = resolveWidgetScheme(themeKey: prefs.getThemeKey(), isDark: isDark)
        let palette = WatchMaterialPalette.resolve(
            family: family,
            isFullColor: rendering == .fullColor,
            showsBackground: showsBackground,
            scheme: scheme
        )
        return content
            .foregroundStyle(palette.primaryText)
            .tint(palette.accent)
            .environment(\.watchMaterialPalette, palette)
            .containerBackground(for: .widget) {
                if palette.usesMaterial {
                    scheme.surfaceContainer
                } else {
                    Color.clear
                }
            }
    }
}
#endif

private struct WatchMaterialSurfaceWatchOS9: ViewModifier {
    @Environment(\.widgetRenderingMode) private var rendering
    @Environment(\.colorScheme) private var colorScheme

    let family: WidgetFamily

    func body(content: Content) -> some View {
        let prefs = AppPrefs.shared
        let isDark = prefs.isDarkMode(isSystemDark: colorScheme == .dark)
        let scheme = resolveWidgetScheme(themeKey: prefs.getThemeKey(), isDark: isDark)
        let palette = WatchMaterialPalette.resolve(
            family: family,
            isFullColor: rendering == .fullColor,
            showsBackground: true,
            scheme: scheme
        )
        return content
            .foregroundStyle(palette.primaryText)
            .tint(palette.accent)
            .environment(\.watchMaterialPalette, palette)
    }
}

extension View {
    func watchMaterialSurface(_ family: WidgetFamily) -> some View {
        modifier(WatchMaterialSurface(family: family))
    }
}
