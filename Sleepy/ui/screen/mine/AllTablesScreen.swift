// AllTablesScreen.swift — ← ui/screen/mine/AllTablesScreen.kt
// 所有课表页: 列表(当前表 primaryContainer+勾/其他 surfaceContainer)+设置入口+新建按钮。

import SwiftUI

struct AllTablesScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: ScheduleViewModel
    let onDismiss: () -> Void
    let onCreateNewTable: () -> Void
    let onOpenEditTable: (Int64) -> Void

    var body: some View {
        let state = viewModel.state
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("all_tables"), onBack: onDismiss)
            ScrollView {
                VStack(spacing: 12) {
                    Spacer().frame(height: 4)
                    ForEach(state.tables) { table in
                        let isCurrent = table.id == state.selectedTableId
                        // ← 原版本 Row 无 spacedBy, 图标钮自身 40×40 盒提供 10/20 视觉间隙
                        HStack(spacing: 0) {
                            Button {
                                if !isCurrent {
                                    // ← 原版本 ce7f7924: 选表后留在本页(选中态就地高亮), 不再强制弹出
                                    viewModel.selectTable(table.id)
                                }
                            } label: {
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
                                        // v7.10.15 导入时间(createdAt>0 才显示; v1.0.16 前老表无此值)
                                        if table.createdAt > 0 {
                                            Text(L10n.format("table_created_at", Self.createdAtText(table.createdAt)))
                                                .font(.system(size: 12))   // ← bodySmall 12
                                                .foregroundColor(isCurrent
                                                    ? colors.onPrimaryContainer.opacity(SleepyTheme.Alpha.highContent)
                                                    : colors.onSurfaceVariant)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .accessibilityIdentifier("table_select_\(table.id)")
                            .accessibilityLabel(table.name)
                            Spacer(minLength: 0)
                            // v7.10.15 duplicate 图标 — 创建课表副本, 置于设置图标左边
                            Button {
                                viewModel.duplicateTable(table.id)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 20))   // ← ContentCopy size(20.dp)
                                    .frame(width: 40, height: 40)   // ← M3 IconButton 40×40
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .accessibilityIdentifier("table_duplicate_\(table.id)")
                            // ← 原 contentDescription = all_tables_duplicate
                            .accessibilityLabel(L10n.format("all_tables_duplicate"))
                            Button {
                                onOpenEditTable(table.id)
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 20))
                                    .frame(width: 40, height: 40)   // ← M3 IconButton 40×40
                                    .foregroundColor(colors.onSurfaceVariant)
                            }
                            .buttonStyle(SleepyButtonStyle())
                            .accessibilityIdentifier("table_edit_\(table.id)")
                            // ← 原 contentDescription = action_settings
                            .accessibilityLabel(L10n.format("action_settings"))
                        }
                        .padding(14)
                        .background(isCurrent ? colors.primaryContainer : colors.surfaceContainer)
                        .cornerRadius(SleepyShapes.large)
                    }

                    // 新建按钮(FilledTonalButton)
                    Button(action: onCreateNewTable) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 24))   // ← 原 Icon 默认 24dp
                            Text(L10n.format("all_tables_new"))
                                .font(.system(size: 14, weight: .medium))   // ← labelLarge 14 Medium
                        }
                        .foregroundColor(colors.onSecondaryContainer)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
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
    let title: String
    var leadingStyle: LeadingStyle = .back
    var titleIdentifier: String = "settings_topbar_title"
    let onBack: () -> Void

    var body: some View {
        // ← M3 TopAppBar: 容器高 64, 标题 titleLarge 22 Normal,
        //   导航钮 40×40 + 前 4dp, 标题起点 = 4+40+4 = 48(= 原 navIcon 44 + 标题盒 4)
        HStack(spacing: 0) {
            Button(action: onBack) {
                switch leadingStyle {
                case .back:
                    Image(systemName: "chevron.left")   // ← 有意差异: iOS 惯用 chevron, 原平台用 ArrowBack 图形
                        .font(.system(size: 24))   // ← LeadingIconSize 24dp(原 20 Medium)
                        .frame(width: 40, height: 40)   // ← M3 IconButton 40×40
                        .foregroundColor(colors.onBackground)
                case .close:
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 40, height: 40)
                        .foregroundColor(colors.onSurfaceVariant)
                }
            }
            .buttonStyle(SleepyButtonStyle())
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
