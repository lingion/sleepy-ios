// ImportSheet.swift — ← ui/screen/imports/ImportSheet.kt (v1.0.61, 1816 行)
// 导入课表弹窗: 教务直连 / 从文本导入(折叠) / 从文件导入 + 支持格式说明 +
// 预览对话框(五模式按钮) + 确认对话框(表名/开始日期/节次编辑器/作息表 Tab) +
// v1.0.56 T9 纯作息导入命名框。
//
// 平台映射: OpenDocument → fileImporter; SnackbarHost → 底部胶囊浮层(← JwImportFlow
// statusMsg 同款); Activity recreate → LocaleHelper 无关此处。

import SwiftUI
import UniformTypeIdentifiers

// --- shared types(← private enum/data class, sheet 自包含) ---

enum ImportApplyMode {
    case replaceCurrent
    case importAsNew
    case appendNonConflict
    /// 当前课表 + 导入数据合并, 创建新课表保存, 用户命名(v7.10.13)
    case appendAsNew
    /// 连冲突课一起追加进当前课表(红标: 会形成同格多层)(v7.10.13)
    case appendAll
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
    /// issue#22: 同 groupId 多地点提示 — 不阻塞导入,只让用户心里有数
    var multiLocationWarnings: [String] = []

    var incomingCount: Int { parseResult.courses.count }
    var conflictCount: Int { conflicts.count }
    var cleanCount: Int { incomingCount - conflictCount }
}

// 外部打开 json → 主壳 pendingImportText(← MainActivity companion, iOS 为全局)
enum PendingImportText {
    static var value: String? = nil
}

/// 格式详情弹窗键(← Android ImportFormat, sheet(item:) 驱动)
enum ImportFormatKey: String, Identifiable, CaseIterable {
    case wakeupShare, wakeupJson, ics, csv, html, plain
    var id: String { rawValue }

    /// L10n key 前缀(wakeupShare → wakeup_share, 其余同 rawValue)
    var l10nKey: String {
        switch self {
        case .wakeupShare: return "wakeup_share"
        case .wakeupJson: return "wakeup_json"
        case .ics, .csv, .html, .plain: return rawValue
        }
    }

    /// 什么时候用(← format_*_when)
    var whenText: String { L10n.format("format_\(l10nKey)_when") }
    /// 识别要求条目(← string-array format_*_spec, 扁平化为 _0.._n)
    var specItems: [String] {
        var items: [String] = []
        var i = 0
        while L10n.has("format_\(l10nKey)_spec_\(i)") {
            items.append(L10n.format("format_\(l10nKey)_spec_\(i)"))
            i += 1
        }
        return items
    }
    /// 示例(← format_*_example)
    var exampleText: String { L10n.format("format_\(l10nKey)_example") }
}

