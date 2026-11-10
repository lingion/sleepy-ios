import SwiftUI

/// 从详情/拖课菜单打开的单次编辑器。存储行、源日和展示日必须来自同一次解析。
struct CourseOccurrenceEditor: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
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
    @State private var room: String
    @State private var fixed: Bool
    @State private var error: String?
    @State private var busy = false
    @State private var prompt: Prompt?
    @State private var pending: PendingSave?
    @State private var showDatePicker = false
    @State private var pickerDate = Date()
    @FocusState private var focusedTime: String?

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
        _room = State(initialValue: row.room)
        _fixed = State(initialValue: row.fixedDate != nil)
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(occurrence.course.alias.isEmpty ? occurrence.course.courseName : occurrence.course.alias)
                            .font(.system(size: 22))
                        Text("\(HolidayTransferOps.dayKey(occurrence.displayDate)) · \(occurrence.course.nodeString())")
                            .font(.system(size: 16))
                        dateCard
                        Toggle(L10n.format("occurrence_fixed_date"), isOn: $fixed)
                            .toggleStyle(OccurrenceCheckboxStyle(identifier: "occurrence_fixed_date"))
                        if hasStandardRange {
                            let shown = IntSliderRange(start: node, end: node + max(step, 1) - 1,
                                                       minimum: 1, maximum: maximumStandardNode)
                            IntRangeSlider(summary: AddCourseScreen.nodeRangeSummary(shown),
                                minValue: 1, maxValue: maximumStandardNode, startValue: shown.start, endValue: shown.end,
                                onValueChange: { node = $0; step = $1 - $0 + 1 },
                                initialStart: occurrence.course.startNode,
                                initialEnd: occurrence.course.startNode + occurrence.course.step - 1,
                                identifier: "occurrence_nodes")
                        } else {
                            HStack(spacing: 12) {
                                nodeInput("start_node", value: $node, invalidValue: Int.min, identifier: "occurrence_node")
                                nodeInput("step_count", value: $step, invalidValue: 0, identifier: "occurrence_step")
                            }
                        }
                        Toggle(L10n.format("occurrence_custom_time"), isOn: Binding(
                            get: { custom }, set: { enabled in
                                if enabled, let range = TimeTableUtils.effectiveCourseTime(isIrregularTime: false,
                                    startTime: "", endTime: "", startNode: node, step: step, timeJson: table.timeJson) {
                                    start = range.0
                                    end = range.1
                                }
                                custom = enabled
                            }))
                            .toggleStyle(OccurrenceCheckboxStyle(identifier: "occurrence_custom_time"))
                        if custom {
                            HStack(spacing: 12) {
                                timeInput("occurrence_start_time", text: $start)
                                timeInput("occurrence_end_time", text: $end)
                            }
                        }
                        FieldTextField(text: $room, label: L10n.format("course_room"))
                            .focused($focusedTime, equals: "occurrence_room")
                            .id("occurrence_room")
                            .accessibilityIdentifier("occurrence_room")
                        if let error {
                            Text(error).foregroundColor(colors.error).accessibilityIdentifier("occurrence_error")
                        }
                        actionButton("occurrence_save", container: colors.primary, content: colors.onPrimary) { prepare(delete: false) }
                        actionButton("occurrence_delete", container: colors.errorContainer, content: colors.onErrorContainer) { prepare(delete: true) }
                        Spacer().frame(height: 16)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .foregroundColor(colors.onSurface)
                .background(colors.surface.ignoresSafeArea())
                .background(GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.size) { _ in revealFocusedTime(using: proxy) }
                })
                .onChange(of: focusedTime) { _ in revealFocusedTime(using: proxy) }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
                    revealFocusedTime(using: proxy)
                }
                .disabled(busy)
                .navigationTitle(L10n.format("occurrence_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.format("cancel"), action: onDismiss)
                            .accessibilityIdentifier("occurrence_cancel")
                    }
                }
                .alert(promptTitle, isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
                    promptButtons
                } message: { Text(promptMessage) }
                .sheet(isPresented: $showDatePicker) { datePickerSheet }
            }
        }
        .navigationViewStyle(.stack)
        .accentColor(colors.primary)
        .accessibilityIdentifier("occurrence_editor")
    }
    private func revealFocusedTime(using proxy: ScrollViewProxy) {
        guard let key = focusedTime else { return }
        // The keyboard and sheet finish resizing after the focus event. Recenter
        // the complete outlined field in the updated viewport, including rotation.
        DispatchQueue.main.async {
            guard focusedTime == key else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(key, anchor: .center) }
        }
    }
    @ViewBuilder private var dateCard: some View {
        if style == .liquidGlass {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.format("occurrence_date"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    pickerDate = date
                    showDatePicker = true
                } label: {
                    Label {
                        Text(date, formatter: dateFormatter)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        AndroidMaterialIcon(name: .calendarMonth, size: 24)
                    }
                }
                .buttonStyle(SleepyPlatformButtonStyle())
                .controlSize(.large)
                .tint(colors.primary)
                .accessibilityIdentifier("occurrence_date")
            }
        } else {
            classicDateCard
        }
    }
    private var classicDateCard: some View {
        Button { pickerDate = date; showDatePicker = true } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.format("occurrence_date")).font(.system(size: 12)).foregroundColor(colors.onSurfaceVariant)
                    Text(date, formatter: dateFormatter).font(.system(size: 16)).foregroundColor(colors.onSurface)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                AndroidMaterialIcon(name: .calendarMonth, size: 24).foregroundColor(colors.primary)
            }
            .padding(16)
            .overlay(RoundedRectangle(cornerRadius: SleepyShapes.medium).stroke(colors.outline, lineWidth: 1))
        }
        .buttonStyle(SleepyPlatformButtonStyle())
        .accessibilityIdentifier("occurrence_date")
    }
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = LocaleHelper.locale(for: AppPrefs.shared.getLanguage())
        formatter.dateStyle = .full
        formatter.timeZone = CourseOccurrences.calendar.timeZone
        return formatter
    }
    private var datePickerSheet: some View {
        ScrollView {
            VStack(spacing: 12) {
                DatePicker(L10n.format("occurrence_date"), selection: $pickerDate,
                           in: datePickerBounds, displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden()
                    .environment(\.timeZone, CourseOccurrences.calendar.timeZone)
                    .environment(\.locale, LocaleHelper.locale(for: AppPrefs.shared.getLanguage()))
                DialogActionButtons(confirmText: L10n.format("ok"), onConfirm: {
                    guard isSelectableOccurrenceDate(pickerDate) else { return }
                    date = CourseOccurrences.calendar.startOfDay(for: pickerDate)
                    showDatePicker = false
                },
                    dismissText: L10n.format("cancel"), onDismiss: { showDatePicker = false },
                    confirmEnabled: isSelectableOccurrenceDate(pickerDate),
                    confirmIdentifier: "date_picker_confirm", dismissIdentifier: "date_picker_cancel")
            }.padding(20)
        }.background(colors.surface).sheetDetents([.large])
    }
    private var datePickerBounds: ClosedRange<Date> {
        let original = CourseOccurrences.calendar.startOfDay(for: occurrence.displayDate)
        guard let first = CourseOccurrences.date(startDate: table.startDate, week: 1, day: 1),
              let last = CourseOccurrences.date(startDate: table.startDate, week: table.maxWeek, day: 7),
              first <= last else { return original...original }
        // Native DatePicker supports one continuous range. If a transferred
        // occurrence lies outside the semester, retain that original day too;
        // the confirmation gate excludes every other day in the gap.
        return min(first, original)...max(last, original)
    }
    private func isSelectableOccurrenceDate(_ candidate: Date) -> Bool {
        let calendar = CourseOccurrences.calendar
        if calendar.isDate(candidate, inSameDayAs: occurrence.displayDate) { return true }
        guard let week = CourseOccurrences.week(startDate: table.startDate, date: candidate) else { return false }
        return week <= table.maxWeek
    }
    private func nodeInput(_ key: String, value: Binding<Int>, invalidValue: Int, identifier: String) -> some View {
        OccurrenceNodeInput(label: L10n.format(key), value: value, invalidValue: invalidValue, identifier: identifier)
    }
    private func timeInput(_ key: String, text: Binding<String>) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain).font(.system(size: 16)).keyboardType(.numbersAndPunctuation)
            .padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 56)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(colors.outline, lineWidth: 1))
            .overlay(alignment: .topLeading) {
                Text(L10n.format(key)).font(.system(size: 12)).foregroundColor(colors.onSurfaceVariant)
                    .padding(.horizontal, 4).background(colors.surface).padding(.leading, 12).offset(y: -7).accessibilityHidden(true)
            }
            .focused($focusedTime, equals: key)
            .accessibilityLabel(L10n.format(key)).accessibilityIdentifier(key).id(key)
    }
    @ViewBuilder
    private func actionButton(_ key: String, container: Color, content: Color, action: @escaping () -> Void) -> some View {
        if style == .liquidGlass {
            Button(role: key == "occurrence_delete" ? .destructive : nil, action: action) {
                Text(L10n.format(key)).frame(maxWidth: .infinity)
            }
            .buttonStyle(SleepyPlatformButtonStyle(prominent: key == "occurrence_save"))
            .controlSize(.large)
            .tint(key == "occurrence_delete" ? colors.error : colors.primary)
            .accessibilityIdentifier(key)
        } else {
            Button(action: action) {
                Text(L10n.format(key)).font(.system(size: 14, weight: .medium)).foregroundColor(content)
                    .frame(maxWidth: .infinity).frame(height: 48).background(container).clipShape(Capsule())
            }.buttonStyle(SleepyButtonStyle()).accessibilityIdentifier(key)
        }
    }

    private var maximumStandardNode: Int { TimeTableUtils.maxStandardNode(table.timeJson) }
    private var hasStandardRange: Bool {
        (1...max(1, maximumStandardNode)).contains(occurrence.course.startNode) && !occurrence.course.isIrregularNode
    }
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
                .accessibilityIdentifier("occurrence_delete_confirm")
        case nil: EmptyView()
        }
        Button(L10n.format("cancel"), role: .cancel) { pending = nil; prompt = nil }
            .accessibilityIdentifier("occurrence_prompt_cancel")
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
                edited.room = room == occurrence.course.room ? room : room.trimmingCharacters(in: .whitespacesAndNewlines)
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

