// PillNavigationBar.swift — ← ui/component/PillNavigationBar.kt
// 胶囊底栏: surfaceContainer 背景 + 4 tab(图标胶囊 64×32 + 下方 label)。
// 选中态: secondaryContainer 胶囊底 / onSurface 文字; 未选中: surfaceVariant 文字。

import SwiftUI

struct PillNavigationBar: View {
    @Environment(\.localWakeUpColors) private var colors
    let items: [PillNavItemData]

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(items) { item in
                PillNavItem(id: item.id, icon: item.icon, label: item.label,
                            selected: item.selected, colors: colors) { item.onClick() }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(colors.surfaceContainer.ignoresSafeArea(edges: .bottom))
    }
}

/// tab 数据(← Tab enum + PillNavItem 参数聚合)
struct PillNavItemData: Identifiable {
    let id: String
    let icon: String          // SF Symbol(← Material icon 等价映射)
    let label: String
    let selected: Bool
    let onClick: () -> Void
}

private struct PillNavItem: View {
    let id: String       // ← G5: 锚点(跨 locale 不变)
    let icon: String
    let label: String
    let selected: Bool
    let colors: WakeUpColorScheme
    let onClick: () -> Void

    // animateColorAsState → SwiftUI 隐式动画(withAnimation 由调用方触发)
    private var pillBg: Color { selected ? colors.secondaryContainer : colors.surfaceContainer }
    private var labelColor: Color { selected ? colors.onSurface : colors.onSurfaceVariant }

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 4) {
                // 图标胶囊 64×32(← shapes.large = 16)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(labelColor)
                    .frame(width: 64, height: 32)
                    .background(pillBg)
                    .cornerRadius(SleepyShapes.large)
                Text(label)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .foregroundColor(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(SleepyButtonStyle())
        .frame(maxWidth: .infinity)
        // ← G5: UI 测试 stable 锚点(每个 tab 一个,跨 locale 不变)
        .accessibilityIdentifier("pill_\(id)")
        .accessibilityLabel(label)
    }
}
