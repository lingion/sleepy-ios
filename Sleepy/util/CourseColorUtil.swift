// CourseColorUtil.swift — ← util/CourseColorUtil.kt 逐行翻译 (GPL-3.0)
// Compose Color → SwiftUI Color; android.graphics.Color → ARGB Int(0xAARRGGBB)
// CoursePalette 依赖在 D4 主题层落地,此处先以 luminance(UInt32) 覆盖 isPaletteDark 的纯计算。

import SwiftUI

/// 课程底色单一事实来源 — 三层结构（决策 D3）
///
/// 收敛原来分散在 TodayScreen / CourseTableView / WeekGridWidgetProvider /
/// WidgetBitmapRenderers 四处的课程配色私有副本，统一为一份逻辑：
///
/// 决策树（所有入口 100% 同源）：
///   ① 用户自定义颜色（color 非空且非哨兵值）→ 直接返回，colorless 不覆盖手动设色
///   ② colorless=true → 返回中性灰（surfaceVariant，与网格线同色保持一致）
///   ③ 否则 → 黄金角 137.508° 基于 groupId 撒 hue，同门课永远同色
///
/// 三层结构：
///   常量层     — GOLDEN_ANGLE / SENTINEL_COLOR / S_LIGHT / S_DARK / L_LIGHT / L_DARK（各定义一次）
///   纯逻辑层   — stableHue / hasCustomColor（无平台依赖）
///   平台适配层 — pickCourseColorSwiftUI / pickCourseColorInt（两套返回类型，同一份逻辑）
enum CourseColorUtil {

    // ============================ 第一层 · 常量 ============================

    /// 黄金角 137.508°，相邻 id 色差最大化（13 门课最少差 ~27°）
    private static let GOLDEN_ANGLE: Float = 137.508

    /// 哨兵色 "#FF6750A4"，标记「未设置颜色」，与主题默认紫完全相同（Phase2 换 isCustomColor 布尔 + DB migration）
    private static let SENTINEL_COLOR = "#FF6750A4"

    /// 亮色模式饱和度（柔和粉彩，不刺眼）
    private static let S_LIGHT: Float = 0.55

    /// 暗色模式饱和度（沉稳低饱和，可读性好）
    private static let S_DARK: Float = 0.40

    /// 亮色模式亮度
    private static let L_LIGHT: Float = 0.82

    /// 暗色模式亮度
    private static let L_DARK: Float = 0.28

    // ============================ 第二层 · 纯逻辑（无平台依赖） ============================

    /// Kotlin String.hashCode(): s[0]*31^(n-1) + ... (Int 溢出回绕)
    /// Swift String.hashValue 每次进程随机化 → 不能用;必须复刻 Java 算法保证同 groupId 同色且跨端一致
    static func javaHash(_ s: String) -> Int64 {
        var h: Int64 = 0
        for u in s.utf8 {
            h = (h &* 31 &+ Int64(u)) & 0xFFFFFFFF
            if h >= 0x80000000 { h -= 0x100000000 }  // Int32 回绕
        }
        return h
    }

