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
                    DatePicker("上课日期", selection: $date, displayedComponents: .date)
                        .environment(\.timeZone, CourseOccurrences.calendar.timeZone)
                        .accessibilityIdentifier("occurrence_date")
                    Toggle("固定日期（不随调休移动）", isOn: $fixed)
                }
                Section("本次上课时间") {
                    NumberStepperField(label: L10n.format("start_node"), value: $node,
                                       minV: minimumNode, maxV: maximumNode)
                    NumberStepperField(label: "结束节次", value: Binding(
                        get: { node + max(step, 1) - 1 }, set: { step = max(1, $0 - node + 1) }),
                                       minV: node, maxV: max(node, maximumNode))
                    Text("原节次：\(occurrence.course.startNode)–\(occurrence.course.startNode + occurrence.course.step - 1)")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("自定义时间", isOn: $custom)
                    if custom {
                        TextField("开始 HH:mm", text: $start).keyboardType(.numbersAndPunctuation)
                        TextField("结束 HH:mm", text: $end).keyboardType(.numbersAndPunctuation)
                    }
                }
                if let error { Section { Text(error).foregroundColor(.red) } }
                Section {
                    Button("保存本次调整") { prepare(delete: false) }
                        .accessibilityIdentifier("occurrence_save")
                    Button("仅删除本次", role: .destructive) { prepare(delete: true) }
                        .accessibilityIdentifier("occurrence_delete")
                }
            }
            .disabled(busy)
            .navigationTitle("调整本次课程")
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
        case .destination: return "该日期有调休课程"
        case .hidden: return "原日课程将被调休覆盖"
        case .outgoing: return "该日课程会随调休移动"
        case .conflicts: return "课程时间冲突"
        case .delete: return "仅删除本次课程？"
        case nil: return ""
        }
    }
    private var promptMessage: String {
        switch prompt {
        case .destination: return "跟随调休会把课程保存到此日对应的源教学日；按原日保存可能不会在当天显示。"
        case .hidden: return "该日的自然课表被补班课表覆盖。仍按原日保存？若需要当天独立显示，请返回并开启固定日期。"
        case .outgoing:
            let target = pending?.transfers.last { HolidayTransferOps.dayKey($0.sourceDate) == HolidayTransferOps.dayKey(date) }?.targetDate
            return "保存后将于 \(target.map(HolidayTransferOps.dayKey) ?? "补班日") 上课。"
        case .conflicts: return pending?.conflicts.joined(separator: "\n") ?? ""
        case .delete: return "\(occurrence.course.courseName)\n\(HolidayTransferOps.dayKey(occurrence.displayDate)) · \(occurrence.course.nodeString())"
        case nil: return ""
        }
    }
    @ViewBuilder private var promptButtons: some View {
        switch prompt {
        case .destination:
            Button("跟随调休") { chooseDestination(follow: true) }
            Button("按原日保存") { present(.hidden) }
        case .hidden:
            Button("仍按原日保存", role: .destructive) { checkConflicts() }
        case .outgoing:
            Button("继续") { checkConflicts() }
        case .conflicts:
            Button("仍然保存", role: .destructive) { commit() }
        case .delete:
            Button("删除本次", role: .destructive) { commit() }
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
            } else { error = "课表或调休设置已变化，请重新打开本次课程。" }
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
            Button("调整或删除本次课程") {
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
