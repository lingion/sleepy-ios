// DialogActionButtons.swift — ← ui/component/DialogActionButtons.kt
// [intentional custom] 官方弹窗的 textButton 槽 = 裸文字按钮; 用户 2026-09-16
// 明确「裸 TextButton 无背景看不出可点」→ 色块按钮 + 宽度自适应换行是 Sleepy 领域需求,
// 官方无等价组合件, 保留薄层。内部消费官方 Button, 全部官方 token。
//
// 弹窗动作按钮行 — 全 app 弹窗 confirm/dismiss/third 唯一入口。
//
// 视觉 = 与全屏按钮同语言 (SleepyTheme.Buttons 高度/圆角): 确认键 primary 色块,
// 取消/第三键 secondaryContainer 色块; 危险确认传 destructive=true 确认键变
// errorContainer; 第三键破坏性传 thirdDestructive=true 第三键变 errorContainer
// (教务导入退出确认: 继续/留草稿=secondary, 退出并删除草稿=error)。
//
// 布局自适应 (2026-09-16 用户第二轮: "文字完整 > 一排"): 先按可用宽度估行内总需求
// (DialogButtonsLayoutPolicy), 放得下 → 一行按必需宽比例分权重; 放不下 → 整组降级
// 竖排全宽按钮, 任何情况下不截断文字。
// 2026-09-18 用户: "一行能搞定的就一行" — 横排等分会把长标签键压到必需宽以下 →
// Text 自动换行。权重必须按各键必需宽比例分配, 短键(「知道了」)少占,
// 长键(「导出排查全量包」)多占, 每键 ≥ 必需宽。
//
// 可用宽度 = 容器实际宽度 (↔ Android BoxWithConstraints maxWidth.value; iOS 以
// PreferenceKey 测量, 首帧未测得前按屏幕宽 - 弹窗左右 padding(24×2) 估计兜底),
// 因此也可独立用于 BottomSheet 等非 AlertDialog 容器。

import SwiftUI

/// ↔ Android BoxWithConstraints: 按钮行所在容器的实际宽度。
private struct DialogContainerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct DialogActionButtons: View {
    @Environment(\.localWakeUpColors) private var colors
    let confirmText: String
    let onConfirm: () -> Void
    var dismissText: String? = nil
    var onDismiss: () -> Void = {}
    var thirdText: String? = nil
    var onThird: () -> Void = {}
    var destructive: Bool = false
    var thirdDestructive: Bool = false
    var confirmEnabled: Bool = true
    // XCUITest 锚点 (G5): 调用方可给确认/取消键挂 identifier
    // (提醒页 reminder_time_confirm / reminder_time_cancel)。默认 nil = 其他调用方零变化。
    var confirmIdentifier: String? = nil
    var dismissIdentifier: String? = nil

    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        // 可用宽度 = 容器实际宽度; 仅首帧测得前用屏幕宽 - 弹窗左右 padding(24×2) 估计兜底
        let availableWidth = measuredWidth > 0 ? measuredWidth : UIScreen.main.bounds.width - 48
        // 顺序 = 取消 → 第三 → 确认(动作在末位), 与 Android labels 一致
        let labels = [dismissText, thirdText, confirmText].compactMap { $0 }
        let horizontal = DialogActionsLayoutPolicyBridge.fit(labels: labels, availableWidthDp: availableWidth)
        // 横排按各键必需宽比例分配权重(每键 ≥ 必需宽), 不等分
        let weights = DialogButtonsLayoutPolicy.normalizedWeights(
            labels: labels,
            fontDpPerChar: DialogActionsLayoutPolicyBridge.LABEL_LARGE_FONT_DP_PER_CJK_CHAR)
        let gap = DialogButtonsLayoutPolicy.ROW_GAP_DP
        // 权重作用于扣除键间距后的剩余宽 (↔ Compose Row.weight 对剩余空间分配)
        let remainingWidth = horizontal
            ? max(availableWidth - gap * CGFloat(max(labels.count - 1, 0)), 0)
            : availableWidth
        // labels 顺序恒为 [取消?, 第三?, 确认], 索引直取
        let dismissWeight = dismissText != nil ? weights.first ?? 1 : 0
        let thirdWeight = thirdText != nil ? weights[weights.count - 2] : 0
        let confirmWeight = weights.last ?? 1

