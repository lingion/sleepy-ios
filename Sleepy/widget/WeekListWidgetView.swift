// WeekListWidgetView.swift — ← WeekListWidget.kt + WidgetBitmapRenderers.renderWeekList
// 本周课表(列表) widget — 7 列日列(列数随 visibleDays)。
// 列卡片: primaryContainer(今天) / surfaceContainer(其他), 14dp 圆角。
// 课程: 彩色胶囊背景 + BOLD 课名。

import SwiftUI
import WidgetKit

struct WeekListWidgetEntry: TimelineEntry {
    let date: Date
    let data: WeekData
}

struct WeekListWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekListWidgetEntry {
        WeekListWidgetEntry(date: Date(), data: WeekListWidgetLoader.loadDataSync())
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekListWidgetEntry) -> Void) {
        completion(WeekListWidgetEntry(date: Date(), data: WeekListWidgetLoader.loadDataSync()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekListWidgetEntry>) -> Void) {
        let entry = WeekListWidgetEntry(date: Date(), data: WeekListWidgetLoader.loadDataSync())
        let refresh = Date().addingTimeInterval(6 * 3600)  // 半天兜底;数据变化由 App 端 reloadAllTimelines 触发
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// 星期标题(英缩写 — Android dayLabels arrayOf("", "Mon"...))
let weekDayLabels = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

/// 列数过滤(决策 D5-12, 对齐 renderWeekList L238-240): visibleDays 空集回退全周防御
func shownDays(_ data: WeekData) -> [DayData] {
    let visibleDays = AppPrefs.shared.getVisibleDays()
    if visibleDays.isEmpty { return data.days }
    return data.days.filter { visibleDays.contains($0.dayOfWeek) }.sorted { $0.dayOfWeek < $1.dayOfWeek }
}

// MARK: - View ← renderWeekList

struct WeekListWidgetEntryView: View {
    let entry: WeekListWidgetEntry

    var body: some View {
        let data = entry.data
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: data.isDark)
        let colorless = AppPrefs.shared.isWidgetColorless()
        let days = shownDays(data)

        Group {
            if !data.hasTable || days.isEmpty {
                Text(L10n.format("widget_create_schedule"))
                    .font(.system(size: 15))
                    .foregroundColor(s.onSurface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                let todayDow = DateUtils.todayDayOfWeek(today: Date())
                HStack(alignment: .top, spacing: 4) {
                    ForEach(days, id: \.dayOfWeek) { day in
                        WeekListDayColumn(day: day, scheme: s, colorless: colorless,
                                          isToday: day.dayOfWeek == todayDow)
                    }
                }
            }
        }
        .padding(6)
        .background(s.bg)
        .widgetURL(URL(string: "sleepy://open"))
    }
}

private struct WeekListDayColumn: View {
    let day: DayData
    let scheme: WidgetScheme
    let colorless: Bool
    let isToday: Bool

    var body: some View {
        let s = scheme
        VStack(alignment: .center, spacing: 0) {
            // 星期标题
            Text(weekDayLabels[day.dayOfWeek])
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isToday ? s.onPrimaryContainer : s.onSurface)
                .padding(.top, 12)
                .padding(.bottom, 2)

            if !day.courses.isEmpty {
                // 课程数量 chip
                Text("\(day.courses.count) 门")
                    .font(.system(size: 9))
                    .foregroundColor(s.onSurfaceVariant)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(s.surfaceVariant)
                    .cornerRadius(50)
                    .padding(.bottom, 6)

                // 课程列表 — 每门课带颜色胶囊背景
                VStack(spacing: 3) {
                    ForEach(day.courses, id: \.id) { course in
                        // ★ 课程颜色背景 (对齐 WeekGrid 风格) — 统一入口 CourseColorUtil (决策 D3)
                        let bgColor = CourseColorUtil.pickCourseColorSwiftUI(
                            course, isDark: s.isDark, neutralColor: s.surfaceVariant, colorless: colorless)
                        Text(course.courseName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(CourseColorUtil.textColorOn(bg: bgColor, isDark: s.isDark,
                                                                         onSurface: s.onSurface))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 3)
                            .frame(height: 16)
                            .background(bgColor)
                            .cornerRadius(4)
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // 列背景: 今天 primaryContainer / 其他 surfaceContainer, 14dp 圆角
        .background(isToday ? s.primaryContainer : s.surfaceContainer)
        .cornerRadius(14)
    }
}

struct WeekListWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekListWidgetRV", provider: WeekListWidgetProvider()) { entry in
            WeekListWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_week_list_label"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
