// ImportSheet.swift — ← ui/screen/imports/ImportSheet.kt (904 行)
// 导入课表弹窗: 教务直连 / 从文本导入(折叠) / 从文件导入 + 支持格式说明 +
// 预览对话框(三模式按钮) + 确认对话框(表名/开始日期/节次编辑器)。
//
// 平台映射: OpenDocument → fileImporter;Activity recreate → LocaleHelper 无关此处。

import SwiftUI
import UniformTypeIdentifiers

// --- shared types(← private enum/data class, sheet 自包含) ---

enum ImportApplyMode {
    case replaceCurrent
    case importAsNew
    case appendNonConflict
}

struct CourseConflict {
    let incoming: CourseEntity
    let existing: CourseEntity
}

struct ImportPreview {
    let targetTableId: Int64
    let targetTableName: String
    let parseResult: ScheduleParser.ParseResult
    let existingCourses: [CourseEntity]
    let conflicts: [CourseConflict]

    var incomingCount: Int { parseResult.courses.count }
    var conflictCount: Int { conflicts.count }
    var cleanCount: Int { incomingCount - conflictCount }
}

// 外部打开 json → 主壳 pendingImportText(← MainActivity companion, iOS 为全局)
enum PendingImportText {
    static var value: String? = nil
}

struct ImportSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScheduleViewModel
    let onJwImportRequested: () -> Void
    let onDismiss: () -> Void
    var onImported: () -> Void = {}
    var onOpenEditTable: (Int64) -> Void = { _ in }

    @State private var textExpanded = false
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    @State private var preview: ImportPreview? = nil
    @State private var pendingMode: ImportApplyMode? = nil
    @State private var confirmedTableName = ""
    @State private var confirmedStartDate = ""
    @State private var confirmedTimeJson = ""
    @State private var showFilePicker = false
    @State private var consumedPending = false

    var body: some View {
        let state = viewModel.state
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 标题
                Text(L10n.format("import_title"))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                    .padding(.bottom, 4)
                Text(L10n.format("import_preview_sub"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.bottom, 16)

                // 行 1: 教务直连
                ImportMethodRow(icon: "qrcode", label: L10n.format("import_jw")) {
                    onDismiss()
                    onJwImportRequested()
                }

                // 行 2: 从文本导入(可折叠)
                ImportMethodRow(icon: "doc.text",
                                label: L10n.format("import_paste"),
                                trailing: textExpanded ? "chevron.up" : "chevron.down") {
                    withAnimation { textExpanded.toggle() }
                }
                if textExpanded {
                    VStack(spacing: 8) {
                        TextField(L10n.format("import_paste_hint"), text: $inputText, axis: .vertical)
                            .lineLimit(4...8)
                            .padding(12)
                            .frame(height: 160, alignment: .topLeading)
                            .background(colors.surfaceContainer)
                            .cornerRadius(SleepyTheme.fieldShape)
                            .overlay(
                                RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                                    .strokeBorder(colors.outline.opacity(SleepyTheme.Alpha.hairline), lineWidth: 1)
                            )
                        Button {
                            isLoading = true
                            let p = ImportSheet.buildImportPreview(inputText, state) { msg in errorMsg = msg }
                            if p != nil { preview = p }
                            isLoading = false
                        } label: {
                            Text(isLoading ? L10n.format("import_parsing") : L10n.format("import_preview"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.onPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(colors.primary)
                                .cornerRadius(SleepyShapes.large)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading || inputText.isEmpty)
                    }
                    .padding(.leading, 56)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .padding(.trailing, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 行 3: 从文件导入
                ImportMethodRow(icon: "square.and.arrow.up", label: L10n.format("import_file")) {
                    showFilePicker = true
                }

                Spacer().frame(height: 20)

                // 支持的导入类型
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.format("import_supported_formats"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                        .padding(.bottom, 8)
                    FormatRow(name: L10n.format("format_wakeup_share"), desc: L10n.format("format_wakeup_desc"))
                    FormatRow(name: L10n.format("format_wakeup_json"), desc: L10n.format("format_json_desc"))
                    FormatRow(name: L10n.format("format_ics"), desc: L10n.format("format_ics_desc"))
                    FormatRow(name: L10n.format("format_csv"), desc: L10n.format("format_csv_desc"))
                    FormatRow(name: L10n.format("format_html"), desc: L10n.format("format_html_desc"))
                    FormatRow(name: L10n.format("format_plain"), desc: L10n.format("format_plain_desc"))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.surfaceContainer)
                .cornerRadius(SleepyShapes.large)

                Spacer().frame(height: 24)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .background(colors.surface)
        // 外部打开 json: pendingImportText 自动触发 paste 路径(一次性消费)
        .onAppear {
            guard !consumedPending else { return }
            consumedPending = true
            if let text = PendingImportText.value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PendingImportText.value = nil
                isLoading = true
                let p = ImportSheet.buildImportPreview(text, state) { msg in errorMsg = msg }
                if p != nil { preview = p }
                isLoading = false
            }
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.json, .plainText, .text, .html, .data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                isLoading = true
                do {
                    let secured = url.startAccessingSecurityScopedResource()
                    defer { if secured { url.stopAccessingSecurityScopedResource() } }
                    let text = try String(contentsOf: url, encoding: .utf8)
                    // 不要在这里 onDismiss() —— preview state 随 sheet 销毁, dialog 永远不弹
                    preview = ImportSheet.buildImportPreview(text, state) { msg in errorMsg = msg }
                } catch {
                    errorMsg = L10n.format("read_failed", error.localizedDescription)
                }
                isLoading = false
            case .failure(let e):
                errorMsg = L10n.format("read_failed", e.localizedDescription)
            }
        }
        // 错误反馈通道(← SnackbarHost)
        .alert(L10n.format("import_title"), isPresented: Binding(
            get: { errorMsg != nil },
            set: { if !$0 { errorMsg = nil } }
        )) {
            Button(L10n.format("ok"), role: .cancel) {}
        } message: {
            Text(errorMsg ?? "")
        }
        // 预览对话框
        .sheet(item: Binding(
            get: { preview.map { PreviewBox(preview: $0) } },
            set: { if $0 == nil { preview = nil } }
        )) { box in
            ImportPreviewDialog(preview: box.preview,
                                onDismiss: { preview = nil }) { mode in
                let existingTable = state.currentTable
                confirmedStartDate = preview!.parseResult.startDate.isEmpty
                    ? (existingTable?.startDate ?? Self.todayISO())
                    : preview!.parseResult.startDate
                confirmedTableName = preview!.parseResult.tableName.isEmpty
                    ? (existingTable?.name ?? L10n.format("default_table_name"))
                    : preview!.parseResult.tableName
                confirmedTimeJson = existingTable?.timeJson ?? TimeTableUtils.DEFAULT_TIME_JSON
                pendingMode = mode
            }
            .presentationDetents([.large])
        }
        // 确认对话框
        .sheet(isPresented: Binding(
            get: { preview != nil && pendingMode != nil },
            set: { if !$0 { pendingMode = nil } }
        )) {
            ImportConfirmDialog(
                startDate: confirmedStartDate,
                tableName: confirmedTableName,
                timeJson: confirmedTimeJson,
                onTableNameChange: { confirmedTableName = $0 },
                onStartDateChange: { confirmedStartDate = $0 },
                onTimeJsonChange: { confirmedTimeJson = $0 },
                onDismiss: { pendingMode = nil },
                onConfirm: {
                    guard let mode = pendingMode, let currentPreview = preview else { return }
                    isLoading = true
                    let resultTableId = ImportSheet.applyImportPreview(
                        preview: currentPreview, mode: mode,
                        confirmedStartDate: confirmedStartDate,
                        confirmedTableName: confirmedTableName,
                        confirmedTimeJson: confirmedTimeJson,
                        onImported: onImported) { msg in errorMsg = msg }
                    preview = nil
                    pendingMode = nil
                    isLoading = false
                    if let tid = resultTableId {
                        onOpenEditTable(tid)
                    }
                })
                .presentationDetents([.large])
        }
    }

    private static func todayISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}

// Identifiable 包装(sheet(item:) 需要)
private struct PreviewBox: Identifiable {
    let id = UUID()
    let preview: ImportPreview
}

// ← ImportMethodRow
private struct ImportMethodRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let icon: String
    let label: String
    var trailing: String? = nil
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 40, height: 40)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.medium)
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.onSurface)
                Spacer()
                if let trailing = trailing {
                    Image(systemName: trailing)
                        .foregroundColor(colors.onSurfaceVariant)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
    }
}

