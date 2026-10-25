// ScheduleConflictBottomSheet.swift — ← ui/screen/mine/ScheduleConflictBottomSheet.kt
// 甲案 (设计文档 §4.1) 三选项 BottomSheet — 绑定了共享作息表时改作息内容, 弹窗决定写入作用域。
//
// 平台映射: Material3 ModalBottomSheet(skipPartiallyExpanded=true) → SwiftUI .sheet
//   (iOS sheet 本就全高展开, 等价 skipPartiallyExpanded; 下拉手势关闭 = onDismissRequest)。
//
// 不变量 (§2.2/§3.4):
//  - 三个选项始终显示(影响数量仅提示, 不改变可选项)
//  - 数据源 = 当前实际生效作息 + 用户本次编辑 (不回退导入快照)
//  - 点选仅记录待执行策略, 不写库; 下次保存才执行
//  - 弹窗外点按 / 「取消」= 仅撤销本次作息改动, 其他字段草稿保留
//
// ★ type-check: body 语句过多时 Swift 5.8 报"extra argument in call"(类型推断上限,
//   本仓 MineScreen/SleepyApp 同病同方) → 头部/选项列表/取消行各抽子 View 独立推导。

import SwiftUI

struct ScheduleConflictBottomSheet: View {
    @Environment(\.localWakeUpColors) private var colors

    let periodTableName: String
    /// 绑定到 periodTableName 的全部课表数(含当前表本身)。<2 = 仅有当前表。
    let boundTableCount: Int
    let onSelect: (SchedulePolicy) -> Void
    let onCancel: () -> Void

    private var otherCount: Int {
        max(boundTableCount - 1, 0)
    }

    private var summaryTail: String {
        if otherCount == 0 {
            return L10n.t("schedule_conflict_dialog_summary_only_this")
        }
        return L10n.format("schedule_conflict_dialog_summary_other_count", otherCount)
    }

    private var syncSub: String {
        if otherCount == 0 {
            return L10n.t("schedule_conflict_option_sync_sub_only")
        }
        return L10n.format("schedule_conflict_option_sync_sub_other", otherCount)
    }

    var body: some View {
        // ← Column.padding(horizontal 16).padding(bottom 32), 无内建 spacing(Spacer 手排)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                optionList
                Spacer().frame(height: 20)
                cancelButton
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // ← Android ModalBottomSheet 未覆写 containerColor → M3 默认 surfaceContainerLow
        //   (同仓 TimeSlotEditor.swift:300 / SmartPeriodEditor.swift:284 同惯例)
        .background(colors.surfaceContainerLow)
    }

    // ← 标题(titleMedium 16 SemiBold) + 摘要(bodyMedium 14, 共享表名 + 影响数)
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.t("schedule_conflict_dialog_title"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(colors.onSurface)
            Spacer().frame(height: 8)
            Text(L10n.format("schedule_conflict_dialog_summary", periodTableName, summaryTail))
                .font(.system(size: 14))
                .foregroundColor(colors.onSurfaceVariant)
            Spacer().frame(height: 20)
        }
    }

    // ← 三选项 (不变量: 始终全显示, 顺序 detach/create/sync 与 Android 一致)
    private var optionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConflictOption(
                title: L10n.t("schedule_conflict_option_detach_title"),
                subtitle: L10n.t("schedule_conflict_option_detach_sub"),
                onClick: {
                onSelect(.detachCopy)
            })
            Spacer().frame(height: 8)
            ConflictOption(
                title: L10n.t("schedule_conflict_option_create_title"),
                subtitle: L10n.t("schedule_conflict_option_create_sub"),
                onClick: {
                onSelect(.createNew)
            })
            Spacer().frame(height: 8)
            ConflictOption(
                title: L10n.format("schedule_conflict_option_sync_title", periodTableName),
                subtitle: syncSub,
                onClick: {
                onSelect(.sync)
            })
        }
    }

    // ← 「取消」= 撤销本次作息改动, 其他字段草稿保留
    //   Row.clip(shapes.large).background(secondaryContainer).padding(vertical 14)
    private var cancelButton: some View {
        Button {
            onCancel()
        } label: {
            Text(L10n.t("cancel"))
                // ← labelLarge 14 + Medium
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(colors.onSecondaryContainer)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(colors.secondaryContainer)
                .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("schedule_conflict_cancel")
    }

    // ← ConflictOption: surfaceContainer 色块 + title(bodyLarge 16) + sub(bodySmall 12),
    //   padding horizontal 16 vertical 14, clip shapes.large
    private func ConflictOption(title: String, subtitle: String, onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurface)
                // ← Spacer(2dp) → VStack spacing 2
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier("schedule_conflict_option")
    }
}
