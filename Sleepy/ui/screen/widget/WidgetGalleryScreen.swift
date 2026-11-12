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
    @Environment(\.sleepyUIStyle) private var uiStyle
    let onDismiss: () -> Void

    // ← v1.0.64: 点卡片 → 该 widget 的添加引导 sheet(平台差异, 文件头注)
    @State private var guideCard: WidgetGalleryCard? = nil
    // ← 每张卡 pin 后的冷却(防连点): receiverName → 冷却中
    @State private var cooling: Set<String> = []
    // ← cards = WidgetGalleryData.buildCards()(数量随注册表走)
    private let groups = WidgetGalleryData.buildGroups()
    @State private var expandedGroupKey: String?

    var body: some View {
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("widget_gallery_title"), onBack: onDismiss)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(WidgetGalleryData.rows(groups, expandedKey: expandedGroupKey)) { row in
                        if row.expanded, let group = row.groups.first {
                            expanded(group)
                        } else {
                            let ratios = WidgetGalleryData.rowBoxAspectRatios(row.groups.map(\.primary), columns: 2)
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(Array(row.groups.enumerated()), id: \.element.id) { index, group in
                                    GalleryCard(card: group.primary, boxAspectRatio: ratios[index],
                                        enabled: !cooling.contains(group.primary.receiverName), title: groupTitle(group)) {
                                        if group.isMultiSize {
                                            withAnimation { expandedGroupKey = group.id }
                                        } else {
                                            tap(group.primary)
                                        }
                                    }
                                }
                                if row.groups.count == 1 { Color.clear.frame(maxWidth: .infinity) }
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(colors.background)
        .navigationBarHidden(true)
        // ← v1.0.64: 原「不支持」snackbar 死胡同 → 添加引导 sheet
        .sheet(item: $guideCard) { card in
            WidgetAddGuideSheet(card: card, onDismiss: { guideCard = nil })
        }
    }

    private func groupTitle(_ group: WidgetGalleryGroup) -> String {
        let name = L10n.format(group.primary.variant.displayNameKey)
        return group.isMultiSize ? name + L10n.format("widget_gallery_multisize") : name
    }

    private func expanded(_ group: WidgetGalleryGroup) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(L10n.format(group.primary.variant.displayNameKey))
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    withAnimation { expandedGroupKey = nil }
                } label: {
                    AndroidSettingsIcon(name: .expandLess, size: 24)
                        .frame(width: uiStyle == .classic ? 48 : nil, height: uiStyle == .classic ? 48 : nil)
                }
                .buttonStyle(SleepyPlatformButtonStyle(cornerRadius: 22, compact: true, shape: .circle))
                .frame(width: 48, height: 48)
                .accessibilityLabel(L10n.format("widget_gallery_collapse"))
                .accessibilityIdentifier("widget_gallery_collapse_\(group.id)")
            }
            .foregroundColor(colors.onSurface)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation { expandedGroupKey = nil } }
            let ratios = WidgetGalleryData.rowBoxAspectRatios(group.cards, columns: 2)
            // Android Row aligns variant columns at the top, including when a title wraps.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .top),
                                GridItem(.flexible(), spacing: 12, alignment: .top)], spacing: 12) {
                ForEach(Array(group.cards.enumerated()), id: \.element.id) { index, card in
                    GalleryCard(card: card, boxAspectRatio: ratios[index],
                        enabled: !cooling.contains(card.receiverName), title: sizeTitle(card)) { tap(card) }
                }
            }
        }
        .padding(14)
        .background(colors.surfaceContainer)
        .cornerRadius(16)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors.outlineVariant.opacity(0.5), lineWidth: 1))
        .accessibilityIdentifier("widget_gallery_expanded_\(group.id)")
    }

    private func sizeTitle(_ card: WidgetGalleryCard) -> String {
        if WeekGridWideMode(kind: card.variant.kind) != nil { return L10n.format(card.variant.displayNameKey) }
        if card.variant.kind == "WeekGridWidgetV19" {
            return L10n.format(card.previewFamily == .systemSmall
                ? "widget_week_grid_small_label" : "widget_week_grid_label")
        }
        let key = card.previewFamily == .systemSmall ? "widget_size_small"
            : card.previewFamily == .systemMedium ? "widget_size_medium" : "widget_size_large"
        return L10n.format(key)
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
    var title: String? = nil
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 8) {
                WidgetGalleryPreview(card: card)
                    .aspectRatio(boxAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .opacity(enabled ? 1 : 0.5)
                    .accessibilityHidden(true)
                Text(title ?? L10n.format(card.variant.displayNameKey))
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
