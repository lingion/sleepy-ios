import SwiftUI

/// App、全彩 Widget、课程 anchor 的 system 分支唯一解析器。
enum SystemColorScheme {
    static func argb(_ color: Color) -> Int {
        let rgb = CustomSchemeDeriver.rgb(of: color)
        func byte(_ value: Float) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        // 0xFF000000 超 Int 字面量正数范围, 按仓库惯例 UInt 拼位后 bitPattern(CourseColorUtil 同款)。
        let argb = (UInt(0xFF) << 24) | (UInt(byte(rgb.r)) << 16)
                   | (UInt(byte(rgb.g)) << 8) | UInt(byte(rgb.b))
        return Int(bitPattern: argb)
    }

    static func resolve(snapshot: SystemColorSnapshot, dark: Bool,
                        increasedContrast: Bool? = nil) -> WakeUpColorScheme {
        let value = snapshot.isValid ? snapshot : .fallback(.invalidSnapshot)
        let base = CustomSchemeDeriver.derive(systemSeed: value.seed, isDark: dark)
        let target = (increasedContrast ?? value.increasedContrast) ? 7.0 : 4.5
        let primary = pair(base.primary, target: target)
        let secondary = pair(base.secondary, target: target)
        let tertiary = pair(base.tertiary, target: target)
        let pc = pair(base.primaryContainer, target: target)
        let sc = pair(base.secondaryContainer, target: target)
        let tc = pair(base.tertiaryContainer, target: target)
        let error = pair(base.error, target: target)
        let ec = pair(base.errorContainer, target: target)
        // 所有 surface 共用同一文字色，避免容器层级切换时文字对比度失守。
        let onSurface: Color = dark ? .white : .black
        func surface(_ color: Color) -> Color { adjusted(color, against: onSurface, target: target) }
        return WakeUpColorScheme(
            primary: primary.bg, onPrimary: primary.fg,
            primaryContainer: pc.bg, onPrimaryContainer: pc.fg,
            secondary: secondary.bg, onSecondary: secondary.fg,
            secondaryContainer: sc.bg, onSecondaryContainer: sc.fg,
            tertiary: tertiary.bg, onTertiary: tertiary.fg,
            tertiaryContainer: tc.bg, onTertiaryContainer: tc.fg,
            background: surface(base.background), onBackground: onSurface,
            surface: surface(base.surface), onSurface: onSurface,
            surfaceVariant: surface(base.surfaceVariant), onSurfaceVariant: onSurface,
            surfaceContainerLowest: surface(base.surfaceContainerLowest),
            surfaceContainerLow: surface(base.surfaceContainerLow),
            surfaceContainer: surface(base.surfaceContainer),
            surfaceContainerHigh: surface(base.surfaceContainerHigh),
            surfaceContainerHighest: surface(base.surfaceContainerHighest),
            outline: adjusted(base.outline, against: surface(base.surface), target: 3),
            outlineVariant: base.outlineVariant, scrim: base.scrim,
            error: error.bg, onError: error.fg, errorContainer: ec.bg, onErrorContainer: ec.fg)
    }

    static func relativeLuminance(_ color: Color) -> Double {
        let rgb = CustomSchemeDeriver.rgb(of: color)
        func linear(_ component: Float) -> Double {
            let x = Double(component)
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.r) + 0.7152 * linear(rgb.g) + 0.0722 * linear(rgb.b)
    }

    static func contrast(_ a: Color, _ b: Color) -> Double {
        let x = relativeLuminance(a), y = relativeLuminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    private static func pair(_ background: Color, target: Double) -> (bg: Color, fg: Color) {
        let foreground: Color = contrast(background, .black) >= contrast(background, .white) ? .black : .white
        return (adjusted(background, against: foreground, target: target), foreground)
    }

    /// 沿黑/白方向最小混合修正；保持 HSV 模板而非另造 HCT 色盘。
    private static func adjusted(_ color: Color, against other: Color, target: Double) -> Color {
        guard contrast(color, other) < target else { return color }
        let endpoint: Float = contrast(.black, other) >= contrast(.white, other) ? 0 : 1
        let rgb = CustomSchemeDeriver.rgb(of: color)
        func mixed(_ amount: Float) -> Color {
            Color(.sRGB, red: Double(rgb.r + (endpoint - rgb.r) * amount),
                  green: Double(rgb.g + (endpoint - rgb.g) * amount),
                  blue: Double(rgb.b + (endpoint - rgb.b) * amount), opacity: 1)
        }
        var low: Float = 0, high: Float = 1
        for _ in 0..<18 {
            let mid = (low + high) / 2
            if contrast(mixed(mid), other) >= target { high = mid } else { low = mid }
        }
        return mixed(high)
    }
}
