// Theme.swift — ← Theme.kt
// 完整 Material You (M3) 调色板 — 基于 switchable.html 的色变量
//
// Surface container 层级体系 (从低到高):
//   surface-dim → surface → surface-bright →
//   surface-container-lowest → surface-container-low → surface-container →
//   surface-container-high → surface-container-highest
//
// Container 角色:
//   primary-container / secondary-container / tertiary-container / error-container
//
// SwiftUI 等价: CompositionLocal → EnvironmentValue;Color(0xFF...) → Color(uiColor:)

import SwiftUI

// MARK: - ← WakeUpColorScheme data class

struct WakeUpColorScheme {
    let primary: Color
    let onPrimary: Color
    let primaryContainer: Color
    let onPrimaryContainer: Color

    let secondary: Color
    let onSecondary: Color
    let secondaryContainer: Color
    let onSecondaryContainer: Color

    let tertiary: Color
    let onTertiary: Color
    let tertiaryContainer: Color
    let onTertiaryContainer: Color

    let background: Color
    let onBackground: Color
    let surface: Color
    let onSurface: Color
    let surfaceVariant: Color
    let onSurfaceVariant: Color
    let surfaceContainerLowest: Color
    let surfaceContainerLow: Color
    let surfaceContainer: Color
    let surfaceContainerHigh: Color
    let surfaceContainerHighest: Color

    let outline: Color
    let outlineVariant: Color
    let scrim: Color

    let error: Color
    let onError: Color
    let errorContainer: Color
    let onErrorContainer: Color
}

// MARK: - 默认淡紫 ← LightScheme / DarkScheme

let lightScheme = WakeUpColorScheme(
    primary: Color(0xFF6750A4),
    onPrimary: .white,
    primaryContainer: Color(0xFFEADDFF),
    onPrimaryContainer: Color(0xFF21005D),

    secondary: Color(0xFF625B71),
    onSecondary: .white,
    secondaryContainer: Color(0xFFE8DEF8),
    onSecondaryContainer: Color(0xFF1D192B),

    tertiary: Color(0xFF7D5260),
    onTertiary: .white,
    tertiaryContainer: Color(0xFFFFD8E4),
    onTertiaryContainer: Color(0xFF31111D),

    background: Color(0xFFFEF7FF),
    onBackground: Color(0xFF1D1B20),
    surface: Color(0xFFFEF7FF),
    onSurface: Color(0xFF1D1B20),
    surfaceVariant: Color(0xFFE7E0EC),
    onSurfaceVariant: Color(0xFF49454F),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFF7F2FA),
    surfaceContainer: Color(0xFFF3EDF7),
    surfaceContainerHigh: Color(0xFFECE6F0),
    surfaceContainerHighest: Color(0xFFE6E0E9),

    outline: Color(0xFF79747E),
    outlineVariant: Color(0xFFCAC4D0),
    scrim: Color(0xFF000000),

    error: Color(0xFFB3261E),
    onError: .white,
    errorContainer: Color(0xFFF9DEDC),
    onErrorContainer: Color(0xFF410E0B)
)

let darkScheme = WakeUpColorScheme(
    primary: Color(0xFFD0BCFF),
    onPrimary: Color(0xFF381E72),
    primaryContainer: Color(0xFF4F378B),
    onPrimaryContainer: Color(0xFFEADDFF),

    secondary: Color(0xFFCCC2DC),
    onSecondary: Color(0xFF332D41),
    secondaryContainer: Color(0xFF4A4458),
    onSecondaryContainer: Color(0xFFE8DEF8),

    tertiary: Color(0xFFEFB8C8),
    onTertiary: Color(0xFF492532),
    tertiaryContainer: Color(0xFF633B48),
    onTertiaryContainer: Color(0xFFFFD8E4),

    background: Color(0xFF141218),
    onBackground: Color(0xFFE6E0E9),
    surface: Color(0xFF141218),
    onSurface: Color(0xFFE6E0E9),
    surfaceVariant: Color(0xFF49454F),
    onSurfaceVariant: Color(0xFFCAC4D0),
    surfaceContainerLowest: Color(0xFF0F0D13),
    surfaceContainerLow: Color(0xFF1D1B20),
    surfaceContainer: Color(0xFF211F26),
    surfaceContainerHigh: Color(0xFF2B2930),
    surfaceContainerHighest: Color(0xFF36343B),

    outline: Color(0xFF938F99),
    outlineVariant: Color(0xFF49454F),
    scrim: Color(0xFF000000),

    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    errorContainer: Color(0xFF8C1D18),
    onErrorContainer: Color(0xFFF9DEDC)
)

