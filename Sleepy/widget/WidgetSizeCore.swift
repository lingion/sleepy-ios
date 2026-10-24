// WidgetSizeCore.swift — ← widget/WidgetSizeCore.kt (纯逻辑, 无 UI, 可单测)
//
// ★ 平台差异: Android 侧由 RemoteViewsWidgetHelper / WeekGridWidgetProvider 在
//   onUpdate 时读 OPTION_APPWIDGET_SIZES 多份候选后调用本核心定向选一份画 bitmap;
//   iOS WidgetKit 不存在「launcher 给多份尺寸候选」的协议 (family 由用户选定,
//   容器尺寸直接来自渲染环境), 故本表暂不被 iOS UI 消费。逐项原样保留 (含单测),
//   供未来预渲染/尺寸解析路径与两端行为对齐使用。
//
// 小组件尺寸选择核心 — OPTION_APPWIDGET_SIZES 定向选择 + 回退语义。
//
// 背景: API31+ SIZES 在横竖双向 widget 上返回 portrait/landscape 两份。
// 面积最大 ≠ 当前方向 (横 320x140 面积 > 竖 120x300) — 选错方向则 shell bitmap
// 按错误宽高画, launcher fitXY 强拉 → 内容变形。
//
// 策略 (2026-09-10 方向契约): 用摆放 hint (OPTION_APPWIDGET_MIN_WIDTH/MIN_HEIGHT,
// 当前 cell 的宽高下界) 解析当前方向, 不再宽度优先 — 旧行为在真方向对上永远取宽者
// (= 横份), 竖放 (常态) 全部拿到横 w/h。判定序:
//   1. 宽度接近 (±2dp) 的镜像对 → 与 hint 无关, 取高度小者 (滚动分支兜底);
//   2. 有 hint → 取与 hint 长宽比同向 (portrait/landscape) 且贴合 hint 的份;
//   3. 无 hint → 默认竖放, 取 h>=w 的份。
// hint 贴合度 = 两边差的最小绝对值 (与当前 cell 最近), 而非面积 — 折叠态/多 cell
// launcher 可能给 3+ 份, 逐份比较不丢弃任何候选。
//
// dp→pt 1:1 (本项目惯例, 参见 WidgetWindowCore.swift)。

import Foundation

/// 尺寸候选 (宽, 高) dp/pt。
struct WidgetSizeDp: Equatable {
    let w: CGFloat
    let h: CGFloat
}

enum WidgetSizeCore {

    private static let mirrorToleranceDp: CGFloat = 2

    /// 从多份尺寸候选定向选出当前方向的一份。
    /// - Parameters:
    ///   - sizes: 尺寸候选列表 (宽, 高)。
    ///   - hint: 当前 cell (宽, 高), 缺省 nil。
    /// - Returns: 选中的尺寸; 候选为空/全非法时 nil。
    static func pickSizeDp(
        _ sizes: [WidgetSizeDp],
        hint: WidgetSizeDp? = nil
    ) -> WidgetSizeDp? {
        let valid = sizes.filter { $0.w > 0 && $0.h > 0 }
        if valid.isEmpty { return nil }
        if valid.count == 1 { return valid[0] }
        // 镜像判据用宽度接近的两份 (排序仅用于取"最宽 vs 次宽"作对参照)
        let sortedByWidth = valid.sorted { $0.w > $1.w }
        let widest = sortedByWidth[0]
        let second = sortedByWidth[1]
        let mirrorPair = valid.count == 2 &&
            abs(widest.w - second.w) <= mirrorToleranceDp
        if mirrorPair {
            // 宽度接近 = 同一方向两份 (OEM 镜像) — 取高度小者, 高度不足滚动分支兜底
            return widest.h <= second.h ? widest : second
        }
        let hDp = hint.flatMap { ($0.w > 0 && $0.h > 0) ? $0 : nil }
        return valid.min(by: { a, b in
            if let h = hDp {
                // 有 hint: 与当前 cell 两边差之和最小者 (贴合度); 同距取面积小者
                // (高度选偏小走滚动分支安全, 选偏大会压扁内容)
                let fitA = abs(a.w - h.w) + abs(a.h - h.h)
                let fitB = abs(b.w - h.w) + abs(b.h - h.h)
                if fitA != fitB { return fitA < fitB }
                return a.w * a.h < b.w * b.h
            } else {
                // 无 hint 默认竖放: h>=w 的份里取宽度最大 (排版空间优先);
                // 全是横态 (h<w) 时取高度最小 (滚动分支兜底)
                let rankA: Int = a.h >= a.w ? 0 : 1
                let rankB: Int = b.h >= b.w ? 0 : 1
                if rankA != rankB { return rankA < rankB }
                if a.w != b.w { return a.w > b.w }
                return a.h < b.h
            }
        })
    }

    /// 回退 (API<31 / launcher 未给 SIZES)。
    ///
    /// 契约 (API29/30 javadoc): MIN_W/MIN_H = 当前尺寸下界, MAX_W/MAX_H = 能达到的上界。
    /// 旧实现混拼 MIN_W × MAX_H = 下界宽配上界高, 1 行 widget 被画成 5 行长图再压扁。
    /// 新语义: MIN 在用 MIN (同源 = 当前尺寸近似); MIN 缺失退 MAX; 全缺用安全默认。
    static func fallbackSizeDp(minW: Int, minH: Int, maxW: Int, maxH: Int) -> (w: Int, h: Int) {
        let w = minW > 0 ? minW : (maxW > 0 ? maxW : 250)
        let h = minH > 0 ? minH : (maxH > 0 ? maxH : 100)
        return (w, h)
    }
}