struct ImportSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScheduleViewModel
    let onJwImportRequested: () -> Void
    let onDismiss: () -> Void
    var onImported: () -> Void = {}
    // ← Android ImportSheet(drafts/onRestoreDraft/onDeleteDraft, 默认空 = 零行为变化)
    var drafts: [ImportDraftRowModel] = []
    var onRestoreDraft: (String) -> Void = { _ in }
    var onDeleteDraft: (String) -> Void = { _ in }

    @State private var showDrafts = false
    @State private var textExpanded = false
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    @State private var preview: ImportPreview? = nil
    @State private var pendingMode: ImportApplyMode? = nil
    // ★ sheet 冲突修复配套: 预览快照(确认 sheet 期间 preview 已置 nil)
    @State private var confirmedPreview: ImportPreview? = nil
    @State private var confirmedTableName = ""
    @State private var confirmedStartDate = ""
    @State private var confirmedTimeJson = ""
    // v1.0.56 T6: 第三 Tab「作息表」— 绑定选择; 确认导入时传给 applyImportPreview 落绑定
    @State private var confirmedBindPeriodTableId: Int64? = nil
    // v1.0.56 T9: 纯作息导入 — 解析结果只有作息表没课程时, 走独立确认框(只建作息表)
    @State private var purePeriodName = ""
    // ← Android snackbar.showSnackbar(import_success): 导入成功提示(不再跳编辑页)
    @State private var successMsg: String? = nil
    @State private var showFilePicker = false
    @State private var detailFormat: ImportFormatKey? = nil

    var body: some View {
        let state = viewModel.state
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 标题与草稿入口 (← Android 标题 Row + Inventory2 IconButton)
                HStack {
                    Text(L10n.format("import_title"))
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                    Spacer()
                    Button {
                        showDrafts = true
                    } label: {
                        // 2026-09-16 用户: 书签不像草稿箱 — Android 换带盖收纳箱
                        // Inventory2; iOS 等价 SF Symbol "shippingbox"(带盖收纳箱)
                        Image(systemName: "shippingbox")
                            .font(.system(size: 22))
                            .foregroundColor(colors.onPrimaryContainer)
                            .frame(width: 48, height: 48)   // ← M3 IconButton 48×48
                            .background(Circle().fill(colors.primaryContainer))
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .accessibilityLabel(L10n.format("import_drafts"))
                    .accessibilityIdentifier("import_drafts_btn")
                }
                .padding(.bottom, 4)
                Text(L10n.format("import_preview_sub"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)
                    .padding(.bottom, 16)

                // 行 1: 教务直连
                ImportMethodRow(id: "import_jw", icon: "qrcode", label: L10n.format("import_jw")) {
                    onDismiss()
                    onJwImportRequested()
                }

                // 行 2: 从文本导入(可折叠)
                ImportMethodRow(id: "import_text", icon: "doc.text",
                                label: L10n.format("import_paste"),
                                trailing: textExpanded ? "chevron.up" : "chevron.down") {
                    withAnimation { textExpanded.toggle() }
                }
                if textExpanded {
                    VStack(spacing: 8) {
                        MultilineFieldCompat(placeholder: L10n.format("import_paste_hint"), text: $inputText, minLines: 4, maxLines: 8)
                            .padding(12)
                            .frame(height: 160, alignment: .topLeading)
                            .background(colors.surfaceContainerHighest)   // ← fieldColors 容器色 surfaceContainerHighest
                            .cornerRadius(SleepyTheme.fieldShape)
                            // ← Android filled TextField, 无描边
                            .accessibilityIdentifier("import_paste_input")
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
                                .frame(height: 48)
                                .background(colors.primary)
                                .cornerRadius(SleepyShapes.large)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("import_preview_btn")
                        .disabled(isLoading || inputText.isEmpty)
                    }
                    .padding(.leading, 56)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .padding(.trailing, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // 行 3: 从文件导入
                ImportMethodRow(id: "import_file", icon: "square.and.arrow.up", label: L10n.format("import_file")) {
                    showFilePicker = true
                }

                Spacer().frame(height: 20)

                // 支持的导入类型
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.format("import_supported_formats"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                        .padding(.bottom, 8)
                    FormatRow(name: L10n.format("format_wakeup_share"), desc: L10n.format("format_wakeup_desc")) {
                        detailFormat = .wakeupShare
                    }
                    FormatRow(name: L10n.format("format_wakeup_json"), desc: L10n.format("format_json_desc")) {
                        detailFormat = .wakeupJson
                    }
                    FormatRow(name: L10n.format("format_ics"), desc: L10n.format("format_ics_desc")) {
                        detailFormat = .ics
                    }
                    FormatRow(name: L10n.format("format_csv"), desc: L10n.format("format_csv_desc")) {
                        detailFormat = .csv
                    }
                    FormatRow(name: L10n.format("format_html"), desc: L10n.format("format_html_desc")) {
                        detailFormat = .html
                    }
                    FormatRow(name: L10n.format("format_plain"), desc: L10n.format("format_plain_desc")) {
                        detailFormat = .plain
                    }
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
        // ← Android SnackbarHost + LaunchedEffect(importJustApplied):
        //   导入成功提示(不再跳编辑课表页), 底部胶囊浮层, 复用 JwImportFlow statusMsg 同款
        .overlay(alignment: .bottom) {
            if let msg = successMsg {
                Text(msg)
                    .font(.system(size: 14))   // ← Android Snackbar bodyMedium 14
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    .padding(.bottom, 16)
                    .transition(.opacity)
                    .onAppear {
                        // UI 测试态延到 6s(← ExportScreen/MineScreen 同款): 串行套件
                        // 下确认 sheet dismiss + 快照延迟会错过 2.5s 存活窗口
                        // (2026-10-24 串行 run: tap 确认→首查 snackbar 间隔 3.6s)。
                        let life: Double = ProcessInfo.processInfo.arguments
                            .contains("-SLEEPY_UI_TEST_SEED") ? 6 : 2.5
                        DispatchQueue.main.asyncAfter(deadline: .now() + life) {
                            if successMsg == msg { withAnimation { successMsg = nil } }
                        }
                    }
                    .accessibilityIdentifier("import_success_snackbar")
            }
        }
        // 外部打开 json: pendingImportText 自动触发 paste 路径。
        // ← Android LaunchedEffect(pendingImportText): 以 pendingImportText 为 key,
        //   sheet 存活期间外部再塞 text 会重新触发预览(旧 onAppear+一次性消费会把
        //   sheet 开着时的推送丢掉)。onAppear 兜冷启动首值, onChange 管后续推送。
        .onAppear { consumePendingImportText() }
        .onChange(of: PendingImportText.value) { _ in consumePendingImportText() }
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
        // 错误反馈通道(← Android AlertDialog 统一弹窗, 2026-09-18 用户: 报错必须
        // 统一弹窗不再是 Snackbar 一闪即逝): 标题 jw_error_dialog_title「导入遇到问题」+
        // 单按钮 jw_err_dismiss「知道了」+ 错误文本可滚动(heightIn max 320dp)
        .alert(L10n.format("jw_error_dialog_title"), isPresented: Binding(
            get: { errorMsg != nil },
            set: { if !$0 { errorMsg = nil } }
        )) {
            Button(L10n.format("jw_err_dismiss"), role: .cancel) {}
        } message: {
            Text(errorMsg ?? "")
        }
        // 预览对话框
        .sheet(item: Binding(
            get: { preview.map { PreviewBox(preview: $0) } },
            set: { if $0 == nil { preview = nil } }
        )) { box in
            // v1.0.56 T9: 纯作息导入(只有 P 区块/节次, 零课程) — 不进课程确认框,
            // 弹独立命名框(预填全局唯一名, 用户可改), 确认只建作息表不建空课表。
            if box.preview.parseResult.courses.isEmpty, let pt = box.preview.parseResult.periodTable {
                PurePeriodImportDialog(
                    parsed: pt,
                    suggestUniqueName: { Self.suggestPurePeriodName(for: pt, state: state, viewModel: viewModel) },
                    courseTableNames: state.tables.map { $0.name },
                    periodTableNames: viewModel.loadAllPeriodTables().map { $0.name },
                    onDismiss: { preview = nil },
                    onConfirm: { candidate in
                        isLoading = true
                        ImportSheet.applyPurePeriodImport(name: candidate, parsed: pt,
                                                          onImported: onImported) { msg in errorMsg = msg }
                        preview = nil
                        isLoading = false
                        // ← Android importJustApplied=true → snackbar 明示已落库
                        showSuccess(L10n.format("import_success"))
                    })
            } else {
            ImportPreviewDialog(preview: box.preview,
                                onDismiss: { preview = nil }) { mode in
                let existingTable = state.currentTable
                confirmedStartDate = preview!.parseResult.startDate.isEmpty
                    ? (existingTable?.startDate ?? Self.todayISO())
                    : preview!.parseResult.startDate
                confirmedTableName = preview!.parseResult.tableName.isEmpty
                    ? (existingTable?.name ?? L10n.format("default_table_name"))
                    : preview!.parseResult.tableName
                // v7.10.16k 无损合并(用户 2026-09-03「哪个大用哪个, 最完整优先」):
                // 不再 ifBlank 单选 — 老表作息与导入作息逐节合并, 节次数取双方最大,
                // 并拓到导入课程实际到达的最大节。导入源 13 节绝不被老表 10 节压小。
                confirmedTimeJson = TimeTableUtils.mergeMostComplete(
                    currentJson: existingTable?.timeJson ?? "",
                    incomingJson: preview!.parseResult.timeJson,
                    requiredNodeCount: preview!.parseResult.nodesPerDay)
                // ★ iOS 16 sheet 冲突修复: 先关预览 sheet 再开确认 sheet —
                //   同一宿主上确认 sheet 会因预览未 dismiss 被丢弃。快照 preview
                //   进 confirmedPreview 持有, 延迟到预览 dismiss 完成后再置模式。
                // v7.10.13 追加模式: 追加到已存在的课表, 命名由目标课表自带, 不需要再问用户 —
                // 直接走 applyImportPreview, 跳过 ImportConfirmDialog(← Android LaunchedEffect)。
                if mode == .appendNonConflict || mode == .appendAll {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        guard let p = preview else { return }
                        isLoading = true
                        _ = ImportSheet.applyImportPreview(
                            preview: p, mode: mode,
                            confirmedStartDateRaw: p.parseResult.startDate.isEmpty
                                ? (state.currentTable?.startDate ?? Self.todayISO())
                                : p.parseResult.startDate,
                            confirmedTableName: state.currentTable?.name ?? "",
                            confirmedTimeJson: TimeTableUtils.mergeMostComplete(
                                currentJson: state.currentTable?.timeJson ?? "",
                                incomingJson: p.parseResult.timeJson,
                                requiredNodeCount: p.parseResult.nodesPerDay),
                            onImported: onImported) { msg in errorMsg = msg }
                        preview = nil
                        pendingMode = nil
                        isLoading = false
                        // ← Android: 导入成功不再跳编辑课表页(假保存闸), snackbar 明示已落库
                        showSuccess(L10n.format("import_success"))
                    }
                    return
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    confirmedPreview = preview
                    pendingMode = mode
                    preview = nil
                }
            }
            .sheetDetents([.large])
            }
        }
        // 确认对话框(pendingMode 驱动; preview 已快照进 confirmedPreview)
        .sheet(isPresented: Binding(
            get: { pendingMode != nil },
            set: { if !$0 { pendingMode = nil } }
        )) {
            ImportConfirmDialog(
                startDate: confirmedStartDate,
                tableName: confirmedTableName,
                timeJson: confirmedTimeJson,
                // 仅"创建新课表"或"追加为新课表"需要命名; 覆盖课表不强制重命名
                showTableName: pendingMode == .importAsNew || pendingMode == .appendAsNew,
                onTableNameChange: { confirmedTableName = $0 },
                onStartDateChange: { confirmedStartDate = $0 },
                onTimeJsonChange: { confirmedTimeJson = $0 },
                onDismiss: { pendingMode = nil },
                // v1.0.56 T6: 第三 Tab「作息表」
                periodTableOptions: viewModel.loadAllPeriodTables().map {
                    PeriodTableOption(id: $0.id, name: $0.name, nodesPerDay: $0.nodesPerDay)
                },
                selectedPeriodTableId: confirmedBindPeriodTableId,
                onSelectPeriodTable: { confirmedBindPeriodTableId = $0 },
                periodTableTimeJsonById: Dictionary(
                    uniqueKeysWithValues: viewModel.loadAllPeriodTables().map { ($0.id, $0.timeJson) }),
                onConfirm: {
                    guard let mode = pendingMode, let currentPreview = confirmedPreview else { return }
                    isLoading = true
                    // 「确认导入」= 唯一写库点, 点下即落库。之后不再跳编辑课表页 —
                    // 那个页面有「保存」按钮, 会造成"没点保存数据也在"的假保存闸误导
                    // (Android v1.0.56 已删跳转, 改 snackbar 明示 import_success)。
                    _ = ImportSheet.applyImportPreview(
                        preview: currentPreview, mode: mode,
                        confirmedStartDateRaw: confirmedStartDate,
                        confirmedTableName: confirmedTableName,
                        confirmedTimeJson: confirmedTimeJson,
                        onImported: onImported,
                        onError: { msg in errorMsg = msg },
                        bindPeriodTableId: confirmedBindPeriodTableId)
                    confirmedPreview = nil
                    preview = nil
                    pendingMode = nil
                    isLoading = false
                    showSuccess(L10n.format("import_success"))
                })
                .sheetDetents([.large])
        }
        // 草稿箱弹窗 (← Android if (showDrafts) ImportDraftSheet(...))
        .sheet(isPresented: $showDrafts) {
            ImportDraftSheet(
                drafts: drafts,
                onDismiss: { showDrafts = false },
                onRestore: { id in
                    showDrafts = false
                    onRestoreDraft(id)
                },
                onDelete: onDeleteDraft)
        }
        // 格式详情弹窗 ("支持格式"每行 ⓘ 点开)
        .sheet(item: $detailFormat) { fmt in
            FormatDetailDialog(format: fmt)
        }
    }

    private static func todayISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// 外部 app 塞来的 json → 自动触发 paste 路径 buildImportPreview。
    /// 一次性消费: 读完即清空全局字段(← Android LaunchedEffect 引用为 key 的语义)。
    private func consumePendingImportText() {
        let state = viewModel.state
        if let text = PendingImportText.value,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            PendingImportText.value = nil
            isLoading = true
            let p = ImportSheet.buildImportPreview(text, state) { msg in errorMsg = msg }
            if p != nil { preview = p }
            isLoading = false
        }
    }

    /// 成功提示(← snackbar.showSnackbar(importSuccessMessage)), 2.5s 自动消失由 overlay onAppear 管。
    /// onImported 由 applyImportPreview / applyPurePeriodImport 内部调用(← Android 同位)。
    private func showSuccess(_ msg: String) {
        withAnimation { successMsg = msg }
    }

    /// ← Android LaunchedEffect 预填: 源名参与全局唯一名顺延(课程表∪作息表)
    static func suggestPurePeriodName(
        for pt: ScheduleParser.ParsedPeriodTable,
        state: ScheduleState,
        viewModel: ScheduleViewModel
    ) -> String {
        let courseNames = state.tables.map { $0.name }
        let periodNames = viewModel.loadAllPeriodTables().map { $0.name }
        return TimeTableUtils.suggestUniqueName(
            pt.name, courseTableNames: courseNames, periodTableNames: periodNames)
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
    let id: String
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
                        .font(.system(size: 24))   // ← Android 无显式 size = 默认 24dp
                        .foregroundColor(colors.onSurfaceVariant)
                }
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(id)
    }
}

// ← FormatRow(每行带 ⓘ 详情入口)
private struct FormatRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let name: String
    let desc: String
    var onDetail: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("•")
                .font(.system(size: 12))
                .foregroundColor(colors.primary)
                .padding(.top, 2)
                .padding(.trailing, 8)
            Text(name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(colors.onSurface)
                .frame(width: 110, alignment: .leading)
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)   // ← Android weight(1f)
            if let onDetail {
                Button(action: onDetail) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))   // ← Android Info 16dp
                        .foregroundColor(colors.onSurfaceVariant)   // ← Android tint onSurfaceVariant
                        .padding(.top, 2)   // ← Android icon padding(top = 2.dp)
                }
                .buttonStyle(SleepyButtonStyle())
                .padding(.leading, 6)   // ← Android icon padding(start = 6.dp)
                .accessibilityLabel(L10n.format("format_detail_content_desc"))
            }
        }
        .padding(.vertical, 3)
    }
}

