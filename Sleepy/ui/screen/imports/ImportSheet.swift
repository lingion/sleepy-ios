// ImportSheet.swift — ← ui/screen/imports/ImportSheet.kt (v1.0.61, 1816 行)
// 导入课表弹窗: 教务直连 / 从文本导入(折叠) / 从文件导入 + 支持格式说明 +
// 预览对话框(五模式按钮) + 确认对话框(表名/开始日期/节次编辑器/作息表 Tab) +
// v1.0.56 T9 纯作息导入命名框。
//
// 平台映射: OpenDocument → fileImporter; SnackbarHost → 底部胶囊浮层(← JwImportFlow
// statusMsg 同款); Activity recreate → LocaleHelper 无关此处。

import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
    /// Stored once per parsed document; editing its confirmation keeps the same identity.
    let id = UUID()
    let targetTableId: Int64
    let targetTableName: String
    let parseResult: ScheduleParser.ParseResult
    let existingCourses: [CourseEntity]
    let conflicts: [CourseConflict]
    /// issue#22: 同 groupId 多地点提示 — 不阻塞导入,只让用户心里有数
    var multiLocationWarnings: [String] = []
    var effectiveTimeJson: String = ""
    var sourceDraftId: String? = nil

    var incomingCount: Int { parseResult.courses.count }
    var conflictCount: Int { conflicts.count }
    var cleanCount: Int { incomingCount - conflictCount }
}

/// Preview and confirmation belong to the same document. Replacing it invalidates old actions.
struct ImportPreviewSession {
    var preview: ImportPreview? = nil
    var pendingMode: ImportApplyMode? = nil
    var confirmedPreview: ImportPreview? = nil
    var confirmedTableName = ""
    var confirmedStartDate = ""
    var confirmedTimeJson = ""
    var confirmedBindPeriodTableId: Int64? = nil

    mutating func replacePreview(_ preview: ImportPreview?) {
        self = ImportPreviewSession(preview: preview)
    }

    /// Failed saves retain the same presented draft, including the dialog's edited name.
    mutating func completeImportIfSaved(_ save: () -> Bool) -> Bool {
        guard save() else { return false }
        replacePreview(nil)
        return true
    }
}

// 外部打开 json → 主壳 pendingImportText(← MainActivity companion, iOS 为全局)
enum PendingImportText {
    static let changedNotification = Notification.Name("sleepy.import.pending.changed")
    private(set) static var deliveryID: UUID?
    static var value: String? = nil {
        didSet {
            deliveryID = value == nil ? nil : UUID()
            NotificationCenter.default.post(name: changedNotification, object: nil)
        }
    }

    static func take() -> String? {
        guard let text = value else { return nil }
        value = nil
        return text
    }
}

/// 格式详情弹窗键(ImportFormat, sheet(item:) 驱动)
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
    var exampleText: String {
        Self.decodeAndroidResourceEscapes(L10n.format("format_\(l10nKey)_example"))
    }

    /// Decode the migrated Android resource layer once. A doubled backslash
    /// belongs to the example itself, such as an ICS DESCRIPTION's literal \n.
    static func decodeAndroidResourceEscapes(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.utf8.count)
        var characters = value.makeIterator()
        while let character = characters.next() {
            guard character == "\\", let escaped = characters.next() else {
                output.append(character)
                continue
            }
            switch escaped {
            case "n": output.append("\n")
            case "t": output.append("\t")
            case "\\": output.append("\\")
            default:
                output.append("\\")
                output.append(escaped)
            }
        }
        return output
    }
}

