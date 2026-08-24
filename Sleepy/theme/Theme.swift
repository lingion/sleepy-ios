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
    surface: Color(0xFFFFFBFE),
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
    onPrimary: Color(0xFF2D165C),
    primaryContainer: Color(0xFF564092),
    onPrimaryContainer: Color(0xFFF2E8FF),

    secondary: Color(0xFFD8CEE8),
    onSecondary: Color(0xFF2C2638),
    secondaryContainer: Color(0xFF524B61),
    onSecondaryContainer: Color(0xFFF0E7FF),

    tertiary: Color(0xFFF4C3D2),
    onTertiary: Color(0xFF472230),
    tertiaryContainer: Color(0xFF6E4452),
    onTertiaryContainer: Color(0xFFFFEAF1),

    background: Color(0xFF141218),
    onBackground: Color(0xFFF4EEF4),
    surface: Color(0xFF161419),
    onSurface: Color(0xFFF4EEF4),
    surfaceVariant: Color(0xFF4F4A55),
    onSurfaceVariant: Color(0xFFE4DCE8),
    surfaceContainerLowest: Color(0xFF100E13),
    surfaceContainerLow: Color(0xFF1D1A22),
    surfaceContainer: Color(0xFF25212B),
    surfaceContainerHigh: Color(0xFF302C36),
    surfaceContainerHighest: Color(0xFF3B3641),

    outline: Color(0xFFA9A2AE),
    outlineVariant: Color(0xFF5C5661),
    scrim: Color(0xFF000000),

    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6)
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

extension EnvironmentValues {
    var localWakeUpColors: WakeUpColorScheme {
        get { self[WakeUpColorsKey.self] }
        set { self[WakeUpColorsKey.self] = newValue }
    }
    var localCoursePalette: CoursePalette {
        get { self[CoursePaletteKey.self] }
        set { self[CoursePaletteKey.self] = newValue }
    }
}

// MARK: - Material You 字体系统 ← SleepyTypography(M3 type scale)

/// 完整 M3 type scale,对应 switchable.html 字号 (11/12/13/15/22, line-height: 13/16/18/22/28)
enum SleepyTypography {
    static let displaySmall = Font.system(size: 28)                        // lh 36
    static let headlineMedium = Font.system(size: 22)                      // lh 28
    static let titleLarge = Font.system(size: 20, weight: .medium)         // lh 26
    static let titleMedium = Font.system(size: 16, weight: .medium)        // lh 22
    static let titleSmall = Font.system(size: 14, weight: .medium)         // lh 20
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
    static let extraLarge = CGFloat(24)
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

    func body(content: Content) -> some View {
        let preset: ThemePreset? = themeKey == ThemePresets.KEY_SYSTEM
            ? nil   // 标记走 dynamic 分支
            : ThemePresets.byKey(themeKey)

        let wakeColors: WakeUpColorScheme
        let palette: CoursePalette
        if let preset = preset {
            wakeColors = darkTheme ? preset.dark : preset.light
        } else {
            wakeColors = Self.dynamicSystemScheme(dark: darkTheme)
        }
        palette = darkTheme ? darkCoursePalette : lightCoursePalette

        return content
            .environment(\.localWakeUpColors, wakeColors)
            .environment(\.localCoursePalette, palette)
    }

    /// Android dynamicColorScheme(context) 的 iOS 等价:系统语义色映射到 M3 槽位
    static func dynamicSystemScheme(dark: Bool) -> WakeUpColorScheme {
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
    }
}

extension View {
    /// ← SleepyThemeProvider { content } 用法等价
    func sleepyThemeProvider(darkTheme: Bool, themeKey: String) -> some View {
        modifier(SleepyThemeProvider(darkTheme: darkTheme, themeKey: themeKey))
    }
}