// ← FormatDetailDialog(格式详情弹窗: 什么时候用 + 识别要求 + 示例; 纯文本独有 AI Prompt)
//   iOS 原生化: List + Section 替代裸 VStack — 自动 inset/grouped 视觉, 系统原生分隔线
private struct FormatDetailDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    let format: ImportFormatKey
    @State private var copiedPrompt = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(format.whenText)
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                        .listRowBackground(colors.surfaceContainer)
                }
                Section(L10n.format("format_help_spec")) {
                    ForEach(format.specItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 12))
                                .foregroundColor(colors.primary)
                                .padding(.top, 2)
                            Text(item)
                                .font(.system(size: 12)) // ← Android bodySmall 12
                                .foregroundColor(colors.onSurface)
                        }
                        .listRowBackground(colors.surfaceContainer)
                    }
                }
                Section(L10n.format("format_help_example")) {
                    Text(format.exampleText
                            .replacingOccurrences(of: "\\n", with: "\n")
                            .replacingOccurrences(of: "\\t", with: "\t"))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(colors.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(colors.surfaceContainer)
                }
                if format == .plain {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.format("ai_prompt_title"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colors.onPrimaryContainer)
                            Text(L10n.format("ai_prompt_hint"))
                                .font(.system(size: 12))
                                .foregroundColor(colors.onPrimaryContainer)
                            Text(L10n.format("ai_prompt_text")
                                    .replacingOccurrences(of: "\\n", with: "\n")
                                    .replacingOccurrences(of: "\\t", with: "\t"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(colors.onPrimaryContainer)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(colors.surfaceContainer)
                                .cornerRadius(SleepyShapes.medium)
                            Button {
                                UIPasteboard.general.string = L10n.format("ai_prompt_text")
                                    .replacingOccurrences(of: "\\n", with: "\n")
                                    .replacingOccurrences(of: "\\t", with: "\t")
                                copiedPrompt = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 16))   // ← Android ContentCopy 16dp
                                    Text(copiedPrompt ? L10n.format("copied") : L10n.format("copy_prompt"))
                                        .font(.system(size: 14, weight: .medium))   // ← labelLarge 14sp Medium
                                }
                                .foregroundColor(colors.onPrimaryContainer)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(colors.primaryContainer)
                                .cornerRadius(SleepyShapes.large)
                            }
                            .buttonStyle(SleepyButtonStyle())
                        }
                        .listRowBackground(colors.primaryContainer)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .background(colors.surface)
            // ← Android 行763 title = titleRes(格式名, 如 format_plain);
            //   旧版误用 format_detail_content_desc「查看格式说明」当标题
            .navigationTitle(L10n.format("format_\(format.l10nKey)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // ← Android 行884-886 关闭按钮 = format_help_close「知道了」(旧版误用 cancel「取消」)
                    Button(L10n.format("format_help_close")) { dismiss() }
                        .foregroundColor(colors.primary)
                }
            }
        }
    }
}

