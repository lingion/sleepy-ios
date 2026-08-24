// TodayWidgetView.swift — ← TodayWidget.kt (Receiver) + WidgetBitmapRenderers.renderToday
// 桌面 Today 小组件 — 今日课程列表。
// 布局: bg 圆角 20 / pad 14 / 标题行(今天·周X + 日期) / 课程胶囊 38dp 高 + 10dp 间距。
// Canvas 手绘坐标 → SwiftUI 等价布局(间距/字号/取色逐项对齐)。

import SwiftUI
import WidgetKit

// MARK: - Entry

struct TodayWidgetEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

struct TodayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayWidgetEntry {
        TodayWidgetEntry(date: Date(), data: TodayWidgetLoader.loadDataSync())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayWidgetEntry) -> Void) {
        completion(TodayWidgetEntry(date: Date(), data: TodayWidgetLoader.loadDataSync()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayWidgetEntry>) -> Void) {
        // 次日 00:05 刷新(日期变化 + 课表数据变化都覆盖 — 后者由 App 端 WidgetCenter.reloadAllTimelines 触发)
        let data = TodayWidgetLoader.loadDataSync()
        let entry = TodayWidgetEntry(date: Date(), data: data)
        var cal = DateUtils.isoCalendar
        cal.timeZone = .current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        let refresh = cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - View ← renderToday

struct TodayWidgetEntryView: View {
    @Environment(\.widgetRenderingMode) var renderingMode
    let entry: TodayWidgetEntry

    var body: some View {
        let data = entry.data
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: data.isDark)
        let prefs = AppPrefs.shared
        let colorless = prefs.isWidgetColorless()
        // ★ 用户显示设置 (决策 D5-12)
        let displayMode = prefs.getDisplayMode()
        let showDate = prefs.isShowDate()

        VStack(alignment: .leading, spacing: 0) {
            // 标题行: 今天 · 周X  +  日期 (★ showDate=false 时隐藏右侧日期)
            HStack(alignment: .firstTextBaseline) {
                Text("\(L10n.format("today_today")) · \(data.dayName)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(s.primary)
                Spacer()
                if showDate {
                    Text(data.dateLabel)
                        .font(.system(size: 12))
                        .foregroundColor(s.onSurfaceVariant)
                }
            }
            .padding(.bottom, 10)

            if !data.hasTable {
                Text(L10n.format("widget_create_schedule"))
                    .font(.system(size: 15))
                    .foregroundColor(s.onSurface)
                Spacer()
            } else if data.courses.isEmpty {
                // 今日无课 → 大字提示 + 副文案
                Text(L10n.format("today_no_course"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(s.onSurface)
                    .padding(.bottom, 6)
                Text(L10n.format("today_rest"))
                    .font(.system(size: 12))
                    .foregroundColor(s.onSurfaceVariant)
                Spacer()
            } else {
                // 课程列表(全部渲染,不截断 — 溢出由 widget 容器裁切,与 Android bitmap 同行为)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 10) {  // 课程胶囊间距放大(用户反馈太紧凑)
                        ForEach(Array(data.courses.enumerated()), id: \.element.id) { _, course in
                            WidgetCourseCard(course: course, timeJson: data.timeJson, scheme: s,
                                             colorless: colorless, fontSizeSp: 12,
                                             displayMode: displayMode)
                                .frame(height: 38)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(s.bg)
        .widgetURL(URL(string: "sleepy://open"))
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayWidgetRV", provider: TodayWidgetProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_today_label"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
