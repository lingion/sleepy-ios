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
import Foundation

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

    /// 表面族/主色替换副本 — widget 侧把动态语义色烘焙成 trait 解析不透明色用
    /// (← WidgetContent.opaqueWidgetSystemScheme)
    func replacing(primary: Color? = nil, onSurface: Color? = nil,
                   onSurfaceVariant: Color? = nil,
                   surface: Color? = nil, surfaceVariant: Color? = nil) -> WakeUpColorScheme {
        WakeUpColorScheme(
            primary: primary ?? self.primary, onPrimary: onPrimary,
            primaryContainer: primaryContainer, onPrimaryContainer: onPrimaryContainer,
            secondary: secondary, onSecondary: onSecondary,
            secondaryContainer: secondaryContainer, onSecondaryContainer: onSecondaryContainer,
            tertiary: tertiary, onTertiary: onTertiary,
            tertiaryContainer: tertiaryContainer, onTertiaryContainer: onTertiaryContainer,
            background: background, onBackground: onBackground,
            surface: surface ?? self.surface, onSurface: onSurface ?? self.onSurface,
            surfaceVariant: surfaceVariant ?? self.surfaceVariant,
            onSurfaceVariant: onSurfaceVariant ?? self.onSurfaceVariant,
            surfaceContainerLowest: surfaceContainerLowest,
            surfaceContainerLow: surfaceContainerLow,
            surfaceContainer: surfaceContainer,
            surfaceContainerHigh: surfaceContainerHigh,
            surfaceContainerHighest: surfaceContainerHighest,
            outline: outline, outlineVariant: outlineVariant, scrim: scrim,
            error: error, onError: onError,
            errorContainer: errorContainer, onErrorContainer: onErrorContainer
        )
    }
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

// ★ v1.0.45 悬浮底栏: 镜像 原版本 LocalNavExtraBottomPadding
//   浮动模式下由 MainActivity 把 dockExtraDp 注入 CompositionLocal,
//   各 scroll 容器消费并 padding(bottom = 16.dp + navExtra) → 列表最后一行
//   不被悬浮药丸遮挡。iOS 端保持同名契约,AppRoot.floatingTabs 注入,scroll
//   容器读 .localNavExtraBottomPadding 与 原版本 一字对齐。docked 模式下为 0。
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
    /// 悬浮底栏额外底部间距(与 原版本 LocalNavExtraBottomPadding 对齐)
    var localNavExtraBottomPadding: CGFloat {
        get { self[NavExtraBottomPaddingKey.self] }
        set { self[NavExtraBottomPaddingKey.self] = newValue }
    }
}

// MARK: - Material You 字体系统 ← SleepyTypography(M3 type scale)

/// 完整 M3 type scale,对应 原版本 1.0.51 的官方字号。
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
/// 原版本 Material 按钮整个 View bounds 可点; SleepyButtonStyle 用
/// contentShape(Rectangle()) 恢复该语义, 全 app Button 一律用它, 禁 .plain。
struct SleepyButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    var dragSource = false

    func makeBody(configuration: Configuration) -> some View {
        #if os(iOS) && !WIDGET_EXT && !WATCH_APP
        let motion = SleepyMotionPolicy(reduceMotion: reduceMotion)
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(motion.pressScale(pressed: configuration.isPressed, enabled: isEnabled, dragSource: dragSource))
            .opacity(configuration.isPressed && isEnabled && !dragSource ? 0.7 : 1.0)
            .animation(motion.fastEffects, value: configuration.isPressed)
        #else
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed && isEnabled && !dragSource ? 0.7 : 1.0)
        #endif
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