// ← ImportPreviewDialog
//   iOS 原生化: NavigationView + List(.insetGrouped) 替代裸 ScrollView → 系统原生导航栏 +
//   系统原生分隔线 + 系统原生 inset 分组, 安全区适配自动处理。底部按钮组保留纯色块(危险动作风格统一)
private struct ImportPreviewDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let preview: ImportPreview
    let onDismiss: () -> Void
    let onApply: (ImportApplyMode) -> Void

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            if preview.targetTableId == 0 {
                                Text(L10n.format("import_new_table_hint"))
                                    .font(.system(size: 12)) // ← Android bodySmall 12
                                    .foregroundColor(colors.primary)
                            } else {
                                Text(L10n.format("import_target_table", preview.targetTableName))
                                    .font(.system(size: 12)) // ← Android bodySmall 12
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                        }
                        .listRowBackground(colors.surfaceContainer)
                    }

                    Section {
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
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }

                    Section {
                        PreviewInfoRow(label: L10n.format("import_table_name"), value: preview.parseResult.tableName)
                            .listRowBackground(colors.surfaceContainer)
                        PreviewInfoRow(label: L10n.format("import_start_date"), value: preview.parseResult.startDate)
                            .listRowBackground(colors.surfaceContainer)
                        if preview.targetTableId != 0 {
                            PreviewInfoRow(label: L10n.format("import_suggestion"),
                                           value: preview.conflictCount == 0
                                               ? L10n.format("import_no_conflict")
                                               : L10n.format("import_conflict_count", preview.conflictCount))
                                .listRowBackground(colors.surfaceContainer)
                        }
                    }

                    // ← issue#22 同名课程多地点提示 (secondaryContainer 卡片, 不阻塞导入)
                    if !preview.multiLocationWarnings.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.format("import_multi_location_warning"))
                                    .font(.system(size: 14, weight: .medium))   // ← titleSmall
                                    .foregroundColor(colors.onSecondaryContainer)
                                ForEach(preview.multiLocationWarnings.prefix(5), id: \.self) { warning in
                                    Text("• \(warning)")
                                        .font(.system(size: 12))   // ← bodySmall
                                        .foregroundColor(colors.onSecondaryContainer)
                                }
                                if preview.multiLocationWarnings.count > 5 {
                                    Text(L10n.format("more_unexpanded", preview.multiLocationWarnings.count - 5))
                                        .font(.system(size: 11, weight: .medium))   // ← labelSmall
                                        .foregroundColor(colors.onSecondaryContainer)
                                }
                            }
                            .listRowBackground(colors.secondaryContainer)
                        }
                    }

                    if !preview.conflicts.isEmpty {
                        Section(L10n.format("import_conflicts")) {
                            ForEach(preview.conflicts.prefix(3)) { conflict in
                                Text("• \(conflict.incoming.courseName) ↔ \(conflict.existing.courseName)（\(DateUtils.localizedDay(conflict.incoming.day)) \(conflict.incoming.nodeString(isShort: true))）")
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onSurfaceVariant)
                                    .listRowBackground(colors.surfaceContainer)
                            }
                            if preview.conflicts.count > 3 {
                                Text(L10n.format("import_conflict_more", preview.conflicts.count - 3))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(colors.onSurfaceVariant)
                                    .listRowBackground(colors.surfaceContainer)
                            }
                        }
                    }

                    if !preview.parseResult.droppedLines.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.format("import_dropped_title", preview.parseResult.droppedLines.count))
                                    .font(.system(size: 14, weight: .medium))   // ← titleSmall 14sp Medium
                                    .foregroundColor(colors.onErrorContainer)
                                Text(L10n.format("import_dropped_hint"))
                                    .font(.system(size: 12))
                                    .foregroundColor(colors.onErrorContainer)
                                ForEach(preview.parseResult.droppedLines.prefix(3), id: \.self) { line in
                                    Text("• \(line)")
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundColor(colors.onErrorContainer)
                                }
                                // ← Android 行1096-1102: 被跳过行 >3 时补「还有 N 行」溢出提示
                                if preview.parseResult.droppedLines.count > 3 {
                                    Text(L10n.format("import_conflict_more", preview.parseResult.droppedLines.count - 3))
                                        .font(.system(size: 11))
                                        .foregroundColor(colors.onErrorContainer)
                                }
                            }
                            .listRowBackground(colors.errorContainer)
                        }
                    }

                    // sleepy-v1 (§7.3): 表级提示(非行级) — T行钳制/节点抬升/chk不符/n=不符/二次表头
                    if !preview.parseResult.warnings.isEmpty {
                        Section {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.format("import_warnings_title"))
                                    .font(.system(size: 14, weight: .medium))   // ← titleSmall
                                    .foregroundColor(colors.onSecondaryContainer)
                                ForEach(preview.parseResult.warnings.prefix(4), id: \.self) { line in
                                    Text("• \(line)")
                                        .font(.system(size: 12))
                                        .foregroundColor(colors.onSecondaryContainer)
                                }
                                if preview.parseResult.warnings.count > 4 {
                                    Text(L10n.format("import_conflict_more", preview.parseResult.warnings.count - 4))
                                        .font(.system(size: 11))
                                        .foregroundColor(colors.onSecondaryContainer)
                                }
                            }
                            .listRowBackground(colors.secondaryContainer)
                        }
                    }

                    // 留出底部按钮区空间
                    Section {
                        Color.clear.frame(height: 100)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .background(colors.surface)

                // 底部按钮组 - 浮动在 List 之上, 保留纯色块风格统一
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        if preview.targetTableId == 0 {
                            PrimaryDialogButton(L10n.format("import_as_new")) {
                                onApply(.importAsNew)
                            }
                        } else {
                            PrimaryDialogButton(L10n.format("import_append_only")) {
                                onApply(.appendNonConflict)
                            }
                            PrimaryDialogButton(L10n.format("import_as_new")) {
                                onApply(.importAsNew)
                            }
                        }
                    }
                    if preview.targetTableId != 0 {
                        HStack(spacing: 8) {
                            Button {
                                onApply(.appendAll)
                            } label: {
                                Text(L10n.format("import_append_conflict"))
                                    .font(.system(size: 14, weight: .medium))
                                    .lineLimit(1)   // ← Android maxLines = 1
                                    .foregroundColor(colors.onErrorContainer)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(colors.errorContainer)
                                    .cornerRadius(SleepyShapes.medium)
                            }
                            .buttonStyle(SleepyButtonStyle())
                            PrimaryDialogButton(L10n.format("import_append_as_new")) {
                                onApply(.appendAsNew)
                            }
                        }
                        Button {
                            onApply(.replaceCurrent)
                        } label: {
                            Text(L10n.format("import_overwrite"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.onErrorContainer)
                                .frame(maxWidth: .infinity)
                                .frame(height: 40)
                                .background(colors.errorContainer)
                                .cornerRadius(SleepyShapes.medium)
                        }
                        .buttonStyle(SleepyButtonStyle())
                    }
                    // ← Android TextButton: 纯文字 40dp, onSurfaceVariant
                    Button(action: onDismiss) {
                        Text(L10n.format("cancel"))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(SleepyButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(
                    LinearGradient(colors: [colors.surface.opacity(0), colors.surface],
                                   startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea(edges: .bottom)
                )
            }
            .navigationTitle(L10n.format("import_preview_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.format("cancel")) { onDismiss() }
                        .foregroundColor(colors.primary)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("import_preview_title")
        }
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
        .buttonStyle(SleepyButtonStyle())
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
                .font(.system(size: 11, weight: .medium))   // ← labelSmall 11sp Medium
                .foregroundColor(fg.opacity(SleepyTheme.Alpha.highContent))
            Text(value)
                .font(.system(size: 22, weight: .bold))   // ← titleLarge 22sp Bold
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
                .font(.system(size: 11, weight: .medium))   // ← labelSmall 11sp Medium
                .foregroundColor(colors.onSurfaceVariant)
            Text(value)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurface)
                .accessibilityIdentifier("import_info_\(label)")
        }
    }
}