struct ImportSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    @Environment(\.localCoursePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScheduleViewModel
    let onDismiss: () -> Void
    var onImported: () -> Void = {}
    // 保留调用方草稿数据接口及教务 incoming 恢复兼容；新导入页无草稿箱入口。
    var drafts: [ImportDraftRowModel] = []
    var onDeleteDraft: (String) -> Void = { _ in }
    var onJwDismissed: () -> Void = {}
    var canCreateNewTable = false
    var targetTableId: Int64? = nil
    var initialImportText: String? = nil
    var onManualCourseSaved: () -> Void = {}

    @State private var consumedInitialImport = false
    @State private var jwPresentation: JwImportPresentation? = nil
    @State private var jwActiveImport = false
    @State private var jwReturn = JwImportReturnState(origin: .importMethods)
    @State private var textExpanded = false
    @State private var inputText = ""
    @State private var importInputHeight: CGFloat = 160
    @State private var inputRevealRequest = 0
    @FocusState private var inputFocused: Bool
    @State private var isLoading = false
    @State private var errorMsg: String? = nil
    @State private var previewSession = ImportPreviewSession()
    // v1.0.56 T9: 纯作息导入 — 解析结果只有作息表没课程时, 走独立确认框(只建作息表)
    @State private var purePeriodName = ""
    // ← 原版本 snackbar.showSnackbar(import_success): 导入成功提示(不再跳编辑页)
    @State private var successMsg: String? = nil
    @State private var showFilePicker = false
    @State private var detailFormat: ImportFormatKey? = nil
    @State private var showWakeUpShare = false
    @State private var wakeUpShareText = ""
    @State private var pendingWakeUpJSON: String?
    @State private var showExistingTables = false
    @State private var pendingSelection: ImportPreview? = nil
    @State private var selectedPreview: ImportPreview? = nil
    @State private var preparationId = UUID()
    @State private var manualEditor: ManualEditorSession?

    private var canImport: Bool {
        !isLoading && (targetTableId == nil || viewModel.state.tables.contains { $0.id == targetTableId })
    }

    var body: some View {
        let state = viewModel.state
        VStack(spacing: 0) {
        SettingsTopBar(title: L10n.format(targetTableId != nil ? "add_course_title" : "create_table_title"),
                       onBack: onDismiss)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if targetTableId != nil {
                    ImportMethodRow(id: "import_existing", icon: "doc.on.doc",
                                    label: L10n.format("add_course_from_existing")) {
                        errorMsg = nil
                        showExistingTables = true
                    }.disabled(!canImport)
                    if !state.tables.contains(where: { $0.id == targetTableId }) {
                        Text(L10n.format("manage_no_table_hint"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                            .padding(16)
                            .accessibilityIdentifier("import_invalid_target_hint")
                    }
                }

                // 行 1: 教务直连
                ImportMethodRow(id: "import_jw", icon: "qrcode", label: L10n.format("import_jw")) {
                    jwPresentation = JwImportPresentation()
                }.disabled(!canImport)
                // 行 2: 从文本导入(可折叠)
                ImportMethodRow(id: "import_text", icon: "doc.text",
                                label: L10n.format("import_paste"),
                                trailing: textExpanded ? "chevron.up" : "chevron.down") {
                    withAnimation { textExpanded.toggle() }
                }
                if textExpanded {
                    VStack(spacing: 8) {
                        importTextField
                            .padding(12)
                            .frame(height: importInputHeight, alignment: .topLeading)
                            .background(colors.surfaceContainerHighest)   // ← fieldColors 容器色 surfaceContainerHighest
                            .cornerRadius(SleepyTheme.fieldShape)
                            .contentShape(Rectangle())
                            .onTapGesture { inputFocused = true }
                            // ← 原 filled TextField, 无描边
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("import_paste_viewport")
                        Button {
                            if WakeUpShareClient.looksLikeShareCode(inputText) {
                                presentWakeUpShare(inputText)
                                return
                            }
                            isLoading = true
                            invalidatePreparedImport()
                            let p = ImportSheet.buildImportPreview(inputText, state, targetTableId: targetTableId) { msg in errorMsg = msg }
                            isLoading = false
                            guard let p else { return }
                            let deliveryId = preparationId
                            // ★ v1.0.62 对齐(根因修复): 原版本 的导入预览是 AlertDialog,
                            //   以 dialog 形式弹出时系统会先收走键盘;iOS 用 .sheet 弹预览时,
                            //   粘贴框仍是 first responder → 键盘不收 → UIKit 把预览 sheet
                            //   的容器整体下移(内容容器 y=874),预览底部按钮落到屏幕外,
                            //   XCUITest 拿到 {{inf,inf}/{0,0}} 的无效 frame 无法点击。
                            //   对策: 先强制收键盘(与 DateTimePickers 同款),再延一小拍弹预览。
                            ImportSheet.dismissKeyboard()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                guard preparationId == deliveryId else { return }
                                acceptPreview(p)
                            }
                        } label: {
                            Text(isLoading ? L10n.format("import_parsing") : L10n.format("import_preview"))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(colors.onPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: style == .liquidGlass ? nil : 48)
                                .sleepyControlSurface(cornerRadius: SleepyShapes.large, tint: colors.primary, prominent: true)
                        }
                        .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
                        .frame(maxWidth: .infinity, minHeight: style == .liquidGlass ? 48 : nil)
                        .tint(colors.primary)
                        .accessibilityIdentifier("import_preview_btn")
                        .disabled(!canImport || inputText.isEmpty)
                    }
                    .padding(.leading, 56)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .padding(.trailing, 4)
                    .id("import_paste_focus_target")
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if targetTableId != nil {
                    ImportMethodRow(id: "import_manual", icon: "plus",
                                    label: L10n.format("add_course_manual"), onClick: beginManualCourse)
                        .disabled(!canImport)
                } else if canCreateNewTable {
                    ImportMethodRow(id: "manage_new_table", icon: "plus",
                                    label: L10n.format("manage_create_blank_table"), onClick: beginManualTable)
                        .disabled(!canImport)
                }

                // 行 3: 从文件导入
                ImportMethodRow(id: "import_file", icon: "square.and.arrow.up", label: L10n.format("import_file")) {
                    showFilePicker = true
                }.disabled(!canImport)

                Spacer().frame(height: 20)

                // 支持的导入类型
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.format("import_supported_formats"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                        .padding(.bottom, 8)
                    FormatRow(id: "format_help_wakeup_share", name: L10n.format("format_wakeup_share"), desc: L10n.format("format_wakeup_desc")) {
                        detailFormat = .wakeupShare
                    }
                    FormatRow(id: "format_help_wakeup_json", name: L10n.format("format_wakeup_json"), desc: L10n.format("format_json_desc")) {
                        detailFormat = .wakeupJson
                    }
                    FormatRow(id: "format_help_ics", name: L10n.format("format_ics"), desc: L10n.format("format_ics_desc")) {
                        detailFormat = .ics
                    }
                    FormatRow(id: "format_help_csv", name: L10n.format("format_csv"), desc: L10n.format("format_csv_desc")) {
                        detailFormat = .csv
                    }
                    FormatRow(id: "format_help_html", name: L10n.format("format_html"), desc: L10n.format("format_html_desc")) {
                        detailFormat = .html
                    }
                    FormatRow(id: "format_help_plain", name: L10n.format("format_plain"), desc: L10n.format("format_plain_desc")) {
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
        .accessibilityIdentifier("import_methods_scroll")
        .scrollDismissesKeyboardImmediatelyCompat()
        .background(colors.background)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { updateImportInputViewport(geometry.size) }
                .onChange(of: geometry.size) { size in
                    updateImportInputViewport(size)
                }
        })
        .onChange(of: inputFocused) { _ in requestImportInputReveal() }
        .onChange(of: textExpanded) { expanded in
            if !expanded { inputFocused = false }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification)) { _ in
            requestImportInputReveal()
        }
        .task(id: inputRevealRequest) {
            await revealImportInput(using: proxy)
        }
        // ← 原版本 SnackbarHost + LaunchedEffect(importJustApplied):
        //   导入成功提示(不再跳编辑课表页), 底部胶囊浮层, 复用 JwImportFlow statusMsg 同款
        .overlay(alignment: .bottom) {
            if let msg = successMsg {
                Text(msg)
                    .font(.system(size: 14))   // ← 原 Snackbar bodyMedium 14
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
        // The window queues later deliveries until this presentation dismisses,
        // preserving the current input, preview, target and any nested JW flow.
        .onAppear { consumePendingImportText() }
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
                    if WakeUpShareClient.looksLikeShareCode(text) {
                        presentWakeUpShare(text)
                    } else {
                        prepareImport(text)
                    }
                } catch {
                    errorMsg = L10n.format("read_failed", error.localizedDescription)
                }
                isLoading = false
            case .failure(let e):
                errorMsg = L10n.format("read_failed", e.localizedDescription)
            }
        }
        // 错误反馈通道(AlertDialog 统一弹窗, 2026-09-18 用户: 报错必须
        // 统一弹窗不再是 Snackbar 一闪即逝): 标题 jw_error_dialog_title「导入遇到问题」+
        // 单按钮 jw_err_dismiss「知道了」+ 错误文本可滚动(heightIn max 320dp)
        .alert(L10n.format("jw_error_dialog_title"), isPresented: Binding(
            get: { errorMsg != nil && previewSession.preview == nil && !showExistingTables },
            set: { if !$0 { errorMsg = nil } }
        )) {
            Button(L10n.format("jw_err_dismiss"), role: .cancel) {}
        } message: {
            Text(errorMsg ?? "")
        }
        .centeredDialog(isPresented: $showExistingTables) {
            existingTablesDialog
        }
        .fullScreenCover(item: Binding(
            get: { pendingSelection.map { PreviewBox(preview: $0) } },
            set: { if $0 == nil { pendingSelection = nil } }
        ), onDismiss: {
            guard let selected = selectedPreview else { return }
            selectedPreview = nil
            previewSession.replacePreview(selected)
        }) { box in
            CourseSelectionSheet(parseResult: box.preview.parseResult, onConfirm: { keys in
                guard pendingSelection?.id == box.preview.id else { return }
                do {
                    let filtered = try AddCoursesImport.filtered(box.preview.parseResult, selectedKeys: keys)
                    selectedPreview = Self.buildImportPreview(filtered, targetTableId: box.preview.targetTableId,
                        sourceDraftId: box.preview.sourceDraftId)
                    pendingSelection = nil
                } catch { errorMsg = error.localizedDescription }
            }, onDismiss: { pendingSelection = nil })
        }
        // Keep the parsed document and every confirmation inside one modal presenter.
        .centeredDialog(isPresented: Binding(
            get: { previewSession.preview != nil },
            set: { if !$0 && !isLoading { previewSession.replacePreview(nil) } }
        )) {
            if let preparedPreview = previewSession.preview {
            let box = PreviewBox(preview: preparedPreview)
            Group {
            // v1.0.56 T9: 纯作息导入(只有 P 区块/节次, 零课程) — 不进课程确认框,
            // 弹独立命名框(预填全局唯一名, 用户可改), 确认只建作息表不建空课表。
            if box.preview.parseResult.courses.isEmpty, let pt = box.preview.parseResult.periodTable {
                PurePeriodImportDialog(
                    parsed: pt,
                    suggestUniqueName: { Self.suggestPurePeriodName(for: pt, state: state, viewModel: viewModel) },
                    courseTableNames: state.tables.map { $0.name },
                    periodTableNames: viewModel.loadAllPeriodTables().map { $0.name },
                    isApplying: isLoading,
                    onDismiss: {
                        guard !isLoading, previewSession.preview?.id == box.preview.id else { return }
                        previewSession.replacePreview(nil)
                    },
                    onConfirm: { candidate in
                        guard previewSession.preview?.id == box.preview.id else { return }
                        isLoading = true
                        let saved = previewSession.completeImportIfSaved {
                            ImportSheet.applyPurePeriodImport(name: candidate, parsed: pt,
                                                              onImported: onImported) { msg in errorMsg = msg }
                        }
                        isLoading = false
                        guard saved else { return }
                        // ← 原版本 importJustApplied=true → snackbar 明示已落库
                        showSuccess(L10n.format("import_success"))
                    })
            } else if canCreateNewTable && targetTableId == nil {
                confirmDialogContent
            } else {
            ImportPreviewDialog(preview: box.preview,
                                courseDecision: targetTableId != nil,
                                isApplying: isLoading,
                                onCourseApply: { decision in applyCourseImport(box.preview, decision: decision) },
                                showConfirm: previewSession.pendingMode != nil,
                                onConfirmDismiss: { previewSession.pendingMode = nil },
                                confirmContent: { AnyView(confirmDialogContent) },
                                onDismiss: {
                                    guard !isLoading, previewSession.preview?.id == box.preview.id else { return }
                                    previewSession.replacePreview(nil)
                                }) { mode in
                guard let currentPreview = previewSession.preview,
                      currentPreview.id == box.preview.id else { return }
                let existingTable = Self.effectiveTargetTable(currentPreview.targetTableId)
                previewSession.confirmedStartDate = currentPreview.parseResult.startDate.isEmpty
                    ? (existingTable?.startDate ?? Self.todayISO())
                    : currentPreview.parseResult.startDate
                previewSession.confirmedTableName = currentPreview.parseResult.tableName.isEmpty
                    ? (existingTable?.name ?? L10n.format("default_table_name"))
                    : currentPreview.parseResult.tableName
                // v7.10.16k 无损合并(用户 2026-09-03「哪个大用哪个, 最完整优先」):
                // 不再 ifBlank 单选 — 老表作息与导入作息逐节合并, 节次数取双方最大,
                // 并拓到导入课程实际到达的最大节。导入源 13 节绝不被老表 10 节压小。
                previewSession.confirmedTimeJson = TimeTableUtils.mergeMostComplete(
                    currentJson: existingTable?.timeJson ?? "",
                    incomingJson: currentPreview.parseResult.timeJson,
                    requiredNodeCount: currentPreview.parseResult.nodesPerDay)
                // ★ 架构对齐 原版本 v1.0.62 (ImportSheet.kt: `if (preview != null &&
                //   pendingMode != null)` 同时组合 ImportPreviewDialog 与 ImportConfirmDialog):
                //   原版本 的预览**不关**, 确认框作为第二个 Dialog 叠在上面, 两者共存。
                //   iOS 早期把确认框做成宿主上的第二个 .sheet, 并靠"先 preview = nil 再延时
                //   0.45s 置 pendingMode"绕开同宿主双 sheet 冲突 —— 结果第二个 sheet 在预览
                //   dismiss 途中被丢弃, 用户看到"点了没反应"(ManageImportUITests
                //   testFullTextImportFlow 失败: 确认对话框未弹出)。
                //   现改为: 预览 sheet 保持打开, 确认框作为**预览 sheet 内部的一层 overlay**
                //   呈现(见 ImportPreviewDialog 的 showConfirm/confirmContent), 与原实现
                //   双对话框同构; 无延时, 无"先关预览"。
                // v7.10.13 追加模式: 追加到已存在的课表, 命名由目标课表自带, 不需要再问用户 —
                // 直接走 applyImportPreview, 跳过 ImportConfirmDialog(LaunchedEffect)。
                // ★ 无需延时: 追加分支不弹确认框, 预览 sheet 保持打开直到导入完成,
                //   不存在"第二个 presentation 被丢弃"的竞态。
                if mode == .appendNonConflict || mode == .appendAll {
                    let p = currentPreview
                    isLoading = true
                    let importedId = ImportSheet.applyImportPreview(
                        preview: p, mode: mode,
                        confirmedStartDateRaw: p.parseResult.startDate.isEmpty
                            ? (existingTable?.startDate ?? Self.todayISO())
                            : p.parseResult.startDate,
                        confirmedTableName: existingTable?.name ?? "",
                        confirmedTimeJson: TimeTableUtils.mergeMostComplete(
                            currentJson: existingTable?.timeJson ?? "",
                            incomingJson: p.parseResult.timeJson,
                            requiredNodeCount: p.parseResult.nodesPerDay),
                        onImported: { finishImported(p) }) { msg in errorMsg = msg }
                    isLoading = false
                    guard importedId != nil else { return }
                    previewSession.replacePreview(nil)
                    isLoading = false
                    // ← 原版本: 导入成功不再跳编辑课表页(假保存闸), snackbar 明示已落库
                    showSuccess(L10n.format("import_success"))
                    return
                }
                // ← 原版本: preview 保持非 nil, pendingMode 同步置位;
                //   确认框作为第二个 Dialog 叠在预览之上(见预览 sheet 内的 overlay)。
                previewSession.confirmedPreview = currentPreview
                previewSession.pendingMode = mode
            }
            }
            }
            .id(box.id)
            .alert(L10n.format("jw_error_dialog_title"), isPresented: Binding(
                get: { errorMsg != nil },
                set: { if !$0 { errorMsg = nil } }
            )) {
                Button(L10n.format("jw_err_dismiss"), role: .cancel) {}
            } message: {
                Text(errorMsg ?? "")
            }
            }
        }
        .sheet(isPresented: $showWakeUpShare, onDismiss: {
            guard let json = pendingWakeUpJSON else { return }
            pendingWakeUpJSON = nil
            prepareImport(json)
        }) {
            WakeUpShareImportSheet(initialText: wakeUpShareText, onResolved: { json in
                pendingWakeUpJSON = json
                ImportSheet.dismissKeyboard()
                showWakeUpShare = false
            }, onCancel: {
                pendingWakeUpJSON = nil
                showWakeUpShare = false
            })
            .environment(\.localWakeUpColors, colors)
        }
        // 原生子 sheet 保留导入方式页及其输入；不拆父页、不用延时换 presentation。
        .sheet(item: $jwPresentation, onDismiss: handleJwDismissed) { presentation in
            JwImportFlow(onFinish: { outcome in
                jwReturn.record(outcome)
                jwPresentation = nil
            }, incomingDraftId: presentation.draftId,
               onActiveImportChanged: { jwActiveImport = $0 },
               targetTableId: targetTableId, newTableOnly: canCreateNewTable && targetTableId == nil)
                .environment(\.localWakeUpColors, colors)
                .environment(\.localCoursePalette, palette)
                .preferredColorScheme(colorScheme)
                .interactiveDismissDisabled(jwActiveImport)
                .sheetDragIndicator(.visible)
        }
        // Keep this methods instance and its paste/preview draft below the editor.
        // Interactive dismissal and the editor's Back action share one discard path.
        .sheet(item: Binding(
            get: { manualEditor },
            set: { if $0 == nil { dismissManualEditor() } }
        )) { session in
            manualEditorContent(session)
                .environment(\.localWakeUpColors, colors)
                .environment(\.localCoursePalette, palette)
                .environment(\.sleepyUIStyle, style)
                .preferredColorScheme(colorScheme)
                .sheetDragIndicator(.visible)
        }
        // 格式详情弹窗 ("支持格式"每行 ⓘ 点开)
        .centeredDialog(isPresented: Binding(get: { detailFormat != nil }, set: { if !$0 { detailFormat = nil } })) {
            if let fmt = detailFormat {
                FormatDetailDialog(format: fmt, onDismiss: { detailFormat = nil })
            }
        }
        }
        }
        .background(colors.background)
    }

    @ViewBuilder
    private func manualEditorContent(_ session: ManualEditorSession) -> some View {
        switch session {
        case .newTable(let tableId, _):
            EditTableScreen(viewModel: viewModel,
                            tableId: tableId,
                            pendingNewTableId: tableId,
                            onDismiss: dismissManualEditor,
                            onDiscardPending: dismissManualEditor,
                            onSaved: finishManualEditor,
                            onDeleted: finishManualEditor)
        case .course(let tableId):
            AddCourseScreen(viewModel: viewModel,
                            onDismiss: dismissManualEditor,
                            onSaved: finishManualEditor,
                            targetTableId: tableId)
        }
    }

    private func beginManualTable() {
        guard manualEditor == nil, canCreateNewTable, targetTableId == nil, canImport else { return }
        inputFocused = false
        Self.dismissKeyboard()
        let fallbackId = viewModel.state.currentTable?.id
        let tableId = viewModel.createEmptyTable(commitSelection: false)
        guard tableId != 0 else { return }
        manualEditor = .newTable(id: tableId, fallbackId: fallbackId)
    }

    private func beginManualCourse() {
        guard manualEditor == nil, let targetTableId, canImport else { return }
        inputFocused = false
        Self.dismissKeyboard()
        manualEditor = .course(targetTableId: targetTableId)
    }

    private func dismissManualEditor() {
        guard let session = manualEditor else { return }
        manualEditor = nil
        if case .newTable(let tableId, let fallbackId) = session {
            viewModel.discardNewTable(tableId, fallbackId: fallbackId)
        }
    }

    private func finishManualEditor() {
        guard let session = manualEditor else { return }
        // Resolve the pending editor before SwiftUI dismisses its child sheet.
        manualEditor = nil
        if case .course = session { onManualCourseSaved() }
    }

    private func updateImportInputViewport(_ size: CGSize) {
        // A short landscape sheet still needs an editable line and room above
        // the keyboard. Publish only the clamped height used by the card, so
        // keyboard/rotation layout does not repeatedly change unrelated state.
        let height = min(160, max(44, floor(size.height - 80)))
        if importInputHeight != height { importInputHeight = height }
        requestImportInputReveal()
    }

    @ViewBuilder
    private var importTextField: some View {
        if #available(iOS 16.0, *) {
            TextField(L10n.format("import_paste_hint"), text: $inputText, axis: .vertical)
                .lineLimit(1...8)
                .focused($inputFocused)
                .accessibilityIdentifier("import_paste_input")
        } else {
            ZStack(alignment: .topLeading) {
                if inputText.isEmpty {
                    Text(L10n.format("import_paste_hint"))
                        .foregroundColor(Color(.placeholderText))
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $inputText)
                    .padding(-4)
                    .focused($inputFocused)
                    .accessibilityIdentifier("import_paste_input")
            }
        }
    }

    private func requestImportInputReveal() {
        guard textExpanded && inputFocused else { return }
        inputRevealRequest &+= 1
    }

    @MainActor
    private func revealImportInput(using proxy: ScrollViewProxy) async {
        guard textExpanded && inputFocused else { return }
        // Geometry and keyboard notifications arrive in a burst during rotation.
        // The view task cancels the previous request and waits for settled layout.
        do { try await Task.sleep(nanoseconds: 100_000_000) }
        catch { return }
        guard !Task.isCancelled && textExpanded && inputFocused else { return }
        // Reveal is part of keyboard layout, not another scroll animation racing
        // UIKit's rotation/caret positioning. Also discard inherited animation.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo("import_paste_focus_target", anchor: .top)
        }
    }

    private func handleJwDismissed() {
        SchoolSelectStateStore.shared.resetForNewEntry()
        jwActiveImport = false
        onJwDismissed()
        // 下滑/取消留在原父页；成功仅在子 sheet 动画结束后关闭父页。
        if jwReturn.didDismiss() {
            onImported()
            onDismiss()
        }
    }

    /// ← 原版本: `if (preview != null && pendingMode != null)` 时把 ImportConfirmDialog
    ///   作为**第二个 Dialog** 叠在预览 Dialog 之上(两者共存, 预览不关)。
    ///   iOS 无"对话框叠对话框"这一层结构, 嵌套 .sheet(挂在预览 sheet 里的
    ///   NavigationView 根上)在 iOS 上会被静默丢弃 —— 表现为"点了导入模式没反应"。
    ///   对策: 确认框作为**预览 sheet 内部的一层 overlay**(同一 presented surface),
    ///   语义与 原版本 的双对话框叠放一致: 预览仍在下面, 确认框盖在上面。
    ///   ⚠️ overlay 必须落在**非** .accessibilityElement(children: .contain) 的
    ///   容器里, 否则确认框的标题会被预览层吞掉(XCUITest 找不到 import_confirm_title)。
    @ViewBuilder
    private var confirmDialogContent: some View {
        ImportConfirmDialog(
            startDate: previewSession.confirmedStartDate,
            tableName: previewSession.confirmedTableName,
            timeJson: previewSession.confirmedTimeJson,
            courses: previewSession.confirmedPreview?.parseResult.courses ?? [],
            droppedLines: previewSession.confirmedPreview?.parseResult.droppedLines ?? [],
            warnings: previewSession.confirmedPreview?.parseResult.warnings ?? [],
            isApplying: isLoading,
            // 仅"创建新课表"或"追加为新课表"需要命名; 覆盖课表不强制重命名
            showTableName: previewSession.pendingMode == .importAsNew || previewSession.pendingMode == .appendAsNew,
            onTableNameChange: { previewSession.confirmedTableName = $0 },
            onStartDateChange: { previewSession.confirmedStartDate = $0 },
            onTimeJsonChange: { previewSession.confirmedTimeJson = $0 },
            onDismiss: {
                guard !isLoading else { return }
                if canCreateNewTable && targetTableId == nil { previewSession.replacePreview(nil) }
                else { previewSession.pendingMode = nil }
            },
            // v1.0.56 T6: 第三 Tab「作息表」
            periodTableOptions: viewModel.loadAllPeriodTables().map {
                PeriodTableOption(id: $0.id, name: $0.name, nodesPerDay: $0.nodesPerDay)
            },
            selectedPeriodTableId: previewSession.confirmedBindPeriodTableId,
            onSelectPeriodTable: { previewSession.confirmedBindPeriodTableId = $0 },
            periodTableTimeJsonById: Dictionary(
                uniqueKeysWithValues: viewModel.loadAllPeriodTables().map { ($0.id, $0.timeJson) }),
            onConfirm: {
                guard let mode = previewSession.pendingMode, let currentPreview = previewSession.confirmedPreview,
                      currentPreview.id == previewSession.preview?.id else { return }
                isLoading = true
                // 「确认导入」= 唯一写库点, 点下即落库。之后不再跳编辑课表页 —
                // 那个页面有「保存」按钮, 会造成"没点保存数据也在"的假保存闸误导
                // (原版本 v1.0.56 已删跳转, 改 snackbar 明示 import_success)。
                let importedId = ImportSheet.applyImportPreview(
                    preview: currentPreview, mode: mode,
                    confirmedStartDateRaw: previewSession.confirmedStartDate,
                    confirmedTableName: previewSession.confirmedTableName,
                    confirmedTimeJson: previewSession.confirmedTimeJson,
                    onImported: { finishImported(currentPreview) },
                    onError: { msg in errorMsg = msg },
                    bindPeriodTableId: previewSession.confirmedBindPeriodTableId)
                isLoading = false
                guard importedId != nil else { return }
                // ← 原版本: 导入成功预览一并关闭 (preview = null)
                previewSession.replacePreview(nil)
                isLoading = false
                showSuccess(L10n.format("import_success"))
            })
    }

    private static func todayISO() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Consume the payload captured by this presentation exactly once. Later
    /// deliveries remain queued at the window and cannot change this target.
    private func consumePendingImportText() {
        guard !consumedInitialImport else { return }
        consumedInitialImport = true
        let state = viewModel.state
        if let text = initialImportText,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // A new delivery invalidates every action and binding choice from the previous one,
            // including when this payload is invalid or must continue through the share flow.
            invalidatePreparedImport()
            errorMsg = nil
            if WakeUpShareClient.looksLikeShareCode(text) {
                presentWakeUpShare(text)
                return
            }
            isLoading = true
            let p = ImportSheet.buildImportPreview(text, state, targetTableId: targetTableId) { msg in errorMsg = msg }
            acceptPreview(p)
            isLoading = false
        }
    }

    private func invalidatePreparedImport() {
        preparationId = UUID()
        pendingSelection = nil
        selectedPreview = nil
        previewSession.replacePreview(nil)
    }

    private func prepareImport(_ text: String) {
        invalidatePreparedImport()
        acceptPreview(Self.buildImportPreview(text, viewModel.state, targetTableId: targetTableId) { errorMsg = $0 })
    }

    private func acceptPreview(_ preview: ImportPreview?) {
        guard let preview else { return }
        do {
            if let targetTableId {
                _ = try AddCoursesImport.target(repository: ScheduleRepository(AppDatabase.getShared()), tableId: targetTableId)
                try AddCoursesImport.validate(preview.parseResult)
                pendingSelection = preview
            } else {
                previewSession.replacePreview(preview)
                // Prepare before SwiftUI constructs the dialog's @State values.
                // An onAppear callback runs after its initial date/name were captured.
                if canCreateNewTable { configureNewTableConfirmation(preview) }
            }
        } catch { errorMsg = error.localizedDescription }
    }

    private func configureNewTableConfirmation(_ preview: ImportPreview) {
        guard previewSession.preview?.id == preview.id else { return }
        previewSession.confirmedPreview = preview
        previewSession.pendingMode = .importAsNew
        previewSession.confirmedStartDate = preview.parseResult.startDate.isEmpty ? Self.todayISO() : preview.parseResult.startDate
        previewSession.confirmedTableName = preview.parseResult.tableName.isEmpty ? L10n.format("default_table_name") : preview.parseResult.tableName
        previewSession.confirmedTimeJson = TimeTableUtils.mergeMostComplete(currentJson: "", incomingJson: preview.parseResult.timeJson,
            requiredNodeCount: max(preview.parseResult.nodesPerDay, preview.parseResult.courses.map { $0.startNode + $0.step - 1 }.max() ?? 0))
    }

    private func finishImported(_ preview: ImportPreview) {
        if let draftId = preview.sourceDraftId {
            try? ImportDraftRepository(AppDatabase.getShared()).delete(draftId)
        }
        onImported()
    }

    private func applyCourseImport(_ displayed: ImportPreview, decision: CourseImportDecision) {
        guard !isLoading, let preview = previewSession.preview, preview.id == displayed.id,
              targetTableId == preview.targetTableId else { return }
        isLoading = true
        let saved = Self.applyCourseImport(preview: preview, decision: decision,
            onImported: { finishImported(preview) }, onError: { errorMsg = $0 })
        isLoading = false
        guard saved != nil else { return }
        previewSession.replacePreview(nil)
        showSuccess(L10n.format("import_success"))
    }

    private var existingTablesDialog: some View {
        CenteredPickerDialog(title: L10n.format("add_course_from_existing"), maxContentHeight: 320,
                             onDismiss: dismissExistingTables,
                             footer: AnyView(HStack {
            Spacer()
            Button(L10n.format("cancel"), action: dismissExistingTables)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.primary)
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("import_source_cancel")
        })) {
            VStack(alignment: .leading, spacing: 8) {
                let sources = viewModel.state.tables.filter { $0.id != targetTableId }
                if sources.isEmpty {
                    Text(L10n.format("add_course_no_source"))
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                        .accessibilityIdentifier("add_course_no_source")
                }
                ForEach(sources) { table in
                    Button {
                        guard canImport, let targetTableId else { return }
                        isLoading = true
                        defer { isLoading = false }
                        do {
                            let result = try AddCoursesImport.source(repository: ScheduleRepository(AppDatabase.getShared()),
                                sourceTableId: table.id, targetTableId: targetTableId)
                            invalidatePreparedImport()
                            showExistingTables = false
                            acceptPreview(Self.buildImportPreview(result, targetTableId: targetTableId))
                        } catch { errorMsg = error.localizedDescription }
                    } label: {
                        Text(table.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colors.primary)
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .disabled(!canImport)
                    .accessibilityIdentifier("import_source_\(table.id)")
                }
                if let errorMsg {
                    Text(errorMsg)
                        .font(.system(size: 12))
                        .foregroundColor(colors.error)
                        .accessibilityIdentifier("import_source_error")
                }
            }
        }
    }

    private func dismissExistingTables() {
        errorMsg = nil
        showExistingTables = false
    }

    private func presentWakeUpShare(_ text: String) {
        invalidatePreparedImport()
        pendingWakeUpJSON = nil
        wakeUpShareText = text
        ImportSheet.dismissKeyboard()
        showWakeUpShare = true
    }

    /// 成功提示(← snackbar.showSnackbar(importSuccessMessage)), 2.5s 自动消失由 overlay onAppear 管。
    /// onImported 由 applyImportPreview / applyPurePeriodImport 内部调用(同位)。
    private func showSuccess(_ msg: String) {
        withAnimation { successMsg = msg }
    }

    /// ← 原版本 LaunchedEffect 预填: 源名参与全局唯一名顺延(课程表∪作息表)
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

