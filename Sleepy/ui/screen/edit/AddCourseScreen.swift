// AddCourseScreen.swift — ← ui/screen/edit/AddCourseScreen.kt (1229 行)
// 新建/编辑课程: 基本信息(名/师/室/注/颜色)+周次范围+多时段 block(按节次/按时间双模式+
// 星期多选)+校验(空名/天数/正数/时间格式/时段重叠)+保存(编辑=组替换,新建=共享 groupId)+
// 删除组。HSV 调色盘(SV 面板+色相条)。

import SwiftUI

enum MeetingInputMode: Hashable { case byNode, byClock }

// ← MeetingBlockDraft(SnapshotStateList → @Published 手动管理)
struct MeetingBlockDraft: Identifiable {
    let id: Int
    var days: Set<Int>
    var mode: MeetingInputMode
    var startNode: Int
    var step: Int
    var startTime: String
    var endTime: String
}

struct ValidationIssue {
    let blockId: Int?
    let message: String
}

struct AddCourseScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    let onBack: () -> Void
    let onSaved: () -> Void
    var editingCourse: CourseEntity? = nil

    @State private var loadedForId: Int64 = -1
    @State private var courseName = ""
    @State private var teacher = ""
    @State private var room = ""
    @State private var note = ""
    @State private var courseColor = ""
    @State private var startWeek = 1
    @State private var endWeek = 16
    @State private var nextBlockId = 2
    @State private var validationIssues: [ValidationIssue] = []
    @State private var showColorPicker = false
    @State private var meetingBlocks: [MeetingBlockDraft] = []
    @State private var showDeleteConfirm = false
    @State private var groupLoaded = false

    private var canSave: Bool { !courseName.trimmingCharacters(in: .whitespaces).isEmpty && !meetingBlocks.isEmpty }

    var body: some View {
        let state = viewModel.state
        let currentTable = state.currentTable

        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format(editingCourse != nil ? "edit_course" : "create_course"),
                           onBack: onBack)
            ScrollView {
                VStack(spacing: 14) {
                    Spacer().frame(height: 2)

                    if !validationIssues.isEmpty {
                        ValidationCard(issues: validationIssues)
                    }

                    basicInfoCard
                    weekRangeCard

                    // 上课时段标题
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.format("meeting_slots"))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(colors.onSurface)
                        Text(L10n.format("meeting_slots_sub"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(meetingBlocks.enumerated()), id: \.element.id) { index, _ in
                        MeetingBlockEditor(
                            title: L10n.format("slot_n", index + 1),
                            block: bindingForBlock(at: index),
                            canRemove: meetingBlocks.count > 1,
                            issues: validationIssues.filter { $0.blockId == meetingBlocks[index].id }.map { $0.message },
                            onRemove: { meetingBlocks.remove(at: index) })
                    }

                    // 新增时段按钮
                    Button {
                        meetingBlocks.append(MeetingBlockDraft(
                            id: nextBlockId, days: [2], mode: .byNode,
                            startNode: 3, step: 2, startTime: "10:00", endTime: "11:40"))
                        nextBlockId += 1
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text(L10n.format("add_slot"))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSecondaryContainer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(colors.secondaryContainer)
                        .cornerRadius(SleepyShapes.large)
                    }
                    .buttonStyle(.plain)

                    // 保存
                    Button(action: { save(state: state) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                            Text(L10n.format(editingCourse != nil ? "save_course" : "create_course_btn"))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(colors.primary)
                        .cornerRadius(SleepyShapes.large)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)

                    // 删除(编辑模式)
                    if editingCourse != nil {
                        Button(action: { showDeleteConfirm = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                Text(L10n.format("delete_course"))
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onErrorContainer)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(colors.errorContainer)
                            .cornerRadius(SleepyShapes.large)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer().frame(height: 32)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(colors.background)
        .onAppear { loadIfNeeded(state: state) }
        .sheet(isPresented: $showColorPicker) {
            ColorPickerDialog(initialHex: courseColor) { hex in
                courseColor = hex
                showColorPicker = false
            } onCancel: {
                showColorPicker = false
            }
            .presentationDetents([.height(420)])
        }
        .alert(L10n.format("confirm_delete"), isPresented: $showDeleteConfirm) {
            Button(L10n.format("delete"), role: .destructive) {
                showDeleteConfirm = false
                if let eg = editingCourse, let tid = state.selectedTableId {
                    try? ScheduleRepository(AppDatabase.getShared()).deleteCourseGroup(tid, eg.groupId)
                }
                onSaved()
            }
            Button(L10n.format("cancel"), role: .cancel) {}
        } message: {
            Text(L10n.format("delete_course_confirm", editingCourse?.courseName ?? ""))
        }
    }

    // ← 基本信息
    private var basicInfoCard: some View {
        CardSection(title: L10n.format("course_basic_info"),
                    subtitle: L10n.format("course_basic_info_sub")) {
            VStack(spacing: 12) {
                FieldTextField(text: $courseName, label: L10n.format("course_name_required"))
                FieldTextField(text: $teacher, label: L10n.format("course_teacher"))
                FieldTextField(text: $room, label: L10n.format("course_room"))
                TextField(L10n.format("course_note"), text: $note, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerLowest)
                    .cornerRadius(SleepyTheme.fieldShape)
                    .overlay(
                        RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                            .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.hairline), lineWidth: 1)
                    )
                // 颜色选择器
                HStack(spacing: 10) {
                    Text(L10n.format("course_color"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurfaceVariant)
                    AutoColorDot(selected: courseColor.isEmpty) { courseColor = "" }
                    CustomColorDot(hex: courseColor.isEmpty ? nil : courseColor) {
                        showColorPicker = true
                    }
                    if !courseColor.isEmpty {
                        Text(courseColor)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }
            }
        }
    }

    // ← 周次范围
    private var weekRangeCard: some View {
        CardSection(title: L10n.format("week_range"),
                    subtitle: L10n.format("week_range_sub")) {
            HStack(spacing: 12) {
                NumberStepperField(label: L10n.format("start_week"), value: $startWeek, minV: 1, maxV: 30)
                NumberStepperField(label: L10n.format("end_week"), value: $endWeek, minV: 1, maxV: 30)
            }
        }
    }

    private func bindingForBlock(at index: Int) -> Binding<MeetingBlockDraft> {
        Binding(
            get: { meetingBlocks[index] },
            set: { meetingBlocks[index] = $0 })
    }

    // ← remember(editingCourse?.id) 初始状态 + 编辑模式查同 groupId 回填多 block
    private func loadIfNeeded(state: ScheduleState) {
        let key = editingCourse?.id ?? 0
        guard loadedForId != key else { return }
        loadedForId = key
        groupLoaded = false
        courseName = editingCourse?.courseName ?? ""
        teacher = editingCourse?.teacher ?? ""
        room = editingCourse?.room ?? ""
        note = editingCourse?.note ?? ""
        let c = editingCourse?.color ?? ""
        courseColor = (c.isEmpty || c == "#FF6750A4") ? "" : c
        startWeek = editingCourse?.startWeek ?? 1
        endWeek = editingCourse?.endWeek ?? 16
        nextBlockId = 2
        validationIssues = []
        meetingBlocks = [Self.initialMeetingBlock(editingCourse)]

        // LaunchedEffect(editingCourse?.groupId): 查同 groupId 分组回填
        if let eg = editingCourse, !eg.groupId.isEmpty, let tid = state.selectedTableId {
            let repo = ScheduleRepository(AppDatabase.getShared())
            if let groupCourses = try? repo.getGroupCourses(tid, eg.groupId), !groupCourses.isEmpty {
                // 按 (ownTime, startNode, step) 分组
                let slots = Dictionary(grouping: groupCourses) { "\($0.ownTime)-\($0.startNode)-\($0.step)" }
                var blocks: [MeetingBlockDraft] = []
                var bid = 1
                for (_, courses) in slots {
                    let first = courses[0]
                    blocks.append(MeetingBlockDraft(
                        id: bid,
                        days: Set(courses.map { $0.day }),
                        mode: first.ownTime ? .byClock : .byNode,
                        startNode: first.startNode,
                        step: first.step,
                        startTime: first.startTime.isEmpty ? "08:00" : first.startTime,
                        endTime: first.endTime.isEmpty ? "09:40" : first.endTime))
                    bid += 1
                }
                meetingBlocks = blocks
            }
        }
        groupLoaded = true
    }

    // ← 保存: 校验 → drafts → 编辑组替换 / 新建共享 groupId
    private func save(state: ScheduleState) {
        let issues = Self.validateCourseDraft(courseName: courseName, blocks: meetingBlocks,
                                              startWeek: startWeek, endWeek: endWeek,
                                              table: state.currentTable)
        validationIssues = issues
        guard issues.isEmpty else { return }

        let normalizedStartWeek = min(startWeek, endWeek)
        let normalizedEndWeek = max(startWeek, endWeek)
        let draftTableId = state.selectedTableId ?? 0
        let drafts = meetingBlocks.flatMap { block in
            block.days.sorted().map { day in
                Self.buildCourseEntity(
                    tableId: draftTableId, groupId: "",
                    courseName: courseName.trimmingCharacters(in: .whitespaces),
                    teacher: teacher.trimmingCharacters(in: .whitespaces),
                    room: room.trimmingCharacters(in: .whitespaces),
                    note: note.trimmingCharacters(in: .whitespaces),
                    day: day, block: block,
                    startWeek: normalizedStartWeek, endWeek: normalizedEndWeek,
                    courseColor: courseColor.isEmpty ? "#FF6750A4" : courseColor)
            }
        }

        let repo = ScheduleRepository(AppDatabase.getShared())
        // 没表就自动建一张
        let tableId = state.selectedTableId ?? viewModel.createEmptyTable()
        var fixedDrafts = drafts
        for i in fixedDrafts.indices { fixedDrafts[i].tableId = tableId }
        if let eg = editingCourse {
            // 编辑: 删同 groupId 全部记录,插入所有新草稿
            let gid = eg.groupId
            for i in fixedDrafts.indices { fixedDrafts[i].groupId = gid }
            try? repo.updateCourseGroup(tableId, gid, fixedDrafts)
        } else {
            // 新建: 所有草稿共享同一个 groupId
            let gid = UUID().uuidString
            for i in fixedDrafts.indices { fixedDrafts[i].groupId = gid }
            _ = try? repo.insertCourses(fixedDrafts)
        }
        onSaved()
    }

    // ← initialMeetingBlock
    static func initialMeetingBlock(_ course: CourseEntity?) -> MeetingBlockDraft {
        guard let course = course else {
            return MeetingBlockDraft(id: 1, days: [1], mode: .byNode, startNode: 1, step: 2,
                                     startTime: "08:00", endTime: "09:40")
        }
        return MeetingBlockDraft(id: 1, days: [course.day],
                                 mode: course.ownTime ? .byClock : .byNode,
                                 startNode: course.startNode, step: course.step,
                                 startTime: course.startTime.isEmpty ? "08:00" : course.startTime,
                                 endTime: course.endTime.isEmpty ? "09:40" : course.endTime)
    }

    // ← buildCourseEntity
    static func buildCourseEntity(tableId: Int64, groupId: String, courseName: String,
                                  teacher: String, room: String, note: String, day: Int,
                                  block: MeetingBlockDraft, startWeek: Int, endWeek: Int,
                                  courseColor: String = "#FF6750A4") -> CourseEntity {
        let ownTime = block.mode == .byClock
        return CourseEntity(
            groupId: groupId, tableId: tableId, courseName: courseName,
            teacher: teacher, room: room, note: note,
            day: day, startNode: block.startNode, step: block.step,
            startWeek: startWeek, endWeek: endWeek, type: 0,
            color: courseColor.isEmpty ? "#FF6750A4" : courseColor,
            ownTime: ownTime,
            startTime: ownTime ? block.startTime : "",
            endTime: ownTime ? block.endTime : "")
    }

    // ← validateCourseDraft
    static func validateCourseDraft(courseName: String, blocks: [MeetingBlockDraft],
                                    startWeek: Int, endWeek: Int, table: TimeTableEntity?) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if courseName.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(blockId: nil, message: L10n.format("course_name_empty")))
        }
        if startWeek <= 0 || endWeek <= 0 {
            issues.append(ValidationIssue(blockId: nil, message: L10n.format("week_must_be_positive")))
        }
        for (index, block) in blocks.enumerated() {
            if block.days.isEmpty {
                issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_at_least_one_day", index + 1)))
            }
            switch block.mode {
            case .byNode:
                if block.startNode <= 0 {
                    issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_start_node_positive", index + 1)))
                }
                if block.step <= 0 {
                    issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_step_positive", index + 1)))
                }
            case .byClock:
                guard let start = parseHm(block.startTime), let end = parseHm(block.endTime) else {
                    issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_time_format", index + 1)))
                    continue
                }
                if start >= end {
                    issues.append(ValidationIssue(blockId: block.id, message: L10n.format("slot_time_order", index + 1)))
                }
            }
        }
        // 时段重叠检测
        for i in blocks.indices {
            for j in (i + 1)..<blocks.count {
                let first = blocks[i], second = blocks[j]
                let overlapDays = first.days.intersection(second.days)
                if overlapDays.isEmpty { continue }
                guard let firstRange = blockRangeMinutes(first, table),
                      let secondRange = blockRangeMinutes(second, table) else { continue }
                if firstRange.0 < secondRange.1 && secondRange.0 < firstRange.1 {
                    let dayText = overlapDays.sorted().map { DateUtils.localizedDay($0) }.joined(separator: " / ")
                    issues.append(ValidationIssue(blockId: second.id,
                                                  message: L10n.format("slot_time_overlap", i + 1, j + 1, dayText)))
                }
            }
        }
        return issues
    }

    // ← blockRangeMinutes
    static func blockRangeMinutes(_ block: MeetingBlockDraft, _ table: TimeTableEntity?) -> (Int, Int)? {
        switch block.mode {
        case .byClock:
            guard let start = parseHm(block.startTime), let end = parseHm(block.endTime) else { return nil }
            return (start, end)
        case .byNode:
            let timeJson = table?.timeJson ?? TimeTableUtils.DEFAULT_TIME_JSON
            let nodes = parseNodeMinuteMap(timeJson)
            guard let start = nodes[block.startNode]?.0 else { return nil }
            guard let end = nodes[block.startNode + block.step - 1]?.1 else { return nil }
            return (start, end)
        }
    }

    // ← parseNodeMinuteMap
    static func parseNodeMinuteMap(_ timeJson: String) -> [Int: (Int, Int)] {
        guard let data = timeJson.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
        var map: [Int: (Int, Int)] = [:]
        for o in arr {
            guard let node = (o["node"] as? NSNumber)?.intValue,
                  let startS = o["start"] as? String,
                  let endS = o["end"] as? String,
                  let s = parseHm(startS), let e = parseHm(endS) else { continue }
            map[node] = (s, e)
        }
        return map
    }

    // ← parseHm("HH:mm" → 当日分钟数)
    static func parseHm(_ value: String) -> Int? {
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }
}

