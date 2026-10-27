// CourseRowView.swift — 课程行卡 (2026-10 watch 伴侣 App)
// ← WidgetCourseCard 显示语义的 watch 重排: 左色条 + 时间/课名/地点。
// 色: CourseColorUtil issue#22 三态取色同源 (组行传入本天可见课集)。
// 名: 手表空间小, 别名非空即显别名 (等价 widget_use_alias 常开)。

import SwiftUI

struct CourseRowView: View {
    let course: CourseEntity
    let table: TimeTableEntity
    let scheme: WidgetScheme
    var mark: CourseMark?
    var groupRows: [CourseEntity] = []

    @EnvironmentObject private var store: WatchStore

    private var color: Color {
        CourseColorUtil.pickCourseColorSwiftUIWithGroupRows(
            course, groupRows: groupRows.isEmpty ? [course] : groupRows,
            isDark: scheme.isDark, neutralColor: scheme.secondaryContainer)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 3)
                .padding(.vertical, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.timeRange(course, table: table))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(scheme.onSurfaceVariant)
                Text(CourseDisplayUtil.displayName(course, !course.alias.isEmpty))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(scheme.onSurface)
                    .lineLimit(2)
                if !course.room.isEmpty {
                    Text(course.room)
                        .font(.system(size: 11))
                        .foregroundColor(scheme.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let mark = mark {
                // 进行中/下一节角标 ← today_screen 实时态的手表降维
                Capsule()
                    .fill(mark == .current ? scheme.primary : scheme.primary.opacity(0.25))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                    .accessibilityLabel(mark == .current ? L10n.t("watch_mark_now") : L10n.t("watch_mark_next"))
            }
        }
        .padding(.vertical, 2)
    }
}
