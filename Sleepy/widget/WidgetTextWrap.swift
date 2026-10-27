// WidgetTextWrap.swift — ← WidgetBitmapRenderers.wrapMax2Lines
// Canvas Paint 手动换行的纯函数移植。渲染本体走 SwiftUI lineLimit(2) (平台等价),
// 但 WeekView FIXED 窗口的 heightOf 预算 (行数 × lineH + 3dp) 必须与 Android
// push() 闸门同一 wrapMax2Lines 口径 → 行数判定用本文件, 禁另起炉灶。

import UIKit

enum WidgetTextWrap {
    /// 9sp 常规字重 — WeekView 课名/页脚字号 (Android 闸门 paint 同参)
    static let font = UIFont.systemFont(ofSize: 9)

    /// fontMetrics 行高 ← (fm.descent − fm.ascent) / density
    static var lineH: CGFloat { font.ascender - font.descender }

    private static func width(_ s: String) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    /// Paint.breakText 等价: 从行首起能放进 maxWidth 的最大前缀字符数
    private static func charsFit(_ text: String, _ maxWidth: CGFloat) -> Int {
        let chars = Array(text)
        guard !chars.isEmpty else { return 0 }
        if width(text) <= maxWidth { return chars.count }
        var lo = 0
        var hi = chars.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if width(String(chars[0..<mid])) <= maxWidth { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// ← wrapMax2Lines 逐行: 最多2行; CJK 按字符断行; Latin 断点优先落在
    /// 拟合区最后 20% 内的空格; 行2 放不下 → 二分截断 "…"; 一字都放不下 → 单 "…"
    static func lines(_ text: String, maxWidth: CGFloat) -> [String] {
        let chars = Array(text)
        let fit = charsFit(text, maxWidth)
        if fit <= 0 { return ["…"] }
        if fit >= chars.count { return [text] }

        // 行1断点: 优先空格 (落在拟合区后 20% 才用), 否则字符边界
        var line1End = fit
        var remainderStart = fit
        if let sp = chars[0..<fit].lastIndex(of: " "), sp > 0, CGFloat(sp) > CGFloat(fit) * 4 / 5 {
            line1End = sp
            remainderStart = sp + 1
        }
        let line1 = String(chars[0..<line1End])
        let remainder = Array(chars[remainderStart...])
        if remainder.isEmpty { return [line1] }
        let remStr = String(remainder)
        if width(remStr) <= maxWidth { return [line1, remStr] }

        var lo = 0
        var hi = remainder.count
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if width(String(remainder[0..<mid]) + "…") <= maxWidth { lo = mid } else { hi = mid - 1 }
        }
        let line2 = lo == 0 ? "…" : String(remainder[0..<lo]) + "…"
        return [line1, line2]
    }

    static func lineCount(_ text: String, maxWidth: CGFloat) -> Int {
        lines(text, maxWidth: maxWidth).count
    }
}