// MARK: - 课程色明暗探针调色板 ← CoursePalette(决策 D5-死代码清理)

/// 原有 10 个命名色全库零读取已删;仅保留 primary — CourseColorUtil.isPaletteDark 读它的亮度判定明暗模式。
/// 课程实际配色走 CourseColorUtil 黄金角 HSL(groupId 撒色),不走本调色板。
struct CoursePalette {
    /// 明暗探针用(亮=0xFFEADDFF / 暗=0xFF4F378B),勿用于课程底色
    let primary: Color
}

let lightCoursePalette = CoursePalette(primary: Color(0xFFEADDFF))  // primary-container
let darkCoursePalette = CoursePalette(primary: Color(0xFF4F378B))

// MARK: - ← staticCompositionLocalOf → EnvironmentKey

private struct WakeUpColorsKey: EnvironmentKey {
    static let defaultValue: WakeUpColorScheme = lightScheme
}

private struct CoursePaletteKey: EnvironmentKey {
    static let defaultValue: CoursePalette = lightCoursePalette
}

// ★ v1.0.45 悬浮底栏: 镜像 Android LocalNavExtraBottomPadding
//   浮动模式下由 MainActivity 把 dockExtraDp 注入 CompositionLocal,
//   各 scroll 容器消费并 padding(bottom = 16.dp + navExtra) → 列表最后一行
//   不被悬浮药丸遮挡。iOS 端保持同名契约,AppRoot.floatingTabs 注入,scroll
//   容器读 .localNavExtraBottomPadding 与 Android 一字对齐。docked 模式下为 0。
private struct NavExtraBottomPaddingKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var localWakeUpColors: WakeUpColorScheme {
        get { self[WakeUpColorsKey.self] }
        set { self[WakeUpColorsKey.self] = newValue }
    }
    var localCoursePalette: CoursePalette {
        get { self[CoursePaletteKey.self] }
        set { self[CoursePaletteKey.self] = newValue }
    }
    /// 悬浮底栏额外底部间距(与 Android LocalNavExtraBottomPadding 对齐)
    var localNavExtraBottomPadding: CGFloat {
        get { self[NavExtraBottomPaddingKey.self] }
        set { self[NavExtraBottomPaddingKey.self] = newValue }
    }
}

// MARK: - Material You 字体系统 ← SleepyTypography(M3 type scale)

/// 完整 M3 type scale,对应 Android 1.0.51 的官方字号。
enum SleepyTypography {
    static let displaySmall = Font.system(size: 36)
    static let headlineMedium = Font.system(size: 28)
    static let titleLarge = Font.system(size: 22)
    static let titleMedium = Font.system(size: 16, weight: .medium)
    static let titleSmall = Font.system(size: 14, weight: .medium)
    static let bodyLarge = Font.system(size: 16)
    static let bodyMedium = Font.system(size: 14)
    static let bodySmall = Font.system(size: 12)
    static let labelLarge = Font.system(size: 14, weight: .medium)
    static let labelMedium = Font.system(size: 12, weight: .medium)
    static let labelSmall = Font.system(size: 11, weight: .medium)
}

// MARK: - Material You 形状系统 ← SleepyShapes(card 16 / panel 18-20 / sheet 24-28 / segment 12 / pill full)

enum SleepyShapes {
    static let extraSmall = CGFloat(4)
    static let small = CGFloat(8)
    static let medium = CGFloat(12)
    static let large = CGFloat(16)
    static let extraLarge = CGFloat(28)
}

// MARK: - 全 app 统一按钮样式 ← a.v.1.0.41 按钮热区修复

