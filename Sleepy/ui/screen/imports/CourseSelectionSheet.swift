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
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    Text(L10n.format("select_courses_count", selected.count, groups.count))
                        .font(.system(size: 12)).foregroundColor(colors.onSurfaceVariant)
                    Spacer()
                    Button(L10n.format(selected.count == groups.count ? "select_courses_none" : "select_courses_all")) {
                        selected = selected.count == groups.count ? [] : Set(groups.map(\.id))
                    }
                    .accessibilityIdentifier("import_select_all")
                }
                .padding(16)
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
                    .padding(.horizontal, 16).padding(.bottom, 16)
                }
                Button(L10n.format("import_confirm")) { onConfirm(selected) }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.onPrimary).frame(maxWidth: .infinity).frame(height: 48)
                    .background(selected.isEmpty ? colors.onSurfaceVariant : colors.primary)
                    .cornerRadius(SleepyShapes.large).padding(16)
                    .disabled(selected.isEmpty).accessibilityIdentifier("import_select_confirm")
            }
            .background(colors.surface).navigationTitle(L10n.format("select_courses_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button(L10n.format("cancel"), action: onDismiss) } }
        }
        .navigationViewStyle(.stack)
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
            Text(L10n.format("course_list_arrangements", group.rows.count)).font(.system(size: 12))
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
