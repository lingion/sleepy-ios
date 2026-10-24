import SwiftUI

// ExitDraftState — Android ui/screen/imports/ExitDraftState.kt → 1:1 纯逻辑移植.
//
// Android 侧: 纯 exit reducer (reduceExitDraftState) — 不存不删, 调用方拥有副作用;
// 2026-09-16 用户: 三个裸 TextButton 既不同排又无色块背景 → 换 DialogActionButtons
// 三键等宽色块一行排. iOS 复用同名组件 Sleepy/ui/component/DialogActionButtons.swift
// (已含 thirdText/onThird/thirdDestructive): dismiss=继续 / third=留草稿 /
// confirm=退出并删除(destructive=true → errorContainer), 键序与破坏性语义 1:1;
// 色块 48 高 / labelLarge 14 Medium / ROW_GAP_DP=8 / 放得下一行按必需宽比例分权、
// 放不下竖排全宽降级, 全部由该组件承担 (2026-09-18 「一行能搞定的就一行」/「文字完整 > 一排」).
// Android AlertDialog onDismissRequest = onContinue (点外部/返回 = 继续) →
// ExitDraftConfirmationDialog 遮罩轻点 = onContinue.

/// 用户离开 import 时的选择 (Android enum 1:1).
enum ExitDraftChoice: Equatable, Codable {
    case continueImport
    case keepDraft
    case deleteDraft
}

/// 退出确认流所需最小状态; 持久化刻意放在 reducer 之外.
struct ExitDraftState: Equatable {
    var activeImport: Bool = false
    var confirmationVisible: Bool = false
}

/// 退出事件 (Android sealed interface 1:1).
enum ExitDraftEvent {
    case requestExit
    case choose(ExitDraftChoice)
}

enum ExitDraftOutcome {
    case none
    case finishDirectly
    case keepDraft
    case deleteDraft
}

struct ExitDraftReduction {
    let state: ExitDraftState
    let outcome: ExitDraftOutcome
}

/// 纯 exit reducer — 不保存/不删除, 调用方拥有副作用 (Android 注释 1:1).
/// iOS 侧现状: 草稿数据切片未落地 (JwCourse/JwSchoolInfo 非 Codable, 无
/// JwImportDraftCodec) → KeepDraft/DeleteDraft 的持久化钩子由 JwImportFlow
/// 调用方侧以标记 TODO 承接 (ImportDraftDao 仅有 id 级 upsert/delete,
/// 可用, 待草稿数据切片提供 payloadJson).
func reduceExitDraftState(
    _ state: ExitDraftState,
    _ event: ExitDraftEvent
) -> ExitDraftReduction {
    switch event {
    case .requestExit:
        if state.activeImport {
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: true),
                outcome: .none)
        } else {
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: false),
                outcome: .finishDirectly)
        }

    case .choose(let choice):
        switch choice {
        case .continueImport:
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: false),
                outcome: .none)
        case .keepDraft:
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: false),
                outcome: .keepDraft)
        case .deleteDraft:
            return ExitDraftReduction(
                state: ExitDraftState(activeImport: state.activeImport, confirmationVisible: false),
                outcome: .deleteDraft)
        }
    }
}

/// 退出确认面 — Android ExitDraftConfirmationDialog 内 text 槽 Column 的 iOS 等价.
/// 三键 = 共享组件 DialogActionButtons: dismiss(继续) → third(留草稿) →
/// confirm(退出并删除, destructive → errorContainer 色块), 顺序/视觉 token/自适应
/// 一行-竖排降级全部由该组件承担, 不再手搓裸按钮。
struct ExitDraftConfirmationCard: View {
    let onContinue: () -> Void
    let onKeepDraft: () -> Void
    let onDeleteDraft: () -> Void

    var body: some View {
        // ↔ Android AlertDialog text = Column { message; Spacer(20.dp); DialogActionButtons }
        //   标题(AlertDialog title)在 ExitDraftConfirmationDialog 承载; 此处 = 内容 + 按钮行.
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.t("jw_import_exit_message"))
            // 继续(dismiss 位 secondary) / 留草稿(third 位 secondary) /
            // 退出并删除草稿(confirm 位 destructive) — 与 Kotlin 实参逐字对应.
            DialogActionButtons(
                confirmText: L10n.t("jw_import_exit_delete_draft"),
                onConfirm: onDeleteDraft,
                dismissText: L10n.t("jw_import_exit_continue"),
                onDismiss: onContinue,
                thirdText: L10n.t("jw_import_exit_keep_draft"),
                onThird: onKeepDraft,
                destructive: true,
                thirdDestructive: false)
        }
    }
}

/// 退出确认弹窗 — Android AlertDialog(onDismissRequest = onContinue) 的 iOS 等价面.
/// 点遮罩外部 = 继续 (↔ onDismissRequest=onContinue / 系统返回), 键序语义见卡片.
struct ExitDraftConfirmationDialog: View {
    @Environment(\.localWakeUpColors) private var colors
    let onContinue: () -> Void
    let onKeepDraft: () -> Void
    let onDeleteDraft: () -> Void

    var body: some View {
        // ↔ AlertDialog scrim 轻点关闭: 遮罩层命中 = onContinue; 卡片本身吞掉点击.
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onContinue)
            VStack(alignment: .leading, spacing: 20) {
                // ↔ AlertDialog title
                Text(L10n.t("jw_import_exit_title"))
                    .font(.headline)
                    .foregroundColor(colors.onSurface)
                ExitDraftConfirmationCard(
                    onContinue: onContinue,
                    onKeepDraft: onKeepDraft,
                    onDeleteDraft: onDeleteDraft)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            // ↔ M3 AlertDialog: surfaceContainerHigh + 官方 dialog 圆角 extraLarge(28)
            .background(RoundedRectangle(cornerRadius: SleepyShapes.extraLarge)
                .fill(colors.surfaceContainerHigh))
            .padding(.horizontal, 24)   // ↔ iOS 弹窗左右 padding 24 (DialogActionButtons 兜底同源)
        }
    }
}