private enum ManualEditorSession: Identifiable {
    case newTable(id: Int64, fallbackId: Int64?)
    case course(targetTableId: Int64)

    var id: String {
        switch self {
        case .newTable(let id, _): return "table:\(id)"
        case .course(let targetTableId): return "course:\(targetTableId)"
        }
    }
}

// Identifiable 包装(sheet(item:) 需要)
// id 从解析后的预览实例读取，不能在 get 闭包里重新生成。
//   .sheet(item:) 的 get 闭包在每次父视图重绘时都会重新求值, 若 id 每次都是新的
//   UUID, SwiftUI 会认为"换了一个 item" → 旧 sheet 关闭 + 新 sheet 重新弹出。
//   点"导入模式"时父状态(pendingMode)一变就触发重绘 → 预览 sheet 被重新呈现,
//   呈现动画中容器停在起始位置(y=874), 模式按钮 frame 落到屏幕外
//   (y=1450…1594), XCUITest 报 "Activation point invalid"(ManageImportUITests
//   testFullTextImportFlow 失败)。稳定 id ⇒ 编辑只更新内容；新文档有独立 id，
//   即使名称、日期、课程数相同，也必须替换旧预览。
private struct PreviewBox: Identifiable {
    let preview: ImportPreview
    var id: UUID { preview.id }
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
                Group {
                    if id == "import_manual" {
                        AndroidMaterialIcon(name: .add, size: 20)
                    } else if id == "import_existing" {
                        AndroidSettingsIcon(name: .contentCopy, size: 20)
                    } else if id == "import_jw" {
                        AndroidSettingsIcon(name: .qrCode2, size: 20)
                    } else if id == "import_text" {
                        AndroidSettingsIcon(name: .description, size: 20)
                    } else if id == "import_file" {
                        AndroidSettingsIcon(name: .fileUpload, size: 20)
                    } else {
                        Image(systemName: icon).font(.system(size: 20))
                    }
                }
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 40, height: 40)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.medium)
                Text(label)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(colors.onSurface)
                Spacer()
                if let trailing = trailing {
                    Group {
                        if trailing == "chevron.up" || trailing == "chevron.down" {
                            AndroidSettingsIcon(name: trailing == "chevron.up" ? .expandLess : .expandMore, size: 24)
                        } else {
                            Image(systemName: trailing).font(.system(size: 24))
                        }
                    }   // ← 原 无显式 size = 默认 24dp
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
    @Environment(\.sleepyUIStyle) private var style
    let id: String
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
                .frame(maxWidth: .infinity, alignment: .leading)   // ← 原 weight(1f)
            if let onDetail {
                Button(action: onDetail) {
                    AndroidSettingsIcon(name: .info, size: 20)   // ← Android 1.0.64 Info 20dp
                        .foregroundColor(colors.onSurfaceVariant)
                        .frame(width: style == .classic ? 48 : nil,
                               height: style == .classic ? 48 : nil)
                }
                .buttonStyle(SleepyPlatformButtonStyle(shape: .circle))
                .frame(width: 48, height: 48)
                .padding(.leading, 6)   // ← 原 icon padding(start = 6.dp)
                .accessibilityLabel(L10n.format("format_detail_content_desc"))
                .accessibilityIdentifier(id)
            }
        }
        .padding(.vertical, 3)
    }
}

