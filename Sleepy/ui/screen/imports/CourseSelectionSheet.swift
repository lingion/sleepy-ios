import SwiftUI

struct CourseSelectionSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let groups: [ImportCourseGroup]
    let onConfirm: (Set<String>) -> Void
    let onDismiss: () -> Void
    @State private var selected: Set<String>

    init(parseResult: ScheduleParser.ParseResult, onConfirm: @escaping (Set<String>) -> Void, onDismiss: @escaping () -> Void) {
        let groups = AddCoursesImport.groups(parseResult.courses)
        self.groups = groups
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _selected = State(initialValue: Set(groups.map(\.id)))
    }

    var body: some View {
        VStack(spacing: 0) {
            selectionTopBar
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        selectionRow(for: group)
                        .background(colors.surfaceContainer).cornerRadius(SleepyShapes.large)
                        .accessibilityIdentifier("select_course#\(index)")
                        .accessibilityValue(selected.contains(group.id) ? "1" : "0")
                        .accessibilityAddTraits(selected.contains(group.id) ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background.ignoresSafeArea())
        .accessibilityAction(.escape, onDismiss)
    }

    private var selectionTopBar: some View {
        Group {
            if #available(iOS 16.0, *) {
                ViewThatFits(in: .horizontal) {
                    inlineSelectionTopBar
                    stackedSelectionTopBar
                }
            } else {
                stackedSelectionTopBar
            }
        }
        .padding(.horizontal, 4)
        .background(colors.background)
    }

    private var inlineSelectionTopBar: some View {
        HStack(spacing: 0) {
            selectionBackButton
            selectionHeading
                .fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
            selectionActions
                .fixedSize(horizontal: true, vertical: true)
        }
        .frame(minHeight: 64)
    }

    private var stackedSelectionTopBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                selectionBackButton
                selectionHeading
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            }
            .frame(minHeight: 64)
            selectionActions
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var selectionBackButton: some View {
        Button(action: onDismiss) {
            AndroidSettingsIcon(name: .arrowBack, size: 24)
                .foregroundColor(colors.onBackground)
                .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.format("cancel"))
        .accessibilityIdentifier("import_select_cancel")
    }

    private var selectionHeading: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.format("select_courses_title"))
                .font(.system(size: 22))
                .foregroundColor(colors.onBackground)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.format("select_courses_count", selected.count, groups.count))
                .font(.system(size: 11))
                .foregroundColor(colors.onSurfaceVariant)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var selectionActions: some View {
        HStack(spacing: 0) {
            Button {
                selected = selected.count == groups.count ? [] : Set(groups.map(\.id))
            } label: {
                Text(L10n.format(selected.count == groups.count ? "select_courses_none" : "select_courses_all"))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 48, minHeight: 48)
            }
            .buttonStyle(.plain)
            .foregroundColor(colors.primary)
            .accessibilityIdentifier("import_select_all")

            Button { onConfirm(selected) } label: {
                Text(L10n.format("import_confirm"))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .frame(minWidth: 48, minHeight: 48)
            }
            .buttonStyle(.plain)
            .foregroundColor(selected.isEmpty ? colors.onSurface.opacity(0.38) : colors.primary)
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("import_select_confirm")
        }
    }

    @ViewBuilder
    private func selectionRow(for group: ImportCourseGroup) -> some View {
        if style == .liquidGlass {
            Toggle(isOn: Binding(
                get: { selected.contains(group.id) },
                set: { setSelected($0, for: group.id) }
            )) {
                courseDetails(for: group)
            }
            .toggleStyle(.switch)
            .tint(colors.primary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        } else {
            Button { setSelected(!selected.contains(group.id), for: group.id) } label: {
                HStack(spacing: 0) {
                    MaterialSelectionIndicator(kind: .checkbox, selected: selected.contains(group.id))
                        .frame(width: 48, height: 48)
                    courseDetails(for: group)
                }
                .padding(.leading, 4)
                .padding(.trailing, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func courseDetails(for group: ImportCourseGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.courseName.isEmpty ? L10n.format("course_detail_title") : group.courseName)
                .font(.system(size: 16, weight: .semibold)).foregroundColor(colors.onSurface)
            if !group.teacher.isEmpty {
                metadata(group.teacher, icon: .person)
            }
            ForEach(group.rooms, id: \.self) { metadata($0, icon: .locationOn) }
            Text(L10n.format("course_list_arrangements", group.rows.count)).font(.system(size: 11))
        }
        .foregroundColor(colors.onSurfaceVariant)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadata(_ text: String, icon: AndroidSettingsIcon.Name) -> some View {
        HStack(spacing: 6) {
            AndroidSettingsIcon(name: icon, size: 14)
            Text(text).font(.system(size: 12))
        }
    }

    private func setSelected(_ isSelected: Bool, for id: String) {
        if isSelected { selected.insert(id) }
        else { selected.remove(id) }
    }
}
