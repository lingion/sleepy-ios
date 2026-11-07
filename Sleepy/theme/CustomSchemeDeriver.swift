// CustomSchemeDeriver.swift — ← ui/theme/CustomSchemeDeriver.kt
// 自定义主题派生引擎 — 色相旋转模板法(M3 色彩角色关系的轻量实现,纯数学可测)。
//
// 算法:以默认淡紫模板(lightScheme/darkScheme,Theme.swift 顶部)为结构基底 —
//   1. 对每个"有色相"的模板角色,读出其 HSV 的 S/V(饱和度/明度)结构,
//      把色相 H 替换为该角色族的种子色相 → 派生色。即模板决定"这个角色该多深
//      多灰",用户种子只决定"往哪个色相走" — 与 M3 tonal palette 从种子色
//      生成整组色调的思想一致,但不引入 material-color-utilities 依赖。
//   2. 色相族分配:primary 族 ← 用户 primary;secondary 族 ← 用户 secondary;
//      tertiary 族 ← 用户 tertiary。各族内全部角色同族同色相,深浅由模板的
//      角色间明度差保证。
//   3. 表面族(background/surface/surfaceVariant/surfaceContainer 系/onSurfaceVariant/
//      outline/outlineVariant/onBackground/onSurface)不取种子饱和度 — 用
//      CustomTheme.surfaceHue + surfaceChroma(低 chroma 中性色,推荐 4-12),
//      明度 V 照抄模板角色。深浅两套各自成立。
//   4. error 族/scrim 是语义色,固定照抄模板不派生。
//   5. onPrimary/onSecondary/onTertiary 等文字色按底色亮度自适应
//      (luminance < 0.5 → 白字,否则黑字)。
//
// ★ iOS 适配:模板色是 SwiftUI Color,读 r/g/b 走 UIColor(color).getRed(与
//   CourseColorUtil.luminance 同一手法);产出色一律 Color(.sRGB,red:green:blue:)。
//   HSV 数学全部收在纯 Double/Float 上(不碰 UIKit),与 原版本 纯 JVM 版同构可测。

import SwiftUI
import UIKit

enum CustomSchemeDeriver {

    /// 表面 chroma 限幅上限 — 超过后表面不再"中性",视觉变彩色背景
    static let SURFACE_CHROMA_MAX = 48.0

    // MARK: - 派生入口

    static func derive(theme: CustomTheme, isDark: Bool) -> WakeUpColorScheme {
        derive(theme: theme, isDark: isDark, systemSeed: nil)
    }

    /// 系统单种子入口：复用模板，灰度不走自定义主题的“无色相回落紫色”。
    static func derive(systemSeed: SystemSeedRGB, isDark: Bool) -> WakeUpColorScheme {
        derive(theme: SleepyThemeProvider.defaultSeedTheme, isDark: isDark, systemSeed: systemSeed)
    }

    private static func derive(theme: CustomTheme, isDark: Bool, systemSeed: SystemSeedRGB?) -> WakeUpColorScheme {
        let template = isDark ? darkScheme : lightScheme
        let systemHSV = systemSeed.map { rgbToHsv(r: Float($0.red) / 255, g: Float($0.green) / 255, b: Float($0.blue) / 255) }
        let primaryHue = systemHSV?.h ?? hueOfSeed(theme.primary, fallback: template.primary)
        let secondaryHue = systemHSV?.h ?? hueOfSeed(theme.secondary, fallback: template.secondary)
        let tertiaryHue = systemHSV.map { normalizeHue(Double($0.h + 60)) }
            ?? hueOfSeed(theme.tertiary, fallback: template.tertiary)
        let surfaceHue = systemHSV?.h ?? normalizeHue(theme.surfaceHue)
        let surfaceChroma = systemHSV.map { min($0.s, 0.08) }
            ?? (Float(min(max(theme.surfaceChroma, 0.0), SURFACE_CHROMA_MAX)) / 100.0)

        func chromatic(_ color: Color, _ hue: Float) -> Color {
            guard let systemHSV else { return deriveChromatic(color, hue) }
            let rgb = rgb(of: color)
            let hsv = rgbToHsv(r: rgb.r, g: rgb.g, b: rgb.b)
            return hsvToColor(h: hue, s: min(hsv.s, systemHSV.s), v: hsv.v)
        }

        // 先派生三个角色族的"底色"(on* 文字色要按它们的实际亮度自适应)
        let derivedPrimary = chromatic(template.primary, primaryHue)
        let derivedSecondary = chromatic(template.secondary, secondaryHue)
        let derivedTertiary = chromatic(template.tertiary, tertiaryHue)

        return WakeUpColorScheme(
            primary: derivedPrimary,
            onPrimary: adaptOn(derivedPrimary),
            primaryContainer: chromatic(template.primaryContainer, primaryHue),
            onPrimaryContainer: chromatic(template.onPrimaryContainer, primaryHue),

            secondary: derivedSecondary,
            onSecondary: adaptOn(derivedSecondary),
            secondaryContainer: chromatic(template.secondaryContainer, secondaryHue),
            onSecondaryContainer: chromatic(template.onSecondaryContainer, secondaryHue),

            tertiary: derivedTertiary,
            onTertiary: adaptOn(derivedTertiary),
            tertiaryContainer: chromatic(template.tertiaryContainer, tertiaryHue),
            onTertiaryContainer: chromatic(template.onTertiaryContainer, tertiaryHue),

            background: deriveSurface(template.background, surfaceHue, surfaceChroma),
            onBackground: deriveSurface(template.onBackground, surfaceHue, surfaceChroma),
            surface: deriveSurface(template.surface, surfaceHue, surfaceChroma),
            onSurface: deriveSurface(template.onSurface, surfaceHue, surfaceChroma),
            surfaceVariant: deriveSurface(template.surfaceVariant, surfaceHue, surfaceChroma),
            onSurfaceVariant: deriveSurface(template.onSurfaceVariant, surfaceHue, surfaceChroma),
            surfaceContainerLowest: deriveSurface(template.surfaceContainerLowest, surfaceHue, surfaceChroma),
            surfaceContainerLow: deriveSurface(template.surfaceContainerLow, surfaceHue, surfaceChroma),
            surfaceContainer: deriveSurface(template.surfaceContainer, surfaceHue, surfaceChroma),
            surfaceContainerHigh: deriveSurface(template.surfaceContainerHigh, surfaceHue, surfaceChroma),
            surfaceContainerHighest: deriveSurface(template.surfaceContainerHighest, surfaceHue, surfaceChroma),

            outline: deriveSurface(template.outline, surfaceHue, surfaceChroma),
            outlineVariant: deriveSurface(template.outlineVariant, surfaceHue, surfaceChroma),
            scrim: template.scrim,

            error: template.error,
            onError: template.onError,
            errorContainer: template.errorContainer,
            onErrorContainer: template.onErrorContainer
        )
    }