        Group {
            if horizontal {
                HStack(spacing: gap) {
                    if let dismissText = dismissText {
                        blockButton(text: dismissText, onClick: onDismiss,
                                    container: colors.secondaryContainer,
                                    content: colors.onSecondaryContainer,
                                    enabled: true,
                                    width: remainingWidth * dismissWeight,
                                    identifier: dismissIdentifier)
                    }
                    if let thirdText = thirdText {
                        blockButton(text: thirdText, onClick: onThird,
                                    container: thirdDestructive ? colors.errorContainer : colors.secondaryContainer,
                                    content: thirdDestructive ? colors.onErrorContainer : colors.onSecondaryContainer,
                                    enabled: true,
                                    width: remainingWidth * thirdWeight)
                    }
                    blockButton(text: confirmText, onClick: onConfirm,
                                container: destructive ? colors.errorContainer : colors.primary,
                                content: destructive ? colors.onErrorContainer : colors.onPrimary,
                                enabled: confirmEnabled,
                                width: remainingWidth * confirmWeight,
                                identifier: confirmIdentifier)
                }
            } else {
                // 竖排降级: 全宽按钮上下堆叠, 文字必然完整。顺序 = 取消 → 第三 → 确认(动作在末位)。
                VStack(spacing: gap) {
                    if let dismissText = dismissText {
                        blockButton(text: dismissText, onClick: onDismiss,
                                    container: colors.secondaryContainer,
                                    content: colors.onSecondaryContainer,
                                    enabled: true,
                                    width: nil,
                                    identifier: dismissIdentifier)
                    }
                    if let thirdText = thirdText {
                        blockButton(text: thirdText, onClick: onThird,
                                    container: thirdDestructive ? colors.errorContainer : colors.secondaryContainer,
                                    content: thirdDestructive ? colors.onErrorContainer : colors.onSecondaryContainer,
                                    enabled: true,
                                    width: nil)
                    }
                    blockButton(text: confirmText, onClick: onConfirm,
                                container: destructive ? colors.errorContainer : colors.primary,
                                content: destructive ? colors.onErrorContainer : colors.onPrimary,
                                enabled: confirmEnabled,
                                width: nil,
                                identifier: confirmIdentifier)
                }
            }
        }
        // ↔ Android BoxWithConstraints(modifier.fillMaxWidth()): 先填满容器给出的宽度,
        // 再经 background 测得自身 = 容器实际宽度(非贪心时测到的是键总宽, 不收敛)
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: DialogContainerWidthKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(DialogContainerWidthKey.self) { measuredWidth = $0 }
    }

    // 2026-09-18 用户: 文字必须完整展示 — 横排按必需宽比例分配(每键 ≥ 文字宽),
    // 竖排全宽更装得下, 两者都不截断。width=nil → 全宽 (fillMaxWidth)。
    // identifier: 调用方传的 XCUITest 锚点, nil = 不挂(其他调用方零变化)。
    @ViewBuilder
    private func blockButton(text: String, onClick: @escaping () -> Void,
                             container: Color, content: Color,
                             enabled: Bool, width: CGFloat?,
                             identifier: String? = nil) -> some View {
        Button(action: onClick) {
            Text(text)
                .font(.system(size: 14, weight: .medium))   // ← labelLarge 14 Medium
                .foregroundColor(content)
                .lineLimit(1)
                .frame(minWidth: width, maxWidth: width ?? .infinity,
                       minHeight: 48, maxHeight: 48)   // 48 ← SleepyTheme.Buttons.regularHeight
                .background(container)
                .cornerRadius(SleepyShapes.large)
        }
        .buttonStyle(SleepyButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : SleepyTheme.Alpha.inactive)
        .modifier(OptionalBlockButtonId(id: identifier))
    }
}

// identifier=nil 时不挂 accessibilityIdentifier(避免空锚点), 其他调用方行为不变。
private struct OptionalBlockButtonId: ViewModifier {
    let id: String?
    @ViewBuilder
    func body(content: Content) -> some View {
        if let id = id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}
