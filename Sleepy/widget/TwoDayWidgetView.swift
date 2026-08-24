// TwoDayWidgetView.swift — ← TwoDayWidget.kt + WidgetBitmapRenderers.renderTwoDay
// 最近两天 widget — 今天 + 明天 (左右两栏并排, 中间竖直分隔)。
// 顶部标签 "最近两天" + 每列(今天/明天 + 日期) 课程胶囊(最大高 44dp)。

import SwiftUI
import WidgetKit

struct TwoDayWidgetEntry: TimelineEntry {
    let date: Date
    let data: TwoDayData
}

struct TwoDayWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TwoDayWidgetEntry {
        TwoDayWidgetEntry(date: Date(), data: TwoDayWidgetLoader.loadDataSync())
    }

    func getSnapshot(in context: Context, completion: @escaping (TwoDayWidgetEntry) -> Void) {
        completion(TwoDayWidgetEntry(date: Date(), data: TwoDayWidgetLoader.loadDataSync()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TwoDayWidgetEntry>) -> Void) {
        let entry = TwoDayWidgetEntry(date: Date(), data: TwoDayWidgetLoader.loadDataSync())
        // 次日 00:05 刷新(今天/明天窗口滚动)
        let cal = DateUtils.isoCalendar
        let tomorrow = cal.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        let refresh = cal.date(bySettingHour: 0, minute: 5, second: 0, of: tomorrow) ?? tomorrow
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - View ← renderTwoDay

struct TwoDayWidgetEntryView: View {
    let entry: TwoDayWidgetEntry

    var body: some View {
        let data = entry.data
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: data.isDark)
        let prefs = AppPrefs.shared
        let colorless = prefs.isWidgetColorless()
        let displayMode = prefs.getDisplayMode()
        let showDate = prefs.isShowDate()

        VStack(alignment: .leading, spacing: 0) {
            // 顶部标签
            Text(L10n.format("widget_twoday_label"))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(s.primary)
                .padding(.bottom, 8)

            if !data.hasTable || data.days.isEmpty {
                Text(L10n.format("widget_create_schedule"))
                    .font(.system(size: 15))
                    .foregroundColor(s.onSurface)
                Spacer()
            } else {
                // ★ 左右两栏: 每天一列, 中间竖直分隔
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(data.days.enumerated()), id: \.element.dayOfWeek) { colIdx, day in
                        TwoDayColumn(day: day, scheme: s, colorless: colorless,
                                     displayMode: displayMode, showDate: showDate,
                                     isLast: colIdx == data.days.count - 1)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(s.bg)
        .widgetURL(URL(string: "sleepy://open"))
    }
}

private struct TwoDayColumn: View {
    let day: DayData
    let scheme: WidgetScheme
    let colorless: Bool
    let displayMode: String
    let showDate: Bool
    let isLast: Bool

    var body: some View {
        let s = scheme
        VStack(alignment: .leading, spacing: 0) {
            // 列标题: 今天/明天/星期 + 日期(★ showDate=false 时隐藏)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(s.primary)
                if showDate {
                    Text(day.dayLabel)
                        .font(.system(size: 10))
                        .foregroundColor(s.onSurfaceVariant)
                }
            }
            .padding(.bottom, 8)

            if day.courses.isEmpty {
                Text(L10n.format("no_course"))
                    .font(.system(size: 11))
                    .foregroundColor(s.onSurfaceVariant)
                Spacer()
            } else {
                // ★ 胶囊固定最大高度 44dp, 不撑满列
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(day.courses, id: \.id) { course in
                            WidgetCourseCard(course: course, timeJson: day.timeJson, scheme: s,
                                             colorless: colorless, fontSizeSp: 10,
                                             displayMode: displayMode)
                                .frame(height: 44)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // 列间竖直分隔线
        .overlay(alignment: .trailing) {
            if !isLast {
                Rectangle()
                    .fill(s.onSurfaceVariant.opacity(0.125))  // 0x20 alpha ≈ 12.5%
                    .frame(width: 1)
                    .padding(.trailing, -5)
            }
        }
    }

    private var title: String {
        if day.isToday { return L10n.format("today_today") }
        if day.isTomorrow { return L10n.format("tomorrow") }
        return day.dayName
    }
}

struct TwoDayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TwoDayWidgetRV", provider: TwoDayWidgetProvider()) { entry in
            TwoDayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_twoday_label"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
