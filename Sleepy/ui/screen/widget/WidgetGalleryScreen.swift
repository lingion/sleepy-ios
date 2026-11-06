// WidgetGalleryScreen.swift — ← ui/screen/widget/WidgetGalleryScreen.kt (v1.0.62 B4)
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
        VStack(spacing: 0) {
            SettingsTopBar(title: L10n.format("widget_gallery_title"), onBack: onDismiss)
            ScrollView {
                // ← LazyVerticalGrid(columns = Fixed(2), contentPadding 16,
                //    horizontal/vertical spacing 12)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                                    GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(cards) { card in
                        GalleryCard(card: card,
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

// ← GalleryCard: Card(padding 10) { Column { Image; Spacer(8); Text } }
private struct GalleryCard: View {
    @Environment(\.localWakeUpColors) private var colors
    let card: WidgetGalleryCard
    let enabled: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 8) {
                // ← Image(painterResource(previewImageRes), ContentScale.Fit):
                //   iOS 无静态预览图 → schematic 占位块(WidgetGalleryData 头注)
                WidgetGalleryPreview(kind: card.variant.kind)
                    // 卡片框 = 代表 family 的真实比例(缩略图与桌面占地等大比例,
                    // 统一比例会让小/中/大脸在框内留白, 与桌面预览不一致)
                    .aspectRatio(WidgetGalleryData.aspectRatio(of: card.previewFamily),
                                 contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(colors.surfaceContainerHighest)
                    .cornerRadius(8)   // ← RoundedCornerShape(8.dp)
                    .opacity(enabled ? 1 : 0.5)
                // ← variant.displayNameRes: titleSmall + maxLines 2 居中
                Text(L10n.format(card.variant.displayNameKey))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(enabled ? colors.onSurface : colors.onSurfaceVariant)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(10)   // ← Card modifier .padding(10.dp)
            .frame(maxWidth: .infinity)
            .background(colors.surfaceContainer)
            .cornerRadius(SleepyShapes.medium)   // ← M3 Card 圆角 medium
        }
        .buttonStyle(SleepyButtonStyle())
        .disabled(!enabled)
        .accessibilityIdentifier("widget_gallery_card_\(card.variant.kind)")
    }
}

// MARK: - schematic 预览(← previewImageRes 的 iOS 等价物)

/// 预览占位块: 按 kind 画该 widget 的形态骨架(色块布局示意, 非真实渲染 —
/// 原版本 预览同为静态图, 不承载真实数据)。
struct WidgetGalleryPreview: View {
    @Environment(\.localWakeUpColors) private var colors
    let kind: String

    /// 占位块底色(与 原版本 预览图 surfaceContainerHighest 底 + 内容块对比同精神)
    private var block: Color { colors.onSurfaceVariant.opacity(0.28) }
    private var accent: Color { colors.primary.opacity(0.55) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                if kind == "WeekGridWidgetV19" {
                    gridPreview(w: w, h: h)
                } else if kind == "TodayWidgetRV" {
                    todayPreview(w: w, h: h)
                } else if kind == "WeekListWidgetRV" {
                    listPreview(w: w, h: h)
                } else if kind == "WeekViewWidgetRV" {
                    columnsPreview(w: w, h: h, groups: 1)
                } else {
                    // TwoDayWidgetRV: 两组竖列(今/明)
                    columnsPreview(w: w, h: h, groups: 2)
                }
            }
        }
    }

    /// 周网格: 顶部星期行 + 节次行 × 课程列块阵(单块 accent = 「当前节」)
    private func gridPreview(w: CGFloat, h: CGFloat) -> some View {
        let cols = 5
        let rows = 4
        let pad = w * 0.06
        let gap = w * 0.02
        let cellW = (w - pad * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let headH = h * 0.12
        let bodyH = h - pad * 2 - headH - gap
        let cellH = (bodyH - gap * CGFloat(rows - 1)) / CGFloat(rows)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<cols, id: \.self) { c in
                RoundedRectangle(cornerRadius: 2)
                    .fill(block)
                    .frame(width: cellW, height: headH * 0.6)
                    .offset(x: pad + CGFloat(c) * (cellW + gap), y: pad)
            }
            ForEach(0..<rows, id: \.self) { r in
                ForEach(0..<cols, id: \.self) { c in
                    let filled = (r * 7 + c * 3) % 5 != 4   // 稀疏点缀, 模拟有课格
                    RoundedRectangle(cornerRadius: 2)
                        .fill((r == 1 && c == 2) ? accent : block.opacity(filled ? 1 : 0.35))
                        .frame(width: cellW, height: cellH)
                        .offset(x: pad + CGFloat(c) * (cellW + gap),
                                y: pad + headH + gap + CGFloat(r) * (cellH + gap))
                }
            }
        }
    }

    /// 今日: 标题行 + 两节课程块(小方卡)
    private func todayPreview(w: CGFloat, h: CGFloat) -> some View {
        let pad = w * 0.1
        return VStack(alignment: .leading, spacing: h * 0.09) {
            RoundedRectangle(cornerRadius: 2)
                .fill(block)
                .frame(width: w * 0.42, height: h * 0.12)
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: w - pad * 2, height: h * 0.26)
            RoundedRectangle(cornerRadius: 3)
                .fill(block)
                .frame(width: (w - pad * 2) * 0.82, height: h * 0.26)
        }
        .padding(pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// 周列表: 三行「星期签 + 课程条」
    private func listPreview(w: CGFloat, h: CGFloat) -> some View {
        let pad = w * 0.06
        return VStack(spacing: h * 0.09) {
            ForEach(0..<3, id: \.self) { r in
                HStack(spacing: w * 0.04) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(r == 0 ? accent : block)
                        .frame(width: w * 0.14, height: h * 0.2)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(block.opacity(r == 2 ? 0.5 : 1))
                        .frame(width: (w - pad * 2) * (r == 1 ? 0.62 : 0.86), height: h * 0.2)
                    Spacer()
                }
            }
        }
        .padding(pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    /// 竖列组: groups=1 周视图(4 列) / groups=2 两日视图(两组各 2 列)
    private func columnsPreview(w: CGFloat, h: CGFloat, groups: Int) -> some View {
        let pad = w * 0.05
        let colW = (w - pad * 2 - w * 0.03 * CGFloat(groups - 1)) / CGFloat(groups * 2)
        return HStack(spacing: groups == 2 ? w * 0.08 : w * 0.03) {
            ForEach(0..<groups * 2, id: \.self) { c in
                VStack(spacing: h * 0.05) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(block)
                        .frame(width: colW, height: h * 0.1)
                    ForEach(0..<3, id: \.self) { r in
                        let show = (c + r) % 3 != 1
                        RoundedRectangle(cornerRadius: 2)
                            .fill((c == 1 && r == 0) ? accent : block.opacity(show ? 1 : 0.3))
                            .frame(width: colW, height: h * (show ? 0.2 : 0.08))
                    }
                }
            }
        }
        .padding(pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