// ← FormatDetailDialog(格式详情弹窗: 什么时候用 + 识别要求 + 示例; 纯文本独有 AI Prompt)
private struct FormatDetailDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let format: ImportFormatKey
    let onDismiss: () -> Void
    @State private var copiedPrompt = false

    var body: some View {
        CenteredPickerDialog(title: L10n.format("format_\(format.l10nKey)"), maxContentHeight: 440,
                             onDismiss: onDismiss, footer: AnyView(
            Button(action: onDismiss) {
                Text(L10n.format("format_help_close"))
                    .foregroundColor(style == .liquidGlass ? colors.onPrimary : colors.primary)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(SleepyPlatformButtonStyle(prominent: true))
            .tint(colors.primary)
            .accessibilityIdentifier("format_help_close")
        )) {
            VStack(alignment: .leading, spacing: 16) {
                    Text(format.whenText)
                        .font(.system(size: 14))
                        .foregroundColor(colors.onSurfaceVariant)
                        .accessibilityIdentifier("format_help_when")
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.format("format_help_spec")).font(SleepyTypography.titleSmall)
                    ForEach(format.specItems, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .font(.system(size: 12))
                                .foregroundColor(colors.primary)
                                .padding(.top, 2)
                            Text(item)
                                .font(.system(size: 12)) // ← 原 bodySmall 12
                                .foregroundColor(colors.onSurface)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.format("format_help_example")).font(SleepyTypography.titleSmall)
                    Text(format.exampleText)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(colors.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(colors.surfaceContainer).cornerRadius(12)
                }
                if format == .plain {
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
                                    AndroidSettingsIcon(name: .contentCopy, size: 16)   // ← 原 ContentCopy 16dp
                                    Text(copiedPrompt ? L10n.format("copied") : L10n.format("copy_prompt"))
                                        .font(.system(size: 14, weight: .medium))   // ← labelLarge 14sp Medium
                                }
                                .foregroundColor(colors.onPrimaryContainer)
                                .frame(maxWidth: .infinity)
                                .frame(height: style == .classic ? 48 : nil)
                                .sleepyControlSurface(cornerRadius: 24, tint: colors.primaryContainer)
                            }
                            .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: 24))
                            .tint(colors.primaryContainer)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .accessibilityIdentifier("import_copy_prompt")
                        }
                        .padding(12).background(colors.primaryContainer).cornerRadius(12)
                }
            }
            .foregroundColor(colors.onSurface)
        }
        .accessibilityIdentifier("format_help_dialog")
    }
}