// ← ImportConfirmDialog
private struct ImportConfirmDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    @State var startDate: String
    @State var tableName: String
    @State var timeJson: String
    var showTableName: Bool = true
    let onTableNameChange: (String) -> Void
    let onStartDateChange: (String) -> Void
    let onTimeJsonChange: (String) -> Void
    let onDismiss: () -> Void
    // v1.0.56 T6: 第三 Tab「作息表」— 绑定现有作息表直接用; nil=未绑定(用解析出的节次)
    // (声明顺序 = 调用点实参顺序: Swift 成员初始化器强制按声明序传参, onConfirm 必须最后)
    var periodTableOptions: [PeriodTableOption] = []
    var selectedPeriodTableId: Int64? = nil
    var onSelectPeriodTable: (Int64?) -> Void = { _ in }
    // id -> timeJson, 绑表时确认校验/落库以表 timeJson 为真源 (用户反馈 2026-09-20 误报修复)
    var periodTableTimeJsonById: [Int64: String] = [:]
    let onConfirm: () -> Void

    @State private var rows: [TimeTableUtils.TimeSlotRow] = []
    @State private var rowsLoaded = false
    @State private var localError: String? = nil
    // issue#28 P2: 自动模式状态必须真实持有并回传 — 旧代码没传 smartConfig/
    // onSmartConfigChange, 落到默认 no-op, "添加课间"点了没有任何反应。
    // issue#23 T5: 初值 = 共享推断从导入解析出的行播种(45 分钟主时长 + 混合时长组
    // 一并识别, 与 EditTableScreen/PeriodTableEditScreen 同规); 行不可推断
    // (缺时间/畸形/断号) → 最简默认兜底, TimeSlotEditor 保持手动模式 + 既有校验。
    @State private var smartConfig = SmartPeriodConfig()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.format("import_confirm_title"))
                    .font(.system(size: 24))   // ← M3 AlertDialog title = headlineSmall 24sp 常规
                    .foregroundColor(colors.onSurface)
                Text(L10n.format("import_confirm_body"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)

                if showTableName {
                    TextField(L10n.format("import_table_name"), text: $tableName)
                        .frame(maxWidth: .infinity)   // ← Android fillMaxWidth()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(colors.surfaceContainerHighest)   // ← fieldColors 容器色 surfaceContainerHighest
                        .cornerRadius(SleepyTheme.fieldShape)
                        .onChange(of: tableName) { onTableNameChange($0) }
                }

                DatePickerField(value: startDate, onValueChange: { newValue in
                    startDate = newValue
                    onStartDateChange(newValue)
                }, label: L10n.format("import_week_start"),
                   // 只在日期错误时标红; 节次错误标到节次区(2026-09-20 反馈: 节次错也标日期框误导)
                   isError: localError != nil && (startDate.trimmingCharacters(in: .whitespaces).isEmpty ||
                       startDate.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) == nil),
                   fillsWidth: true)

                if let localError = localError {
                    Text(localError)
                        .font(.system(size: 12))
                        .foregroundColor(colors.error)
                }

                TimeSlotEditor(rows: rows, onRowsChange: { newRows in
                    rows = newRows
                    onTimeJsonChange(TimeTableUtils.buildTimeJsonFromRows(newRows))
                }, smartConfig: smartConfig, onSmartConfigChange: { smartConfig = $0 },
                   // v1.0.56 T6: 第三 Tab「作息表」
                   periodTableOptions: periodTableOptions,
                   selectedPeriodTableId: selectedPeriodTableId,
                   onSelectPeriodTable: onSelectPeriodTable)
            }
            .padding(20)
        }
        .background(colors.surface)
        .onAppear {
            guard !rowsLoaded else { return }
            rowsLoaded = true
            rows = TimeTableUtils.parseTimeSlotRows(timeJson)
            // issue#28 P2 + issue#23 T5 播种: 与 Android remember { resolveAutoPeriodConfig
            // (rows, null) ?: SmartPeriodConfig(totalPeriods=max(1,rows), startTime=首行或"08:00") } 同规
            smartConfig = resolveAutoPeriodConfig(rows: rows, stored: nil)
                ?? SmartPeriodConfig(
                    startTime: {
                        let s = rows.first?.start ?? ""
                        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "08:00" : s
                    }(),
                    totalPeriods: max(rows.count, 1))
        }
        .safeAreaInset(edge: .bottom) {
            // 2026-09-16 用户: 裸 TextButton 无边界无色块 — 统一色块按钮行
            DialogActionButtons(
                confirmText: L10n.format("import_confirm"),
                onConfirm: validateAndConfirm,
                dismissText: L10n.format("back"),
                onDismiss: onDismiss)
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
        // v1.0.56 T6 修正: 绑了作息表(id>0)时以表的 timeJson 为真源;
        // 旧代码无条件校验手动 rows, 解析源没回节次时间 → 误报「第 X 节时间不能为空」(用户反馈 2026-09-20)
        let effectiveRows = Self.effectiveRowsForConfirm(
            manualRows: rows, bindId: selectedPeriodTableId, tables: periodTableTimeJsonById)
        let emptyRows = effectiveRows.filter { $0.start.isEmpty || $0.end.isEmpty }
        if let first = emptyRows.first {
            localError = L10n.format("slot_time_required", first.node)
            return
        }
        let timeRegex = "^\\d{2}:\\d{2}$"
        let invalidRows = effectiveRows.filter {
            $0.start.range(of: timeRegex, options: .regularExpression) == nil ||
            $0.end.range(of: timeRegex, options: .regularExpression) == nil ||
            $0.start >= $0.end
        }
        if let first = invalidRows.first {
            localError = L10n.format("slot_time_invalid", first.node)
            return
        }
        localError = nil
        onTimeJsonChange(TimeTableUtils.buildTimeJsonFromRows(effectiveRows))
        onConfirm()
    }

    /// ← TimeTableUtils.effectiveRowsForConfirm: 绑定作息表时校验/落库以表 timeJson 为真源
    static func effectiveRowsForConfirm(
        manualRows: [TimeTableUtils.TimeSlotRow],
        bindId: Int64?,
        tables: [Int64: String]
    ) -> [TimeTableUtils.TimeSlotRow] {
        guard let id = bindId, id > 0, let json = tables[id] else { return manualRows }
        return TimeTableUtils.parseTimeSlotRows(json)
    }
}

