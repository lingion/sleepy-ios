// ManagementPage.swift — ← ui/screen/manage/ManagementPage.kt
// 课表管理页: 当前课表摘要卡 + 4 管理卡(导入/新建/手动添加/编辑) + ImportSheet。

import SwiftUI

struct ManagementPage: View {
    @Environment(\.localWakeUpColors) private var colors
    @ObservedObject var viewModel: ScheduleViewModel
    var autoShowImportSheet: Bool = false
    let onJwImportRequested: () -> Void
    let onCreateNewTableRequested: () -> Void
    let onManualAdd: () -> Void
    let onEditCurrentTable: () -> Void
    var onImported: () -> Void = {}
    var onOpenEditTable: (Int64) -> Void = { _ in }

    @State private var showImportSheet: Bool

    init(viewModel: ScheduleViewModel,
         autoShowImportSheet: Bool = false,
         onJwImportRequested: @escaping () -> Void,
         onCreateNewTableRequested: @escaping () -> Void,
         onManualAdd: @escaping () -> Void,
         onEditCurrentTable: @escaping () -> Void,
         onImported: @escaping () -> Void = {},
         onOpenEditTable: @escaping (Int64) -> Void = { _ in }) {
        self.viewModel = viewModel
        self.autoShowImportSheet = autoShowImportSheet
        self.onJwImportRequested = onJwImportRequested
        self.onCreateNewTableRequested = onCreateNewTableRequested
        self.onManualAdd = onManualAdd
        self.onEditCurrentTable = onEditCurrentTable
        self.onImported = onImported
        self.onOpenEditTable = onOpenEditTable
        _showImportSheet = State(initialValue: autoShowImportSheet)
    }

    var body: some View {
        let state = viewModel.state
        let table = state.currentTable
        ScrollView {
            VStack(spacing: 16) {
                Text(L10n.format("tab_manage"))
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(colors.onBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("manage_page_title")

                // 当前课表摘要
                if let table = table {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.format("manage_current_table"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(colors.primary)
                        Text(table.name)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(colors.onSurface)
                        Text(L10n.format("table_info", table.startDate, state.currentWeek, state.courses.count))
                            .font(.system(size: 12))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.surfaceContainer)
                    .cornerRadius(SleepyShapes.large)
                }

                // 管理按钮(4 个)
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
                    ManageCard(id: "manage_add_course", icon: "plus",
                               title: L10n.format("manage_manual_add"),
                               subtitle: L10n.format("manage_manual_add_sub"),
                               onClick: onManualAdd)
                    ManageCard(id: "manage_edit_current", icon: "pencil",
                               title: L10n.format("manage_edit_current"),
                               subtitle: L10n.format("manage_edit_current_sub"),
                               onClick: onEditCurrentTable)
                }
            }
            .padding(16)
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
                onOpenEditTable: onOpenEditTable)

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
