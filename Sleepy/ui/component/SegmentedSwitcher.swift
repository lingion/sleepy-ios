// SegmentedSwitcher.swift — ← ui/component/SegmentedSwitcher.kt
// 单选分段按钮 — 主视图模式切换(整周/卡片)。
// M3 SegmentedButton → SwiftUI custom(等价适配:iOS 16 无原生 Material SegmentedButton,
// Picker(segmented) 风格差异大 → 自绘 M3 样式: 40dp 高/选中段 secondaryContainer 底)。

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
                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? colors.onSecondaryContainer : colors.onSurfaceVariant)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            Group {
                                if isSelected {
                                    // 选中段: secondaryContainer 底 + 小圆角浮层
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(colors.secondaryContainer)
                                        .padding(.vertical, 3)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(colors.surfaceContainer)
        .cornerRadius(10)
    }
}
