// WidgetGalleryData.swift — ← widget/WidgetGalleryData.kt (v1.0.62 B4)
//
// 画廊卡片 = allWidgetVariants 的 1:1 投影(设计 §4 不变量②)。
// 数量零硬编码: 注册表新增变体, 画廊自动多一张卡片。
// 纯数据、纯函数 — 不触碰 WidgetKit runtime, buildCards 可进单测。
//
// ★ 平台差异(差异表#8 附注):
//   - 原版本: 13 档 base/small/wide × receiver, 预览 = previewImageRes 静态图,
//     卡片框比例 = variant 声明尺寸 widthDp/heightDp (S 110×110 / M 300×160 / L 300×250)。
//   - iOS: StaticConfiguration 不支持同 kind 多档实例 → 保留 5 kind × family
//     (WidgetVariantInfo.swift 头注), 画廊按 5 kind 出卡; 预览无静态图资源,
//     用 schematic 占位块(WidgetGalleryScreen.WidgetGalleryPreview), 卡片框比例
//     = 代表 family 的真实宽高比 — 与 原版本「缩略图与桌面占地等大比例」同一契约。
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
    var id: String { variant.kind }
    /// ← receiverName = receiverClass.name — iOS kind 即唯一键(冷却/去重锚点)
    var receiverName: String { variant.kind }
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

    /// ← 卡片框 = 该 variant 声明尺寸的真实比例(缩略图与桌面占地等大比例)。
    /// iOS family 真实宽高比: small ≈ 1.0(158×158) / medium ≈ 2.0(329×158) /
    /// large ≈ 0.95(329×345) — 原版本 M 档 1.875 / L 档 1.2 的 iOS 对位。
    static func aspectRatio(of family: WidgetFamily) -> CGFloat {
        #if os(watchOS)
        return 1.0   // watch 共源编译占位(同上, 画廊页仅 iOS 承载)
        #else
        switch family {
        case .systemSmall: return 1.0
        case .systemMedium: return 2.0
        case .systemLarge: return 0.95
        default: return 1.0
        }
        #endif
    }
}
