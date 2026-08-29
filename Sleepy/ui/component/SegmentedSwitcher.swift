// SegmentedSwitcher.swift — ← ui/component/SegmentedSwitcher.kt
// 单选分段按钮 — 主视图模式切换(整周/卡片)。
// M3 SegmentedButton → SwiftUI custom(等价适配:iOS 16 无原生 Material SegmentedButton,
// Picker(segmented) 风格差异大 → 自绘 M3 样式: 总高 42dp/外框 14dp 圆角 surfaceContainer/
// 内衬 4dp/选中段 secondaryContainer 底 12dp 圆角 ← L44-L70)。

import SwiftUI

struct SegmentedSwitcher<T: Hashable>: View {
    @Environment(\.localWakeUpColors) private var colors
    let options: [(T, String)]
    let selected: T
    let onSelect: (T) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, pair in
                let (value, label) = pair
                let isSelected = value == selected
                Button {
                    onSelect(value)
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? colors.onSecondaryContainer : colors.onSurfaceVariant)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            Group {
                                if isSelected {
                                    // 选中段: secondaryContainer 底(12dp 圆角 ← L66)
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(colors.secondaryContainer)
                                }
                            }
                        )
                }
                .buttonStyle(SleepyButtonStyle())
                .accessibilityIdentifier("seg_\(label)")
            }
        }
        .padding(4)                       // ← L47 内衬(选中段浮层与外框间距)
        .frame(maxWidth: .infinity)
        .frame(height: 42)                // ← L45 总高
        .background(colors.surfaceContainer)
        .cornerRadius(14)                 // ← L46 外框圆角
    }
}
