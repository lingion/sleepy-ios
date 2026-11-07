import SwiftUI

/// 从详情/拖课菜单打开的原生单次编辑器。存储行、源日和展示日必须来自同一次解析。
struct CourseOccurrenceEditor: View {
    let occurrence: CourseOccurrence
    let table: TimeTableEntity
    let repository: ScheduleRepository
    let onSaved: () -> Void
    let onDismiss: () -> Void

    @State private var date: Date
    @State private var node: Int
    @State private var step: Int
    @State private var custom: Bool
    @State private var start: String
    @State private var end: String
    @State private var fixed: Bool
    @State private var error: String?
    @State private var busy = false
    @State private var prompt: Prompt?
    @State private var pending: PendingSave?

    private enum Prompt { case destination, hidden, outgoing, conflicts, delete }
    private struct PendingSave {
        var replacement: CourseEntity?
        let courses: [CourseEntity]
        let transfers: [HolidayTransferEntry]
        let table: TimeTableEntity
        var conflicts: [String] = []
    }

    init(occurrence: CourseOccurrence, table: TimeTableEntity, repository: ScheduleRepository,
         onSaved: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.occurrence = occurrence
        self.table = table
        self.repository = repository
        self.onSaved = onSaved
        self.onDismiss = onDismiss
        let row = occurrence.course
        let range = TimeTableUtils.effectiveCourseTime(isIrregularTime: row.ownTime || row.isIrregularTime,
            startTime: row.startTime, endTime: row.endTime, startNode: row.startNode, step: row.step, timeJson: table.timeJson)
        _date = State(initialValue: occurrence.displayDate)
        _node = State(initialValue: row.startNode)
        _step = State(initialValue: row.step)
        _custom = State(initialValue: row.ownTime || row.isIrregularTime)
        _start = State(initialValue: range?.0 ?? "08:00")
        _end = State(initialValue: range?.1 ?? "09:40")
        _fixed = State(initialValue: row.fixedDate != nil)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text(occurrence.course.alias.isEmpty ? occurrence.course.courseName : occurrence.course.alias)
                        .font(.headline)
                    Text("\(HolidayTransferOps.dayKey(occurrence.displayDate)) · \(occurrence.course.nodeString())")
                        .foregroundStyle(.secondary)
                    DatePicker(L10n.format("occurrence_date"), selection: $date, displayedComponents: .date)
                        .environment(\.timeZone, CourseOccurrences.calendar.timeZone)
                        .accessibilityIdentifier("occurrence_date")
                    Toggle(L10n.format("occurrence_fixed_date"), isOn: $fixed)
                }
                Section(L10n.format("occurrence_time")) {
                    NumberStepperField(label: L10n.format("start_node"), value: $node,
                                       minV: minimumNode, maxV: maximumNode)
                    NumberStepperField(label: L10n.format("occurrence_end_node"), value: Binding(
                        get: { node + max(step, 1) - 1 }, set: { step = max(1, $0 - node + 1) }),
                                       minV: node, maxV: max(node, maximumNode))
                    Text(L10n.format("occurrence_original_nodes", occurrence.course.startNode, occurrence.course.startNode + occurrence.course.step - 1))
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(L10n.format("occurrence_custom_time"), isOn: $custom)
                    if custom {
                        TextField(L10n.format("occurrence_start_time"), text: $start).keyboardType(.numbersAndPunctuation)
                        TextField(L10n.format("occurrence_end_time"), text: $end).keyboardType(.numbersAndPunctuation)
                    }
                }
                if let error { Section { Text(error).foregroundColor(.red) } }
                Section {
                    Button(L10n.format("occurrence_save")) { prepare(delete: false) }
                        .accessibilityIdentifier("occurrence_save")
                    Button(L10n.format("occurrence_delete"), role: .destructive) { prepare(delete: true) }
                        .accessibilityIdentifier("occurrence_delete")
                }
            }
            .disabled(busy)
            .navigationTitle(L10n.format("occurrence_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(L10n.format("cancel"), action: onDismiss) } }
            .alert(promptTitle, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
                promptButtons
            } message: { Text(promptMessage) }
        }
        .accessibilityIdentifier("occurrence_editor")
    }

    private var minimumNode: Int { TimeTableUtils.parseTimeSlotRows(table.timeJson).map { $0.node }.min() ?? 1 }
    private var maximumNode: Int { TimeTableUtils.parseTimeSlotRows(table.timeJson).map { $0.node }.max() ?? 1 }
    private var promptTitle: String {
        switch prompt {
        case .destination: return L10n.format("occurrence_destination_title")
        case .hidden: return L10n.format("occurrence_hidden_title")
        case .outgoing: return L10n.format("occurrence_outgoing_title")
        case .conflicts: return L10n.format("conflict_detail_title")
        case .delete: return L10n.format("occurrence_delete_title")
        case nil: return ""
        }
    }
    private var promptMessage: String {
        switch prompt {
        case .destination: return L10n.format("occurrence_destination_message")
        case .hidden: return L10n.format("occurrence_hidden_message")
        case .outgoing:
            let target = pending?.transfers.last { HolidayTransferOps.dayKey($0.sourceDate) == HolidayTransferOps.dayKey(date) }?.targetDate
            return L10n.format("occurrence_outgoing_message", target.map(HolidayTransferOps.dayKey) ?? L10n.format("occurrence_transfer_day"))
        case .conflicts: return pending?.conflicts.joined(separator: "\n") ?? ""
        case .delete: return "\(occurrence.course.courseName)\n\(HolidayTransferOps.dayKey(occurrence.displayDate)) · \(occurrence.course.nodeString())"
        case nil: return ""
        }
    }
    @ViewBuilder private var promptButtons: some View {
        switch prompt {
        case .destination:
            Button(L10n.format("occurrence_follow_transfer")) { chooseDestination(follow: true) }
            Button(L10n.format("occurrence_keep_date")) { present(.hidden) }
        case .hidden:
            Button(L10n.format("occurrence_keep_date"), role: .destructive) { checkConflicts() }
        case .outgoing:
            Button(L10n.format("occurrence_continue")) { checkConflicts() }
        case .conflicts:
            Button(L10n.format("conflict_detail_save_anyway"), role: .destructive) { commit() }
        case .delete:
            Button(L10n.format("occurrence_delete"), role: .destructive) { commit() }
        case nil: EmptyView()
        }
        Button(L10n.format("cancel"), role: .cancel) { pending = nil; prompt = nil }
    }

    private func prepare(delete: Bool) {
        guard !busy else { return }
        error = nil
        do {
            guard let storedTable = try repository.getTable(table.id) else { throw CourseOccurrences.ValidationError.invalidOccurrence }
            let effective = storedTable.hydratedWith(try repository.effectivePeriodTable(tableId: table.id))
            let courses = try repository.getCourses(table.id)
            let transfers = AppPrefs.shared.getHolidayTransfers(table.id)
            guard courses.contains(occurrence.course),
                  let resolved = CourseOccurrences.resolve(course: occurrence.course, displayDate: occurrence.displayDate,
                                                           table: effective, transfers: transfers),
                  HolidayTransferOps.dayKey(resolved.sourceDate) == HolidayTransferOps.dayKey(occurrence.sourceDate) else {
                throw CourseOccurrences.ValidationError.invalidOccurrence
            }
            var replacement: CourseEntity?
            if !delete {
                var edited = occurrence.course
                edited.startNode = node
                edited.step = step
                edited.ownTime = custom
                edited.isIrregularTime = custom
                edited.isIrregularNode = TimeTableUtils.parseTimeSlotRows(effective.timeJson).contains { $0.node == node && $0.edgeClass != nil }
                edited.startTime = custom ? start.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                edited.endTime = custom ? end.trimmingCharacters(in: .whitespacesAndNewlines) : ""
                try CourseOccurrences.validateTime(edited, table: effective)
                edited = edited.normalizeNode(timeJson: effective.timeJson)
                let unchangedDate = HolidayTransferOps.dayKey(date) == HolidayTransferOps.dayKey(occurrence.displayDate)
                let target = unchangedDate && !fixed ? occurrence.sourceDate : date
                replacement = try CourseOccurrences.atDate(edited, date: target, table: effective, fixed: fixed)
            }
            pending = PendingSave(replacement: replacement, courses: courses, transfers: transfers, table: effective)
            if delete { prompt = .delete; return }
            if !fixed && HolidayTransferOps.dayKey(date) != HolidayTransferOps.dayKey(occurrence.displayDate) {
                if transfers.contains(where: { HolidayTransferOps.dayKey($0.targetDate) == HolidayTransferOps.dayKey(date) }) {
                    prompt = .destination; return
                }
                if transfers.contains(where: { HolidayTransferOps.dayKey($0.sourceDate) == HolidayTransferOps.dayKey(date) }) {
                    prompt = .outgoing; return
                }
            }
            checkConflicts()
        } catch { self.error = error.localizedDescription }
    }

    private func chooseDestination(follow: Bool) {
        guard var draft = pending, let replacement = draft.replacement else { return }
        do {
            if follow, let source = HolidayTransferOps.courseDateForDate(date, draft.transfers) {
                draft.replacement = try CourseOccurrences.atDate(replacement, date: source, table: draft.table, fixed: false)
            }
            pending = draft
            checkConflicts()
        } catch { self.error = error.localizedDescription; pending = nil }
    }

    private func checkConflicts() {
        guard var draft = pending, let replacement = draft.replacement else { return }
        do {
            let remaining = try CourseOccurrences.without(occurrence.course, sourceDate: occurrence.sourceDate, startDate: draft.table.startDate)
            draft.conflicts = CourseOccurrences.conflictDetails(drafts: [replacement],
                stored: draft.courses.filter { $0.id != occurrence.course.id } + remaining,
                table: draft.table, transfers: draft.transfers)
            pending = draft
            if draft.conflicts.isEmpty { commit() } else { present(.conflicts) }
        } catch { self.error = error.localizedDescription; pending = nil }
    }

    private func commit() {
        guard let draft = pending, !busy else { return }
        busy = true
        defer { busy = false; pending = nil }
        do {
            if try repository.saveOccurrence(occurrence, replacement: draft.replacement, expectedCourses: draft.courses,
                                             expectedTable: draft.table, expectedTransfers: draft.transfers) {
                onSaved()
                onDismiss()
            } else { error = L10n.format("occurrence_stale") }
        } catch { self.error = error.localizedDescription }
    }

    /// SwiftUI alert 按钮会自动关闭当前弹窗；下一步等关闭回写完成再呈现。
    private func present(_ next: Prompt) {
        prompt = nil
        DispatchQueue.main.async { prompt = next }
    }
}

