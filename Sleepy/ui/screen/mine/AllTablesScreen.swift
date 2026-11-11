// AllTablesScreen.swift — ← ui/screen/mine/AllTablesScreen.kt
// 所有课表页: 列表(当前表 primaryContainer+勾/其他 surfaceContainer)+设置入口+新建按钮。

import SwiftUI
import UIKit

struct AllTablesScreen: View {
    @Environment(\.sleepyUIStyle) private var uiStyle
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScheduleViewModel
    let onDismiss: () -> Void
    let onCreateNewTable: () -> Void
    let onOpenEditTable: (Int64) -> Void
    @State private var copyTarget: TimeTableEntity?
    @State private var copyName = ""
    @State private var copying = false
    @State private var duplicateError: String? = nil
    @State private var updateTarget: TimeTableEntity?
    @State private var updateActive = false
    @State private var periodTables: [PeriodTableEntity] = []

    var body: some View {
        let state = viewModel.state
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("all_tables"), onBack: onDismiss)
            if let duplicateError {
                Text(duplicateError)
                    .font(.system(size: 12))
                    .foregroundColor(colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("table_duplicate_save_error")
            }
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 12) {
                        Spacer().frame(height: 4)
                        ForEach(state.tables) { table in
                            tableCard(table, availableWidth: geometry.size.width - 32)
                        }

                        // 新建按钮(FilledTonalButton)
                        Button(action: onCreateNewTable) {
                            HStack(spacing: 8) {
                                AndroidMaterialIcon(name: .add, size: 24)   // ← 原 Icon 默认 24dp
                                Text(L10n.format("all_tables_new"))
                                    .font(.system(size: 14, weight: .medium))   // ← labelLarge 14 Medium
                            }
                            .foregroundColor(colors.onSecondaryContainer)
                            .frame(maxWidth: .infinity)
                            .frame(height: uiStyle == .liquidGlass ? nil : 48)
                            .sleepyControlSurface(cornerRadius: SleepyShapes.large, tint: colors.secondaryContainer, prominent: true)
                        }
                        .buttonStyle(SleepyPlatformButtonStyle(prominent: true, cornerRadius: SleepyShapes.large))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .tint(colors.secondaryContainer)
                        Spacer().frame(height: 16)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .background(colors.background)
        .onAppear { periodTables = viewModel.loadAllPeriodTables() }
        .onReceive(viewModel.$allPeriodTables) { periodTables = $0 }
        .sheet(item: $updateTarget, onDismiss: {
            updateActive = false
            viewModel.occurrenceSaved()
        }) { target in
            JwImportFlow(onFinish: { _ in updateTarget = nil },
                         onActiveImportChanged: { updateActive = $0 },
                         targetTableId: target.id, updateExistingCourses: true,
                         updateRepository: viewModel.occurrenceRepository)
                .interactiveDismissDisabled(updateActive)
        }
        .centeredDialog(isPresented: Binding(
            get: { copyTarget != nil },
            set: { if !$0 { dismissCopy() } }
        )) {
            if let target = copyTarget {
                copyDialog(target)
            }
        }
    }

    private func dismissCopy() {
        guard !copying else { return }
        copyTarget = nil
    }

