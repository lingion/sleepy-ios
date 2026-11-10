// WidgetGalleryData.swift — ← widget/WidgetGalleryData.kt (v1.0.63)
//
// 画廊卡片 = allWidgetVariants 的 1:1 投影(设计 §4 不变量②)。
// 数量零硬编码: 注册表新增变体, 画廊自动多一张卡片。
// 纯数据、纯函数 — 不触碰 WidgetKit runtime, buildCards 可进单测。
//
// ★ 平台差异(差异表#8 附注):
//   - 原版本: 13 档 base/small/wide × receiver, 预览 = previewImageRes 静态图,
//     卡片框比例 = variant 声明尺寸 widthDp/heightDp (S 110×110 / M 300×160 / L 300×250)。
//   - iOS: 同 kind 的尺寸由 WidgetFamily 承担，画廊按现有 5 kind 出卡。
//     固定样例数据复用生产 SwiftUI renderer；同排按代表 family 面积最大者定框，
//     其他预览按原比例 Fit 居中，不增加外层卡片背景。
//   - receiverName 等价 = kind: WidgetCenter.getCurrentConfigurations 的 kind
//     即 iOS 唯一实例标识(WidgetManagementScreen.swift 头注)。

import Foundation
import WidgetKit

/// ← WidgetGalleryCard: variant 1:1 投影 + iOS 侧代表 family。
struct WidgetGalleryCard: Identifiable {
    let variant: WidgetVariantInfo
    /// 画廊卡展示用的代表 family — 5 kind 各取最代表性尺寸(原 base 档
    /// S/M/L 混排的 iOS 简化, 见文件头注)。
    let previewFamily: WidgetFamily
    var id: String { variant.kind + "|" + previewFamily.description }
    /// ← receiverName = receiverClass.name — iOS kind 即唯一键(冷却/去重锚点)
    var receiverName: String { variant.kind }
}

struct WidgetGalleryGroup: Identifiable {
    let id: String
    let cards: [WidgetGalleryCard]
    var primary: WidgetGalleryCard { cards[0] }
    var isMultiSize: Bool { cards.count > 1 }
}

struct WidgetGalleryRow: Identifiable {
    let groups: [WidgetGalleryGroup]
    var expanded: Bool = false
    var id: String { (expanded ? "expanded|" : "collapsed|") + groups.map(\.id).joined(separator: "|") }
}

enum WidgetGalleryData {
    /// ← buildCards(): ALL_WIDGET_VARIANTS.map { WidgetGalleryCard(it) }。
    /// 代表 family 逐 kind 定版: WeekGrid = 大格网(L 系), Today = 小 glance(S 系),
    /// WeekList / WeekView / TwoDay = 中宽(M 系)。
    static func buildCards() -> [WidgetGalleryCard] {
        allWidgetVariants.map { variant in
            WidgetGalleryCard(variant: variant, previewFamily: previewFamily(for: variant.kind))
        }
    }

    /// WidgetKit exposes size families under each kind. The dedicated wide grid joins its grid family.
    static func buildGroups() -> [WidgetGalleryGroup] {
        #if os(watchOS)
        return buildCards().map { WidgetGalleryGroup(id: $0.variant.kind, cards: [$0]) }
        #else
        var order: [String] = []
        var grouped: [String: [WidgetGalleryCard]] = [:]
        for variant in allWidgetVariants {
            let key = variant.kind == "WeekGridWideWidget" ? "WeekGridWidgetV19" : variant.kind
            if grouped[key] == nil { order.append(key) }
            let families: [WidgetFamily] = variant.kind == "WeekGridWideWidget"
                ? [.systemMedium] : [.systemLarge, .systemMedium, .systemSmall]
            grouped[key, default: []] += families.map { WidgetGalleryCard(variant: variant, previewFamily: $0) }
        }
        return order.map { key in
            WidgetGalleryGroup(id: key, cards: grouped[key]!.sorted {
                let lhs = previewSize(of: $0.previewFamily), rhs = previewSize(of: $1.previewFamily)
                return lhs.width * lhs.height > rhs.width * rhs.height
            })
        }
        #endif
    }

    /// The expanded family occupies a full row; preceding/following groups keep their order.
    static func rows(_ groups: [WidgetGalleryGroup], expandedKey: String?) -> [WidgetGalleryRow] {
        func collapsed(_ items: ArraySlice<WidgetGalleryGroup>) -> [WidgetGalleryRow] {
            let items = Array(items)
            return stride(from: 0, to: items.count, by: 2).map {
                WidgetGalleryRow(groups: Array(items[$0..<min($0 + 2, items.count)]))
            }
        }
        guard let index = groups.firstIndex(where: { $0.id == expandedKey }) else { return collapsed(groups[...]) }
        return collapsed(groups[..<index]) + [WidgetGalleryRow(groups: [groups[index]], expanded: true)] +
            collapsed(groups[(index + 1)...])
    }

    private static func previewFamily(for kind: String) -> WidgetFamily {
        #if os(watchOS)
        // watchOS 无 systemSmall/Medium/Large(WidgetKit 标注 unavailable);
        // 画廊页仅 iOS 承载(ui/screen/widget 不进 watch target) → 本映射在
        // watch 共源编译下不可达, 取 accessory 家族占位保编译。
        return .accessoryCircular
        #else
        switch kind {
        case "WeekGridWidgetV19": return .systemLarge
        case "TodayWidgetRV": return .systemSmall
        default: return .systemMedium
        }
        #endif
    }

    /// Canonical iOS preview canvases; the gallery scales each canvas without stretching.
    static func previewSize(of family: WidgetFamily) -> CGSize {
        #if os(watchOS)
        return CGSize(width: 158, height: 158)
        #else
        switch family {
        case .systemSmall: return CGSize(width: 158, height: 158)
        case .systemMedium: return CGSize(width: 329, height: 158)
        case .systemLarge: return CGSize(width: 329, height: 345)
        default: return CGSize(width: 158, height: 158)
        }
        #endif
    }

    static func aspectRatio(of family: WidgetFamily) -> CGFloat {
        let size = previewSize(of: family)
        return size.width / size.height
    }

    /// Android #231: each row uses the largest declared-area variant as its leader.
    static func rowBoxAspectRatios(_ cards: [WidgetGalleryCard], columns: Int) -> [CGFloat] {
        precondition(columns > 0)
        return cards.indices.map { index in
            let rowStart = index / columns * columns
            let rowEnd = min(rowStart + columns, cards.count)
            var leader = cards[rowStart]
            for card in cards[rowStart..<rowEnd] {
                let candidate = previewSize(of: card.previewFamily)
                let current = previewSize(of: leader.previewFamily)
                if candidate.width * candidate.height > current.width * current.height { leader = card }
            }
            return aspectRatio(of: leader.previewFamily)
        }
    }
}
