// WeekView.swift — 手表周课表 (2026-10 watch 伴侣 App)
// 本周七天 × 逐日课程列表。← WeekListWidget 语义的 watch 重排 (纵向 List 下钻)。
// 每天用真实日期走 HolidayTransferHelper 调休映射 + 学期过滤 (与 store.courses(on:) 同源)。

import SwiftUI

struct WeekView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme

    var body: some View {
        let scheme = WatchPalette.scheme(envDark: envScheme == .dark)
        Group {
            if let table = store.currentTable() {
                let days = weekDays(table: table)
                List {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                        Section(header: dayHeader(day, scheme: scheme, table: table)) {
                            if day.courses.isEmpty {
                                Text("—")
                                    .font(.footnote).foregroundColor(scheme.onSurfaceVariant)
                            } else {
                                ForEach(Array(day.courses.enumerated()), id: \.offset) { _, c in
                                    NavigationLink {
                                        CourseDetailView(course: c, table: table, groupRows: day.courses)
                                    } label: {
                                        CourseRowView(course: c, table: table, scheme: scheme,
                                                      groupRows: day.courses)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            } else {
                Text(L10n.t("watch_no_table_hint"))
                    .font(.footnote).foregroundColor(scheme.onSurfaceVariant)
                    .multilineTextAlignment(.center).padding()
            }
        }
        .navigationTitle(Text(L10n.t("tab_schedule")))
    }

    struct DayBucket { let date: Date; let dow: Int; let courses: [CourseEntity]; let isToday: Bool }

    private func weekDays(table: TimeTableEntity) -> [DayBucket] {
        let today = Date()
        return (1...7).map { dow -> DayBucket in
            // 共享 DateUtils 周一=1 口径 (今天所在周, 同 WeekGridWidgetLoader 列序)
            let date = DateUtils.dateOfWeekDay(ref: today, dayOfWeek: dow)
            return DayBucket(date: date, dow: dow,
                             courses: store.courses(on: date, table: table),
                             isToday: DateUtils.isDateToday(date))
        }
    }

    @ViewBuilder
    private func dayHeader(_ day: DayBucket, scheme: WidgetScheme, table: TimeTableEntity) -> some View {
        HStack(spacing: 4) {
            Text(DateUtils.localizedDay(day.dow))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(day.isToday ? scheme.primary : scheme.onSurface)
            Text(DateUtils.shortDate(day.date))
                .font(.system(size: 10))
                .foregroundColor(scheme.onSurfaceVariant)
            if day.isToday {
                Text(L10n.t("today_today"))
                    .font(.system(size: 9))
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(scheme.primary.opacity(0.2)))
                    .foregroundColor(scheme.primary)
            }
        }
    }
}
