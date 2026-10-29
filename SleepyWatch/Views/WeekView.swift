// WeekView.swift — 整周视图 (2026-10 watch 伴侣 App)
// 语义 ← iOS 网格周模式 + WeekListWidgetLoader 同源:
// · 列 = 周一起 7 天 (手表=手机固定口径, iOS 无周起始设置), visible_days 过滤;
// · 列头 = 本地化星期 + show_date 镜像日期 + 节假日/调休标注 (有节假日或调休时
//   直接写「放假/补班 X」, 灰显由 shouldGrey 决策核判定 — 读磁盘镜像纯函数);
// · 列内课行 = store.courses(on:) (调休换日 + 学期过滤 + 节次排序共享层全口径)。

import SwiftUI

struct WeekView: View {
    @EnvironmentObject private var store: WatchStore
    @Environment(\.colorScheme) private var envScheme

    var body: some View {
        let scheme = WatchPalette.scheme(envDark: envScheme == .dark)
        Group {
            if let table = store.currentTable() {
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        // 锚定周 ← ScheduleViewModel:259 / WidgetWeekSource.resolvedToday:
                        // nearest_busy_day 镜像开且今日无剩余课 → 跳最近有课日所在周
                        ForEach(weekColumns(anchor: store.weekAnchorDate(table)), id: \.self) { date in
                            dayColumn(date: date, table: table, scheme: scheme)
                        }
                    }
                    .padding(8)
                }
            } else {
                Text(L10n.t("watch_no_table_hint"))
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundColor(scheme.onSurfaceVariant)
                    .padding()
            }
        }
        .navigationTitle(Text(L10n.t("tab_schedule")))
        // watchOS List 默认缩进在手表上留大片死边, 归零
        .environment(\.defaultMinListRowHeight, 30)
    }

    /// 锚定周 (周一..周日) 中可见的星期 (visible_days 1=一..7=日)
    private func weekColumns(anchor: Date) -> [Date] {
        store.weekDates(today: anchor)
            .filter { store.visibleDays.contains(DateUtils.todayDayOfWeek(today: $0)) }
    }

    @ViewBuilder
    private func dayColumn(date: Date, table: TimeTableEntity, scheme: WidgetScheme) -> some View {
        let courses = store.courses(on: date, table: table)
        let grey = store.shouldGrey(date, tableId: table.id)
        let isTransferDay = store.isTransferSourceDay(date, tableId: table.id)
        VStack(alignment: .leading, spacing: 4) {
            // 列头: 星期 (灰显日降对比) + 日期 (show_date) + 标注行
            VStack(alignment: .leading, spacing: 0) {
                Text(DateUtils.localizedDay(DateUtils.todayDayOfWeek(today: date)))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(grey ? scheme.onSurfaceVariant : scheme.primary)
                if store.showDate {
                    Text(DateUtils.shortDate(date))
                        .font(.system(size: 9))
                        .foregroundColor(scheme.onSurfaceVariant)
                }
                if grey {
                    // 「放假 X」/「补班 X」/「无课」 — store 内同源前缀复用 iOS 键。
                    // WidgetScheme 无 error token, 固定红 = iOS 节假日标注同源色
                    Text(store.greyAnnotation(date, tableId: table.id))
                        .font(.system(size: 9))
                        .foregroundColor(WatchPalette.errorColor(isDark: scheme.isDark))
                        .lineLimit(1)
                } else if isTransferDay {
                    // 用户调休上班日 (非法定节假日): 那天上换日后的课 — 列已呈现,
                    // 仅点一枚圆点提示「此列为调休得来」(WidgetScheme 无 tertiary → primary)
                    Circle().fill(scheme.primary).frame(width: 5, height: 5)
                        .accessibilityLabel(L10n.t("holiday_list_workdays"))
                }
            }
            ForEach(courses) { course in
                NavigationLink {
                    CourseDetailView(course: course, table: table, groupRows: courses)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.slotLabel(course, table: table))
                            .font(.system(size: 9, weight: .medium).monospacedDigit())
                            .foregroundColor(scheme.onSurfaceVariant)
                        Text(CourseDisplayUtil.displayName(course, store.useGridAlias && !course.alias.isEmpty))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(scheme.onSurface)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 8).fill(scheme.surfaceVariant))
                }
                .buttonStyle(SleepyButtonStyle())
            }
            if courses.isEmpty && !grey && !isTransferDay {
                Text(L10n.t("no_course"))
                    .font(.system(size: 9))
                    .foregroundColor(scheme.onSurfaceVariant)
            }
        }
        .frame(width: 64, alignment: .leading)
    }
}