// Preview details scroll independently from the import choices.
struct ImportPreviewDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let preview: ImportPreview
    var courseDecision = false
    var isApplying = false
    var onCourseApply: (CourseImportDecision) -> Void = { _ in }
    @State private var decision = CourseImportDecision()
    var showConfirm: Bool = false
    var onConfirmDismiss: () -> Void = {}
    var confirmContent: () -> AnyView = { AnyView(EmptyView()) }
    let onDismiss: () -> Void
    let onApply: (ImportApplyMode) -> Void

    var body: some View {
        ZStack {
            CenteredPickerDialog(title: L10n.format("import_preview_title"), titleIdentifier: "import_preview_title", maxContentHeight: 440,
                                 onDismiss: { if !isApplying { onDismiss() } },
                                 footer: AnyView(previewActions.disabled(isApplying))) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(preview.targetTableId == 0
                         ? L10n.format("import_new_table_hint")
                         : L10n.format("import_target_table", preview.targetTableName))
                        .font(.system(size: 12))
                        .foregroundColor(preview.targetTableId == 0 ? colors.primary : colors.onSurfaceVariant)
                    HStack(spacing: 8) {
                        PreviewMetricCard(label: L10n.format("import_courses"), value: "\(preview.incomingCount)",
                                          bg: colors.primaryContainer, fg: colors.onPrimaryContainer)
                        if preview.targetTableId != 0 {
                            PreviewMetricCard(label: L10n.format("import_conflicts"), value: "\(preview.conflictCount)",
                                              bg: preview.conflictCount > 0 ? colors.errorContainer : colors.secondaryContainer,
                                              fg: preview.conflictCount > 0 ? colors.onErrorContainer : colors.onSecondaryContainer)
                            PreviewMetricCard(label: L10n.format("import_appendable"), value: "\(preview.cleanCount)",
                                              bg: colors.tertiaryContainer, fg: colors.onTertiaryContainer)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PreviewInfoRow(label: L10n.format("import_table_name"), value: preview.parseResult.tableName)
                        PreviewInfoRow(label: L10n.format("import_start_date"), value: preview.parseResult.startDate)
                        if preview.targetTableId != 0 {
                            PreviewInfoRow(label: L10n.format("import_suggestion"),
                                           value: preview.conflictCount == 0 ? L10n.format("import_no_conflict")
                                               : L10n.format("import_conflict_count", preview.conflictCount))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12).background(colors.surfaceContainer).cornerRadius(SleepyShapes.large)
                    if !preview.multiLocationWarnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.format("import_multi_location_warning")).font(.system(size: 14, weight: .medium))
                            ForEach(preview.multiLocationWarnings.prefix(5), id: \.self) { Text("• \($0)").font(.system(size: 12)) }
                            if preview.multiLocationWarnings.count > 5 {
                                Text(L10n.format("more_unexpanded", preview.multiLocationWarnings.count - 5)).font(.system(size: 11))
                            }
                        }
                        .foregroundColor(colors.onSecondaryContainer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(colors.secondaryContainer).cornerRadius(SleepyShapes.large)
                    }
                    if !preview.conflicts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.format("import_conflicts")).font(.system(size: 14, weight: .medium))
                            ForEach(preview.conflicts.prefix(3)) { conflict in
                                Text("• \(conflict.incoming.courseName) ↔ \(conflict.existing.courseName)（\(DateUtils.localizedDay(conflict.incoming.day)) \(conflict.incoming.nodeString(isShort: true))）")
                                    .font(.system(size: 12))
                            }
                            if preview.conflicts.count > 3 {
                                Text(L10n.format("import_conflict_more", preview.conflicts.count - 3)).font(.system(size: 11))
                            }
                        }
                        .foregroundColor(colors.onSurfaceVariant)
                    }
                    if !preview.parseResult.droppedLines.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.format("import_dropped_title", preview.parseResult.droppedLines.count)).font(.system(size: 14, weight: .medium))
                            Text(L10n.format("import_dropped_hint")).font(.system(size: 12))
                            ForEach(preview.parseResult.droppedLines.prefix(3), id: \.self) {
                                Text("• \($0)").font(.system(size: 12, design: .monospaced))
                            }
                            if preview.parseResult.droppedLines.count > 3 {
                                Text(L10n.format("import_conflict_more", preview.parseResult.droppedLines.count - 3)).font(.system(size: 11))
                            }
                        }
                        .foregroundColor(colors.onErrorContainer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(colors.errorContainer).cornerRadius(SleepyShapes.large)
                    }
                    if !preview.parseResult.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.format("import_warnings_title")).font(.system(size: 14, weight: .medium))
                            ForEach(preview.parseResult.warnings.prefix(4), id: \.self) { Text("• \($0)").font(.system(size: 12)) }
                            if preview.parseResult.warnings.count > 4 {
                                Text(L10n.format("import_conflict_more", preview.parseResult.warnings.count - 4)).font(.system(size: 11))
                            }
                        }
                        .foregroundColor(colors.onSecondaryContainer)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(colors.secondaryContainer).cornerRadius(SleepyShapes.large)
                    }
                }
            }
            .accessibilityHidden(showConfirm)
            .allowsHitTesting(!showConfirm)
            if showConfirm {
                confirmContent()
                    .accessibilityIdentifier("import_confirm_overlay")
            }
        }
    }

    private var previewActions: some View {
        VStack(spacing: 12) {
            if courseDecision {
                Toggle(isOn: $decision.backupOriginal) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.format("import_backup_original")).font(.system(size: 16))
                        Text(L10n.format("import_backup_original_sub")).font(.system(size: 12)).foregroundColor(colors.onSurfaceVariant)
                    }
                }
                .toggleStyle(SleepyToggleStyle(showsLabel: true)).tint(colors.primary)
                .accessibilityIdentifier("import_preview_backup")
                Toggle(isOn: $decision.appendConflicts) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.format("import_append_conflicts_option")).font(.system(size: 16))
                        Text(L10n.format("import_append_conflicts_option_sub")).font(.system(size: 12)).foregroundColor(colors.onSurfaceVariant)
                    }
                }
                .toggleStyle(SleepyToggleStyle(showsLabel: true)).tint(colors.primary)
                .accessibilityIdentifier("import_preview_append")
                HStack(spacing: 8) {
                    cancelButton
                    PrimaryDialogButton(L10n.format("import_confirm"), identifier: "import_preview_apply") {
                        onCourseApply(decision)
                    }
                }
            } else {
        HStack(spacing: 8) {
            if preview.targetTableId == 0 {
                PrimaryDialogButton(L10n.format("import_as_new"), identifier: "import_mode_as_new") {
                    onApply(.importAsNew)
                }
            } else {
                PrimaryDialogButton(L10n.format("import_append_only"), identifier: "import_mode_append_only") {
                    onApply(.appendNonConflict)
                }
                PrimaryDialogButton(L10n.format("import_as_new"), identifier: "import_mode_as_new") {
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
                        .lineLimit(1)   // ← 原 maxLines = 1
                        .foregroundColor(colors.onErrorContainer)
                        .frame(maxWidth: .infinity)
                        .frame(height: style == .liquidGlass ? nil : 40)
                        .sleepyControlSurface(cornerRadius: SleepyShapes.medium, tint: colors.errorContainer, prominent: true)
                }
                .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.medium))
                .frame(maxWidth: .infinity, minHeight: style == .liquidGlass ? 44 : nil)
                .tint(colors.errorContainer)
                .accessibilityIdentifier("import_mode_append_conflict")
                PrimaryDialogButton(L10n.format("import_append_as_new"), identifier: "import_mode_append_as_new") {
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
                    .frame(height: style == .liquidGlass ? nil : 40)
                    .sleepyControlSurface(cornerRadius: SleepyShapes.medium, tint: colors.errorContainer, prominent: true)
            }
            .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.medium))
            .frame(maxWidth: .infinity, minHeight: style == .liquidGlass ? 44 : nil)
            .tint(colors.errorContainer)
            .accessibilityIdentifier("import_mode_overwrite")
        }
                cancelButton
            }
        }
        .foregroundColor(colors.onSurface)
    }

    private var cancelButton: some View {
        Button(action: onDismiss) {
            Text(L10n.format("cancel"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity)
                .frame(height: style == .classic ? 40 : nil)
        }
        .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: SleepyShapes.medium))
        .frame(maxWidth: .infinity, minHeight: style == .liquidGlass ? 44 : nil)
        .accessibilityIdentifier("import_preview_cancel")
    }
}

