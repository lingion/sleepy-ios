// WeekView.swift — 整周视图 (2026-10 watch 伴侣 App)
// 语义 ← iOS 网格周模式 + WeekListWidgetLoader 同源:
// · 分组 = 周一起 7 天 (手表=手机固定口径, iOS 无周起始设置), visible_days 过滤;
// · 分组标题 = 本地化星期 + show_date 镜像日期 + 节假日/调休标注 (有节假日或调休时
//   直接写「放假/补班 X」, 灰显由 shouldGrey 决策核判定 — 读磁盘镜像纯函数);
// · 分组内课行 = store.courses(on:) (调休换日 + 学期过滤 + 节次排序共享层全口径)。

import SwiftUI

struct WeekView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme

    var body: some View {
        let scheme = WatchPalette.scheme(envDark: envScheme == .dark)
        Group {
            if let table = store.currentTable() {
                // Horizontal swipes belong to the root tab pager. Use the same
                // vertical scrolling axis as Today, including during fast tab changes.
                let courses = store.allCourses(table: table)
                let period = store.boundPeriod(for: table)
                List {
                    ForEach(weekColumns(anchor: store.weekAnchorDate(table, courses: courses)), id: \.self) { date in
                        daySection(date: date, table: table, period: period, courses: courses, scheme: scheme)
                    }
                }
                .listStyle(.plain)
                .accessibilityIdentifier("watch_week_agenda")
            } else {
                Text(L10n.t("watch_no_table_hint"))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(scheme.onSurfaceVariant)
                    .padding()
            }
        }
        .navigationTitle(Text(L10n.t("tab_schedule")))
    }

    /// 锚定周 (周一..周日) 中可见的星期 (visible_days 1=一..7=日)
    private func weekColumns(anchor: Date) -> [Date] {
        store.weekDates(today: anchor)
            .filter { store.visibleDays.contains(DateUtils.todayDayOfWeek(today: $0)) }
    }

    private func daySection(date: Date, table base: TimeTableEntity, period: PeriodTableEntity?,
                            courses loaded: [CourseEntity], scheme: WidgetScheme) -> some View {
        let table = store.tableForDisplay(base, on: date, period: period)
        let courses = store.courses(on: date, table: table, previewBeforeStart: true, loadedCourses: loaded)
        let grey = store.shouldGrey(date, tableId: table.id)
        let isTransferDay = store.isMakeupDay(date, tableId: table.id)

        return Section {
            if courses.isEmpty {
                Text(L10n.t("no_course"))
                    .font(.footnote)
                    .foregroundColor(scheme.onSurfaceVariant)
            }
            ForEach(courses) { course in
                NavigationLink {
                    CourseDetailView(course: course, table: table, groupRows: courses)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CourseDisplayUtil.displayName(course, store.useGridAlias && !course.alias.isEmpty))
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(scheme.onSurface)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(store.slotLabel(course, table: table))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(scheme.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(DateUtils.localizedDay(DateUtils.todayDayOfWeek(today: date)))
                        .foregroundColor(grey ? scheme.onSurfaceVariant : scheme.primary)
                    if store.showDate {
                        Text(DateUtils.shortDate(date))
                            .foregroundColor(scheme.onSurfaceVariant)
                    }
                    if isTransferDay && !grey {
                        Circle().fill(scheme.primary).frame(width: 5, height: 5)
                            .accessibilityLabel(L10n.t("holiday_list_workdays"))
                    }
                }
                if grey {
                    Text(store.greyAnnotation(date, tableId: table.id))
                        .foregroundColor(WatchPalette.errorColor(isDark: scheme.isDark))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
