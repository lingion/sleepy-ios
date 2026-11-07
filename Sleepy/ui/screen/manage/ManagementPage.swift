// ManagementPage.swift — ← ui/screen/manage/ManagementPage.kt
// 课表管理页：摘要编辑、独立全部课表入口和四个管理操作。

import SwiftUI

struct ManagementPage: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localCoursePalette) private var palette
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    @ObservedObject var viewModel: ScheduleViewModel
    var autoShowImportSheet: Bool = false
    let onCreateNewTableRequested: () -> Void
    let onManualAdd: () -> Void
    let onEditCurrentTable: () -> Void
    var onExportRequested: () -> Void = {}
    var onImported: () -> Void = {}
    // 2026-09-21 用户令: 点当前课表大卡 → 跳「所有课表」页(onOpenAllTables)
    var onOpenAllTables: () -> Void = {}
    var onOpenPeriodTables: () -> Void = {}
    // v1.0.56 T7: 新建作息表 — 内部建表(自动命名+全局唯一)落库后回调新 id, 调用方进其编辑页
    var onCreateNewPeriodTableRequested: (Int64) -> Void = { _ in }
    // 草稿列表/删除由宿主提供；恢复由导入方式页保留原入口后呈现。
    var drafts: [ImportDraftRowModel] = []
    var onDeleteDraft: (String) -> Void = { _ in }
    var onJwDismissed: () -> Void = {}

    @State private var showImportSheet: Bool
    @State private var createTableAfterDismiss = false

    init(viewModel: ScheduleViewModel,
         autoShowImportSheet: Bool = false,
         onCreateNewTableRequested: @escaping () -> Void,
         onManualAdd: @escaping () -> Void,
         onEditCurrentTable: @escaping () -> Void,
         onExportRequested: @escaping () -> Void = {},
         onImported: @escaping () -> Void = {},
         onOpenAllTables: @escaping () -> Void = {},
         onOpenPeriodTables: @escaping () -> Void = {},
         onCreateNewPeriodTableRequested: @escaping (Int64) -> Void = { _ in },
         drafts: [ImportDraftRowModel] = [],
         onDeleteDraft: @escaping (String) -> Void = { _ in },
         onJwDismissed: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.autoShowImportSheet = autoShowImportSheet
        self.onCreateNewTableRequested = onCreateNewTableRequested
        self.onManualAdd = onManualAdd
        self.onEditCurrentTable = onEditCurrentTable
        self.onExportRequested = onExportRequested
        self.onImported = onImported
        self.onOpenAllTables = onOpenAllTables
        self.onOpenPeriodTables = onOpenPeriodTables
        self.onCreateNewPeriodTableRequested = onCreateNewPeriodTableRequested
        self.drafts = drafts
        self.onDeleteDraft = onDeleteDraft
        self.onJwDismissed = onJwDismissed
        _showImportSheet = State(initialValue: autoShowImportSheet)
    }

    var body: some View {
        let state = viewModel.state
        let table = state.currentTable
        ScrollView {
            VStack(spacing: 16) {
                Text(L10n.format("manage_title"))
                    // ← Material 3 headlineMedium.copy(Medium) = 28sp/medium (ManagementPage.kt L82)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(colors.onBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("manage_page_title")

                HStack(alignment: .top, spacing: 8) {
                    Button(action: onEditCurrentTable) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.format("manage_current_table"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(colors.primary)
                            Text(table?.name ?? L10n.format("manage_no_table"))
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(colors.onSurface)
                            Text(table.map { L10n.format("table_info", $0.startDate, state.currentWeek, state.courses.count) }
                                 ?? L10n.format("manage_no_table_hint"))
                                .font(.system(size: 12))
                                .foregroundColor(colors.onSurfaceVariant)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(table == nil)
                    .accessibilityIdentifier("manage_edit_current")
                    Button(action: onOpenAllTables) {
                        Text(L10n.format("manage_view_all_tables"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.onSurfaceVariant)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("manage_all_tables")
                }
                .padding(16)
                .background(colors.surfaceContainer)
                .cornerRadius(SleepyShapes.large)

                VStack(spacing: 12) {
                    ManageCard(id: "manage_import", icon: "square.and.arrow.up",
                               title: L10n.format("manage_add_table"),
                               subtitle: L10n.format("manage_add_table_sub")) {
                        showImportSheet = true
                    }
                    ManageCard(id: "manage_add_course", icon: "plus",
                               title: L10n.format("manage_manual_add"),
                               subtitle: L10n.format("manage_manual_add_sub"),
                               onClick: onManualAdd)
                    ManageCard(id: "manage_period_tables", icon: "clock",
                               title: L10n.format("manage_period_tables"),
                               subtitle: L10n.format("manage_period_tables_sub"),
                               onClick: onOpenPeriodTables)
                    ManageCard(id: "manage_export", icon: "square.and.arrow.up.on.square",
                               title: L10n.format("manage_export"),
                               subtitle: L10n.format("manage_export_sub"),
                               onClick: onExportRequested)
                }
            }
            .padding(16)
            // 悬浮底栏额外余量(→ 原版本 LocalNavExtraBottomPadding): 镜像原实现
            //   padding(bottom = 16.dp + navExtra) 让列表最后一行不被悬浮药丸遮住。
            .padding(.bottom, navExtra)
        }
        .background(colors.background)
        .sheet(isPresented: $showImportSheet, onDismiss: {
            if createTableAfterDismiss {
                createTableAfterDismiss = false
                onCreateNewTableRequested()
            }
        }) {
            ImportSheet(
                viewModel: viewModel,
                onDismiss: { showImportSheet = false },
                onImported: onImported,
                drafts: drafts,
                onDeleteDraft: onDeleteDraft,
                onJwDismissed: onJwDismissed,
                onCreateNewTable: {
                    createTableAfterDismiss = true
                    showImportSheet = false
                })
                .environment(\.localWakeUpColors, colors)
                .environment(\.localCoursePalette, palette)
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
