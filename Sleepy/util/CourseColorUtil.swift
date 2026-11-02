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
///   ② colorless=true → 返回当前主题最浅的 surface container（secondaryContainer）
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
    static let S_LIGHT: Float = 0.55

    /// 暗色模式饱和度（沉稳低饱和，可读性好）
    static let S_DARK: Float = 0.40

    /// 亮色模式亮度
    static let L_LIGHT: Float = 0.82

    /// 暗色模式亮度
    static let L_DARK: Float = 0.28

    // ============================ 第二层 · 纯逻辑（无平台依赖） ============================

    /// Kotlin String.hashCode(): s[0]*31^(n-1) + ... (Int 溢出回绕)
    /// Java/Kotlin 按 UTF-16 code unit 迭代 → 必须遍历 s.utf16(非 s.utf8),否则中文
    /// groupId(如「高等数学」)两端哈希不同、同课跨端异色,违背本文件「复刻 Java 算法、
    /// 跨端一致」契约。Swift String.hashValue 每次进程随机化 → 不能用。
    static func javaHash(_ s: String) -> Int64 {
        var h: Int64 = 0
        for u in s.utf16 {
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

    /// 复刻 Java Character.isWhitespace 口径(与 Foundation .whitespacesAndNewlines 不同):
    /// 含表意空格 U+3000、OGHAM U+1680、0x1C-0x1F 等;不含不换行空格 U+00A0/U+2007/U+202F。
    /// Kotlin isNotBlank/isNullOrBlank/String.trim 均以此为准,哨兵/空白判定跨端一致必须用此谓词。
    private static func isJavaWhitespace(_ c: Unicode.Scalar) -> Bool {
        switch c.value {
        case 0x0009...0x000D, 0x001C...0x001F, 0x0020,
             0x1680, 0x2000...0x2006, 0x2008...0x200A,
             0x2028, 0x2029, 0x205F, 0x3000:
            return true
        default:
            return false
        }
    }

    /// Kotlin String.isNotBlank() 等价: 非空且不全是 Java 空白字符
    static func isNotBlank(_ s: String) -> Bool {
        return s.unicodeScalars.contains { !isJavaWhitespace($0) }
    }

    /// 判定课程是否有用户自定义颜色：color 非空且非哨兵值。
    /// 哨兵判定收敛到此单点，为后续铺路。
    ///
    /// TODO(Phase2): 哨兵值 #FF6750A4 与主题默认紫完全相同，用户主动选紫主题或导入指定此色
    ///   会被误判为「未设置」→ 需改为 isCustomColor 布尔字段 + DB migration。
    static func hasCustomColor(_ course: CourseEntity) -> Bool {
        // ← isNotBlank 语义(Java Character.isWhitespace 口径,含全角空格 U+3000),与 Kotlin 对齐
        isNotBlank(course.color)
            && course.color.uppercased() != SENTINEL_COLOR
    }

    /// hex-only 版哨兵判定 — 无实体上下文的调用方(改组色 UI 显示组色源)取用,
    /// 判定口径与 hasCustomColor 完全一致,哨兵值仍收敛到 SENTINEL_COLOR 单点。
    static func hasCustomColorHex(_ hex: String) -> Bool {
        isNotBlank(hex) && hex.uppercased() != SENTINEL_COLOR
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
    /// 0xFFFFFFFF 系字面量在 watchOS(arm64_32, Int=32 位)溢 Int 字面量编译不过 →
    /// bitPattern 形态: 64 位 iOS 取值与旧字面量逐位一致, 32 位落 -1/-16777216
    /// (位模式等价, 且本路径在 watch 无调用方)。2026-10 watch 伴侣 App。
    static func textColorOn(bg: Int, isDark: Bool, onSurface: Int) -> Int {
        if luminance(bg) < 0.5 { return Int(bitPattern: 0xFFFFFFFF) }
        if isDark { return Int(bitPattern: 0xFF000000) }
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
    /// watchOS(arm64_32) 下 0xFF<<24 超 Int 字面量范围 → UInt32 域组装后截断回 Int;
    /// 64 位 iOS 取值与旧写法逐位一致。
    static func hslToColorInt(_ h: Float, _ s: Float, _ l: Float) -> Int {
        let (r0, g0, b0) = hslRGB(h, s, l)
        let m = l - ((1 - abs(2 * l - 1)) * s) / 2
        let r = Int((min(max(r0 + m, 0), 1)) * 255)
        let g = Int((min(max(g0 + m, 0), 1)) * 255)
        let b = Int((min(max(b0 + m, 0), 1)) * 255)
        let argb: UInt32 = (UInt32(0xFF) << 24) | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
        return Int(truncatingIfNeeded: argb)
    }

    // ============================ 第三层 · 平台适配入口 ============================

    /// "#RRGGBB" 或 "#AARRGGBB" 解析(= android.graphics.Color.parseColor 语义)
    /// 6 位省略 alpha=FF; 8 位完整。
    /// 与 Android 对齐的硬校验: '#' 前缀必带 —— android.graphics.Color.parseColor 对无 '#'
    /// 输入抛 IllegalArgumentException,上层 runCatching 落空回退 neutral/HSL 分支;
    /// iOS 若照收裸 hex(如 "FF5722")会让坏 hex 自定义色在两端走不同分支。
    static func parseColor(_ hex: String) -> Int? {
        parseColorUInt32(hex).map { Int(truncatingIfNeeded: $0) }
    }

    /// UInt32 形态解析 — SwiftUI 渲染路径专用。watchOS(arm64_32, Int=32 位)上
    /// ARGB>Int32.max 的自定义课色经 Int 中间态会运行时崩溃 (Int(4293589503)),
    /// 本入口从根上绕开; 64 位 iOS 语义与 parseColor 逐位一致。2026-10 watch 伴侣 App。
    static func parseColorUInt32(_ hex: String) -> UInt32? {
        guard hex.hasPrefix("#") else { return nil }
        var s = String(hex.dropFirst())
        if s.count == 6 {
            s = "FF" + s
        }
        guard s.count == 8,
              s.allSatisfy({ $0.isHexDigit }),
              let v = UInt32(s, radix: 16) else { return nil }
        return v
    }

    /// SwiftUI 路径取色入口（TodayScreen / CourseTableView / watch App）
    /// - neutralColor: colorless 统一底色，即 scheme.secondaryContainer
    /// - persistedHue: 派生档持久 hue (v1.0.62 B1)，nil = CLASSIC/查无 → stableHue 老路径。
    static func pickCourseColorSwiftUI(_ course: CourseEntity, isDark: Bool,
                                       neutralColor: Color, colorless: Bool = false,
                                       persistedHue: Float? = nil) -> Color {
        if hasCustomColor(course), let argb = parseColorUInt32(course.color) {
            return Color(uiArgb: argb)
        }
        if colorless { return neutralColor }
        let hue = persistedHue ?? stableHue(course.groupId)
        let s = isDark ? S_DARK : S_LIGHT
        let l = isDark ? L_DARK : L_LIGHT
        return hslToColor(hue, s, l)
    }

    /// Canvas 路径取色入口（Widget 渲染）
    /// - persistedHue: 同 SwiftUI 版 (spec §2.3 三路一致)。
    static func pickCourseColorInt(_ course: CourseEntity, isDark: Bool,
                                   neutralColorInt: Int, colorless: Bool = false,
                                   persistedHue: Float? = nil) -> Int {
        if hasCustomColor(course), let argb = parseColor(course.color) {
            return argb
        }
        if colorless { return neutralColorInt }
        let hue = persistedHue ?? stableHue(course.groupId)
        let s = isDark ? S_DARK : S_LIGHT
        let l = isDark ? L_DARK : L_LIGHT
        return hslToColorInt(hue, s, l)
    }

    // ============================ 第三层 · issue#22 3 态取色入口 ============================
    //
    // 旧 pickCourseColorSwiftUI/pickCourseColorInt 不动 — 语义是"整门课一个色",
    // 被 WidgetContent 之类纯 group-level 渲染路径使用。
    // issue#22 同名课程多地点修复后, WeekGrid/WeekList/Widget/Today 等渲染
    // 每个 block 独立色的入口走下方 *WithGroupRows 版本。

    /// SwiftUI 路径 · issue#22 3 态取色入口。
    /// - row: 目标行; groupRows: 同 groupId 所有行(含 row 自身), AUTO 模式按行序算 hue
    /// - persistedHue: 派生档持久 hue (v1.0.62 B1); nil = CLASSIC 档或查无 → 走 stableHue 老路径。
    ///   GROUP 行: 直接作 base; AUTO 行: 取代「组色源 hex 解析 hue」作黄金角推进的 base。
    ///   优先级红线不变: 单课自定义色 > colorless > persistedHue/stableHue。
    static func pickCourseColorSwiftUIWithGroupRows(
        _ row: CourseEntity, groupRows: [CourseEntity], isDark: Bool,
        neutralColor: Color, colorless: Bool = false, persistedHue: Float? = nil
    ) -> Color {
        switch row.colorMode {
        case CourseColorMode.CUSTOM:
            return parseColorUInt32(row.color).map { Color(uiArgb: $0) } ?? neutralColor
        case CourseColorMode.AUTO:
            if colorless { return neutralColor }
            let hue = GoldenAngleColor.forRow(
                row, groupRows, groupSourceColorHex(groupRows), persistedBaseHue: persistedHue
            )
            let (s, l) = GoldenAngleColor.hsl(hue, isDark)
            return hslToColor(hue, s, l)
        default:  // GROUP(0) 或未知值 → 组级行为
            if hasCustomColor(row), let argb = parseColorUInt32(row.color) {
                return Color(uiArgb: argb)
            }
            if colorless { return neutralColor }
            let hue = persistedHue ?? stableHue(row.groupId)
            let s = isDark ? S_DARK : S_LIGHT
            let l = isDark ? L_DARK : L_LIGHT
            return hslToColor(hue, s, l)
        }
    }

    /// Canvas 路径 · issue#22 3 态取色入口 (供 Widget 渲染)
    /// persistedHue 语义与 SwiftUI 版同源 (spec §2.3 三路一致)。
    static func pickCourseColorIntWithGroupRows(
        _ row: CourseEntity, groupRows: [CourseEntity], isDark: Bool,
        neutralColorInt: Int, colorless: Bool = false, persistedHue: Float? = nil
    ) -> Int {
        switch row.colorMode {
        case CourseColorMode.CUSTOM:
            return parseColor(row.color) ?? neutralColorInt
        case CourseColorMode.AUTO:
            if colorless { return neutralColorInt }
            let hue = GoldenAngleColor.forRow(
                row, groupRows, groupSourceColorHex(groupRows), persistedBaseHue: persistedHue
            )
            let (s, l) = GoldenAngleColor.hsl(hue, isDark)
            return hslToColorInt(hue, s, l)
        default:  // GROUP(0) 或未知值 → 组级行为
            if hasCustomColor(row), let argb = parseColor(row.color) {
                return argb
            }
            if colorless { return neutralColorInt }
            let hue = persistedHue ?? stableHue(row.groupId)
            let s = isDark ? S_DARK : S_LIGHT
            let l = isDark ? L_DARK : L_LIGHT
            return hslToColorInt(hue, s, l)
        }
    }

    /// 组色源 — 同 groupId 内 colorMode=GROUP 中 id 最小的行的 color
    static func groupSourceColorHex(_ groupRows: [CourseEntity]) -> String {
        var source: CourseEntity? = groupRows
            .filter { $0.colorMode == CourseColorMode.GROUP }
            .min { $0.id < $1.id }
        if source == nil {
            source = groupRows.min { $0.id < $1.id }
        }
        return source?.color ?? ""
    }

    // ============================ v1.0.62 B1 · 安全弧配色 ============================

    /// 安全弧常量 — spec docs/architecture/spec-course-color-harmony-2026-10-18.md §2.2
    /// 色环挖掉两段禁区, 把 [0,240) 均匀映射进剩余两允许弧。
    private static let ARC_UNITS: Int = 240       // 允许弧参数域大小
    private static let ARC_STEP_DEG: Int = 2        // 扫描步进
    static let MIN_SEP_DEG: Float = 10.0            // 增量避让最小间距

    /// ARGB Int → HSL 色相 (0..360)。无彩度（黑白灰）回 0f — colorToHSL 对灰阶的
    /// hue 是未定义噪声，归零避免 anchor 抖动。供三路径统一解析主题 primary 色相。
    /// 自实现而非 Colorutils.colorToHSL：平台实现对纯绿 (00FF00) 返回 hue=0
    /// （契约测试实测），且自实现保证三路解析逐位一致。
    static func hueOf(_ argb: Int) -> Float {
        let r = Float((argb >> 16) & 0xFF) / 255
        let g = Float((argb >> 8) & 0xFF) / 255
        let b = Float(argb & 0xFF) / 255
        let maxc = max(r, g, b)
        let minc = min(r, g, b)
        let delta = maxc - minc
        if delta < 0.0001 { return 0 }
        var h: Float = 0
        if maxc == r {
            h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxc == g {
            h = (b - r) / delta + 2
        } else {
            h = (r - g) / delta + 4
        }
        h *= 60
        h = h.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return h
    }

    /// Color → HSL 色相 (0..360)。SwiftUI 路径用 UIColor 取色。
    static func hueOf(_ color: Color) -> Float {
        // SwiftUI Color → UIColor → ARGB
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let argb = (Int(a * 255) << 24) | (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
        return hueOf(argb)
    }

    /// 主题和谐化色相 — 安全弧公式（spec §2.2）。
    /// 以 anchor（主题 primary / 用户种子色的色相）为原点，色环挖掉两段禁区，
    /// 把 [0,240) 均匀映射进剩余两允许弧：
    ///   禁区1 [anchor-30°, anchor+30°]   主题保护带 — 课色不与 UI 主色混淆
    ///   禁区2 [anchor+150°, anchor+210°] 补色带     — 杜绝「紫配黄」扎眼（M3 同源规则）
    /// 纯函数确定性：同 (anchor, groupId) 永远同 hue，故落库值与渲染兜底值同源。
    /// 明暗不参与本函数（只切 S/L），hue 跨深浅恒定。
    static func safeArcHue(anchor: Float, groupId: String) -> Float {
        return hueFromT(anchor: anchor, t: seedT(groupId))
    }

    /// safeArcHue 的 t 种子: hashCode → [0,240) 均匀映射（两段 120° 允许弧的参数域）。
    private static func seedT(_ groupId: String) -> Int {
        return Int(javaHash(groupId) & 0x7FFFFFFF) % ARC_UNITS
    }

    /// t ∈ [0,240) → hue: [0,120) 落允许弧A (anchor+30..150)，[120,240) 落允许弧B (anchor+210..330)。
    private static func hueFromT(anchor: Float, t: Int) -> Float {
        let offset: Float = t < ARC_UNITS / 2 ? 30 + Float(t) : 210 + Float(t - ARC_UNITS / 2)
        return (((anchor + offset).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360))
    }

    /// 环上最短角距 (0..180)。
    private static func ringDelta(_ a: Float, _ b: Float) -> Float {
        var d = ((a - b).truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        if d > 180 { d = 360 - d }
        return d
    }

    /// 增量避让取色 — 重算/写表路径专用（spec §2.3 触发 1/2/3/6, §2.4 新课补色）。
    /// 纯哈希 safeArcHue 在 240° 弧上对任意 13 门课做不到 ≥10° 保证间距
    /// （碰撞模拟实证 worst-case ≈0°），故落库时按 taken 列表增量滑位：
    ///   ① 以 safeArcHue 产出为起点 t0，沿弧参数 t 每次 +2 扫描整圈；
    ///   ② 首个与所有 taken 环距 ≥ minSep 的槽位即返回 → 已放置课永不受影响（钉死性:
    ///      taken 只增不改，同前缀重算逐位复现）；
    ///   ③ 弧饱和（>~24 门）时无解不抛异常，退化为「与 taken 最小环距最大」的槽位 —
    ///      仍在允许弧，只是间距妥协（可见行为：课极多时相邻课色趋近，不撞主题/补色区）。
    /// 两允许弧之间的跨弧环距恒 ≥ 60°（禁区几何保证），间距约束只在同弧内起作用。
    /// 纯函数确定性：同 (anchor, groupId, taken) 永远同 hue。
    static func resolveHueWithSpacing(
        anchor: Float, groupId: String, taken: [Float],
        minSep: Float = MIN_SEP_DEG
    ) -> Float {
        let t0 = seedT(groupId)
        if taken.isEmpty { return hueFromT(anchor: anchor, t: t0) }
        var t = t0
        var bestT = t0
        var bestGap: Float = -1
        let steps = ARC_UNITS / ARC_STEP_DEG
        for _ in 0..<steps {
            let hue = hueFromT(anchor: anchor, t: t)
            let gap = taken.map { ringDelta(hue, $0) }.min()!
            if gap >= minSep { return hue }
            if gap > bestGap { bestGap = gap; bestT = t }
            t = (t + ARC_STEP_DEG) % ARC_UNITS
        }
        return hueFromT(anchor: anchor, t: bestT)
    }

    /// 增量补色规划（spec §2.4「新课只增不改」/ §6 测试7 色相层）— 纯函数, 无 DB 依赖:
    ///   gids = 待补色的**新**组（既有组由调用方过滤, 钉死性: existing 永不移动）;
    ///   起点 = safeArcHue, 沿 [resolveHueWithSpacing] 避让既有 hue + 本批已产色滑位。
    /// anchor=null（CLASSIC）→ 空规划, 调用方零写入 — 升级默认档 course_colors 保持空表。
    /// 键序 = gids 序（调用方保证确定性, 同输入同输出）。
    static func planHuesForGroups(
        anchor: Float?, existingHues: [Float], gids: [String]
    ) -> [String: Float] {
        if anchor == nil { return [:] }
        let a = anchor!
        var taken = existingHues
        var plan: [String: Float] = [:]
        for gid in gids {
            if plan.keys.contains(gid) { continue } // 同批同名(重复 gid)只产一次, 防双写互撞
            let hue = resolveHueWithSpacing(anchor: a, groupId: gid, taken: taken)
            plan[gid] = hue
            taken.append(hue)
        }
        return plan
    }

    /// 三档模式 anchor 决策（spec §2.1）— 单一事实来源，渲染/重算三路共用：
    ///   CLASSIC → nil（不派生, 渲染走 stableHue 老路径）
    ///   FOLLOW_THEME → 主题 primary 的 hue
    ///   CUSTOM → 用户种子色 hue；种子未初始化(-1)回退主题 hue（升级首进不崩不回红）
    /// 入参 themePrimaryArgb: 解析规则逐条对齐 App 端 SleepyThemeProvider 与 widget
    /// resolveWidgetScheme（system→动态取色在此不可达: 胶水只用于写侧兜底）
    static func resolveAnchor(
        mode: Int, themePrimaryArgb: Int, seedHue: Float
    ) -> Float? {
        switch mode {
        case AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME:
            return hueOf(themePrimaryArgb)
        case AppPrefs.COURSE_COLOR_MODE_CUSTOM:
            if seedHue >= 0 {
                return ((seedHue.truncatingRemainder(dividingBy: 360) + 360)
                    .truncatingRemainder(dividingBy: 360))
            }
            return hueOf(themePrimaryArgb)
        default:
            return nil
        }
    }

    /// 便捷: 用默认主题色解析 anchor。用于 AppearanceScreen/CourseColorSection 的实时预览。
    static func resolveAnchorSafe(mode: Int, seed: Float) -> Float {
        let preset = ThemePresets.byKey(ThemePresets.KEY_DEFAULT)
        let argb = colorToArgb(preset.light.primary)
        return resolveAnchor(mode: mode, themePrimaryArgb: argb, seedHue: seed) ?? 0
    }

    /// Color → ARGB Int (0xAARRGGBB) — 用于 resolveAnchorSafe 的默认主题色。
    private static func colorToArgb(_ color: Color) -> Int {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Int(a * 255) << 24) | (Int(r * 255) << 16) | (Int(g * 255) << 8) | Int(b * 255)
    }

}

// ← GoldenAngleColor (issue#22 AUTO 模式, 不落库确定性重算)
enum GoldenAngleColor {
    private static let GOLDEN_ANGLE_DEG: Float = 137.508
    private static let SATURATION_LIGHT: Float = 0.55
    private static let SATURATION_DARK: Float = 0.40
    private static let LIGHTNESS_LIGHT: Float = 0.82
    private static let LIGHTNESS_DARK: Float = 0.28

    /// forRow — hue = 组色源 hue + idx*137.508°, idx = row.id 在同组行升序中的序号
    /// - persistedBaseHue: 派生档持久 hue（v1.0.62 B1 spec §2.1 决策树 ③）— 非 nil 时取代
    ///   hex 解析作黄金角推进基色（组级基色=持久表值, 行偏移语义不变）; nil = CLASSIC 老路径零变化。
    static func forRow(
        _ row: CourseEntity, _ groupRows: [CourseEntity], _ srcHex: String?,
        persistedBaseHue: Float? = nil
    ) -> Float {
        let baseHue = persistedBaseHue ?? parseHexHue(srcHex)
        let sorted = groupRows.sorted { $0.id < $1.id }
        let idx = sorted.firstIndex { $0.id == row.id } ?? 0
        let raw = baseHue + Float(idx) * GOLDEN_ANGLE_DEG
        return ((raw.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360))
    }

    /// hsl — 由 isDark 定 (saturation, lightness)
    static func hsl(_ hue: Float, _ isDark: Bool) -> (Float, Float) {
        let s = isDark ? SATURATION_DARK : SATURATION_LIGHT
        let l = isDark ? LIGHTNESS_DARK : LIGHTNESS_LIGHT
        return (s, l)
    }

    /// parseHexHue — 空白/坏 hex 回 0 (androidx runCatching+getOrDefault 语义)
    /// 空白口径 = Kotlin isNullOrBlank (Java Character.isWhitespace,含全角空格 U+3000)
    private static func parseHexHue(_ hex: String?) -> Float {
        guard let h = hex, CourseColorUtil.isNotBlank(h) else { return 0 }
        if let argb = CourseColorUtil.parseColorUInt32(h) {
            return rgbToHslHue(Int(truncatingIfNeeded: argb))
        }
        return 0
    }

    /// rgbToHslHue — androidx RGBToHSL 的 hue 分量 (只取 hue)
    private static func rgbToHslHue(_ argb: Int) -> Float {
        let r = Float((argb >> 16) & 0xFF) / 255
        let g = Float((argb >> 8) & 0xFF) / 255
        let b = Float(argb & 0xFF) / 255
        let maxc = max(r, g, b)
        let minc = min(r, g, b)
        if maxc == minc { return 0 }
        let d = maxc - minc
        var h: Float = 0
        if maxc == r {
            h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        } else if maxc == g {
            h = (b - r) / d + 2
        } else {
            h = (r - g) / d + 4
        }
        h = h * 60
        h = h.truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }
        return h
    }
}

extension Color {
    init(uiArgb v: UInt32) {
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: Double((v >> 24) & 0xFF) / 255)
    }
}
