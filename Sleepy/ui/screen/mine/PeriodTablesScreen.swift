// PeriodTablesScreen.swift — ← ui/screen/mine/PeriodTablesScreen.kt
// 独立时间节次表管理页(issue#40 设计 §4.1) — 我的页入口, 只管时间表增删改查,
// 不混入课程编辑。列表显示各时间表 + "已绑定 N 张课表"。
//
// v1.0.56 T7: 删除入口迁至编辑页底部 — 本页不持有删除弹窗/绑定拦截状态。
// v1.0.56 T8: 复制先命名, 确认后才落库; 复制成功留在管理页。

import SwiftUI

struct PeriodTablesScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onBack: () -> Void
    let onOpenEdit: (Int64) -> Void
    var onCreateNew: (Int64) -> Void

    @EnvironmentObject var viewModel: ScheduleViewModel
    @State private var periodTables: [PeriodTableEntity] = []
    @State private var courseTables: [TimeTableEntity] = []
    @State private var copyTarget: PeriodTableEntity?
    @State private var copyName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            newButton
        }
        // ← Android Scaffold(containerColor = colors.background) + TopAppBar
        //   containerColor(background)(PeriodTablesScreen.kt:81-97)。浮层容器
        //   PresentOverlay 不给页面铺底, 每页必须自带不透明根背景 — 与
        //   CourseListScreen/PeriodHeaderSettingsScreen 等兄弟页同式, 否则
        //   页面透出下层 Tab 内容(iPhone 6 真机复现: 作息表页透明悬浮)。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
        .accessibilityIdentifier("period_tables_screen")
        .navigationBarHidden(true)
        .onAppear { reload() }
        .sheet(item: $copyTarget) { target in
            copyDialog(target)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
            }
            .accessibilityLabel(Text(L10n.t("back")))
            Spacer()
            Text(L10n.t("period_tables_title"))
                .font(.headline)
            Spacer()
            Color.clear.frame(width: 30, height: 30)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                Color.clear.frame(height: 2)
                ForEach(periodTables) { pt in
                    row(pt)
                }
                Color.clear.frame(height: 80)
            }
            .padding(.horizontal, 16)
        }
    }

    private func row(_ pt: PeriodTableEntity) -> some View {
        let bound = courseTables.filter { $0.periodTableId == pt.id }.count
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pt.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colors.onSurface)
                Text(L10n.format("period_table_bound_count", bound))
                    .font(.caption)
                    .foregroundColor(colors.onSurfaceVariant)
            }
            Spacer()
            Button {
                onOpenEdit(pt.id)
            } label: {
                Image(systemName: "square.and.pencil")
                    .foregroundColor(colors.onSurfaceVariant)
            }
            .accessibilityLabel(Text(L10n.t("edit_table_title")))
            Button {
                if let suggested = viewModel.suggestPeriodTableCopyName(sourceId: pt.id) {
                    copyTarget = pt
                    copyName = suggested
                }
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundColor(colors.onSurfaceVariant)
            }
            .accessibilityLabel(Text(L10n.t("period_table_copy")))
            // v1.0.56 T7: 删除键在编辑页底部, 行内只留 编辑+复制
        }
        .padding(16)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.extraLarge)
    }

    private var newButton: some View {
        Button {
            let newId = viewModel.insertPeriodTable(name: L10n.t("period_table_new"))
            if newId > 0 { onCreateNew(newId) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text(L10n.t("period_table_new"))
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(colors.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)   // ← SleepyTheme.Buttons.ctaHeight
            .background(colors.primary)
            .cornerRadius(SleepyShapes.large)   // ← SleepyTheme.Buttons.shape
        }
        .buttonStyle(SleepyButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 复制弹窗 (v1.0.56 T8: 先命名后落库)

    private func copyDialog(_ target: PeriodTableEntity) -> some View {
        let candidate = copyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameTaken = !candidate.isEmpty && TimeTableUtils.isTableNameTaken(
            candidate,
            courseTableNames: courseTables.map { $0.name },
            periodTableNames: periodTables.map { $0.name }
        )
        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("period_table_copy_dialog_title"))
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(colors.onSurface)
            FieldTextField(text: $copyName, label: L10n.t("period_table_name_label"))
                .disableAutocorrection(true)
            if nameTaken {
                Text(L10n.t("period_table_name_taken"))
                    .font(.system(size: 12))
                    .foregroundColor(colors.error)
            }
            Spacer().frame(height: 12)
            // 2026-09-16 用户: 裸 TextButton 无边界无色块 — 统一色块按钮行
            DialogActionButtons(
                confirmText: L10n.t("ok"),
                onConfirm: {
                    // 二次查重: 列表可能在弹窗打开期间变化, 不能只信预览态
                    let newId = viewModel.copyPeriodTableAs(sourceId: target.id, newName: candidate)
                    if newId > 0 {
                        copyTarget = nil
                        reload()
                    }
                },
                dismissText: L10n.t("cancel"),
                onDismiss: { copyTarget = nil },
                confirmEnabled: !candidate.isEmpty && !nameTaken)
        }
        .padding(24)
        .background(colors.surface)
    }

    private func reload() {
        periodTables = viewModel.loadAllPeriodTables()
        courseTables = viewModel.state.tables
    }
}