// ← FormatRow
private struct FormatRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let name: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: 12))
                .foregroundColor(colors.primary)
                .padding(.top, 2)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.onSurface)
                .frame(width: 110, alignment: .leading)
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(colors.onSurfaceVariant)
        }
        .padding(.vertical, 3)
    }
}

// ← ImportPreviewDialog
private struct ImportPreviewDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let preview: ImportPreview
    let onDismiss: () -> Void
    let onApply: (ImportApplyMode) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.format("import_preview_title"))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(colors.onSurface)
                    if preview.targetTableId == 0 {
                        Text(L10n.format("import_new_table_hint"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.primary)
                    } else {
                        Text(L10n.format("import_target_table", preview.targetTableName))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                }

                HStack(spacing: 8) {
                    PreviewMetricCard(label: L10n.format("import_courses"),
                                      value: "\(preview.incomingCount)",
                                      bg: colors.primaryContainer, fg: colors.onPrimaryContainer)
                    if preview.targetTableId != 0 {
                        PreviewMetricCard(label: L10n.format("import_conflicts"),
                                          value: "\(preview.conflictCount)",
                                          bg: preview.conflictCount > 0 ? colors.errorContainer : colors.secondaryContainer,
                                          fg: preview.conflictCount > 0 ? colors.onErrorContainer : colors.onSecondaryContainer)
                        PreviewMetricCard(label: L10n.format("import_appendable"),
                                          value: "\(preview.cleanCount)",
                                          bg: colors.tertiaryContainer, fg: colors.onTertiaryContainer)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    PreviewInfoRow(label: L10n.format("import_table_name"), value: preview.parseResult.tableName)
                    PreviewInfoRow(label: L10n.format("import_start_date"), value: preview.parseResult.startDate)
                    if preview.targetTableId != 0 {
                        PreviewInfoRow(label: L10n.format("import_suggestion"),
                                       value: preview.conflictCount == 0
                                           ? L10n.format("import_no_conflict")
                                           : L10n.format("import_conflict_count", preview.conflictCount))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(colors.surfaceContainer)
                .cornerRadius(SleepyShapes.large)

                if !preview.conflicts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.format("import_conflicts"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onSurface)
                        ForEach(preview.conflicts.prefix(3)) { conflict in
                            Text("• \(conflict.incoming.courseName) ↔ \(conflict.existing.courseName)（\(DateUtils.localizedDay(conflict.incoming.day)) \(conflict.incoming.nodeString(isShort: true))）")
                                .font(.system(size: 12))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        if preview.conflicts.count > 3 {
                            Text(L10n.format("import_conflict_more", preview.conflicts.count - 3))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surfaceContainer)
                    .cornerRadius(SleepyShapes.large)
                }

                // 按钮组
                VStack(spacing: 8) {
                    if preview.targetTableId == 0 {
                        // 没有任何课表时只允许"作为新课表导入"
                        PrimaryDialogButton(L10n.format("import_as_new")) {
                            onApply(.importAsNew)
                        }
                    } else {
                        HStack(spacing: 8) {
                            PrimaryDialogButton(L10n.format("import_append_only")) {
                                onApply(.appendNonConflict)
                            }
                            PrimaryDialogButton(L10n.format("import_as_new")) {
                                onApply(.importAsNew)
                            }
                        }
                        Button {
                            onApply(.replaceCurrent)
                        } label: {
                            Text(L10n.format("import_overwrite"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.error)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .overlay(
                                    RoundedRectangle(cornerRadius: SleepyShapes.medium)
                                        .strokeBorder(colors.error, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Button(action: onDismiss) {
                        Text(L10n.format("cancel"))
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .background(colors.surface)
    }
}

extension CourseConflict: Identifiable {
    var id: String { "\(incoming.id)-\(existing.id)" }
}

private struct PrimaryDialogButton: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let action: () -> Void

    init(_ title: String, _ action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.onPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(colors.primary)
                .cornerRadius(SleepyShapes.medium)
        }
        .buttonStyle(.plain)
    }
}

// ← PreviewMetricCard
private struct PreviewMetricCard: View {
    let label: String
    let value: String
    let bg: Color
    let fg: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(fg)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bg)
        .cornerRadius(SleepyShapes.large)
    }
}

// ← PreviewInfoRow
private struct PreviewInfoRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(colors.onSurfaceVariant)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurface)
        }
    }
}

// ← ImportConfirmDialog
private struct ImportConfirmDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    @State var startDate: String
    @State var tableName: String
    @State var timeJson: String
    let onTableNameChange: (String) -> Void
    let onStartDateChange: (String) -> Void
    let onTimeJsonChange: (String) -> Void
    let onDismiss: () -> Void
    let onConfirm: () -> Void

    @State private var rows: [TimeTableUtils.TimeSlotRow] = []
    @State private var rowsLoaded = false
    @State private var localError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.format("import_confirm_title"))
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(colors.onSurface)
                Text(L10n.format("import_confirm_body"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)

                TextField(L10n.format("import_table_name"), text: $tableName)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainer)
                    .cornerRadius(SleepyTheme.fieldShape)
                    .onChange(of: tableName) { onTableNameChange($0) }

                DatePickerField(value: startDate, onValueChange: { newValue in
                    startDate = newValue
                    onStartDateChange(newValue)
                }, label: L10n.format("import_week_start"), isError: localError != nil)

                if let localError = localError {
                    Text(localError)
                        .font(.system(size: 12))
                        .foregroundColor(colors.error)
                }

                TimeSlotEditor(rows: rows, onRowsChange: { newRows in
                    rows = newRows
                    onTimeJsonChange(TimeTableUtils.buildTimeJsonFromRows(newRows))
                })
            }
            .padding(20)
        }
        .background(colors.surface)
        .onAppear {
            guard !rowsLoaded else { return }
            rowsLoaded = true
            rows = TimeTableUtils.parseTimeSlotRows(timeJson)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: onDismiss) {
                    Text(L10n.format("back"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                .buttonStyle(.plain)
                Spacer()
                Button(action: validateAndConfirm) {
                    Text(L10n.format("import_confirm"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(colors.surface)
        }
    }

    // ← confirmButton 内校验链: 空日期/格式/空时间/非法时间
    private func validateAndConfirm() {
        if startDate.trimmingCharacters(in: .whitespaces).isEmpty {
            localError = L10n.format("import_start_date_required")
            return
        }
        let dateRegex = "^\\d{4}-\\d{2}-\\d{2}$"
        if startDate.range(of: dateRegex, options: .regularExpression) == nil {
            localError = L10n.format("start_date_format")
            return
        }
        let emptyRows = rows.filter { $0.start.isEmpty || $0.end.isEmpty }
        if let first = emptyRows.first {
            localError = L10n.format("slot_time_required", first.node)
            return
        }
        let timeRegex = "^\\d{2}:\\d{2}$"
        let invalidRows = rows.filter {
            $0.start.range(of: timeRegex, options: .regularExpression) == nil ||
            $0.end.range(of: timeRegex, options: .regularExpression) == nil ||
            $0.start >= $0.end
        }
        if let first = invalidRows.first {
            localError = L10n.format("slot_time_invalid", first.node)
            return
        }
        localError = nil
        onTimeJsonChange(TimeTableUtils.buildTimeJsonFromRows(rows))
        onConfirm()
    }
}

// ==================== 业务逻辑(buildImportPreview / applyImportPreview / conflict) ====================

extension ImportSheet {

    // ← buildImportPreview
    static func buildImportPreview(
        _ text: String,
        _ state: ScheduleState,
        onError: (String) -> Void
    ) -> ImportPreview? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onError(L10n.format("import_content_empty"))
            return nil
        }
        // selectedTableId 缺失时也能导入 — tableId=0, apply 时按 ImportAsNew 自动建表
        let tableId = state.selectedTableId ?? 0
        let repo = ScheduleRepository(AppDatabase.getShared())
        switch ScheduleParser.parse(text, defaultTableId: tableId) {
        case .success(let parseResult):
            let existingTable = tableId == 0 ? nil : try? repo.getTable(tableId)
            let existingCourses = tableId == 0 ? [] : ((try? repo.getCourses(tableId)) ?? [])
            let conflicts: [CourseConflict] = tableId == 0 ? [] : parseResult.courses.compactMap { incoming in
                existingCourses.first { Self.coursesConflict(incoming, $0) }
                    .map { CourseConflict(incoming: incoming, existing: $0) }
            }
            return ImportPreview(
                targetTableId: tableId,
                targetTableName: existingTable?.name ?? L10n.format("manage_current_table"),
                parseResult: parseResult,
                existingCourses: existingCourses,
                conflicts: conflicts)
        case .failure(let e):
            onError(L10n.format("import_failed", e.localizedDescription))
            return nil
        }
    }

    // ← applyImportPreview: 三模式落地
    @discardableResult
    static func applyImportPreview(
        preview: ImportPreview,
        mode: ImportApplyMode,
        confirmedStartDate: String,
        confirmedTableName: String,
        confirmedTimeJson: String,
        onImported: () -> Void,
        onError: (String) -> Void
    ) -> Int64? {
        let repo = ScheduleRepository(AppDatabase.getShared())
        switch mode {
        case .replaceCurrent:
            if let existing = try? repo.getTable(preview.targetTableId) {
                var copy = existing
                copy.name = confirmedTableName.trimmingCharacters(in: .whitespaces).isEmpty
                    ? preview.parseResult.tableName
                    : confirmedTableName.trimmingCharacters(in: .whitespaces)
                copy.startDate = confirmedStartDate
                copy.timeJson = confirmedTimeJson
                try? repo.updateTable(copy)
            }
            try? repo.replaceCourses(preview.targetTableId, preview.parseResult.courses)
            onImported()
            return preview.targetTableId
        case .importAsNew:
            let base = try? repo.getTable(preview.targetTableId)
            let existingNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
            var newTable = TimeTableEntity(
                name: uniqueImportedTableName(confirmedTableName, existingNames),
                startDate: confirmedStartDate,
                maxWeek: base?.maxWeek ?? 20,
                nodesPerDay: base?.nodesPerDay ?? 12,
                timeJson: confirmedTimeJson,
                isDefault: false)
            newTable.color = base?.color ?? "#FF6750A4"
            let newTableId = (try? repo.insertTable(newTable)) ?? 0
            var courses = preview.parseResult.courses
            for i in courses.indices {
                courses[i].id = 0
                courses[i].tableId = newTableId
            }
            _ = try? repo.insertCourses(courses)
            try? repo.setDefault(newTableId)
            onImported()
            return newTableId
        case .appendNonConflict:
            let cleanCourses = preview.parseResult.courses.filter { incoming in
                !preview.existingCourses.contains { Self.coursesConflict(incoming, $0) }
            }
            if cleanCourses.isEmpty {
                onError(L10n.format("import_all_conflict"))
                return nil
            }
            var courses = cleanCourses
            for i in courses.indices {
                courses[i].id = 0
                courses[i].tableId = preview.targetTableId
            }
            _ = try? repo.insertCourses(courses)
            onImported()
            return preview.targetTableId
        }
    }

    // ← coursesConflict: 同日 + 周次区间重叠 + 节次区间重叠
    static func coursesConflict(_ a: CourseEntity, _ b: CourseEntity) -> Bool {
        if a.day != b.day { return false }
        if a.endWeek < b.startWeek || b.endWeek < a.startWeek { return false }
        let aStart = a.startNode
        let aEnd = a.startNode + a.step - 1
        let bStart = b.startNode
        let bEnd = b.startNode + b.step - 1
        return aStart <= bEnd && bStart <= aEnd
    }

    // ← uniqueImportedTableName
    static func uniqueImportedTableName(_ base: String, _ existingNames: [String]) -> String {
        let def = L10n.format("default_table_name")
        let effective = base.isEmpty ? def : base
        if !existingNames.contains(effective) {
            return effective.isEmpty ? "\(def)1" : effective
        }
        var index = 2
        while existingNames.contains("\(effective)\(index)") ||
              existingNames.contains("\(effective)(\(index))") {
            index += 1
        }
        return "\(effective)\(index)"
    }
}

// Optional.map 语义链(嵌套 optional 展平用)
extension Optional {
    func `let`<R>(_ transform: (Wrapped) -> R) -> R? {
        map(transform) ?? nil
    }
}
