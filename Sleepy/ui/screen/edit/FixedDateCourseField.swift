import SwiftUI

/// 组编辑也保留定日身份；日期选择同步周次字段，供原有节次编辑器使用。
struct FixedDateCourseField: View {
    @Binding var block: MeetingBlockDraft
    let table: TimeTableEntity

    private var selectedDate: Date {
        block.fixedDate.flatMap { CourseOccurrences.parseDate($0) }
            ?? CourseOccurrences.date(startDate: table.startDate, week: block.startWeek, day: block.days.sorted().first ?? 1)
            ?? Date()
    }

    private func setDate(_ date: Date) {
        guard let week = CourseOccurrences.week(startDate: table.startDate, date: date), week <= table.maxWeek else { return }
        block.fixedDate = HolidayTransferOps.dayKey(date)
        block.days = [CourseOccurrences.day(date)]
        block.startWeek = week
        block.endWeek = week
        block.weekType = 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L10n.format("occurrence_fixed_date"), isOn: Binding(
                get: { block.fixedDate != nil },
                set: { enabled in if enabled { setDate(selectedDate) } else { block.fixedDate = nil } }))
                .toggleStyle(.switch)
                .accessibilityIdentifier("course_fixed_date_toggle")
            if block.fixedDate != nil,
               let first = CourseOccurrences.date(startDate: table.startDate, week: 1, day: 1),
               let last = CourseOccurrences.date(startDate: table.startDate, week: table.maxWeek, day: 7), first <= last {
                DatePicker(L10n.format("occurrence_date"), selection: Binding(get: { selectedDate }, set: setDate), in: first...last, displayedComponents: .date)
                    .environment(\.timeZone, CourseOccurrences.calendar.timeZone)
                    .accessibilityIdentifier("course_fixed_date_picker")
            }
        }
        .padding()
    }
}