/// PlainButtonStyle 的 hit-test 只认 label 前景内容(图标/文字 glyph),
/// padding+background 色块不参与命中 → 用户点色块无反应, 必须点中图标/文字。
/// Android Material 按钮整个 View bounds 可点; SleepyButtonStyle 用
/// contentShape(Rectangle()) 恢复该语义, 全 app Button 一律用它, 禁 .plain。
struct SleepyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - 扩展字号 ← SleepyTextStyle(switchable.html 额外尺寸 9/10/13/15)

enum SleepyTextStyle {
    static func micro() -> Font { .system(size: 9) }
    static func smallMeta() -> Font { .system(size: 10) }
    static func dayLabel() -> Font { .system(size: 13, weight: .semibold) }
    static func sectionHead() -> Font { .system(size: 15, weight: .medium) }
}

// MARK: - 全局访问入口 ← SleepyTheme object

// SwiftUI 里 SleepyTheme.colors 由 @Environment 承担(见 EnvironmentValues 扩展);
// 静态部分(形状/字号/alpha)保留同名入口。

enum SleepyTheme {

    /** 统一输入框形状 — 全 app 输入框唯一档位 */
    static let fieldShape: CGFloat = SleepyShapes.medium

    /** 语义 alpha 档位 — 替代散落的野值,全 app 只许这几个 ← Alpha object */
    enum Alpha {
        /** 高内容强调(时间轴文字/主容器上副文字) */
        static let highContent: Double = 0.8
        /** 微弱边界(divider/卡片描边) */
        static let hairline: Double = 0.3
        /** 着色背景(选中态底色/色块背景) */
        static let tinted: Double = 0.12
        /** 未选中态强调减弱(按钮/文字提示) */
        static let inactive: Double = 0.6
    }
}

// MARK: - Color(hex:) 便捷(Compose Color(0xFF...) → SwiftUI)

