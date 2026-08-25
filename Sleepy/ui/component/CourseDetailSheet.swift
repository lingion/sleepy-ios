// CourseDetailSheet.swift — ← ui/component/CourseDetailSheet.kt
// 课程详情 Bottom Sheet — 仿 switchable.html .modal-backdrop
// 结构: Header(课程名) → TimeChip(secondaryContainer pill) → 字段行 → 编辑按钮。

import SwiftUI

struct CourseDetailSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let course: CourseEntity?
    var timeString: String? = nil
    var onEdit: ((CourseEntity) -> Void)? = nil

    var body: some View {
        if let course = course {
            VStack(alignment: .leading, spacing: 0) {
                // Header ← SheetHeader (surface-container)
                HStack {
                    Text(course.courseName.isEmpty ? L10n.format("course_detail_title") : course.courseName)
                        .font(SleepyTypography.titleLarge)
                        .foregroundColor(colors.onSurface)
                        .lineLimit(3)
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("detail_close")
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.surfaceContainer)

                // Body
                VStack(alignment: .leading, spacing: 12) {
                    if let timeString = timeString {
                        TimeChip(text: timeString)
                    }

                    DetailRow(key: L10n.format("course_field_name"),
                              value: course.courseName.isEmpty ? "—" : course.courseName)
                    if !course.teacher.isEmpty {
                        DetailRow(key: L10n.format("course_field_teacher"), value: course.teacher)
                    }
                    if !course.room.isEmpty {
                        DetailRow(key: L10n.format("course_field_room"), value: course.room)
                    }
                    DetailRow(key: L10n.format("course_field_week"),
                              value: L10n.format("course_week_range", course.nodeString(isShort: true),
                                                 course.startWeek, course.endWeek))
                    if !course.note.isEmpty {
                        DetailRow(key: L10n.format("course_field_note"), value: course.note)
                    }

                    if let onEdit = onEdit {
                        Button {
                            onEdit(course)
                        } label: {
                            Text(L10n.format("course_detail_edit_course"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.onPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(colors.primary)
                                .cornerRadius(SleepyShapes.large)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("detail_edit")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .padding(.bottom, 12)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
    }

    private func onDismiss() {
        dismiss()
    }
}

// ← TimeChip
private struct TimeChip: View {
    @Environment(\.localWakeUpColors) private var colors
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(colors.onSecondaryContainer)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(colors.secondaryContainer)
            .cornerRadius(SleepyShapes.medium)
    }
}

// ← DetailRow
private struct DetailRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(key)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
                .frame(width: 54, alignment: .leading)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