// ← ValidationCard
private struct ValidationCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let issues: [ValidationIssue]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.format("fix_issues_first"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onErrorContainer)
            ForEach(issues.prefix(4)) { issue in
                Text("• \(issue.message)")
                    .font(.system(size: 12))
                    .foregroundColor(colors.onErrorContainer)
            }
            if issues.count > 4 {
                Text(L10n.format("more_unexpanded", issues.count - 4))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(colors.onErrorContainer)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.errorContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

extension ValidationIssue: Identifiable {
    var id: String { "\(blockId ?? -1)-\(message)" }
}

// ← CardSection(带副标题)
private struct CardSection<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.extraLarge)
    }
}

// ← MeetingBlockEditor
private struct MeetingBlockEditor: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    @Binding var block: MeetingBlockDraft
    let canRemove: Bool
    let issues: [String]
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                    Text(block.days.isEmpty
                         ? L10n.format("select_at_least_one_day")
                         : L10n.format("selected_days",
                                       block.days.sorted().map { DateUtils.localizedDay($0) }.joined(separator: " / ")))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
                if canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
            }

            ModePicker(mode: block.mode) { block.mode = $0 }
            MultiDayPicker(selectedDays: block.days) { day in
                if block.days.contains(day) { block.days.remove(day) } else { block.days.insert(day) }
            }

            switch block.mode {
            case .byNode:
                HStack(spacing: 12) {
                    NumberStepperField(label: L10n.format("start_node"), value: Binding(
                        get: { block.startNode }, set: { block.startNode = $0 }), minV: 1, maxV: 12)
                    NumberStepperField(label: L10n.format("step_count"), value: Binding(
                        get: { block.step }, set: { block.step = $0 }), minV: 1, maxV: 8)
                }
            case .byClock:
                HStack(spacing: 12) {
                    TimePickerField(value: block.startTime, onValueChange: { block.startTime = $0 },
                                    label: L10n.format("start_time"))
                    TimePickerField(value: block.endTime, onValueChange: { block.endTime = $0 },
                                    label: L10n.format("end_time"))
                }
            }

            if !issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues, id: \.self) { issue in
                        Text(issue)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(colors.error)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainerHigh)
        .cornerRadius(SleepyShapes.large)
        .overlay(
            RoundedRectangle(cornerRadius: SleepyShapes.large)
                .strokeBorder(issues.isEmpty ? Color.clear : colors.error, lineWidth: 1.5)
        )
    }
}