extension CourseConflict: Identifiable {
    var id: String { "\(incoming.id)-\(existing.id)" }
}

private struct PrimaryDialogButton: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var style
    let title: String
    var identifier: String? = nil
    let action: () -> Void

    init(_ title: String, identifier: String? = nil, _ action: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.onPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: style == .liquidGlass ? nil : 40)
                .sleepyControlSurface(cornerRadius: SleepyShapes.medium, tint: colors.primary, prominent: true)
        }
        .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.medium))
        .frame(maxWidth: .infinity, minHeight: style == .liquidGlass ? 44 : nil)
        .tint(colors.primary)
        // 稳定标识: 预览底部按钮浮在 List 之上, XCUITest 按 label 找元素时偶发拿到
        // 无效 frame({inf, inf}/{0.0,0.0}) → "Failed to compute hit point"。给显式
        // identifier 后 UI 测试可按 id 精确定位, 不依赖本地化文案。
        .modifier(PrimaryDialogButtonIdentifier(identifier: identifier))
    }
}

/// 仅在 identifier 非空时挂 accessibilityIdentifier(空串会被 UIKit 当成有效 id, 反而误命中)
private struct PrimaryDialogButtonIdentifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier, !identifier.isEmpty {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
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
    var courses: [CourseEntity] = []
    var droppedLines: [String] = []
    var warnings: [String] = []
    var isApplying = false
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
    @State private var usedDefaultTimes = false
    @State private var localError: String? = nil
    // issue#28 P2: 自动模式状态必须真实持有并回传 — 旧代码没传 smartConfig/
    // onSmartConfigChange, 落到默认 no-op, "添加课间"点了没有任何反应。
    // issue#23 T5: 初值 = 共享推断从导入解析出的行播种(45 分钟主时长 + 混合时长组
    // 一并识别, 与 EditTableScreen/PeriodTableEditScreen 同规); 行不可推断
    // (缺时间/畸形/断号) → 最简默认兜底, TimeSlotEditor 保持手动模式 + 既有校验。
    @State private var smartConfig = SmartPeriodConfig()