    /// 基于课程组 ID 计算稳定色相（0°~360°）。
    /// hue 种子必须是 groupId（课程身份标识），不能用 course.id（数据库自增主键，随导入顺序漂移）。
    static func stableHue(_ groupId: String) -> Float {
        let prod = Float(Int32(truncatingIfNeeded: javaHash(groupId))) * GOLDEN_ANGLE
        return (prod.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// 判定课程是否有用户自定义颜色：color 非空且非哨兵值。
    /// 哨兵判定收敛到此单点，为后续铺路。
    ///
    /// TODO(Phase2): 哨兵值 #FF6750A4 与主题默认紫完全相同，用户主动选紫主题或导入指定此色
    ///   会被误判为「未设置」→ 需改为 isCustomColor 布尔字段 + DB migration。
    static func hasCustomColor(_ course: CourseEntity) -> Bool {
        !course.color.isEmpty && course.color.uppercased() != SENTINEL_COLOR
    }

    /// 明暗探针 — 读 CoursePalette.primary 亮度。
    /// 注意: 只能用 CoursePalette（亮=0xFFEADDFF / 暗=0xFF4F378B），不能用 WakeUpColorScheme.primary
    /// （亮色=0xFF6750A4 加权亮度 0.38 会被误判为暗色）。
    static func isPaletteDark(_ p: CoursePalette) -> Bool {
        CourseColorUtil.luminance(p.primary) < 0.5
    }

    /// 明暗探针 — 读 CoursePalette.primary 亮度(D4 主题落地后接 CoursePalette)。
    /// 注意: 只能用 CoursePalette（亮=0xFFEADDFF / 暗=0xFF4F378B）。
    static func isPaletteDark(primaryArgb: UInt32) -> Bool {
        let r = Float((primaryArgb >> 16) & 0xFF) / 255
        let g = Float((primaryArgb >> 8) & 0xFF) / 255
        let b = Float(primaryArgb & 0xFF) / 255
        let lum = 0.299 * r + 0.587 * g + 0.114 * b
        return lum < 0.5
    }

    // ============================ 第二层 · 文字色亮度自适应（决策 D5-13） ============================

    /// BT.601 加权亮度（0~1）— 纯函数，权重与人眼感光曲线一致（绿最敏感）。
    /// ARGB Int 版本。
    static func luminance(_ color: Int) -> Float {
        let r = Float((color >> 16) & 0xFF) / 255
        let g = Float((color >> 8) & 0xFF) / 255
        let b = Float(color & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b
    }

    /// SwiftUI Color 版本 — 同 BT.601 权重
    static func luminance(_ color: Color) -> Float {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return Float(0.299 * r + 0.587 * g + 0.114 * b)
    }

    /// 按背景亮度自适应选文字色 — 深色自定义课色上文字必须可读（决策 D5-13）：
    ///   深色底（luminance<0.5） → 白字
    ///   浅色底+浅色主题         → onSurface
    ///   浅色底+暗色主题         → 黑字
    static func textColorOn(bg: Color, isDark: Bool, onSurface: Color) -> Color {
        if luminance(bg) < 0.5 { return .white }
        if isDark { return .black }
        return onSurface
    }

    /// Canvas 路径版本（ARGB Int）— 同一决策树，供 Widget 渲染
    static func textColorOn(bg: Int, isDark: Bool, onSurface: Int) -> Int {
        if luminance(bg) < 0.5 { return 0xFFFFFFFF }
        if isDark { return 0xFF000000 }
        return onSurface
    }

    // ============================ 第二层 · HSL 转换 ============================

    private static func hslRGB(_ h: Float, _ s: Float, _ l: Float) -> (Float, Float, Float) {
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        switch h {
        case ..<60:   return (c, x, 0)
        case ..<120:  return (x, c, 0)
        case ..<180:  return (0, c, x)
        case ..<240:  return (0, x, c)
        case ..<300:  return (x, 0, c)
        default:      return (c, 0, x)
        }
    }

    /// HSL → SwiftUI Color
    static func hslToColor(_ h: Float, _ s: Float, _ l: Float) -> Color {
        let (r, g, b) = hslRGB(h, s, l)
        let m = l - ((1 - abs(2 * l - 1)) * s) / 2
        return Color(red: Double(r + m), green: Double(g + m), blue: Double(b + m))
    }

    /// HSL → ARGB Int（供 Widget Canvas 路径）
    static func hslToColorInt(_ h: Float, _ s: Float, _ l: Float) -> Int {
        let (r0, g0, b0) = hslRGB(h, s, l)
        let m = l - ((1 - abs(2 * l - 1)) * s) / 2
        let r = Int((min(max(r0 + m, 0), 1)) * 255)
        let g = Int((min(max(g0 + m, 0), 1)) * 255)
        let b = Int((min(max(b0 + m, 0), 1)) * 255)
        return (0xFF << 24) | (r << 16) | (g << 8) | b
    }

    // ============================ 第三层 · 平台适配入口 ============================

    /// "#RRGGBB" 或 "#AARRGGBB" 解析(= android.graphics.Color.parseColor 的子集)
    /// 6 位省略 alpha=FF; 8 位完整。
    static func parseColor(_ hex: String) -> Int? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 6 {
            s = "FF" + s
        }
        guard s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        return Int(v)
    }

    /// SwiftUI 路径取色入口（TodayScreen / CourseTableView）
    /// - neutralColor: colorless 灰底，即 scheme.surfaceVariant
    static func pickCourseColorSwiftUI(_ course: CourseEntity, isDark: Bool,
                                       neutralColor: Color, colorless: Bool = false) -> Color {
        if hasCustomColor(course), let argb = parseColor(course.color) {
            return Color(uiArgb: UInt32(argb))
        }
        if colorless { return neutralColor }
        let hue = stableHue(course.groupId)
        let s = isDark ? S_DARK : S_LIGHT
        let l = isDark ? L_DARK : L_LIGHT
        return hslToColor(hue, s, l)
    }

    /// Canvas 路径取色入口（Widget 渲染）
    static func pickCourseColorInt(_ course: CourseEntity, isDark: Bool,
                                   neutralColorInt: Int, colorless: Bool = false) -> Int {
        if hasCustomColor(course), let argb = parseColor(course.color) {
            return argb
        }
        if colorless { return neutralColorInt }
        let hue = stableHue(course.groupId)
        let s = isDark ? S_DARK : S_LIGHT
        let l = isDark ? L_DARK : L_LIGHT
        return hslToColorInt(hue, s, l)
    }
}

extension Color {
    /// ARGB UInt32 → SwiftUI Color
    init(uiArgb v: UInt32) {
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: Double((v >> 24) & 0xFF) / 255)
    }
}