/// 供详情页接入的完整入口；先按 id 取原行，拒绝使用网格投影副本进行写入。
struct CourseOccurrenceActions: View {
    let courseId: Int64
    let displayDate: Date
    let table: TimeTableEntity
    let repository: ScheduleRepository
    let onSaved: () -> Void
    @State private var target: EditorTarget?
    @State private var error: String?
    private struct EditorTarget: Identifiable { let id = UUID(); let occurrence: CourseOccurrence; let table: TimeTableEntity }

    var body: some View {
        VStack {
            Button(L10n.format("occurrence_actions")) {
                do {
                    guard let course = try repository.getCourse(courseId),
                          let stored = try repository.getTable(table.id) else { throw CourseOccurrences.ValidationError.invalidOccurrence }
                    let effective = stored.hydratedWith(try repository.effectivePeriodTable(tableId: stored.id))
                    guard let occurrence = CourseOccurrences.resolve(course: course, displayDate: displayDate, table: effective,
                        transfers: AppPrefs.shared.getHolidayTransfers(stored.id)) else { throw CourseOccurrences.ValidationError.invalidOccurrence }
                    target = EditorTarget(occurrence: occurrence, table: effective)
                    error = nil
                } catch { self.error = error.localizedDescription }
            }
            .accessibilityIdentifier("course_occurrence_actions")
            if let error { Text(error).foregroundColor(.red) }
        }
        .sheet(item: $target) { item in
            CourseOccurrenceEditor(occurrence: item.occurrence, table: item.table, repository: repository,
                                   onSaved: onSaved, onDismiss: { target = nil })
        }
    }
}