private struct OccurrenceNodeInput: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    @Binding var value: Int
    let invalidValue: Int
    let identifier: String
    @State private var text: String

    init(label: String, value: Binding<Int>, invalidValue: Int, identifier: String) {
        self.label = label
        self._value = value
        self.invalidValue = invalidValue
        self.identifier = identifier
        self._text = State(initialValue: String(value.wrappedValue))
    }

    private func parsedValue(_ input: String) -> Int {
        // Android keeps the raw node/step text and validates Int on save.
        // Preserve invalid input visibly while making the existing save
        // validation reject it instead of silently saving an older value.
        Int32(input).map { Int($0) } ?? invalidValue
    }

    var body: some View {
        TextField("", text: Binding(get: { text }, set: {
            text = $0
            value = parsedValue($0)
        }))
        .textFieldStyle(.plain).font(.system(size: 16)).keyboardType(.numbersAndPunctuation)
        .padding(.horizontal, 16).frame(maxWidth: .infinity).frame(height: 56)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(colors.outline, lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Text(label).font(.system(size: 12)).foregroundColor(colors.onSurfaceVariant)
                .padding(.horizontal, 4).background(colors.surface).padding(.leading, 12).offset(y: -7)
                .accessibilityHidden(true)
        }
        .accessibilityLabel(label).accessibilityIdentifier(identifier)
        .onChange(of: value) { updated in
            if parsedValue(text) != updated { text = String(updated) }
        }
    }
}

private struct OccurrenceCheckboxStyle: ToggleStyle {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let identifier: String

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if style == .liquidGlass {
            Toggle(isOn: configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
                .tint(colors.primary)
                .accessibilityIdentifier(identifier)
        } else {
            classicCheckbox(configuration: configuration)
        }
    }

    private func classicCheckbox(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 0) {
                MaterialSelectionIndicator(kind: .checkbox, selected: configuration.isOn)
                    .frame(width: 48, height: 48)
                configuration.label.font(.system(size: 16)).foregroundColor(colors.onSurface).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(identifier)
        .accessibilityValue(configuration.isOn ? "1" : "0")
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
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
