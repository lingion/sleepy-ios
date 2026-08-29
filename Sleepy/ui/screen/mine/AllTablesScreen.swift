// AllTablesScreen.swift — ← ui/screen/mine/AllTablesScreen.kt
// 所有课表页: 列表(当前表 primaryContainer+勾/其他 surfaceContainer)+设置入口+新建按钮。

import SwiftUI

struct AllTablesScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScheduleViewModel
    let onBack: () -> Void
    let onCreateNewTable: () -> Void
    let onOpenEditTable: (Int64) -> Void

    var body: some View {
        let state = viewModel.state
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("all_tables"), onBack: onBack)
            ScrollView {
                VStack(spacing: 12) {
                    Spacer().frame(height: 4)
                    ForEach(state.tables) { table in
                        let isCurrent = table.id == state.selectedTableId
                        // ← Kotlin Row + noRippleClickable: 行用 tap 手势而非 Button,
                        //   否则嵌套在内层 Button(齿轮)的点击会冒泡给行, 齿轮永远打不开编辑页
                        HStack(spacing: 12) {
                                if isCurrent {
                                    Image(systemName: "checkmark.circle")
                                        .font(.system(size: 24))
                                        .foregroundColor(colors.primary)
                                } else {
                                    RoundedRectangle(cornerRadius: SleepyShapes.medium)
                                        .fill(colors.outlineVariant)
                                        .frame(width: 24, height: 24)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    // ★ M3 对比度修正: 当前行配 onPrimaryContainer 系
                                    Text(table.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(isCurrent ? colors.onPrimaryContainer : colors.onSurface)
                                    Text(isCurrent ? L10n.format("current_table_week", state.currentWeek)
                                                   : L10n.format("table_start_date", table.startDate))
                                        .font(.system(size: 12))
                                        .foregroundColor(isCurrent
                                            ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                                            : colors.onSurfaceVariant)
                                }
                                Spacer()
                                Button {
                                    onOpenEditTable(table.id)
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 20))
                                        .foregroundColor(colors.onSurfaceVariant)
                                }
                                .buttonStyle(SleepyButtonStyle())
                                .accessibilityIdentifier("table_edit_\(table.id)")
                            }
                            .padding(14)
                            .background(isCurrent ? colors.primaryContainer : colors.surfaceContainer)
                            .cornerRadius(SleepyShapes.large)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isCurrent {
                                    viewModel.selectTable(table.id)
                                    onBack()
                                }
                            }
                    }

                    // 新建按钮(FilledTonalButton)
                    Button(action: onCreateNewTable) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                            Text(L10n.format("all_tables_new"))
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSecondaryContainer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(colors.secondaryContainer)
                        .cornerRadius(SleepyShapes.large)
                    }
                    .buttonStyle(SleepyButtonStyle())
                    Spacer().frame(height: 16)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(colors.background)
    }
}

// 设置页统一顶栏(← TopAppBar 模式, 各设置页共用)
struct SettingsTopBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(colors.onBackground)
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityIdentifier("topbar_back")
            Text(title)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(colors.onBackground)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(colors.background)
    }
}