    private func copyDialog(_ target: TimeTableEntity) -> some View {
        let candidate = copyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = !candidate.isEmpty && !TimeTableUtils.isTableNameTaken(candidate,
            courseTableNames: viewModel.state.tables.map(\.name), periodTableNames: periodTables.map(\.name))
        let actions = DialogActionButtons(confirmText: L10n.t("ok"), onConfirm: {
            guard valid, !copying else { return }
            copying = true
            if viewModel.duplicateTable(target.id, newName: candidate, onFailure: { duplicateError = $0 }) {
                copyTarget = nil
            }
            copying = false
        }, dismissText: L10n.t("cancel"), onDismiss: dismissCopy, confirmEnabled: valid && !copying,
            confirmIdentifier: "table_copy_confirm", dismissIdentifier: "table_copy_cancel")
        return CenteredPickerDialog(title: L10n.t("all_tables_duplicate"), onDismiss: dismissCopy,
                                    footer: AnyView(actions)) {
            VStack(alignment: .leading, spacing: 20) {
                FieldTextField(text: $copyName, label: L10n.t("edit_table_name"))
                    .disabled(copying)
                    .accessibilityIdentifier("table_copy_name")
                if !candidate.isEmpty && !valid {
                    Text(L10n.t("table_copy_duplicate"))
                        .foregroundColor(colors.error)
                        .accessibilityIdentifier("table_copy_name_error")
                }
                if let duplicateError {
                    Text(duplicateError)
                        .font(.system(size: 12))
                        .foregroundColor(colors.error)
                        .accessibilityIdentifier("table_copy_save_error")
                }
            }
        }
        .foregroundColor(colors.onSurface)
    }

