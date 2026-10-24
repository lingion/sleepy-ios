// ColorPickerDialog.swift — ← ui/component/ColorPickerDialog.kt 平台差异说明
//
// 平台差异: Android Compose Canvas 自制 SV/Hue 面板 + 预览 + 按钮行 → iOS 14+ 直接接
// UIColorPickerViewController 原生, 在 NativeColorPicker.swift 落地 (2026-09-11 移植时决策,
// 详见 NativeColorPicker.swift 顶部关于块)。本文件不产出 Swift View, 仅记录等价关系 + 保留
// HSV 纯函数给 NativeColorPicker 复用 (后续可迁移到独立 util)。
//
// Android 端 ColorPickerDialog.kt 翻译要素对照(便于审计/回查):
//   @Composable fun ColorPickerDialog(initialHex, onConfirm, onDismiss)
//   = iOS NativeColorPicker(initialHex, onSelect) + 标题(course_color) + 取消按钮
//   internal fun SVPanel / HueSlider
//   = iOS UIColorPickerViewController (色盘 + 吸管 + 历史色, UIKit 自带)
//   HSV ↔ RGB 换算
//   = iOS UIColor.init(hex:) / toHexString() 扩展, 已位于 NativeColorPicker.swift 内
//   String.format("#%08X") 8 位 hex 输出(含 alpha=FF)
//   = iOS String(format: "#%08X", (0xFF << 24) | (r << 16) | (g << 8) | b), 与 NativeColorPicker 现行实现一致
//
// 1:1 翻译不适用原因: iOS 14+ UIKit 自带取色面板比 Android 自制 SV/Hue 面板更精炼
// (吸管 + 历史色 + 透明度滑杆), 代码量从 ~188 行 → ~50 行。SPEC 平台差异表
// "原生化控件"类。
//
// ⚠ 2026-10-19 F056 复检确认: 下述两处 NativeColorPicker 残余漂移属实(本 agent 禁改他文件,
//   已把精确修复行报给集成者; 本文件 ColorPickerHSV 的截尾取整/非法回退缺陷已对齐 Android):
//   1. 非法 hex 兜底色: NativeColorPicker.swift:42/52 `UIColor(hex: initialHex) ?? .systemBlue`
//      → Android ColorPickerDialog.kt:57-58 getOrDefault(0xFF6750A4)。两处均改为
//        UIColor(hex: initialHex) ?? UIColor(hex: "#FF6750A4")!
//      CustomThemeEditorScreen 直接传 draft.primary/secondary/tertiary, 非法值现会开成 systemBlue。
//   2. 取消语义: Android 取消/onDismissRequest(kotlin:71/129)永不发 onConfirm;
//      iOS NativeColorPicker.swift:74-79 colorPickerViewControllerDidFinish 在「未选色直接关闭」
//      时也提交当前色 → 最小对齐修复 = 该方法改为空实现(不提交)。
//      DidSelect 即点即提交(kotlin 无预览/确认两步)属 2026-09-11 原生化既定决策, 保留。
//
//   ✅ 2026-10-21 F056 round6 收口: 上述两处 NativeColorPicker 修复已由集成者落地
//      (NativeColorPicker.swift:42/52 兜底色 = UIColor(hex: "6750A4")!; :74-76 DidFinish 改空实现
//       不再自动提交)。本文件 ColorPickerHSV 三处对齐复核通过: hsv(from:) 非法回退 #6750A4 =
//       Android getOrDefault; hex() 通道取整 Int(x*255+0.5 floor) = Android (int)(255*v+0.5)
//       半值向上截断(x∈[0,1] 全扫描 0 偏差); 审计员 issue#3「Int((r1+m)*255) 截尾」描述的是旧代码,
//       与现行文件不符, 作废。F056 全部 issue 已闭合。
//
// 接入方 (AddCourseScreen) 已切到 NativeColorPicker; 任何新调用方应直接使用 NativeColorPicker,
// 不应再回退到本文件名的旧接口。本文件保留为「移植差量文档」+ HSV 工具枚举。

import Foundation

/// HSV 换算工具枚举 — 留作 NativeColorPicker / 自定义主题编辑器复用的纯函数集。
/// Android 端 ColorPickerDialog.kt 内部 colorToHSV / HSVToColor 等价;
/// NativeColorPicker 当前直接走 UIColor.init(hex:) / toHexString(), 本枚举备用。
enum ColorPickerHSV {
    /// h ∈ [0, 360), s,v ∈ [0, 1] → #RRGGBB 大写 hex (与 Android #%08X 同形, alpha=FF 占位)
    static func hex(h: Double, s: Double, v: Double) -> String {
        let hh = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let c = v * s
        let x = c * (1 - abs((hh.truncatingRemainder(dividingBy: 2)) - 1))
        let m = v - c
        let (r1, g1, b1): (Double, Double, Double)
        switch Int(hh) {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        // Android Color.HSVToColor: (int)(255.0f * v + 0.5f) = 恒半值向上取整。
        // 用 +0.5 floor 而非 .rounded()(默认 toNearestOrEven), 奇数 .5 平局才与 Android 一致
        // (2026-10-19 F056: 原 .rounded() 在 126.5 这类平局给 126, Android 给 127)。
        let r = Int(((r1 + m) * 255 + 0.5).rounded(.down))
        let g = Int(((g1 + m) * 255 + 0.5).rounded(.down))
        let b = Int(((b1 + m) * 255 + 0.5).rounded(.down))
        return String(format: "#%08X", (0xFF << 24) | (r << 16) | (g << 8) | b)
    }

    /// 解析 #RRGGBB / #AARRGGBB → (h, s, v) — 与 Android Color.colorToHSV 等价。
    /// 非法输入(长度错 / 含非 hex 字符)回退 #6750A4, 对齐 Android
    /// ColorPickerDialog.kt:57-58 `runCatching{toColorInt()}.getOrDefault(0xFF6750A4)`
    /// (2026-10-18 F056: 原实现长度错回白色(0,0,1)、字符错回黑色, 均与 Android 不符)。
    static func hsv(from hex: String) -> (h: Double, s: Double, v: Double) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        // Android toColorInt 要求全串均为 hex 字符, 任一非法字符即抛 → 回退
        let parsed = (cleaned.count == 6 || cleaned.count == 8)
            && cleaned.allSatisfy(\.isHexDigit)
            && Scanner(string: cleaned).scanHexInt64(&rgb)
        guard parsed else {
            return hsv(r: 0x67, g: 0x50, b: 0xA4)   // Android getOrDefault(0xFF6750A4)
        }
        // 6 位与 8 位都取低 24 位(8 位时 alpha=高字节, 丢弃) — 与原实现一致
        return hsv(r: (rgb >> 16) & 0xFF, g: (rgb >> 8) & 0xFF, b: rgb & 0xFF)
    }

    /// RGB(0-255) → HSV, 逐式对齐 android.graphics.Color.colorToHSV。
    private static func hsv(r: UInt64, g: UInt64, b: UInt64) -> (h: Double, s: Double, v: Double) {
        let rf = Double(r) / 255
        let gf = Double(g) / 255
        let bf = Double(b) / 255
        let mx = max(rf, gf, bf)
        let mn = min(rf, gf, bf)
        let d = mx - mn
        var h: Double = 0
        if d > 0 {
            if mx == rf { h = (gf - bf) / d }
            else if mx == gf { h = 2 + (bf - rf) / d }
            else { h = 4 + (rf - gf) / d }
            h *= 60
            if h < 0 { h += 360 }
        }
        let s = mx == 0 ? 0 : d / mx
        return (h, s, mx)
    }
}
