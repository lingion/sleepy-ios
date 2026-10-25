// ManagementPage.swift — ← ui/screen/manage/ManagementPage.kt
// 课表管理页: 当前课表摘要卡 + 6 管理卡(导入/新建课表/新建作息表/手动添加/编辑/导出) + ImportSheet。

import SwiftUI

struct ManagementPage: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    @ObservedObject var viewModel: ScheduleViewModel
    var autoShowImportSheet: Bool = false
    let onJwImportRequested: () -> Void
    let onCreateNewTableRequested: () -> Void
    let onManualAdd: () -> Void
    let onEditCurrentTable: () -> Void
    var onExportRequested: () -> Void = {}
    var onImported: () -> Void = {}
    // 2026-09-21 用户令: 点当前课表大卡 → 跳「所有课表」页(← Android onOpenAllTables)
    var onOpenAllTables: () -> Void = {}
    // v1.0.56 T7: 新建作息表 — 内部建表(自动命名+全局唯一)落库后回调新 id, 调用方进其编辑页
    var onCreateNewPeriodTableRequested: (Int64) -> Void = { _ in }
    // ← Android drafts/onRestoreDraft/onDeleteDraft(默认空 = 零行为变化)
    var drafts: [ImportDraftRowModel] = []
    var onRestoreDraft: (String) -> Void = { _ in }
    var onDeleteDraft: (String) -> Void = { _ in }

    @State private var showImportSheet: Bool

    init(viewModel: ScheduleViewModel,
         autoShowImportSheet: Bool = false,
         onJwImportRequested: @escaping () -> Void,
         onCreateNewTableRequested: @escaping () -> Void,
         onManualAdd: @escaping () -> Void,
         onEditCurrentTable: @escaping () -> Void,
         onExportRequested: @escaping () -> Void = {},
         onImported: @escaping () -> Void = {},
         onOpenAllTables: @escaping () -> Void = {},
         onCreateNewPeriodTableRequested: @escaping (Int64) -> Void = { _ in },
         drafts: [ImportDraftRowModel] = [],
         onRestoreDraft: @escaping (String) -> Void = { _ in },
         onDeleteDraft: @escaping (String) -> Void = { _ in }) {
        self.viewModel = viewModel
        self.autoShowImportSheet = autoShowImportSheet
        self.onJwImportRequested = onJwImportRequested
        self.onCreateNewTableRequested = onCreateNewTableRequested
        self.onManualAdd = onManualAdd
        self.onEditCurrentTable = onEditCurrentTable
        self.onExportRequested = onExportRequested
        self.onImported = onImported
        self.onOpenAllTables = onOpenAllTables
        self.onCreateNewPeriodTableRequested = onCreateNewPeriodTableRequested
        self.drafts = drafts
        self.onRestoreDraft = onRestoreDraft
        self.onDeleteDraft = onDeleteDraft
        _showImportSheet = State(initialValue: autoShowImportSheet)
    }

    var body: some View {
        let state = viewModel.state
        let table = state.currentTable
        ScrollView {
            VStack(spacing: 16) {
                Text(L10n.format("tab_manage"))
                    // ← Material 3 headlineMedium.copy(Medium) = 28sp/medium (ManagementPage.kt L82)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(colors.onBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("manage_page_title")

                // 当前课表摘要
                // 2026-09-21 用户令: 点整卡 → 跳「所有课表」页(← Android noRippleClickable(onOpenAllTables))
                if let table = table {
                    VStack(alignment: .leading, spacing: 8) {
                        // ← Android L114-126: Row[manage_current_table(weight 1f), manage_view_all_tables]
                        HStack(spacing: 0) {
                            Text(L10n.format("manage_current_table"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colors.primary)
                            Spacer()
                            Text(L10n.format("manage_view_all_tables"))
                                // ← labelMedium 12/medium
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        Text(table.name)
                            // ← Material 3 titleLarge.copy(SemiBold) = 22sp/semibold (ManagementPage.kt L129)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(colors.onSurface)
                        Text(L10n.format("table_info", table.startDate, state.currentWeek, state.courses.count))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surfaceContainer)
                    .cornerRadius(SleepyShapes.large)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenAllTables)
                    .accessibilityIdentifier("manage_current_table_card")
                }

                // 管理按钮(6 个: 导入 / 新建课表 / 新建作息表 / 手动添加 / 编辑 / 导出)
                VStack(spacing: 12) {
                    ManageCard(id: "manage_import", icon: "square.and.arrow.up",
                               title: L10n.format("manage_import"),
                               subtitle: L10n.format("manage_import_sub")) {
                        showImportSheet = true
                    }
                    ManageCard(id: "manage_new_table", icon: "sparkles",
                               title: L10n.format("manage_new_table"),
                               subtitle: L10n.format("manage_new_table_sub"),
                               onClick: onCreateNewTableRequested)
                    // v1.0.56 T7: 新建作息表 — 插在「新建课表」正下方(用户指定卡位, ← Android L158-173)
                    ManageCard(id: "manage_new_period_table", icon: "clock",
                               title: L10n.format("manage_new_period_table"),
                               subtitle: L10n.format("manage_new_period_table_sub")) {
                        // 建表(自动唯一命名, T2 suggestUniqueName)落库后回调新 id
                        let newId = viewModel.insertPeriodTableWithUniqueName(
                            name: "",
                            defaultName: L10n.format("period_table_new"))
                        if newId > 0 { onCreateNewPeriodTableRequested(newId) }
                    }
                    ManageCard(id: "manage_add_course", icon: "plus",
                               title: L10n.format("manage_manual_add"),
                               subtitle: L10n.format("manage_manual_add_sub"),
                               onClick: onManualAdd)
                    ManageCard(id: "manage_edit_current", icon: "pencil",
                               title: L10n.format("manage_edit_current"),
                               subtitle: L10n.format("manage_edit_current_sub"),
                               onClick: onEditCurrentTable)
                    ManageCard(id: "manage_export", icon: "square.and.arrow.up.on.square",
                               title: L10n.format("manage_export"),
                               subtitle: L10n.format("manage_export_sub"),
                               onClick: onExportRequested)
                }
            }
            .padding(16)
            // 悬浮底栏额外余量(→ Android LocalNavExtraBottomPadding): 镜像 Android
            //   padding(bottom = 16.dp + navExtra) 让列表最后一行不被悬浮药丸遮住。
            .padding(.bottom, navExtra)
        }
        .background(colors.background)
        .sheet(isPresented: $showImportSheet) {
            ImportSheet(
                viewModel: viewModel,
                onJwImportRequested: {
                    showImportSheet = false
                    onJwImportRequested()
                },
                onDismiss: { showImportSheet = false },
                onImported: onImported,
                drafts: drafts,
                onRestoreDraft: onRestoreDraft,
                onDeleteDraft: onDeleteDraft)

        }
    }
}

// ← ManageCard
private struct ManageCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundColor(colors.onPrimaryContainer)
                    .frame(width: 44, height: 44)
                    .background(colors.primaryContainer)
                    .cornerRadius(SleepyShapes.medium)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
            }
            .padding(16)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(id)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}