    // MARK: - 角色派生

    /// 有色相角色派生:保留模板角色的 S/V 结构,替换色相。
    /// 模板角色本身无色相(纯白/纯黑/纯灰,S≈0)→ 色相替换无视觉意义,照抄模板。
    private static func deriveChromatic(_ templateColor: Color, _ seedHue: Float) -> Color {
        let rgb = rgb(of: templateColor)
        let hsv = rgbToHsv(r: rgb.r, g: rgb.g, b: rgb.b)
        // S 极低(≈中性)的角色色相替换不产生可见变化 — 直接保留模板,避免浮点噪声
        if hsv.s < 0.02 { return templateColor }
        return hsvToColor(h: seedHue, s: hsv.s, v: hsv.v)
    }

    /// 表面族派生:模板明度 V + surfaceHue/surfaceChroma 低饱和中性
    private static func deriveSurface(_ templateColor: Color, _ surfaceHue: Float, _ surfaceChroma: Float) -> Color {
        let rgb = rgb(of: templateColor)
        let v = rgbToHsv(r: rgb.r, g: rgb.g, b: rgb.b).v
        return hsvToColor(h: surfaceHue, s: surfaceChroma, v: v)
    }

    /// on* 文字色按派生底色亮度自适应:深底白字,浅底黑字
    private static func adaptOn(_ derivedBase: Color) -> Color {
        luminance(derivedBase) < 0.5 ? .white : .black
    }

    // MARK: - 种子解析

    /// 解析种子 hex 的色相;解析失败/无色相 → 模板同角色色相兜底
    private static func hueOfSeed(_ hex: String, fallback: Color) -> Float {
        guard let color = parseHex(hex) else { return hueOrFallback(fallback) }
        let rgb = rgb(of: color)
        return hueOf(r: rgb.r, g: rgb.g, b: rgb.b) ?? hueOrFallback(fallback)
    }

    private static func hueOrFallback(_ color: Color) -> Float {
        let rgb = rgb(of: color)
        let hsv = rgbToHsv(r: rgb.r, g: rgb.g, b: rgb.b)
        return hsv.s < 0.02 ? 0 : hsv.h
    }

    /// "#RRGGBB" / "#AARRGGBB" 解析;失败返回 null(容错,不抛)
    static func parseHex(_ hex: String) -> Color? {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count == 7 || s.count == 9 else { return nil }
        guard s.hasPrefix("#") else { return nil }
        let body = String(s.dropFirst())
        guard body.allSatisfy({ $0.isHexDigit }) else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: body).scanHexInt64(&value) else { return nil }
        // 6 位 = RGB;8 位 = AARRGGBB(与 原版本 Color(argb) 同序,取低 24 位)
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    // MARK: - 纯 HSV 转换(不碰 UIKit,单测安全)