extension Color {
    init(_ hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - ← SleepyThemeProvider @Composable → SwiftUI ViewModifier

/// "跟随系统"(KEY_SYSTEM)在 iOS 16 的等价:SwiftUI 无 Material You 动态取色 API,
/// 降级为系统语义色(Color(uiColor: .systemBackground 等))构造 scheme — 见 dynamicSystemScheme()。
/// 其他 5 套用预设的 light/dark scheme。
struct SleepyThemeProvider: ViewModifier {
    let darkTheme: Bool
    let themeKey: String
    /// Invalidation token for same-id edits of the selected custom theme. The body intentionally
    /// does not inspect it; a changed value re-runs the modifier and re-reads CustomThemeStore.getById.
    var customThemeVersion: String = ""

    func body(content: Content) -> some View {
        let customThemeInvalidation = customThemeVersion
        _ = customThemeInvalidation
        // "custom:<id>" 走用户自定义主题:CustomThemeStore 读种子 → CustomSchemeDeriver
        //   派生整套深浅 scheme(与 widget resolveWidgetScheme 同一派生函数);已删 id
        //   读不到 → 用默认淡紫种子派生(与 Android Theme.kt 回落语义逐字一致)。
        let isCustom = themeKey.hasPrefix(ThemePresets.CUSTOM_KEY_PREFIX)
        // preset==nil 仅在 "system" → dynamic 分支(Android preset==null 同义)
        let preset: ThemePreset? = (isCustom || themeKey == ThemePresets.KEY_SYSTEM)
            ? nil
            : ThemePresets.byKey(themeKey)

        let wakeColors: WakeUpColorScheme
        let palette: CoursePalette
        if isCustom {
            let id = String(themeKey.dropFirst(ThemePresets.CUSTOM_KEY_PREFIX.count))
            let seed = CustomThemeStore.getById(id) ?? Self.defaultSeedTheme
            wakeColors = CustomSchemeDeriver.derive(theme: seed, isDark: darkTheme)
        } else if let preset = preset {
            wakeColors = darkTheme ? preset.dark : preset.light
        } else {
            wakeColors = Self.dynamicSystemScheme(dark: darkTheme)
        }
        palette = darkTheme ? darkCoursePalette : lightCoursePalette

        return content
            .environment(\.localWakeUpColors, wakeColors)
            .environment(\.localCoursePalette, palette)
    }

    /// "custom:<id>" 的 id 读不到(已删/损坏)时的回落种子 = 默认淡紫。
    /// ← Android Theme.kt 里就地构造的 CustomTheme(#6750A4/#625B71/#7D5260, 265/8)
    static let defaultSeedTheme = CustomTheme(
        id: "",
        name: "",
        primary: "#6750A4",
        secondary: "#625B71",
        tertiary: "#7D5260",
        surfaceHue: 265.0,
        surfaceChroma: 8.0,
        createdAt: 0
    )

    /// Android dynamicColorScheme(context) 的 iOS 等价:系统语义色映射到 M3 槽位
    static func dynamicSystemScheme(dark: Bool) -> WakeUpColorScheme {
        #if os(watchOS)
        // watchOS SDK 无 iOS 语义色族(systemPurple/systemBackground/label 等
        // unavailable) — "system" 主题键在手表回落 M3 默认预设 (默认套主色
        // #6750A4 即本映射 systemPurple 的视觉基准, 两端观感同源)。2026-10 watch 伴侣 App。
        let preset = ThemePresets.byKey(ThemePresets.KEY_DEFAULT)
        return dark ? preset.dark : preset.light
        #else
        WakeUpColorScheme(
            primary: Color(uiColor: .systemPurple),
            onPrimary: dark ? Color(0xFF2D165C) : .white,
            primaryContainer: dark ? Color(0xFF564092) : Color(0xFFEADDFF),
            onPrimaryContainer: dark ? Color(0xFFF2E8FF) : Color(0xFF21005D),
            secondary: Color(uiColor: .systemGray),
            onSecondary: dark ? Color(0xFF2C2638) : .white,
            secondaryContainer: dark ? Color(0xFF524B61) : Color(0xFFE8DEF8),
            onSecondaryContainer: dark ? Color(0xFFF0E7FF) : Color(0xFF1D192B),
            tertiary: Color(uiColor: .systemPink),
            onTertiary: dark ? Color(0xFF472230) : .white,
            tertiaryContainer: dark ? Color(0xFF6E4452) : Color(0xFFFFD8E4),
            onTertiaryContainer: dark ? Color(0xFFFFEAF1) : Color(0xFF31111D),
            background: Color(uiColor: .systemBackground),
            onBackground: Color(uiColor: .label),
            surface: Color(uiColor: .secondarySystemBackground),
            onSurface: Color(uiColor: .label),
            surfaceVariant: Color(uiColor: .tertiarySystemFill),
            onSurfaceVariant: Color(uiColor: .secondaryLabel),
            surfaceContainerLowest: dark ? Color(0xFF100E13) : .white,
            surfaceContainerLow: dark ? Color(0xFF1D1A22) : Color(0xFFF7F2FA),
            surfaceContainer: dark ? Color(0xFF25212B) : Color(0xFFF3EDF7),
            surfaceContainerHigh: dark ? Color(0xFF302C36) : Color(0xFFECE6F0),
            surfaceContainerHighest: dark ? Color(0xFF3B3641) : Color(0xFFE6E0E9),
            outline: dark ? Color(0xFFA9A2AE) : Color(0xFF79747E),
            outlineVariant: dark ? Color(0xFF5C5661) : Color(0xFFCAC4D0),
            scrim: .black,
            error: Color(uiColor: .systemRed),
            onError: dark ? Color(0xFF690005) : .white,
            errorContainer: dark ? Color(0xFF93000A) : Color(0xFFF9DEDC),
            onErrorContainer: dark ? Color(0xFFFFDAD6) : Color(0xFF410E0B)
        )
        #endif
    }
}

extension View {
    /// ← SleepyThemeProvider { content } 用法等价
    func sleepyThemeProvider(darkTheme: Bool, themeKey: String) -> some View {
        modifier(SleepyThemeProvider(darkTheme: darkTheme, themeKey: themeKey))
    }
}