    private func tableCard(_ table: TimeTableEntity, availableWidth: CGFloat) -> some View {
        let isCurrent = table.id == viewModel.state.selectedTableId
        let titleWidth = min(56, (table.name as NSString).size(withAttributes: [
            .font: UIFont.systemFont(ofSize: 14, weight: .semibold)
        ]).width)
        let contentWidth = availableWidth - 28
        let actionsWidth: CGFloat = 48 * 3
        let regularFits = contentWidth >= 24 + 12 + titleWidth + actionsWidth
        let markerSize: CGFloat = regularFits ? 24 : 20
        let titleGap: CGFloat = regularFits ? 12 : 8
        let actionsBelow = contentWidth < markerSize + titleGap + titleWidth + actionsWidth
        return VStack(alignment: .leading, spacing: 0) {
            if actionsBelow {
                tableIdentity(table, isCurrent: isCurrent, markerSize: markerSize, titleGap: titleGap)
                tableActions(table).frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack(spacing: 0) {
                    tableIdentity(table, isCurrent: isCurrent, markerSize: markerSize, titleGap: titleGap)
                    tableActions(table)
                }
            }
            if table.createdAt > 0 {
                Text(L10n.format("table_created_at", Self.createdAtText(table.createdAt)))
                    .font(.system(size: 12))
                    .foregroundColor(isCurrent
                        ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                        : colors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, markerSize + titleGap)
                    .padding(.top, 4)
                    .accessibilityIdentifier("table_created_at_\(table.id)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(isCurrent ? colors.primaryContainer : colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }

    private func tableIdentity(_ table: TimeTableEntity, isCurrent: Bool,
                               markerSize: CGFloat, titleGap: CGFloat) -> some View {
        Button {
            if !isCurrent { viewModel.selectTable(table.id) }
        } label: {
            HStack(spacing: titleGap) {
                if isCurrent {
                    AndroidSettingsIcon(name: .checkCircle, size: markerSize)
                        .foregroundColor(colors.primary)
                } else {
                    RoundedRectangle(cornerRadius: SleepyShapes.medium)
                        .fill(colors.outlineVariant)
                        .frame(width: markerSize, height: markerSize)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(table.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(isCurrent ? colors.onPrimaryContainer : colors.onSurface)
                        .lineLimit(2)
                    Text(isCurrent ? L10n.format("current_table_week", viewModel.state.currentWeek)
                                   : L10n.format("table_start_date", table.startDate))
                        .font(.system(size: 12))
                        .foregroundColor(isCurrent
                            ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                            : colors.onSurfaceVariant)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("table_select_\(table.id)")
        .accessibilityLabel(table.name)
    }

    private func tableActions(_ table: TimeTableEntity) -> some View {
        HStack(spacing: 0) {
            Button {
                duplicateError = nil
                copyTarget = table
                copyName = TimeTableUtils.suggestUniqueName(table.name,
                    courseTableNames: viewModel.state.tables.map(\.name), periodTableNames: periodTables.map(\.name))
            } label: {
                AndroidSettingsIcon(name: .contentCopy, size: 20)
                    .frame(width: uiStyle == .classic ? 48 : nil, height: uiStyle == .classic ? 48 : nil)
                    .foregroundColor(colors.onSurfaceVariant)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 24, compact: true, shape: .circle))
            .frame(width: 48, height: 48)
            .accessibilityIdentifier("table_duplicate_\(table.id)")
            .accessibilityLabel(L10n.format("all_tables_duplicate"))
            Button { updateTarget = table } label: {
                AndroidSettingsIcon(name: .refresh, size: 20)
                    .frame(width: uiStyle == .classic ? 48 : nil, height: uiStyle == .classic ? 48 : nil)
                    .foregroundColor(colors.onSurfaceVariant)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 24, compact: true, shape: .circle))
            .frame(width: 48, height: 48)
            .accessibilityIdentifier("table_update_from_school_\(table.id)")
            .accessibilityLabel(L10n.t("course_update_from_school"))
            Button { onOpenEditTable(table.id) } label: {
                AndroidSettingsIcon(name: .settings, size: 20)
                    .frame(width: uiStyle == .classic ? 48 : nil, height: uiStyle == .classic ? 48 : nil)
                    .foregroundColor(colors.onSurfaceVariant)
                    .contentShape(Rectangle())
            }
            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 24, compact: true, shape: .circle))
            .frame(width: 48, height: 48)
            .accessibilityIdentifier("table_edit_\(table.id)")
            .accessibilityLabel(L10n.format("action_settings"))
        }
        .fixedSize(horizontal: true, vertical: false)
    }

}

extension AllTablesScreen {
    // yyyy-MM-dd HH:mm:ss 系统时区(Instant+DateTimeFormatter)
    static func createdAtText(_ millis: Int64) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = .current
        return f.string(from: Date(timeIntervalSince1970: Double(millis) / 1000))
    }
}

// 设置页统一顶栏(← TopAppBar 模式, 各设置页共用)
struct SettingsTopBar: View {
    enum LeadingStyle {
        case back      // Push navigation: chevron.left, id: "topbar_back", label: "back"
        case close     // Modal presentation: xmark.circle.fill, id: "topbar_close", label: "action_close"
    }

    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.sleepyUIStyle) private var uiStyle
    let title: String
    var leadingStyle: LeadingStyle = .back
    var titleIdentifier: String = "settings_topbar_title"
    let onBack: () -> Void

    var body: some View {
        // ← M3 TopAppBar: 容器高 64, 标题 titleLarge 22 Normal。
        // 原生图标保持 intrinsic 尺寸; Classic 与 Android 共用48pt触控槽。
        HStack(spacing: 0) {
            Button(action: onBack) {
                switch leadingStyle {
                case .back:
                    AndroidSettingsIcon(name: .arrowBack, size: 24)
                        .frame(width: uiStyle == .classic ? 48 : nil, height: uiStyle == .classic ? 48 : nil)
                        .foregroundColor(colors.onBackground)
                case .close:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: uiStyle == .classic ? 48 : nil, height: uiStyle == .classic ? 48 : nil)
                        .foregroundColor(colors.onSurfaceVariant)
                }
            }
            .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 20, compact: true, shape: .circle))
            .frame(width: 48, height: 48)
            .accessibilityIdentifier(leadingStyle == .close ? "topbar_close" : "topbar_back")
            .accessibilityLabel(L10n.format(leadingStyle == .close ? "action_close" : "back"))
            .padding(.leading, 4)   // ← TopAppBarHorizontalPadding 4dp
            Text(title)
                .accessibilityIdentifier(titleIdentifier)
                .font(.system(size: 22))   // ← 原 TopAppBar titleLarge 22 Normal(去 Medium)
                .foregroundColor(colors.onBackground)
                .padding(.leading, 4)   // ← 标题盒水平内边距 4dp
            Spacer()
        }
        .frame(height: 64)   // ← TopAppBarSmallTokens.ContainerHeight 64dp
        .background(colors.background)
    }
}
