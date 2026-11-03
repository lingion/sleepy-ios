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

struct TableReminderScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void

    // ← 原 vm = viewModel(): pending 写队列 + tables 流。iOS 页内状态机即可
    // (无跨页复用需求; ScheduleViewModel 同层先例)。
    @State private var tables: [TimeTableEntity] = []
    @State private var pendingIds: Set<Int64> = []
    @State private var snackMessage: String? = nil
    // ← 原版本 AppPrefs.isReminderEnabled(ctx) remember 一次性读 (进页快照)。
    @State private var masterEnabled = AppPrefs.shared.isReminderEnabled()

    private let repo = ScheduleRepository(AppDatabase.getShared())
    @State private var tablesCancellable: AnyCancellable? = nil

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("table_reminder_title"), onBack: onDismiss)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ← 原版本 subtitle: 总开关开 → subtitle, 关 → master_off 警示文案
                    Text(L10n.format(masterEnabled ? "table_reminder_subtitle" : "table_reminder_master_off"))
                        .font(.system(size: 14))   // ← bodyMedium 14sp
                        .foregroundColor(colors.onSurfaceVariant)

                    if tables.isEmpty {
                        Text(L10n.format("table_reminder_empty"))
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurfaceVariant)
                    }
                    // ← 原版本 items(key = id): 行 = surfaceContainer 卡 + 整行 toggleable
                    ForEach(tables) { table in
                        let enabled = !pendingIds.contains(table.id)
                        HStack(spacing: 12) {
                            Text(table.name)
                                .font(.system(size: 14, weight: .medium))   // ← titleSmall
                                .foregroundColor(colors.onSurface)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Toggle("", isOn: Binding(
                                get: { table.reminderEnabled },
                                set: { setEnabled(table.id, $0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: colors.primary))
                            .disabled(!enabled)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(colors.surfaceContainer)
                        .cornerRadius(SleepyShapes.large)
                        .contentShape(Rectangle())
                        // ← 原版本 toggleable(enabled = enabled): 在飞写入时整行不可点
                        // (SwiftUI 无 onTapGesture(where:), guard 等价)。
                        .onTapGesture {
                            guard enabled else { return }
                            setEnabled(table.id, !table.reminderEnabled)
                        }
                        .opacity(enabled ? 1 : 0.6)
                        .accessibilityIdentifier("table_reminder_row_\(table.id)")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(colors.background)
        // ← 原版本 Toast 失败提示 → snackbar 叠层 (AboutScreen:300-318 同款)
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
            // ← repository.observeAllTables() collectAsStateWithLifecycle
            tablesCancellable = repo.observeAllTables()
                .catch { _ in Just<[TimeTableEntity]>([]) }
                .receive(on: DispatchQueue.main)
                .sink { tables in self.tables = tables }
        }
        .onDisappear { tablesCancellable = nil }
    }

    /// ← 原版本 vm.setEnabled: 在飞即吞 (return), 否则 pending+id → repo 写 →
    /// catch 失败 Toast → finally pending−id。iOS repo 调用同步 throws, 语义同。
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

#Preview {
    TableReminderScreen(onDismiss: {})
}