// ← ModePicker
private struct ModePicker: View {
    @Environment(\.localWakeUpColors) private var colors
    let mode: MeetingInputMode
    let onChange: (MeetingInputMode) -> Void

    var body: some View {
        let modes: [(MeetingInputMode, String)] = [
            (.byNode, L10n.format("mode_by_node")),
            (.byClock, L10n.format("mode_by_time"))
        ]
        HStack(spacing: 0) {
            ForEach(modes, id: \.0) { m, label in
                let sel = mode == m
                Button {
                    onChange(m)
                } label: {
                    Text(label)
                        .font(.system(size: 14, weight: sel ? .semibold : .medium))
                        .foregroundColor(sel ? colors.onSecondaryContainer : colors.onSurfaceVariant)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            Group {
                                if sel {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colors.secondaryContainer)
                                        .padding(.vertical, 3)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(colors.surfaceContainer)
        .cornerRadius(10)
    }
}

// ← MultiDayPicker(4+3 两行)
private struct MultiDayPicker: View {
    @Environment(\.localWakeUpColors) private var colors
    let selectedDays: Set<Int>
    let onToggleDay: (Int) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach([Array(1...4), Array(5...7)], id: \.self) { row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.self) { day in
                        let selected = selectedDays.contains(day)
                        Button {
                            onToggleDay(day)
                        } label: {
                            Text(DateUtils.localizedDay(day))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(selected ? colors.onPrimary : colors.onSurface)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(selected ? colors.primary : colors.surfaceContainerHighest)
                                .cornerRadius(SleepyShapes.medium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: SleepyShapes.medium)
                                        .strokeBorder(selected ? Color.clear : colors.outlineVariant, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    if row.count < 4 {
                        ForEach(0..<(4 - row.count), id: \.self) { _ in Spacer() }
                    }
                }
            }
        }
    }
}

// ← NumberField(数字输入, 外部值同步 + 空回退 min)
struct NumberStepperField: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    @Binding var value: Int
    var minV: Int
    var maxV: Int

    @State private var text: String = ""

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, text: Binding(
                get: { text.isEmpty ? "\(value)" : text },
                set: { txt in
                    text = txt
                    if txt.isEmpty {
                        value = minV   // 清空时回退最小值
                    } else if let v = Int(txt) {
                        value = Swift.min(Swift.max(v, minV), maxV)
                    }
                }
            ))
            .keyboardType(.numberPad)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(colors.surfaceContainerLowest)
            .cornerRadius(SleepyTheme.fieldShape)
            .overlay(
                RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                    .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.hairline), lineWidth: 1)
            )
        }
        .onAppear { text = "\(value)" }
    }
}