// ← v1.0.56 T9 纯作息导入命名确认框(← Android 行436-508)
// courses.isEmpty && periodTable != nil 时替代 ImportPreviewDialog: 预填全局唯一名
// (课程表∪作息表, 后缀 2/3 预览即可见), 查重红标, 确认只建作息表不建空课表。
private struct PurePeriodImportDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let parsed: ScheduleParser.ParsedPeriodTable
    /// 预填唯一名 = 源名参与全局唯一名顺延; ← Android LaunchedEffect(currentPreview) 一次性播种
    let suggestUniqueName: () -> String
    let courseTableNames: [String]
    let periodTableNames: [String]
    let onDismiss: () -> Void
    /// 回调入参 = 已 trim 的候选名(非空且未撞名)
    let onConfirm: (String) -> Void

    @State private var name = ""
    @State private var seeded = false

    private var candidate: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameTaken: Bool {
        !candidate.isEmpty && TimeTableUtils.isTableNameTaken(
            candidate, courseTableNames: courseTableNames, periodTableNames: periodTableNames)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.format("period_table_import_title"))
                    .font(.system(size: 24))
                    .foregroundColor(colors.onSurface)
                Text(L10n.format("period_table_import_body"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)
                VStack(alignment: .leading, spacing: 4) {
                    TextField(L10n.format("period_table_name_label"), text: $name)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(colors.surfaceContainerHighest)
                        .cornerRadius(SleepyTheme.fieldShape)
                        .overlay(RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                            .stroke(nameTaken ? colors.error : Color.clear, lineWidth: 1))
                    if nameTaken {
                        Text(L10n.format("period_table_name_taken"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.error)
                    }
                }
                DialogActionButtons(
                    confirmText: L10n.format("period_table_import_confirm"),
                    onConfirm: { onConfirm(candidate) },
                    dismissText: L10n.format("cancel"),
                    onDismiss: onDismiss,
                    confirmEnabled: !candidate.isEmpty && !nameTaken)
            }
            .padding(20)
        }
        .background(colors.surface)
        .onAppear {
            // ← Android LaunchedEffect(currentPreview): 每个预览对象播一次预填名
            guard !seeded else { return }
            seeded = true
            name = suggestUniqueName()
        }
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
            // ← issue#22: 同 groupId 多地点提示 — 不阻塞导入, 让用户心里有数
            var multiLocWarnings: [String] = []
            let roomGroups = Dictionary(grouping: parseResult.courses) { $0.groupId }
            for (gid, cs) in roomGroups {
                if gid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
                let distinctRooms = Set(cs.map { $0.room.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty })
                if distinctRooms.count >= 2 {
                    multiLocWarnings.append(L10n.format(
                        "import_multi_location_warning_detail", cs.first?.courseName ?? "", distinctRooms.count))
                }
            }
            return ImportPreview(
                targetTableId: tableId,
                targetTableName: existingTable?.name ?? L10n.format("manage_current_table"),
                parseResult: parseResult,
                existingCourses: existingCourses,
                conflicts: conflicts,
                multiLocationWarnings: multiLocWarnings)
        case .failure(let e):
            onError(L10n.format("import_failed", e.localizedDescription))
            return nil
        }
    }

    // ← applyImportPreview: 五模式落地 (v1.0.61 全对齐)
    @discardableResult
    static func applyImportPreview(
        preview: ImportPreview,
        mode: ImportApplyMode,
        confirmedStartDateRaw: String,
        confirmedTableName: String,
        confirmedTimeJson: String,
        onImported: () -> Void,
        onError: (String) -> Void,
        // v1.0.56 T6: 第三 Tab「作息表」绑定 — 非 nil 且 ImportAsNew 时, 新建课表直接绑该表
        bindPeriodTableId: Int64? = nil
    ) -> Int64? {
        let repo = ScheduleRepository(AppDatabase.getShared())
        // v7.10.16 撤回: 整个导入是一个动作 — 批内只保首快照, 撤回一次回退到导入前。
        // defer 收口(↔ Android try/finally): 分支里的 early return 也要退出批边界。
        UndoManager.shared.beginBatch()
        defer { UndoManager.shared.endBatch() }
        // 应用约定 startDate=周一；用户在确认框可能手填非周一日期，落库前归一（issue #5）
        let confirmedStartDate = normalizeStartDate(confirmedStartDateRaw)
        switch mode {
        case .replaceCurrent:
            if let existing = try? repo.getTable(preview.targetTableId) {
                let newName = confirmedTableName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? preview.parseResult.tableName
                    : confirmedTableName.trimmingCharacters(in: .whitespacesAndNewlines)
                // 时间域写回真实 owner: 绑定独立作息表时写 period_tables, 不污染兼容列
                let bound = existing.periodTableId.flatMap { try? repo.getPeriodTable($0) }
                var nameDateCopy = existing
                nameDateCopy.name = newName
                nameDateCopy.startDate = confirmedStartDate
                try? repo.updateTable(nameDateCopy)
                if let bound = bound {
                    var updatedBound = bound
                    updatedBound.timeJson = confirmedTimeJson
                    if preview.parseResult.nodesPerDay > 0 {
                        updatedBound.nodesPerDay = preview.parseResult.nodesPerDay
                    }
                    _ = try? repo.savePeriodTable(updatedBound)
                } else {
                    var copy = nameDateCopy
                    copy.timeJson = confirmedTimeJson
                    copy.nodesPerDay = preview.parseResult.nodesPerDay > 0 ? preview.parseResult.nodesPerDay : existing.nodesPerDay
                    try? repo.updateTable(copy)
                }
            }
            // sleepy-v1 (§3.4 契约一): 解析端权威 groupId → 绕过 assignGroupIds 再分配
            if preview.parseResult.groupIdsAuthoritative {
                try? repo.replaceCoursesKeepingGroups(preview.targetTableId, preview.parseResult.courses)
            } else {
                try? repo.replaceCourses(preview.targetTableId, preview.parseResult.courses)
            }
            // v7.10.12: 整表替换不过闸门(换的是整张表, 拦截太武断), 但超层时提示
            let badDays = ConflictLayoutEngine.daysExceedingTwoLanes(preview.parseResult.courses)
            if !badDays.isEmpty {
                onError(L10n.format("import_three_layers_kept", dayNames(badDays)))
            }
            onImported()
            return preview.targetTableId
        case .importAsNew:
            let base = (try? repo.getTable(preview.targetTableId)) ?? nil
            // issue#40 §6: 新格式带 P 区块 → 建 period_tables 并绑定(恢复共享关系);
            // 旧格式 periodTable=nil → 不建(课表用自己兼容列, 不误共享)。
            // v1.0.56 T6: 用户在第三 Tab 显式选了作息表 → 绑定用户所选(优先于自动建表绑定);
            // v1.0.56 T10: 自动建表走全局唯一名顺延(撞名加后缀, 禁与既有课表/作息表同名)
            var importedPeriodTableId: Int64? = bindPeriodTableId
            if importedPeriodTableId == nil, let pt = preview.parseResult.periodTable {
                let courseNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
                let periodNames = ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
                let entity = PeriodTableEntity(
                    name: TimeTableUtils.suggestUniqueName(
                        pt.name, courseTableNames: courseNames, periodTableNames: periodNames),
                    nodesPerDay: pt.nodesPerDay,
                    timeJson: pt.timeJson)
                if let newId = (try? repo.insertPeriodTable(entity)) ?? nil, newId > 0 {
                    importedPeriodTableId = newId
                }
            }
            let existingNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
            var newTable = TimeTableEntity(
                name: uniqueImportedTableName(confirmedTableName, existingNames),
                startDate: confirmedStartDate,
                maxWeek: preview.parseResult.maxWeek > 0 ? preview.parseResult.maxWeek : (base?.maxWeek ?? 20),
                nodesPerDay: preview.parseResult.nodesPerDay > 0 ? preview.parseResult.nodesPerDay : base?.nodesPerDay ?? 12,
                timeJson: confirmedTimeJson,
                isDefault: false)
            newTable.color = base?.color ?? "#FF6750A4"
            newTable.periodTableId = importedPeriodTableId
            let newTableId = (try? repo.insertTable(newTable)) ?? 0
            var courses = preview.parseResult.courses
            for i in courses.indices {
                courses[i].id = 0
                courses[i].tableId = newTableId
            }
            // sleepy-v1: groupId 权威时保留分区(ImportAsNew 全量落新课表, 等价 replace 语义)
            if preview.parseResult.groupIdsAuthoritative {
                _ = try? repo.insertCoursesKeepingGroups(courses)
            } else {
                _ = try? repo.insertCourses(courses)
            }
            try? repo.setDefault(newTableId)
            // v7.10.12: 整表新建不过闸门, 超层时提示(同 ReplaceCurrent 策略)
            let badDaysNew = ConflictLayoutEngine.daysExceedingTwoLanes(preview.parseResult.courses)
            if !badDaysNew.isEmpty {
                onError(L10n.format("import_three_layers_kept", dayNames(badDaysNew)))
            }
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
            // v7.10.16x 三层闸门改相对判定(用户 2026-09-10 报"预览 8 门全不冲突,
            // 仅追加不冲突却 toast 全部冲突"): 旧绝对判定连坐原表已有超层天上的无辜候选。
            // 与 AppendAsNew(v7.10.16j)同规: 只剔**让某天新超 2 层**的候选(因它而恶化才拦)。
            let baseExceeding = ConflictLayoutEngine.daysExceedingTwoLanes(preview.existingCourses)
            var survivors: [CourseEntity] = []
            var droppedDays = Set<Int>()
            for cand in cleanCourses {
                if ConflictLayoutEngine.daysExceedingTwoLanes(preview.existingCourses + [cand]) == baseExceeding {
                    survivors.append(cand)
                } else {
                    droppedDays.insert(cand.day)
                }
            }
            if survivors.isEmpty {
                onError(L10n.format("import_all_conflict"))
                return nil
            }
            if survivors.count < cleanCourses.count {
                onError(L10n.format("import_three_layers_dropped", dayNames(droppedDays)))
            }
            var courses = survivors
            for i in courses.indices {
                courses[i].id = 0
                courses[i].tableId = preview.targetTableId
            }
            if preview.parseResult.groupIdsAuthoritative {
                _ = try? repo.insertCoursesKeepingGroups(courses)
            } else {
                _ = try? repo.insertCourses(courses)
            }
            // v7.10.16k 无损延伸: 老表作息∪导入作息, 并拓到导入课程实际到达的最大节。
            // 旧代码 timeJson 空白(粘贴文本常态)就整段跳过 → 课程入库了课表却不延伸 = 静默丢。
            // 2026-09-23: 绑定共享作息表时写入兼容列不生效(水合读 period); 写回真正 owner。
            extendTimeDomain(repo: repo, tableId: preview.targetTableId,
                             incomingJson: preview.parseResult.timeJson,
                             requiredNodeCount: preview.parseResult.nodesPerDay)
            onImported()
            return preview.targetTableId
        case .appendAsNew:
            // 当前课表 + 导入数据合并 → 新课表(用户命名)
            let base = (try? repo.getTable(preview.targetTableId)) ?? nil
            let incoming = preview.parseResult
            // v7.10.16k: 时间表 = 用户确认框里的 confirmedTimeJson 优先(它本身就是
            // mergeMostComplete 的无损合并初值, 用户又可手拓); 万一为空白再兜底无损合并。
            // mergedRows 恒非空(mergeMostComplete 至少 1 行), nodesPerDay 恒取行数。
            let mergedTimeJson = confirmedTimeJson.isEmpty
                ? TimeTableUtils.mergeMostComplete(
                    currentJson: base?.timeJson ?? "",
                    incomingJson: incoming.timeJson,
                    requiredNodeCount: incoming.nodesPerDay)
                : confirmedTimeJson
            let mergedRows = TimeTableUtils.parseTimeSlotRows(mergedTimeJson)
            let existingNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
            var newTable = TimeTableEntity(
                name: uniqueImportedTableName(confirmedTableName, existingNames),
                startDate: confirmedStartDate,
                maxWeek: incoming.maxWeek > 0 ? incoming.maxWeek : (base?.maxWeek ?? 20),
                nodesPerDay: !mergedRows.isEmpty ? mergedRows.count : (base?.nodesPerDay ?? 12),
                timeJson: mergedTimeJson,
                isDefault: false)
            newTable.color = base?.color ?? "#FF6750A4"
            let newTableId = (try? repo.insertTable(newTable)) ?? 0
            // 当前课表原课 + 导入课程合并导入新课表
            // v7.10.16i: 老课全量保留。v7.10.16j(用户 2026-09-03「新课表=纯老表复制」):
            // 三层闸门改为**只拦新增冲突** — 候选违规判定只看新增候选本身是否比原表
            // 多出新层(before/after 对比); 原表已有超层不再连坐, 冲突课不进新课表(防重复入库)。
            let cleanIncoming = incoming.courses.filter { inc in
                !preview.existingCourses.contains { existing in Self.coursesConflict(inc, existing) }
            }
            let oldCourses: [CourseEntity]
            if let b = base, let fetched = (try? repo.getCourses(b.id)) ?? nil {
                oldCourses = fetched
            } else {
                oldCourses = []
            }
            let beforeDays = ConflictLayoutEngine.daysExceedingTwoLanes(oldCourses)
            let afterDays = ConflictLayoutEngine.daysExceedingTwoLanes(oldCourses + cleanIncoming)
            if afterDays != beforeDays {
                let droppedDays = afterDays.subtracting(beforeDays)
                onError(L10n.format("import_three_layers_kept", dayNames(droppedDays)))
            }
            // AppendAsNew 合并新老课: 导入侧 groupId 权威时仅对导入课保组, 老课照原样保组
            var mergedCourses = (oldCourses + cleanIncoming).map { c in
                var copy = c; copy.id = 0; copy.tableId = newTableId; return copy
            }
            if preview.parseResult.groupIdsAuthoritative {
                _ = try? repo.insertCoursesKeepingGroups(mergedCourses)
                mergedCourses = []
            } else {
                _ = try? repo.insertCourses(mergedCourses)
                mergedCourses = []
            }
            // v7.10.16j: 合并新课表建完即激活 — 缺 setDefault 则用户仍看老表
            try? repo.setDefault(newTableId)
            onImported()
            return newTableId
        case .appendAll:
            // 连冲突课一起追加进当前课表 — 冲突/闸门全部放行, 仅提示(与整表新建同策略)。
            // 用户 2026-09-03: 该按钮的存在意义就是"冲突也要进来", 剔除即违背语义。
            let allCourses = preview.parseResult.courses
            if allCourses.isEmpty {
                onError(L10n.format("import_content_empty"))
                return nil
            }
            let badDaysAll = ConflictLayoutEngine.daysExceedingTwoLanes(preview.existingCourses + allCourses)
            if !badDaysAll.isEmpty {
                onError(L10n.format("import_three_layers_kept", dayNames(badDaysAll)))
            }
            var courses = allCourses
            for i in courses.indices {
                courses[i].id = 0
                courses[i].tableId = preview.targetTableId
            }
            if preview.parseResult.groupIdsAuthoritative {
                _ = try? repo.insertCoursesKeepingGroups(courses)
            } else {
                _ = try? repo.insertCourses(courses)
            }
            // v7.10.16k: 节次无损延伸 — 与 AppendNonConflict 同策略(不再要求导入带 timeJson)
            // 2026-09-23: 绑定态写 period_tables(真正 owner), 不污染兼容列。
            extendTimeDomain(repo: repo, tableId: preview.targetTableId,
                             incomingJson: preview.parseResult.timeJson,
                             requiredNodeCount: preview.parseResult.nodesPerDay)
            onImported()
            return preview.targetTableId
        }
    }

    // ← v1.0.56 T9 纯作息导入: 只建一张作息表, 不建空课表。
    // 名字已由确认框查重; 落库前再走 suggestUniqueName 兜底(同屏并发导入等边缘)。
    static func applyPurePeriodImport(
        name: String,
        parsed: ScheduleParser.ParsedPeriodTable,
        onImported: () -> Void,
        onError: (String) -> Void
    ) {
        let repo = ScheduleRepository(AppDatabase.getShared())
        UndoManager.shared.beginBatch()
        defer { UndoManager.shared.endBatch() }
        let courseNames = ((try? repo.getAllTables()) ?? []).map { $0.name }
        let periodNames = ((try? repo.getAllPeriodTables()) ?? []).map { $0.name }
        let unique = TimeTableUtils.suggestUniqueName(
            name, courseTableNames: courseNames, periodTableNames: periodNames)
        let entity = PeriodTableEntity(
            name: unique,
            nodesPerDay: max(parsed.nodesPerDay, 1),
            timeJson: parsed.timeJson)
        if (try? repo.insertPeriodTable(entity)) == nil {
            onError(L10n.format("import_failed", ""))
            return
        }
        onImported()
    }

    /// v7.10.16k 节次无损延伸(← Android 行1644-1664/1741-1760): 插课后把老表作息∪导入作息
    /// 写回真实 owner(绑表写 period_tables, 未绑写兼容列 + nodesPerDay=延伸后最大节)。
    static func extendTimeDomain(
        repo: ScheduleRepository,
        tableId: Int64,
        incomingJson: String,
        requiredNodeCount: Int
    ) {
        guard let existingTable = (try? repo.getTable(tableId)) ?? nil else { return }
        let bound = existingTable.periodTableId.flatMap { (try? repo.getPeriodTable($0)) ?? nil }
        let extended = TimeTableUtils.mergeMostComplete(
            currentJson: bound?.timeJson ?? existingTable.timeJson,
            incomingJson: incomingJson,
            requiredNodeCount: requiredNodeCount)
        if let bound = bound {
            if extended != bound.timeJson {
                let newMaxNode = TimeTableUtils.parseTimeSlotRows(extended).map { $0.node }.max() ?? bound.nodesPerDay
                var updated = bound
                updated.timeJson = extended
                updated.nodesPerDay = newMaxNode
                _ = try? repo.savePeriodTable(updated)
            }
        } else if extended != existingTable.timeJson {
            let newMaxNode = TimeTableUtils.parseTimeSlotRows(extended).map { $0.node }.max() ?? existingTable.nodesPerDay
            var updated = existingTable
            updated.timeJson = extended
            updated.nodesPerDay = newMaxNode
            try? repo.updateTable(updated)
        }
    }

    /// ← DateUtils.kt normalizeStartDate(应用约定 startDate=周一, issue #5;
    /// 与 JwImportViewModel.normalizeStartDate 同一实现/同一严格语义):
    /// 非法/欠宽输入原样返回, 不许宽松顺延成别的日期。
    static func normalizeStartDate(_ startDate: String) -> String {
        guard let parsed = DateUtils.parseDate(startDate),
              DateUtils.fullDate(parsed) == startDate else { return startDate }
        return DateUtils.fullDate(Calendar.isoMondayOfWeek(parsed))
    }

    /// 被剔除课所在 day 的本地化名(← Android dayNames: " / " join)
    static func dayNames(_ days: Set<Int>) -> String {
        days.sorted().map { DateUtils.localizedDay($0) }.joined(separator: " / ")
    }

    // ← coursesConflict: 同日 + 周次区间重叠 + 节次区间重叠
    // nonisolated: 纯函数(只读 CourseEntity 值字段), Android 无线程约束 —
    // 预览冲突计算在 Task.detached 后台段调用(JwImportFlow rebuildPreview)。
    nonisolated static func coursesConflict(_ a: CourseEntity, _ b: CourseEntity) -> Bool {
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