    var body: some View {
        CenteredPickerDialog(title: L10n.format("import_confirm_title"), titleIdentifier: "import_confirm_title", maxContentHeight: 560,
                             onDismiss: { if !isApplying { onDismiss() } },
                             footer: AnyView(DialogActionButtons(
                                confirmText: L10n.format("import_confirm"),
                                onConfirm: validateAndConfirm,
                                dismissText: L10n.format("back"),
                                onDismiss: { if !isApplying { onDismiss() } },
                                confirmEnabled: !isApplying,
                                confirmIdentifier: "import_dialog_confirm",
                                dismissIdentifier: "import_dialog_back"))) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.format("export_course_count", courses.count))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurface)
                    .accessibilityIdentifier("import_confirm_course_count")
                if !droppedLines.isEmpty {
                    Text(L10n.format("import_dropped_title", droppedLines.count))
                        .font(.system(size: 14)).foregroundColor(colors.error)
                        .accessibilityIdentifier("import_confirm_dropped")
                    ForEach(droppedLines.prefix(3), id: \.self) {
                        Text($0).font(.system(size: 12)).foregroundColor(colors.onSurfaceVariant)
                    }
                }
                ForEach(warnings, id: \.self) {
                    Text($0).font(.system(size: 12)).foregroundColor(colors.onSurfaceVariant)
                }
                Text(L10n.format("import_confirm_body"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)

                if showTableName {
                    FieldTextField(text: $tableName, label: L10n.format("import_table_name"))
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

                if rowsLoaded {
                    ScrollView {
                    TimeSlotEditor(rows: $rows, onRowsChange: { newRows in
                        rows = newRows
                        onTimeJsonChange(TimeTableUtils.buildTimeJsonFromRows(newRows))
                    }, usedDefaultTimes: usedDefaultTimes, smartConfig: smartConfig, onSmartConfigChange: { smartConfig = $0 },
                       // v1.0.56 T6: 第三 Tab「作息表」
                       periodTableOptions: periodTableOptions,
                       selectedPeriodTableId: selectedPeriodTableId,
                       onSelectPeriodTable: onSelectPeriodTable)
                    }
                    .frame(height: 320)
                    .accessibilityIdentifier("import_confirm_periods_scroll")
                } else {
                    ProgressView()
                }
            }
            .disabled(isApplying)
        }
        .onAppear {
            guard !rowsLoaded else { return }
            let initialized = TimeTableUtils.initialManualRows(timeJson: timeJson)
            rows = initialized.rows
            usedDefaultTimes = initialized.usedDefaults || timeJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            timeJson = TimeTableUtils.buildTimeJsonFromRows(rows)
            onTimeJsonChange(timeJson)
            // issue#28 P2 + issue#23 T5 播种: 与 原 remember { resolveAutoPeriodConfig
            // (rows, null) ?: SmartPeriodConfig(totalPeriods=max(1,rows), startTime=首行或"08:00") } 同规
            smartConfig = resolveAutoPeriodConfig(rows: rows, stored: nil)
                ?? SmartPeriodConfig(
                    startTime: {
                        let s = rows.first?.start ?? ""
                        return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "08:00" : s
                    }(),
                    totalPeriods: max(rows.count, 1))
            rowsLoaded = true
        }
    }

    // ← confirmButton 内校验链: 空日期/格式/空时间/非法时间
    private func validateAndConfirm() {
        guard !isApplying else { return }
        if startDate.trimmingCharacters(in: .whitespaces).isEmpty {
            localError = L10n.format("import_start_date_required")
            return
        }
        let dateRegex = "^\\d{4}-\\d{2}-\\d{2}$"
        if startDate.range(of: dateRegex, options: .regularExpression) == nil ||
            DateUtils.parseDate(startDate).map({ DateUtils.fullDate($0) != startDate }) != false {
            localError = L10n.format("start_date_format")
            return
        }
        // v1.0.56 T6 修正: 绑了作息表(id>0)时以表的 timeJson 为真源;
        // 旧代码无条件校验手动 rows, 解析源没回节次时间 → 误报「第 X 节时间不能为空」(用户反馈 2026-09-20)
        if let id = selectedPeriodTableId, id > 0,
           let boundJson = periodTableTimeJsonById[id] {
            if TimeTableUtils.strictPeriodRows(boundJson) == nil {
                localError = TimeTableUtils.PeriodValidationResult.invalidData.errorMessage
                return
            }
        }
        let effectiveRows = Self.effectiveRowsForConfirm(
            manualRows: rows, bindId: selectedPeriodTableId, tables: periodTableTimeJsonById)
        if let missing = TimeTableUtils.firstMissingCourseNode(courses: courses, rows: effectiveRows) {
            localError = L10n.format("slot_time_required", missing)
            return
        }
        let emptyRows = effectiveRows.filter { $0.start.isBlank || $0.end.isBlank }
        if let first = emptyRows.first {
            localError = L10n.format("slot_time_required", first.node)
            return
        }
        let validation = CourseImportPolicy.validateConfirmationRows(effectiveRows)
        if validation != .valid {
            localError = validation.errorMessage
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

// ← v1.0.56 T9 纯作息导入命名确认框(行436-508)
// courses.isEmpty && periodTable != nil 时替代 ImportPreviewDialog: 预填全局唯一名
// (课程表∪作息表, 后缀 2/3 预览即可见), 查重红标, 确认只建作息表不建空课表。
private struct PurePeriodImportDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let parsed: ScheduleParser.ParsedPeriodTable
    /// 预填唯一名 = 源名参与全局唯一名顺延; ← 原版本 LaunchedEffect(currentPreview) 一次性播种
    let suggestUniqueName: () -> String
    let courseTableNames: [String]
    let periodTableNames: [String]
    var isApplying = false
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
        CenteredPickerDialog(title: L10n.format("period_table_import_title"),
                             titleIdentifier: "import_pure_period_title",
                             onDismiss: { if !isApplying { onDismiss() } },
                             footer: AnyView(DialogActionButtons(
                                confirmText: L10n.format("period_table_import_confirm"),
                                onConfirm: { if !isApplying { onConfirm(candidate) } },
                                dismissText: L10n.format("cancel"),
                                onDismiss: { if !isApplying { onDismiss() } },
                                confirmEnabled: !isApplying && !candidate.isEmpty && !nameTaken,
                                confirmIdentifier: "import_pure_period_confirm",
                                dismissIdentifier: "import_pure_period_dismiss"))) {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.format("period_table_import_body"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)
                VStack(alignment: .leading, spacing: 4) {
                    FieldTextField(text: $name, label: L10n.format("period_table_name_label"))
                        .overlay(RoundedRectangle(cornerRadius: SleepyTheme.fieldShape)
                            .strokeBorder(nameTaken ? colors.error : Color.clear, lineWidth: 1))
                        .accessibilityIdentifier("import_pure_period_field")
                    if nameTaken {
                        Text(L10n.format("period_table_name_taken"))
                            .font(.system(size: 12))
                            .foregroundColor(colors.error)
                    }
                }
            }
            .disabled(isApplying)
        }
        .onAppear {
            // ← 原版本 LaunchedEffect(currentPreview): 每个预览对象播一次预填名
            guard !seeded else { return }
            seeded = true
            name = suggestUniqueName()
        }
    }
}

// ==================== 业务逻辑(buildImportPreview / applyImportPreview / conflict) ====================

extension ImportSheet {

    /// 强制收走系统键盘(与 DateTimePickers 的做法同款)。
    /// 弹预览 sheet 前必须调用:粘贴框仍是 first responder 时键盘不收,
    /// UIKit 会把预览 sheet 的内容容器整体下移到屏幕之外。
    static func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    static func effectiveTargetTable(_ tableId: Int64, repository: ScheduleRepository? = nil) -> TimeTableEntity? {
        let repo = repository ?? ScheduleRepository(AppDatabase.getShared())
        return try? AddCoursesImport.target(repository: repo, tableId: tableId)
    }

