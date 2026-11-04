// ScheduleDisplayScreen.swift — ← ui/screen/mine/ScheduleDisplayScreen.kt
// 课表显示设置页 — 网格/周缩放 + 圆角比例 + 冲突样式三档 + 参数滑杆。
// Reusable body used directly at the bottom of AppearanceScreen.

import SwiftUI

/// 复用主体 — AppearanceScreen 底部直接嵌入。
struct ScheduleDisplayContent: View {
    @Environment(\.localWakeUpColors) private var colors
    @State private var gridScale: Double = AppPrefs.shared.getGridScale()
    @State private var weekScale: Double = AppPrefs.shared.getWeekScale()
    @State private var cornerRatio: Double = AppPrefs.shared.getGridCornerRatio()
    @State private var conflictStyle: String = AppPrefs.shared.getConflictStyle()
    @State private var conflictStackInset: Double = AppPrefs.shared.getConflictStackInset()
    @State private var conflictRailInset: Double = AppPrefs.shared.getConflictRailInset()
    @State private var conflictFoldSize: Double = AppPrefs.shared.getConflictFoldSize()
    // 同一页面身份内仅捕获一次，切换冲突样式/重复 onAppear 都保留进页基线。
    @State private var baselineGridScale: Double? = nil
    @State private var baselineWeekScale: Double? = nil
    @State private var baselineCornerRatio: Double? = nil
    @State private var baselineConflictStackInset: Double? = nil
    @State private var baselineConflictRailInset: Double? = nil
    @State private var baselineConflictFoldSize: Double? = nil

    var body: some View {
        VStack(spacing: 8) {
            DisplaySlider(
                label: L10n.t("settings_pill_scale"), value: $gridScale,
                valueText: "\(Int(gridScale * 100))%", range: 0.7...1.3,
                onValueChange: { gridScale = Double(Int($0 * 20)) / 20 },
                onFinished: { AppPrefs.shared.setGridScale(gridScale) },
                baseline: baselineGridScale
            )
            DisplaySlider(
                label: L10n.t("settings_pill_week_scale"), value: $weekScale,
                valueText: "\(Int(weekScale * 100))%", range: 0.7...1.3,
                onValueChange: { weekScale = Double(Int($0 * 20)) / 20 },
                onFinished: { AppPrefs.shared.setWeekScale(weekScale) },
                baseline: baselineWeekScale
            )
            DisplaySlider(
                label: L10n.t("settings_pill_corner"), value: $cornerRatio,
                valueText: "\(Int(cornerRatio * 100))%", range: 0...2,
                onValueChange: { cornerRatio = Double(Int($0 * 20)) / 20 },
                onFinished: { AppPrefs.shared.setGridCornerRatio(cornerRatio) },
                baseline: baselineCornerRatio
            )
            // 冲突课程样式 — 课表显示 Section 的下级分组: 子标题降级区分
            Text(L10n.t("settings_conflict_style"))
                .font(SleepyTypography.labelMedium)   // ← 原 labelMedium
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            conflictStylePicker
            conflictStyleSlider
        }
        .onAppear { captureBaselines() }
    }

    private var conflictStylePicker: some View {
        // ← 原版本 ScheduleDisplayScreen.kt SegmentedSwitcher(options,
        //   selected = conflictStyle, containerColor = surfaceContainerHighest) +
        //   Modifier.fillMaxWidth(): Picker(.segmented) 无法 honor containerColor
        //   降对比与 thumb 弹簧, 换共享组件(PeriodHeaderSettingsScreen 同款)。
        //   原版本 无 height 覆盖 → 组件默认 42pt, 不外加 frame。
        SegmentedSwitcher(
            options: [("stack", L10n.t("settings_conflict_stack")),
                      ("fold", L10n.t("settings_conflict_fold")),
                      ("rail", L10n.t("settings_conflict_rail"))],
            selected: conflictStyle,
            onSelect: { v in
                // ← 原 onSelect 内直写 AppPrefs.setConflictStyle, 无 onChange 回路
                conflictStyle = v
                AppPrefs.shared.setConflictStyle(v)
            },
            // ← 原 containerColor = surfaceContainerHighest: 铺在页面背景上
            //   同色会隐形, 降一级保持对比
            containerColor: colors.surfaceContainerHighest
        )
    }

