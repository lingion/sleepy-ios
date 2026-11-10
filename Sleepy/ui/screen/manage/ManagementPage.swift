// ManagementPage.swift — ← ui/screen/manage/ManagementPage.kt
// 课表管理页：摘要编辑、独立全部课表入口和四个管理操作。

import SwiftUI

struct ManagementPage: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.localNavExtraBottomPadding) private var navExtra
    @ObservedObject var viewModel: ScheduleViewModel
    let onImportRequested: () -> Void
    let onAddCourses: () -> Void
    let onEditCurrentTable: () -> Void
    let onExportRequested: () -> Void
    let onOpenAllTables: () -> Void
    let onOpenPeriodTables: () -> Void

    var body: some View {
        let state = viewModel.state
        let table = state.currentTable
        ScrollView {
            VStack(spacing: 16) {
                Text(L10n.format("manage_title"))
                    // ← v1.0.63 ManagementPage: headlineMedium.copy(Bold).
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(colors.onBackground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("manage_page_title")

                HStack(alignment: .top, spacing: 0) {
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
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .disabled(table == nil)
                    .accessibilityIdentifier("manage_edit_current")
                    Button(action: onOpenAllTables) {
                        Text(L10n.format("manage_view_all_tables"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colors.onSurfaceVariant)
                            .padding(.horizontal, 12)
                            .frame(minWidth: 58, minHeight: 48)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    .accessibilityIdentifier("manage_all_tables")
                    // Android's TextButton is positioned independently of
                    // the summary column's sixteen-point content padding.
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                }
                .background(colors.surfaceContainer)
                .cornerRadius(SleepyShapes.large)

                VStack(spacing: 12) {
                    ManageCard(id: "manage_import", icon: "square.and.arrow.up",
                               title: L10n.format("manage_add_table"),
                               subtitle: L10n.format("manage_add_table_sub")) {
                        onImportRequested()
                    }
                    ManageCard(id: "manage_add_course", icon: "plus",
                               title: L10n.format("manage_manual_add"),
                               subtitle: L10n.format("manage_manual_add_sub"),
                               onClick: onAddCourses)
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
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(id)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}
