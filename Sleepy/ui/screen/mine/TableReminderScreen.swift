// TableReminderScreen.swift — ← ui/screen/mine/TableReminderScreen.kt (原版本) 逐行移植
//
// v1.0.62 B3: 每课表提醒开关独立页。原版本 语义 1:1:
//   • 列表 = observeAllTables() (库态即真源, DB authoritative);
//   • 行 = 课表名 + Switch, toggleable 整行可点;
//   • TableReminderViewModel.pending → iOS pendingIds: 每表同一时刻至多一次在飞写入
//     (重复点按「if (id in pending) return」直接吞掉, 行置灰);
//   • 写失败 Toast(table_reminder_save_failed) → iOS 页内 snackbar (AboutScreen 同款
//     .task(id:) 2.5s 自动收);
//   • 副标题随总开关切换 subtitle / master_off 文案 (总开关关着仍可先配各表);
//   • 空库提示 table_reminder_empty。
// 入口: ReminderScreen「课表提醒」行 (本页以 sheet 呈现 — HolidaySettings 同款内嵌链,
// 原版本 侧是 NavHost push 路由 SleepyRoute.TableReminder; iOS overlay 等价 = 根浮层
// 需共享文件新增 OverlayScreen case, 与 widgetManagement/holiday 先例一致走内嵌 sheet,
// 行为等价: 进出带侧滑/下拉手势关闭)。

import SwiftUI
import Combine

struct TableReminderCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let masterEnabled: Bool
    var onError: ((String) -> Void)? = nil

    @State private var expanded = false
    @State private var tables: [TimeTableEntity] = []
    @State private var pendingIds: Set<Int64> = []
    @State private var tablesCancellable: AnyCancellable? = nil
    private let repo = ScheduleRepository(AppDatabase.getShared())

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(sleepySettingsExpand) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: SettingsLayout.controlGap) {
                    Text(L10n.format("settings_table_reminder_scope"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                    Spacer()
                    AndroidSettingsIcon(name: .expandMore, size: 20)
                        .foregroundColor(colors.onSurfaceVariant)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .padding(.vertical, 12)
                .frame(minHeight: SettingsLayout.minRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityIdentifier("reminder_table_reminder_entry")

            if expanded {
                TableReminderContent(
                    masterEnabled: masterEnabled,
                    tables: tables,
                    pendingIds: pendingIds,
                    onToggle: { id, enabled in setEnabled(id, enabled) }
                )
                .padding(.top, SettingsLayout.headerGap)
                .padding(.bottom, SettingsLayout.cardInset)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, SettingsLayout.cardInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
        .animation(sleepySettingsExpand, value: expanded)
        .onAppear {
            tablesCancellable = repo.observeAllTables()
                .catch { _ in Just<[TimeTableEntity]>([]) }
                .receive(on: DispatchQueue.main)
                .sink { tables in
                    self.tables = resolveReminderTableScope(tables: tables, selectedTableId: tables.first { $0.isDefault }?.id)
                }
        }
        .onDisappear { tablesCancellable = nil }
    }

    private func setEnabled(_ id: Int64, _ enabled: Bool) {
        guard !pendingIds.contains(id) else { return }
        pendingIds.insert(id)
        do {
            try repo.setTableReminderEnabled(id: id, enabled: enabled)
        } catch {
            onError?(L10n.format("table_reminder_save_failed"))
        }
        pendingIds.remove(id)
    }
}

struct TableReminderContent: View {
    @Environment(\.localWakeUpColors) private var colors
    let masterEnabled: Bool
    let tables: [TimeTableEntity]
    let pendingIds: Set<Int64>
    let onToggle: (Int64, Bool) -> Void
    var rowBackground: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.format(masterEnabled ? "table_reminder_subtitle" : "table_reminder_master_off"))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

            if tables.isEmpty {
                Text(L10n.format("table_reminder_empty"))
                    .font(.system(size: 14))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            ForEach(tables) { table in
                let enabled = !pendingIds.contains(table.id)
                HStack(spacing: 12) {
                    Text(table.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colors.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Toggle("", isOn: Binding(
                        get: { table.reminderEnabled },
                        set: { onToggle(table.id, $0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(SleepyToggleStyle())
                    .tint(colors.primary)
                    .disabled(!enabled)
                }
                .padding(16)
                .background(rowBackground ?? colors.surfaceContainerLow)
                .cornerRadius(SleepyShapes.large)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard enabled else { return }
                    onToggle(table.id, !table.reminderEnabled)
                }
                .opacity(enabled ? 1 : 0.6)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("table_reminder_row_\(table.id)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TableReminderScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void

    @State private var tables: [TimeTableEntity] = []
    @State private var pendingIds: Set<Int64> = []
    @State private var snackMessage: String? = nil
    @State private var masterEnabled = AppPrefs.shared.isReminderEnabled()

    private let repo = ScheduleRepository(AppDatabase.getShared())
    @State private var tablesCancellable: AnyCancellable? = nil

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("settings_table_reminder_scope"), onBack: onDismiss)
            ScrollView {
                TableReminderContent(
                    masterEnabled: masterEnabled,
                    tables: tables,
                    pendingIds: pendingIds,
                    onToggle: { setEnabled($0, $1) },
                    rowBackground: colors.surfaceContainer
                )
                .padding(16)
            }
        }
        .background(colors.background)
        .overlay(alignment: .bottom) {
            if let msg = snackMessage {
                Text(msg)
                    .font(.system(size: 14))
                    .accessibilityIdentifier("table_reminder_snackbar")
                    .foregroundColor(colors.onSurface)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)
                    .padding(.bottom, 12)
                    .task(id: msg) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { snackMessage = nil }
                    }
            }
        }
        .onAppear {
            masterEnabled = AppPrefs.shared.isReminderEnabled()
            tablesCancellable = repo.observeAllTables()
                .catch { _ in Just<[TimeTableEntity]>([]) }
                .receive(on: DispatchQueue.main)
                .sink { tables in self.tables = resolveReminderTableScope(tables: tables, selectedTableId: tables.first { $0.isDefault }?.id) }
        }
        .onDisappear { tablesCancellable = nil }
    }

    private func setEnabled(_ id: Int64, _ enabled: Bool) {
        guard !pendingIds.contains(id) else { return }
        pendingIds.insert(id)
        do {
            try repo.setTableReminderEnabled(id: id, enabled: enabled)
        } catch {
            snackMessage = L10n.format("table_reminder_save_failed")
        }
        pendingIds.remove(id)
    }
}

#if compiler(>=5.9)
#Preview {
    TableReminderScreen(onDismiss: {})
}
#endif
