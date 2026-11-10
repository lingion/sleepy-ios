import SwiftUI

struct CourseSelectionSheet: View {
    @Environment(\.localWakeUpColors) private var colors
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
                            Button {
                                if selected.contains(group.id) { selected.remove(group.id) }
                                else { selected.insert(group.id) }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: selected.contains(group.id) ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 24)).foregroundColor(colors.primary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(group.courseName.isEmpty ? L10n.format("course_detail_title") : group.courseName)
                                            .font(.system(size: 16, weight: .semibold)).foregroundColor(colors.onSurface)
                                        if !group.teacher.isEmpty { Label(group.teacher, systemImage: "person").font(.system(size: 12)) }
                                        ForEach(group.rooms, id: \.self) { Label($0, systemImage: "mappin").font(.system(size: 12)) }
                                        Text(L10n.format("course_list_arrangements", group.rows.count)).font(.system(size: 12))
                                    }
                                    .foregroundColor(colors.onSurfaceVariant)
                                    Spacer(minLength: 0)
                                }
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                .background(colors.surfaceContainer).cornerRadius(SleepyShapes.large)
                            }
                            .buttonStyle(.plain)
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
}