// ── 课程颜色选择器 ──

// ← AutoColorDot
private struct AutoColorDot: View {
    @Environment(\.localWakeUpColors) private var colors
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            ZStack {
                Circle()
                    .fill(colors.surfaceVariant)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle().strokeBorder(selected ? colors.primary : colors.outlineVariant,
                                              lineWidth: selected ? 2.5 : 0.5)
                    )
                Text(L10n.format("label_from"))
                    .font(.system(size: 11))
                    .foregroundColor(colors.onSurfaceVariant)
            }
        }
        .buttonStyle(.plain)
    }
}

// ← CustomColorDot
private struct CustomColorDot: View {
    @Environment(\.localWakeUpColors) private var colors
    let hex: String?
    let onClick: () -> Void

    var body: some View {
        let c = hex.flatMap { CourseColorUtil.parseColor($0).map { Color(uiArgb: UInt32($0)) } }
            ?? colors.surfaceVariant
        Button(action: onClick) {
            ZStack {
                Circle()
                    .fill(c)
                    .frame(width: 32, height: 32)
                    .overlay(Circle().strokeBorder(colors.outlineVariant, lineWidth: 0.5))
                if hex == nil {
                    Text("＋")
                        .font(.system(size: 16))
                        .foregroundColor(colors.onSurfaceVariant)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// ← ColorPickerDialog(HSV: SV 面板 + 色相条)
private struct ColorPickerDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let initialHex: String
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var hue: Double = 269
    @State private var saturation: Double = 0.71
    @State private var value: Double = 0.64
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.format("course_color"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(colors.onSurface)

            SVPanel(hue: $hue, saturation: $saturation, value: $value)
                .frame(height: 200)
                .cornerRadius(SleepyShapes.large)

            HueSlider(hue: $hue)
                .frame(height: 36)
                .cornerRadius(SleepyShapes.large)

            // 预览 + Hex
            HStack(spacing: 12) {
                Circle()
                    .fill(currentUIColor)
                    .frame(width: 40, height: 40)
                    .overlay(Circle().strokeBorder(colors.outlineVariant, lineWidth: 1))
                Text(currentHex)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(colors.onSurfaceVariant)
                Spacer()
                Button(L10n.format("ok")) { onConfirm(currentHex) }
                    .foregroundColor(colors.primary)
                Button(L10n.format("cancel"), action: onCancel)
                    .foregroundColor(colors.onSurfaceVariant)
            }
        }
        .padding(20)
        .background(colors.surface)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            // 解析初始 HSV(Android colorToHSV 等价)
            let argb = initialHex.isEmpty ? 0xFF6750A4 : (CourseColorUtil.parseColor(initialHex) ?? 0xFF6750A4)
            let r = Double((argb >> 16) & 0xFF) / 255
            let g = Double((argb >> 8) & 0xFF) / 255
            let b = Double(argb & 0xFF) / 255
            let hsv = rgbToHsv(r: r, g: g, b: b)
            hue = hsv.0 * 360
            saturation = hsv.1
            value = hsv.2
        }
    }

    private var currentUIColor: Color {
        let rgb = hsvToRgb(h: hue / 360, s: saturation, v: value)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    private var currentHex: String {
        let rgb = hsvToRgb(h: hue / 360, s: saturation, v: value)
        let r = Int(round(rgb.0 * 255)), g = Int(round(rgb.1 * 255)), b = Int(round(rgb.2 * 255))
        return String(format: "#FF%02X%02X%02X", r, g, b)
    }

    private func rgbToHsv(r: Double, g: Double, b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b)
        let delta = mx - mn
        var h: Double = 0
        if delta != 0 {
            if mx == r { h = ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / delta + 2 }
            else { h = (r - g) / delta + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        return (h / 360, mx == 0 ? 0 : delta / mx, mx)
    }

    private func hsvToRgb(h: Double, s: Double, v: Double) -> (Double, Double, Double) {
        let i = Int(h * 6)
        let f = h * 6 - Double(i)
        let p = v * (1 - s)
        let q = v * (1 - f * s)
        let t = v * (1 - (1 - f) * s)
        switch i % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}

// ← SVPanel: 横=饱和度, 纵=明度(上明下暗)
private struct SVPanel: View {
    @Binding var hue: Double
    @Binding var saturation: Double
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 纯色相底
                Rectangle().fill(pureHueColor)
                // 白色横向渐变(左白→右透明)
                LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                // 黑色纵向渐变(上透明→下黑)
                LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                // 指示器
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 2))
                    .position(x: saturation * geo.size.width,
                              y: (1 - value) * geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        saturation = min(max(g.location.x / geo.size.width, 0), 1)
                        value = min(max(1 - g.location.y / geo.size.height, 0), 1)
                    }
            )
        }
    }