    static func buildImportPreview(
        _ text: String,
        _ state: ScheduleState,
        targetTableId: Int64? = nil,
        repository: ScheduleRepository? = nil,
        onError: (String) -> Void
    ) -> ImportPreview? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            onError(L10n.format("import_content_empty")); return nil
        }
        let tableId = targetTableId ?? state.selectedTableId ?? 0
        switch ScheduleParser.parse(text, defaultTableId: tableId) {
        case .success(let result):
            return buildImportPreview(result, targetTableId: tableId, repository: repository)
        case .failure(let error):
            onError(L10n.format("import_failed", error.localizedDescription)); return nil
        }
    }

    static func buildImportPreview(
        _ parseResult: ScheduleParser.ParseResult,
        targetTableId: Int64,
        repository: ScheduleRepository? = nil,
        sourceDraftId: String? = nil
    ) -> ImportPreview? {
        let repo = repository ?? ScheduleRepository(AppDatabase.getShared())
        let existingTable = effectiveTargetTable(targetTableId, repository: repo)
        let existingCourses = targetTableId == 0 ? [] : ((try? repo.getCourses(targetTableId)) ?? [])
        let effectiveTimeJson = CourseImportPolicy.timeJsonForAppend(current: existingTable?.timeJson ?? "",
            incoming: parseResult.timeJson, requiredNodes: max(parseResult.nodesPerDay,
                parseResult.courses.map { $0.startNode + $0.step - 1 }.max() ?? 0),
            bound: existingTable?.periodTableId != nil)
        let conflicts = parseResult.courses.compactMap { incoming in
            existingCourses.first { CourseImportPolicy.conflicts(incoming, $0, timeJson: effectiveTimeJson) }
                .map { CourseConflict(incoming: incoming, existing: $0) }
        }
        let warnings = Dictionary(grouping: parseResult.courses, by: \.groupId).compactMap { group, rows -> String? in
            guard !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            let rooms = Set(rows.map { $0.room.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
            return rooms.count >= 2 ? L10n.format("import_multi_location_warning_detail", rows[0].courseName, rooms.count) : nil
        }
        return ImportPreview(targetTableId: targetTableId,
            targetTableName: existingTable?.name ?? L10n.format("manage_current_table"), parseResult: parseResult,
            existingCourses: existingCourses, conflicts: conflicts, multiLocationWarnings: warnings,
            effectiveTimeJson: effectiveTimeJson, sourceDraftId: sourceDraftId)
    }

    @discardableResult
    static func applyCourseImport(preview: ImportPreview, decision: CourseImportDecision,
                                  onImported: () -> Void, onError: (String) -> Void,
                                  repository: ScheduleRepository? = nil) -> Int64? {
        let repo = repository ?? ScheduleRepository(AppDatabase.getShared())
        do {
            try AddCoursesImport.validate(preview.parseResult)
            let count = try repo.appendImportedCoursesWithBackup(preview.targetTableId, courses: preview.parseResult.courses,
                incomingTimeJson: preview.parseResult.timeJson, requiredNodeCount: preview.parseResult.nodesPerDay,
                keepGroups: preview.parseResult.groupIdsAuthoritative, backupOriginal: decision.backupOriginal,
                appendConflicts: decision.appendConflicts)
            guard count > 0 else { onError(L10n.format("import_all_conflict")); return nil }
            onImported()
            return preview.targetTableId
        } catch { onError(L10n.format("read_failed", error.localizedDescription)); return nil }
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
        bindPeriodTableId: Int64? = nil,
        repository: ScheduleRepository? = nil
    ) -> Int64? {
        let repo = repository ?? ScheduleRepository(AppDatabase.getShared())
        // v7.10.16 撤回: 整个导入是一个动作 — 批内只保首快照, 撤回一次回退到导入前。
        // defer 收口(↔ 原版本 try/finally): 分支里的 early return 也要退出批边界。
        UndoManager.shared.beginBatch()
        defer { UndoManager.shared.endBatch() }
        // 应用约定 startDate=周一；用户在确认框可能手填非周一日期，落库前归一（issue #5）
        let confirmedStartDate = normalizeStartDate(confirmedStartDateRaw)
        do {
        switch mode {
        case .replaceCurrent:
            let name = confirmedTableName.trimmingCharacters(in: .whitespacesAndNewlines)
            try repo.replaceImportedTable(preview.targetTableId,
                name: name.isEmpty ? preview.parseResult.tableName : name,
                startDate: confirmedStartDate, maxWeek: preview.parseResult.maxWeek,
                nodesPerDay: preview.parseResult.nodesPerDay, timeJson: confirmedTimeJson,
                courses: preview.parseResult.courses, keepGroups: preview.parseResult.groupIdsAuthoritative)
            let badDays = ConflictLayoutEngine.daysExceedingTwoLanes(preview.parseResult.courses)
            if !badDays.isEmpty { onError(L10n.format("import_three_layers_kept", dayNames(badDays))) }
            onImported()
            return preview.targetTableId
        case .importAsNew:
            let base = try repo.getTable(preview.targetTableId)
            // issue#40 §6: 新格式带 P 区块 → 建 period_tables 并绑定(恢复共享关系);
            // v1.0.62 B7b 用户 2026-10-05(2a): 无 P 区块(旧格式/粘贴文本)不再"不建" — 恒以确认页
            // 最终 confirmedTimeJson 兜底建表并绑定, 三个入口作息表行为统一。
            // v1.0.56 T6: 用户在第三 Tab 显式选了作息表 → 绑定用户所选(优先于自动建表绑定);
            // v1.0.56 T10: 自动建表走全局唯一名顺延(撞名加后缀, 禁与既有课表/作息表同名)
            let courseNames = try repo.getAllTables().map { $0.name }
            let periodNames = try repo.getAllPeriodTables().map { $0.name }
            // ← 原版本 importedPeriodTableDraft: 选中既有作息表则共享, 否则确认行 owns 新表
            let importedPeriod = importedPeriodTableDraft(
                bindingId: bindPeriodTableId,
                name: TimeTableUtils.suggestUniqueName(
                    preview.parseResult.periodTable?.name ?? confirmedTableName.trimmingCharacters(in: .whitespacesAndNewlines),
                    courseTableNames: courseNames,
                    periodTableNames: periodNames,
                    defaultName: preview.parseResult.tableName),
                confirmedTimeJson: confirmedTimeJson)
            // v1.0.62 B7b ← repo.importNewTable: 表+作息表+课程+默认切换单事务原子提交
            let newTableId = try repo.importNewTable(
                table: TimeTableEntity(
                    name: uniqueImportedTableName(confirmedTableName, courseNames),
                    startDate: confirmedStartDate,
                    maxWeek: preview.parseResult.maxWeek > 0 ? preview.parseResult.maxWeek : (base?.maxWeek ?? 20),
                    nodesPerDay: max(TimeTableUtils.parseTimeSlotRows(confirmedTimeJson).count, 1),
                    timeJson: confirmedTimeJson,
                    color: base?.color ?? "#FF6750A4",
                    isDefault: false, importSourceJson: preview.parseResult.importSourceJson),
                courses: preview.parseResult.courses,
                periodTable: importedPeriod,
                bindPeriodTableId: bindPeriodTableId,
                keepGroups: preview.parseResult.groupIdsAuthoritative)
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
            try repo.appendImportedCourses(preview.targetTableId, courses: courses,
                incomingTimeJson: preview.parseResult.timeJson,
                requiredNodeCount: preview.parseResult.nodesPerDay,
                keepGroups: preview.parseResult.groupIdsAuthoritative)
            onImported()
            return preview.targetTableId
        case .appendAsNew:
            // 当前课表 + 导入数据合并 → 新课表(用户命名)
            let base = try repo.getTable(preview.targetTableId)
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
            // v1.0.62 B7b 用户 2026-10-05(2a): 合并新建课表同样恒建+绑作息表(以 mergedTimeJson 为源)。
            let courseNames = try repo.getAllTables().map { $0.name }
            let periodNames = try repo.getAllPeriodTables().map { $0.name }
            let mergedName = uniqueImportedTableName(confirmedTableName, courseNames)
            let mergedPeriod = PeriodTableEntity(
                name: TimeTableUtils.suggestUniqueName(
                    mergedName, courseTableNames: courseNames, periodTableNames: periodNames),
                nodesPerDay: max(mergedRows.count, 1),
                timeJson: mergedTimeJson)
            // 当前课表原课 + 导入课程合并导入新课表
            // v7.10.16i: 老课全量保留。v7.10.16j(用户 2026-09-03「新课表=纯老表复制」):
            // 三层闸门改为**只拦新增冲突** — 候选违规判定只看新增候选本身是否比原表
            // 多出新层(before/after 对比); 原表已有超层不再连坐, 冲突课不进新课表(防重复入库)。
            let cleanIncoming = incoming.courses.filter { inc in
                !preview.existingCourses.contains { existing in Self.coursesConflict(inc, existing) }
            }
            let oldCourses: [CourseEntity]
            if let b = base {
                oldCourses = try repo.getCourses(b.id)
            } else {
                oldCourses = []
            }
            let beforeDays = ConflictLayoutEngine.daysExceedingTwoLanes(oldCourses)
            let afterDays = ConflictLayoutEngine.daysExceedingTwoLanes(oldCourses + cleanIncoming)
            if afterDays != beforeDays {
                let droppedDays = afterDays.subtracting(beforeDays)
                onError(L10n.format("import_three_layers_kept", dayNames(droppedDays)))
            }
            // 全量合并入库: 老课 + 全部非重复导入课(仅提示, 不再剔除 — 闸门只拦编辑恶化,
            // 合并是新建课表, 用户明确要的就是并集)
            // AppendAsNew 合并新老课: 导入侧 groupId 权威时仅对导入课保组, 老课照原样保组
            // v1.0.62 B7b ← repo.importNewTable: 表+作息表+课程+默认切换单事务原子提交
            // (id/tableId 重置在 importNewTable 内统一做, 调用方不再自行拷贝)
            let newTableId = try repo.importNewTable(
                table: TimeTableEntity(
                    name: mergedName,
                    startDate: confirmedStartDate,
                    maxWeek: incoming.maxWeek > 0 ? incoming.maxWeek : (base?.maxWeek ?? 20),
                    nodesPerDay: max(mergedRows.count, 1),
                    timeJson: mergedTimeJson,
                    color: base?.color ?? "#FF6750A4",
                    isDefault: false, importSourceJson: incoming.importSourceJson),
                courses: oldCourses + cleanIncoming,
                periodTable: mergedPeriod,
                keepGroups: preview.parseResult.groupIdsAuthoritative)
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
            try repo.appendImportedCourses(preview.targetTableId, courses: courses,
                incomingTimeJson: preview.parseResult.timeJson,
                requiredNodeCount: preview.parseResult.nodesPerDay,
                keepGroups: preview.parseResult.groupIdsAuthoritative)
            onImported()
            return preview.targetTableId
        }
        } catch {
            onError(L10n.format("import_failed", error.localizedDescription))
            return nil
        }
    }

    // ← v1.0.56 T9 纯作息导入: 只建一张作息表, 不建空课表。
    // 名字已由确认框查重; 落库前再走 suggestUniqueName 兜底(同屏并发导入等边缘)。
    @discardableResult
    static func applyPurePeriodImport(
        name: String,
        parsed: ScheduleParser.ParsedPeriodTable,
        repository: ScheduleRepository? = nil,
        onImported: () -> Void,
        onError: (String) -> Void
    ) -> Bool {
        let repo = repository ?? ScheduleRepository(AppDatabase.getShared())
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
            return false
        }
        onImported()
        return true
    }

    /// v7.10.16k 节次无损延伸(行1644-1664/1741-1760): 插课后把老表作息∪导入作息
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

    /// 被剔除课所在 day 的本地化名(dayNames: " / " join)
    static func dayNames(_ days: Set<Int>) -> String {
        days.sorted().map { DateUtils.localizedDay($0) }.joined(separator: " / ")
    }

    // ← coursesConflict: 同日 + 周次区间重叠 + 节次区间重叠
    // nonisolated: 纯函数(只读 CourseEntity 值字段), 原版本 无线程约束 —
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