/// Small process-local LRU. Derivation runs outside the lock; concurrent misses may
/// compute twice, but callers always receive a value for their immutable input.
final class ThemeValueCache<Key: Equatable, Value> {
    private let capacity: Int
    private let lock = NSLock()
    private var entries: [(key: Key, value: Value)] = []

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    func value(for key: Key, create: () -> Value) -> Value {
        lock.lock()
        if let index = entries.firstIndex(where: { $0.key == key }) {
            let hit = entries.remove(at: index)
            entries.append(hit)
            lock.unlock()
            return hit.value
        }
        lock.unlock()
        let value = create()
        lock.lock()
        defer { lock.unlock() }
        if let index = entries.firstIndex(where: { $0.key == key }) {
            let hit = entries.remove(at: index)
            entries.append(hit)
            return hit.value
        }
        entries.append((key, value))
        if entries.count > capacity { entries.removeFirst() }
        return value
    }
}

/// system 使用公开窗口 tint 快照派生 HSV/M3 角色色；来源不代表壁纸或主屏幕设置。
/// 其他 5 套用预设的 light/dark scheme。
struct SleepyThemeProvider: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.systemColorSnapshot) private var systemSnapshot
    @Environment(\.colorSchemeContrast) private var contrast
    #if os(iOS) && !WIDGET_EXT && !WATCH_APP
    @State private var uiStyle = SleepyUIStyle(preference: AppPrefs.shared.getUiStyle())
    #endif
    let darkTheme: Bool
    let themeKey: String
    /// Same-id edits re-run the modifier. Resolution also reads the current document,
    /// so direct defaults writes and imports cannot leave a cached endpoint stale.
    var customThemeVersion: String = ""

    private struct TerminalKey: Equatable {
        let themeKey: String
        let dark: Bool
        let increasedContrast: Bool
        let customTheme: CustomTheme?
        let systemSeed: SystemSeedRGB?
    }
    private static let customTerminals = ThemeValueCache<TerminalKey, WakeUpColorScheme>(capacity: 16)
    // The raw document is retained once, rather than in every terminal key. Large
    // imports bypass both caches so their strings/rows do not become long-lived.
    private static let customDocuments = ThemeValueCache<String, [CustomTheme]>(capacity: 1)
    private static let maximumCustomDocumentBytes = 32_768
    #if os(iOS) && !WIDGET_EXT && !WATCH_APP
    private static let terminalVectors = ThemeValueCache<TerminalKey, ThemeColorVector>(capacity: 16)
    #endif

    func body(content: Content) -> some View {
        let customThemeInvalidation = customThemeVersion
        _ = customThemeInvalidation
        let snapshot = systemSnapshot ?? SystemColorSeedStore.read()
        let palette = darkTheme ? darkCoursePalette : lightCoursePalette
        #if os(iOS) && !WIDGET_EXT && !WATCH_APP
        let vector = Self.terminalVector(themeKey: themeKey, dark: darkTheme,
            snapshot: snapshot, increasedContrast: contrast == .increased)

        return content
            .modifier(InterpolatedThemeColors(vector: vector, reduceMotion: reduceMotion))
            .animation(reduceMotion ? nil : SleepyMotionPolicy(reduceMotion: false).defaultEffects, value: vector)
            .environment(\.localCoursePalette, palette)
            .environment(\.sleepyUIStyle, uiStyle)
            .toggleStyle(SleepyToggleStyle())
            .onReceive(AppPrefs.shared.uiStylePublisher) { uiStyle = SleepyUIStyle(preference: $0) }
        #else
        let wakeColors = Self.resolve(themeKey: themeKey, dark: darkTheme,
            snapshot: snapshot, increasedContrast: contrast == .increased)
        return content
            .environment(\.localWakeUpColors, wakeColors)
            .environment(\.localCoursePalette, palette)
        #endif
    }

    /// 统一终值解析入口；根布局中的颜色消费者须下沉读取插值后的 environment。
    static func resolve(themeKey: String, dark: Bool, snapshot: SystemColorSnapshot,
                        increasedContrast: Bool) -> WakeUpColorScheme {
        if themeKey == ThemePresets.KEY_SYSTEM {
            return SystemColorScheme.resolve(snapshot: snapshot, dark: dark, increasedContrast: increasedContrast)
        }
        if !themeKey.hasPrefix(ThemePresets.CUSTOM_KEY_PREFIX) {
            let preset = ThemePresets.byKey(themeKey)
            return dark ? preset.dark : preset.light
        }
        let input = terminalInput(themeKey: themeKey, dark: dark, snapshot: snapshot,
                                  increasedContrast: increasedContrast)
        return resolve(input.key, cacheable: input.cacheable)
    }

    #if os(iOS) && !WIDGET_EXT && !WATCH_APP
    /// Only provider endpoints are cached. Presentation vectors remain owned by
    /// InterpolatedThemeColors, including retargeting and reduced-motion behavior.
    static func terminalVector(themeKey: String, dark: Bool, snapshot: SystemColorSnapshot,
                               increasedContrast: Bool) -> ThemeColorVector {
        let input = terminalInput(themeKey: themeKey, dark: dark, snapshot: snapshot,
                                  increasedContrast: increasedContrast)
        let create = {
            ThemeColorVector(scheme: resolve(input.key, cacheable: input.cacheable),
                             dark: dark, increasedContrast: increasedContrast)
        }
        return input.cacheable ? terminalVectors.value(for: input.key, create: create) : create()
    }
    #endif

    private static func terminalInput(themeKey: String, dark: Bool, snapshot: SystemColorSnapshot,
                                      increasedContrast: Bool) -> (key: TerminalKey, cacheable: Bool) {
        var customTheme: CustomTheme?
        var cacheable = true
        if themeKey.hasPrefix(ThemePresets.CUSTOM_KEY_PREFIX) {
            let id = String(themeKey.dropFirst(ThemePresets.CUSTOM_KEY_PREFIX.count))
            let raw = CustomThemeStore.defaults.string(forKey: CustomThemeCore.KEY_THEMES) ?? ""
            cacheable = raw.utf8.count <= maximumCustomDocumentBytes
            let themes = cacheable
                ? customDocuments.value(for: raw) { CustomThemeCore.parse(raw) }
                : CustomThemeCore.parse(raw)
            customTheme = CustomThemeCore.getById(themes, id) ?? defaultSeedTheme
        }
        let seed: SystemSeedRGB? = themeKey == ThemePresets.KEY_SYSTEM
            ? (snapshot.isValid ? snapshot.seed : .fallback) : nil
        return (TerminalKey(themeKey: themeKey, dark: dark, increasedContrast: increasedContrast,
                            customTheme: customTheme, systemSeed: seed), cacheable)
    }

    private static func resolve(_ key: TerminalKey, cacheable: Bool) -> WakeUpColorScheme {
        if let theme = key.customTheme {
            let create = { CustomSchemeDeriver.derive(theme: theme, isDark: key.dark) }
            return cacheable ? customTerminals.value(for: key, create: create) : create()
        }
        if let seed = key.systemSeed {
            return SystemColorScheme.resolve(seed: seed, dark: key.dark,
                                              increasedContrast: key.increasedContrast)
        }
        let preset = ThemePresets.byKey(key.themeKey)
        return key.dark ? preset.dark : preset.light
    }

    /// "custom:<id>" 的 id 读不到(已删/损坏)时的回落种子 = 默认淡紫。
    /// ← 原版本 Theme.kt 里就地构造的 CustomTheme(#6750A4/#625B71/#7D5260, 265/8)
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

    /// 非视图调用方使用共享快照；视图 provider 使用所属窗口环境，避免多窗口串色。
    static func dynamicSystemScheme(dark: Bool) -> WakeUpColorScheme {
        SystemColorScheme.resolve(snapshot: SystemColorSeedStore.read(), dark: dark)
    }
}

extension View {
    /// ← SleepyThemeProvider { content } 用法等价
    func sleepyThemeProvider(darkTheme: Bool, themeKey: String) -> some View {
        modifier(SleepyThemeProvider(darkTheme: darkTheme, themeKey: themeKey))
    }
}