    private var pureHueColor: Color {
        let h = hue / 360
        let i = Int(h * 6)
        let f = h * 6 - Double(i)
        let q = 1 - f
        switch i % 6 {
        case 0: return Color(red: 1, green: f, blue: 0)
        case 1: return Color(red: q, green: 1, blue: 0)
        case 2: return Color(red: 0, green: 1, blue: f)
        case 3: return Color(red: 0, green: q, blue: 1)
        case 4: return Color(red: f, green: 0, blue: 1)
        default: return Color(red: 1, green: 0, blue: q)
        }
    }
}

// ← HueSlider: 360° 彩虹条
private struct HueSlider: View {
    @Binding var hue: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: (0...6).map { rainbowHue(Double($0) / 6) },
                               startPoint: .leading, endPoint: .trailing)
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .overlay(Circle().fill(rainbowHue(hue / 360)).frame(width: 16, height: 16))
                    .position(x: (hue / 360) * geo.size.width, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        hue = min(max(g.location.x / geo.size.width, 0), 1) * 360
                    }
            )
        }
    }

    private func rainbowHue(_ h: Double) -> Color {
        let i = Int(h * 6)
        let f = h * 6 - Double(i)
        let q = 1 - f
        switch i % 6 {
        case 0: return Color(red: 1, green: f, blue: 0)
        case 1: return Color(red: q, green: 1, blue: 0)
        case 2: return Color(red: 0, green: 1, blue: f)
        case 3: return Color(red: 0, green: q, blue: 1)
        case 4: return Color(red: f, green: 0, blue: 1)
        default: return Color(red: 1, green: 0, blue: q)
        }
    }
}
