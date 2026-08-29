// SettingsCards.swift — ← ui/component/SettingsCards.kt
// 设置页公共卡片 — 自 AppearanceScreen 抽出(外观/通用两页共用):
// SectionHeader 分组标题 / SettingsCard 折叠卡 / DisplayModeOption 单选项 / SettingToggleRow 开关行。

import SwiftUI

// ← SectionHeader
struct SectionHeader: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onBackground)
            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

// ← SettingsCard: 折叠卡(箭头随展开旋转, 内容高度+淡入同拍)
struct SettingsCard<Content: View>: View {
    @Environment(\.localWakeUpColors) private var colors
    let title: String
    let expanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    init(title: String, expanded: Bool, onToggle: @escaping () -> Void,
         @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.expanded = expanded
        self.onToggle = onToggle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onToggle) {
                HStack {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(colors.onSurface)
                    Spacer()
                    // 箭头随展开旋转, 与内容动画同拍
                    Image(systemName: "chevron.down")
                        .font(.system(size: 20))
                        .foregroundColor(colors.onSurfaceVariant)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .buttonStyle(SleepyButtonStyle())
            .accessibilityIdentifier("card_\(title)")
            // 展开动画: 高度+淡入同拍
            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    content()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.surfaceContainer)
        .cornerRadius(SleepyShapes.large)
    }
}

// ← DisplayModeOption
struct DisplayModeOption: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    let subtitle: String
    let selected: Bool
    let onClick: () -> Void

    /// G5 锚点(自动取 label)
    var aid: String { "opt_\(label)" }

    var body: some View {
        Button(action: onClick) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 16))
                        .foregroundColor(selected ? colors.primary : colors.onSurface)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(colors.onSurfaceVariant)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20))
                        .foregroundColor(colors.primary)
                }
            }
        }
        .buttonStyle(SleepyButtonStyle())
        .accessibilityIdentifier(aid)
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
    }
}

// ← SettingToggleRow
struct SettingToggleRow: View {
    @Environment(\.localWakeUpColors) private var colors
    let label: String
    let subtitle: String
    let checked: Bool
    let onCheckedChange: (Bool) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(colors.onSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(colors.onSurfaceVariant)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { checked },
                set: { onCheckedChange($0) }
            ))
            .toggleStyle(.switch)
            .tint(colors.primary)   // checkedTrackColor=primary
            .labelsHidden()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }
}
