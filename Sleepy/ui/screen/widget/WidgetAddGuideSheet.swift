// WidgetAddGuideSheet.swift — 小组件添加引导 sheet (v1.0.64)
// ★ 平台差异(取代 差异表#8 附注的「恒 NOT_SUPPORTED」分支): iOS WidgetKit 无
//   任何应用内程序化 pin API — SDK 实证 AppIntents 无 WidgetShortcut/
//   RelevantShortcut; Intents.INRelevantShortcut.widgetKind(iOS 15+)只能向
//   系统注册建议、弹出时机不可编程(本切片不采用, 理由见设计 §5)。
//   → 画廊点卡片 = 弹本引导页: 三步图文 + 复制组件名供桌面搜索。

import SwiftUI

struct WidgetAddGuideSheet: View {
    @Environment(\.localWakeUpColors) private var colors
    let card: WidgetGalleryCard
    let onDismiss: () -> Void
    @State private var copied = false

    /// 系统小组件库里该条目的显示名 = configurationDisplayName(L10n label),
    /// 用户搜索时输入的就是它(WidgetVariantInfo 注册表单一真源)。
    private var displayName: String { L10n.format(card.variant.displayNameKey) }

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("widget_guide_title"),
                           leadingStyle: .close, onBack: onDismiss)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 组件名行: 名称 + 复制按钮(搜桌面小组件库用)
                    HStack(spacing: 8) {
                        Text(L10n.format("widget_guide_search_hint", displayName))
                            .font(.system(size: 14))
                            .foregroundColor(colors.onSurface)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            UIPasteboard.general.string = displayName
                            withAnimation { copied = true }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 16))
                                Text(copied ? L10n.format("copied")
                                            : L10n.format("widget_guide_copy_name"))
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(colors.primary)
                        }
                        .buttonStyle(SleepyButtonStyle())
                        .accessibilityIdentifier("widget_guide_copy")
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 20)

                    // 该组件形态示意(画廊同款 schematic)
                    WidgetGalleryPreview(kind: card.variant.kind)
                        .aspectRatio(WidgetGalleryData.aspectRatio(of: card.previewFamily),
                                     contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(colors.surfaceContainerHighest)
                        .cornerRadius(8)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 24)

                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, text in
                        stepRow(number: idx + 1, text: text)
                        if idx < steps.count - 1 { Spacer().frame(height: 16) }
                    }
                    Spacer().frame(height: 32)
                }
            }
        }
        .background(colors.background)
        .accessibilityIdentifier("widget_guide_sheet")
    }

    private var steps: [String] {
        [L10n.format("widget_guide_step_hold"),
         L10n.format("widget_guide_step_plus"),
         L10n.format("widget_guide_step_search"),
         L10n.format("widget_guide_step_drag")]
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.onPrimary)
                .frame(width: 24, height: 24)
                .background(colors.primary)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(colors.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("widget_guide_step_\(number)")
    }
}
