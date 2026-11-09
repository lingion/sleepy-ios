// WidgetGalleryScreen.swift — ← ui/screen/widget/WidgetGalleryScreen.kt (v1.0.63)
// 添加小组件画廊页(设计 §3 末层): WidgetManagementScreen 右上「＋」进入, 把
// allWidgetVariants 全部渲染成预览卡片(数量随注册表走, 零硬编码)。
//
// ★ 平台差异(差异表#8 附注, v1.0.64 更新): 原版本 点卡片 = WidgetPinRequest
//   .request 发起系统「添加到主屏幕」确认(requestPinAppWidget); iOS WidgetKit
//   无任何应用内程序化 pin API(SDK 实证: AppIntents 无 WidgetShortcut,
//   INRelevantShortcut.widgetKind 仅系统择时建议、不可编程) → 点卡片弹
//   添加引导 sheet(三步图文 + 复制组件名), 取代此前「恒 NOT_SUPPORTED」
//   死胡同 snackbar。点后该卡禁用 ~2s 防连点(冷却)照搬。

import SwiftUI
import WidgetKit

struct WidgetGalleryScreen: View {
    @Environment(\.localWakeUpColors) private var colors
    let onDismiss: () -> Void

    // ← v1.0.64: 点卡片 → 该 widget 的添加引导 sheet(平台差异, 文件头注)
    @State private var guideCard: WidgetGalleryCard? = nil
    // ← 每张卡 pin 后的冷却(防连点): receiverName → 冷却中
    @State private var cooling: Set<String> = []
    // ← cards = WidgetGalleryData.buildCards()(数量随注册表走)
    private let cards = WidgetGalleryData.buildCards()

    var body: some View {
        let boxAspectRatios = WidgetGalleryData.rowBoxAspectRatios(cards, columns: 2)
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("widget_gallery_title"), onBack: onDismiss)
            ScrollView {
                // ← LazyVerticalGrid(columns = Fixed(2), contentPadding 16,
                //    horizontal/vertical spacing 12)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top),
                                    GridItem(.flexible(), spacing: 12, alignment: .top)],
                          spacing: 12) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        GalleryCard(card: card,
                                    boxAspectRatio: boxAspectRatios[index],
                                    enabled: !cooling.contains(card.receiverName)) {
                            tap(card)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(colors.background)
        .navigationBarHidden(true)
        // ← v1.0.64: 原「不支持」snackbar 死胡同 → 添加引导 sheet
        .sheet(item: $guideCard) { card in
            WidgetAddGuideSheet(card: card, onDismiss: { guideCard = nil })
        }
    }

    /// ← onClick: 冷却置位 → WidgetPinRequest.request → 2s 后解除。
    /// iOS 无 requestPinAppWidget 等价(平台差异, 文件头注) → 弹添加引导 sheet。
    private func tap(_ card: WidgetGalleryCard) {
        guard !cooling.contains(card.receiverName) else { return }
        cooling.insert(card.receiverName)
        withAnimation { guideCard = card }
        // ← scope.launch { delay(2000); cooling.value -= receiverName }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            cooling.remove(card.receiverName)
        }
    }
}

// Android #245: the widget face and its label stand directly on the gallery background.
private struct GalleryCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let card: WidgetGalleryCard
    let boxAspectRatio: CGFloat
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 8) {
                WidgetGalleryPreview(card: card)
                    .aspectRatio(boxAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .opacity(enabled ? 1 : 0.5)
                    .accessibilityHidden(true)
                Text(L10n.format(card.variant.displayNameKey))
                    .font(SleepyTypography.titleSmall)
                    .foregroundColor(enabled ? colors.onSurface : colors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SleepyButtonStyle())
        .disabled(!enabled)
        .accessibilityIdentifier("widget_gallery_card_\(card.variant.kind)")
    }
}
