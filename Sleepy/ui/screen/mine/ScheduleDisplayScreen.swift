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
    // 幽灵基线 — 进页那一刻快照,退出页面前不更新
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
                .font(SleepyTypography.labelMedium)   // ← Android labelMedium
                .foregroundColor(colors.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            conflictStylePicker
            conflictStyleSlider
        }
        .onAppear { captureBaselines() }
    }

    private var conflictStylePicker: some View {
        // ← Android ScheduleDisplayScreen.kt SegmentedSwitcher(options,
        //   selected = conflictStyle, containerColor = surfaceContainerHighest) +
        //   Modifier.fillMaxWidth(): Picker(.segmented) 无法 honor containerColor
        //   降对比与 thumb 弹簧, 换共享组件(PeriodHeaderSettingsScreen 同款)。
        //   Android 无 height 覆盖 → 组件默认 42pt, 不外加 frame。
        SegmentedSwitcher(
            options: [("stack", L10n.t("settings_conflict_stack")),
                      ("fold", L10n.t("settings_conflict_fold")),
                      ("rail", L10n.t("settings_conflict_rail"))],
            selected: conflictStyle,
            onSelect: { v in
                // ← Android onSelect 内直写 AppPrefs.setConflictStyle, 无 onChange 回路
                conflictStyle = v
                AppPrefs.shared.setConflictStyle(v)
            },
            // ← Android containerColor = surfaceContainerHighest: 铺在页面背景上
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
    // 幽灵基线捕获 — 进页那一刻快照
    private func captureBaselines() {
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
        // ← Android Scaffold/TopAppBar containerColor = colorScheme.background
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
    /// 幽灵基线 — 进页那一刻的初值;拖离原值时显示浅色细条。nil = 不显示幽灵。
    var baseline: Double? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text("\(label)  \(valueText)")
                .font(SleepyTypography.bodyMedium)    // ← Android bodyMedium
                .frame(maxWidth: .infinity, alignment: .leading)
            // 幽灵滑杆: GeometryReader 量轨道宽, 在基线位置叠加细条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Slider(
                        value: Binding(
                            get: { value },
                            set: { onValueChange($0) }
                        ),
                        in: range,
                        onEditingChanged: { editing in
                            if !editing { onFinished() }
                        }
                    )
                    // 幽灵细条: 仅当 baseline 存在且当前值偏离基线时显示
                    if let base = baseline {
                        let epsilon = (range.upperBound - range.lowerBound) * 0.025
                        if abs(value - base) > epsilon {
                            let fraction = (base - range.lowerBound) / (range.upperBound - range.lowerBound)
                            // 轨道两端各留约 11pt 给 thumb, 细条投影在可滑动区间内
                            let trackPadding: CGFloat = 11
                            let trackWidth = geo.size.width - trackPadding * 2
                            let xPos = trackPadding + trackWidth * CGFloat(fraction)
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.45))
                                .frame(width: 3, height: 16)
                                .cornerRadius(1.5)
                                .position(x: xPos, y: geo.size.height / 2)
                                .allowsHitTesting(false) // 不吃手势
                        }
                    }
                }
            }
            .frame(height: 32)
        }
    }
}