    @ViewBuilder
    private var conflictStyleSlider: some View {
        switch conflictStyle {
        case "stack":
            DisplaySlider(
                label: L10n.t("settings_conflict_stack_inset"), value: $conflictStackInset,
                valueText: "\(Int(conflictStackInset))dp",
                range: AppPrefs.CONFLICT_TOP_INSET_RANGE.lowerBound...AppPrefs.CONFLICT_TOP_INSET_RANGE.upperBound,
                onValueChange: { conflictStackInset = $0.rounded() },
                onFinished: { AppPrefs.shared.setConflictStackInset(conflictStackInset) },
                baseline: baselineConflictStackInset
            )
        case "rail":
            DisplaySlider(
                label: L10n.t("settings_conflict_rail_inset"), value: $conflictRailInset,
                valueText: "\(Int(conflictRailInset))dp",
                range: AppPrefs.CONFLICT_TOP_INSET_RANGE.lowerBound...AppPrefs.CONFLICT_TOP_INSET_RANGE.upperBound,
                onValueChange: { conflictRailInset = $0.rounded() },
                onFinished: { AppPrefs.shared.setConflictRailInset(conflictRailInset) },
                baseline: baselineConflictRailInset
            )
        case "fold":
            DisplaySlider(
                label: L10n.t("settings_conflict_fold_size"), value: $conflictFoldSize,
                valueText: "\(Int(conflictFoldSize))dp",
                range: AppPrefs.CONFLICT_FOLD_SIZE_RANGE.lowerBound...AppPrefs.CONFLICT_FOLD_SIZE_RANGE.upperBound,
                onValueChange: { conflictFoldSize = $0.rounded() },
                onFinished: { AppPrefs.shared.setConflictFoldSize(conflictFoldSize) },
                baseline: baselineConflictFoldSize
            )
        default:
            EmptyView()
        }
    }

    private func captureBaselines() {
        guard baselineGridScale == nil else { return }
        baselineGridScale = gridScale
        baselineWeekScale = weekScale
        baselineCornerRatio = cornerRatio
        baselineConflictStackInset = conflictStackInset
        baselineConflictRailInset = conflictRailInset
        baselineConflictFoldSize = conflictFoldSize
    }
}

struct ScheduleDisplayScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .medium))
                }
                .accessibilityLabel(Text(L10n.t("back")))
                Spacer()
                Text(L10n.t("appearance_section_schedule_display"))
                    .font(.headline)
                Spacer()
                Color.clear.frame(width: 30, height: 30)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            ScheduleDisplayContent()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Spacer()
        }
        // ← 原版本 Scaffold/TopAppBar containerColor = colorScheme.background
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.background)
        .navigationBarHidden(true)
    }
}

private struct DisplaySlider: View {
    let label: String
    @Binding var value: Double  // 直接绑定父 view 的 @State;回写量化值,滑块与标签同步
    let valueText: String
    let range: ClosedRange<Double>
    let onValueChange: (Double) -> Void
    let onFinished: () -> Void
    /// 进页初值；nil 时不显示幽灵标记。
    var baseline: Double? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text("\(label)  \(valueText)")
                .font(SleepyTypography.bodyMedium)    // ← 原 bodyMedium
                .frame(maxWidth: .infinity, alignment: .leading)
            NativeBaselineSlider(value: value, range: range, baseline: baseline,
                                 label: label, valueText: valueText,
                                 onValueChange: onValueChange, onFinished: onFinished)
                .frame(height: 32)
        }
    }
}
