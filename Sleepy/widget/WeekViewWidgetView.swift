// WeekViewWidgetView.swift — ← WeekViewWidget.kt + WidgetBitmapRenderers.renderWeekView
// 本周课表(周视图) widget — 复刻 DaySummaryCell (CourseTableView.kt L559-L642)。
// 列卡片同 WeekList;课程列表: 纯文本无胶囊背景, take(5), onSurfaceVariant 色,
// today 列 onPrimaryContainer@0.82alpha, 课程间分隔线(可选开关)。

import SwiftUI
import WidgetKit

struct WeekViewWidgetEntry: TimelineEntry {
    let date: Date
    let data: WeekData
}

struct WeekViewWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeekViewWidgetEntry {
        WidgetArchiveLog.append(kind: "WeekViewWidgetRV", family: context.family.description, result: "success")
        return WeekViewWidgetEntry(date: Date(), data: WeekListWidgetLoader.loadDataSync())
    }

    func getSnapshot(in context: Context, completion: @escaping (WeekViewWidgetEntry) -> Void) {
        WidgetArchiveLog.append(kind: "WeekViewWidgetRV", family: context.family.description, result: "success")
        completion(WeekViewWidgetEntry(date: Date(), data: WeekListWidgetLoader.loadDataSync()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeekViewWidgetEntry>) -> Void) {
        let entry = WeekViewWidgetEntry(date: Date(), data: WeekListWidgetLoader.loadDataSync())
        let refresh = Date().addingTimeInterval(6 * 3600)
        WidgetArchiveLog.append(kind: "WeekViewWidgetRV", family: context.family.description, result: "success")
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - View ← renderWeekView

struct WeekViewWidgetEntryView: View {
    let entry: WeekViewWidgetEntry

    var body: some View {
        let data = entry.data
        let s = resolveWidgetScheme(themeKey: data.themeKey, isDark: data.isDark)
        let showSeparator = AppPrefs.shared.isWidgetSeparator()
        let days = shownDays(data)

        Group {
            if !data.hasTable || days.isEmpty {
                Text(L10n.format("widget_create_schedule"))
                    .font(.system(size: 15))
                    .foregroundColor(s.onSurface)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                let todayDow = DateUtils.todayDayOfWeek(today: Date())
                VStack(spacing: 0) {
                    // ★ 学期外: 顶部全宽状态行(只画一次, 同 renderWeekList)
                    if data.semesterStatus != .inRange {
                        Text(data.semesterStatus == .beforeStart
                             ? L10n.format("semester_not_started")
                             : L10n.format("semester_ended"))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(s.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)
                    }
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(days, id: \.dayOfWeek) { day in
                            WeekViewDayColumn(day: day, scheme: s, isToday: day.dayOfWeek == todayDow,
                                              showSeparator: showSeparator)
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(s.bg)
        .widgetURL(URL(string: "sleepy://open"))
    }
}

private struct WeekViewDayColumn: View {
    let day: DayData
    let scheme: WidgetScheme
    let isToday: Bool
    let showSeparator: Bool

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
                    .padding(.bottom, 4)  // 4dp gap (DaySummaryCell L624)

                // 课程 mini-list — 最多2行换行 + 课程间分隔线(可选), take(5)
                VStack(spacing: 3) {  // 3dp (原2dp太紧, 对齐胶囊版)
                    ForEach(Array(day.courses.prefix(5).enumerated()), id: \.element.id) { idx, course in
                        // today → onPrimaryContainer@0.82alpha, 其他 → onSurfaceVariant
                        Text(course.courseName)
                            .font(.system(size: 9))
                            .foregroundColor(isToday
                                ? s.onPrimaryContainer.opacity(0.82)
                                : s.onSurfaceVariant)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)   // wrapMax2Lines → 最多2行,超出截断
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                        // 课程间分隔: 开关ON→1dp@40%线; OFF→纯3dp留白(由 VStack spacing 提供)
                        if showSeparator && idx < min(day.courses.count, 5) - 1 {
                            Rectangle()
                                .fill(s.onSurfaceVariant.opacity(0.4))
                                .frame(height: 1)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(isToday ? s.primaryContainer : s.surfaceContainer)
        .cornerRadius(14)
    }
}

struct WeekViewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekViewWidgetRV", provider: WeekViewWidgetProvider()) { entry in
            WeekViewWidgetEntryView(entry: entry)
        }
        .configurationDisplayName(L10n.format("widget_week_view_label"))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