    /// RGB(0-1)→HSV;返回 (h 0-360, s 0-1, v 0-1)。无色相(s≈0)时 h=0
    static func rgbToHsv(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
        // 原版本: max = maxOf(r,g,b).coerceIn(0,1); min = minOf(r,g,b).coerceIn(0,1)
        let cr = clamped(r), cg = clamped(g), cb = clamped(b)
        let mx = Swift.max(cr, Swift.max(cg, cb))
        let mn = Swift.min(cr, Swift.min(cg, cb))
        let d = mx - mn
        let s = mx <= 0 ? 0 : d / mx
        if d < 1e-6 { return (0, s, mx) }
        var h: Float
        if mx == cr {
            h = 60 * (((cg - cb) / d).truncatingRemainder(dividingBy: 6))
        } else if mx == cg {
            h = 60 * ((cb - cr) / d + 2)
        } else {
            h = 60 * ((cr - cg) / d + 4)
        }
        if h < 0 { h += 360 }
        return (h, min(max(s, 0), 1), mx)
    }

    private static func clamped(_ v: Float) -> Float { min(max(v, 0), 1) }

    /// HSV → 量化到 8-bit 的 RGB(0-1);越界输入收敛后计算,不抛不 NaN
    static func hsvToRgb(h: Float, s: Float, v: Float) -> (r: Float, g: Float, b: Float) {
        let hh = normalizeHue(Double(h))
        let ss = min(max(s, 0), 1)
        let vv = min(max(v, 0), 1)
        let c = vv * ss
        let x = c * (1 - abs((hh / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = vv - c
        let r1: Float, g1: Float, b1: Float
        switch hh {
        case ..<60: (r1, g1, b1) = (c, x, 0)
        case ..<120: (r1, g1, b1) = (x, c, 0)
        case ..<180: (r1, g1, b1) = (0, c, x)
        case ..<240: (r1, g1, b1) = (0, x, c)
        case ..<300: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return (quantize(r1 + m), quantize(g1 + m), quantize(b1 + m))
    }

    /// HSV → Color(h 0-360, s/v 0-1);与 原版本 同样量化到 8-bit
    static func hsvToColor(h: Float, s: Float, v: Float) -> Color {
        let rgb = hsvToRgb(h: h, s: s, v: v)
        return Color(.sRGB, red: Double(rgb.r), green: Double(rgb.g), blue: Double(rgb.b), opacity: 1)
    }

    /// Kotlin `roundToInt()` = Math.round = floor(x+0.5);Swift 默认 `.toNearestOrEven`
    /// 会在 x.5 上分歧(0.3*255=76.5 → Kotlin 77 / Swift-even 76),故显式 awayFromZero。
    private static func quantize(_ channel: Float) -> Float {
        Float(min(255, max(0, Int((channel * 255).rounded(.awayFromZero))))) / 255
    }

    /// 色相归一化到 [0, 360):负值/超 360/NaN/Inf 均收敛
    static func normalizeHue(_ h: Double) -> Float {
        if h.isNaN || h.isInfinite { return 0 }
        let m = h.truncatingRemainder(dividingBy: 360)
        return Float(m < 0 ? m + 360 : m)
    }

    /// 色相探针;无色相(s≈0)返回 nil
    static func hueOf(r: Float, g: Float, b: Float) -> Float? {
        let hsv = rgbToHsv(r: r, g: g, b: b)
        return hsv.s < 1e-4 ? nil : hsv.h
    }

    static func hueOf(_ color: Color) -> Float? {
        let rgb = rgb(of: color)
        return hueOf(r: rgb.r, g: rgb.g, b: rgb.b)
    }

    // MARK: - Color ↔ 分量桥接(iOS 适配层)

    /// 模板/种子 Color → r/g/b(0-1)。
    /// ★ 必须落到 sRGB 再读分量:UIColor(Color) 在高色域设备上可能落在设备 RGB(=Display P3),
    ///   直接 getRed 会读到 P3 分量(sRGB #FF0000 → 0.92/0.20/0),派生与 hex 展示都会跑色。
    ///   本 SDK 没有 CGColor.converting / UIColor.usingColorSpace,故:已是 sRGB 直接读分量,
    ///   否则用 1×1 sRGB 位图上下文绘制一次让 CoreGraphics 做色域转换。
    static func rgb(of color: Color) -> (r: Float, g: Float, b: Float) {
        let ui = UIColor(color)
        let cg = ui.cgColor
        let spaceName = (cg.colorSpace?.name as String?) ?? ""
        if spaceName == (CGColorSpace.sRGB as String) || spaceName == (CGColorSpace.extendedSRGB as String),
           let comps = cg.components, comps.count >= 3 {
            return (Float(comps[0]), Float(comps[1]), Float(comps[2]))
        }
        if let converted = rgbViaSRGBBitmap(cg) { return converted }
        return components(of: ui)
    }

    private static func rgbViaSRGBBitmap(_ cg: CGColor) -> (r: Float, g: Float, b: Float)? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(cg)
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return (Float(pixel[0]) / 255.0, Float(pixel[1]) / 255.0, Float(pixel[2]) / 255.0)
    }

    private static func components(of ui: UIColor) -> (r: Float, g: Float, b: Float) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Float(r), Float(g), Float(b))
    }

    /// BT.601 亮度(与 CourseColorUtil.luminance 同权重)
    static func luminance(_ color: Color) -> Float {
        let rgb = rgb(of: color)
        return 0.299 * rgb.r + 0.587 * rgb.g + 0.114 * rgb.b
    }
}
