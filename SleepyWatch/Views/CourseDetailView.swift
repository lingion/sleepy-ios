// CourseDetailView.swift — 课程详情 (2026-10 watch 伴侣 App)
// 手表 List→push 详情: 时间/节次/星期/周次/教师/教室/备注。

import SwiftUI

struct CourseDetailView: View {
    let course: CourseEntity
    let table: TimeTableEntity
    var groupRows: [CourseEntity] = []

    @Environment(\.colorScheme) private var envScheme
    @EnvironmentObject private var store: WatchStore

    var body: some View {
        let scheme = WatchPalette.scheme(envDark: envScheme == .dark)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(store.timeRange(course, table: table))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundColor(scheme.onSurfaceVariant)
                Text(CourseDisplayUtil.displayName(course, !course.alias.isEmpty))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(scheme.onSurface)
                infoRow(L10n.t("course_field_week"), course.nodeString(), scheme)
                infoRow(L10n.t("watch_detail_day"), DateUtils.localizedDay(course.day), scheme)
                infoRow(L10n.t("week_range"), "\(course.startWeek)-\(course.endWeek)", scheme)
                if !course.teacher.isEmpty {
                    infoRow(L10n.t("notif_channel_fluid_field_teacher"), course.teacher, scheme)
                }
                if !course.room.isEmpty {
                    infoRow(L10n.t("notif_channel_fluid_field_room"), course.room, scheme)
                }
                if !course.note.isEmpty {
                    infoRow(L10n.t("course_field_note"), course.note, scheme)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .navigationTitle(Text(CourseDisplayUtil.displayName(course, !course.alias.isEmpty)))
    }

    private func infoRow(_ label: String, _ value: String, _ scheme: WidgetScheme) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(scheme.onSurfaceVariant)
            Text(value)
                .font(.system(size: 12))
                .foregroundColor(scheme.onSurface)
        }
    }
}
