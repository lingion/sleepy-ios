#if os(iOS) && !WIDGET_EXT && !WATCH_APP
import SwiftUI
import UIKit

/// 固定 30 槽 × RGBA；zero 也保留 120 维，向量运算不能截断或钳位。
struct ThemeColorVector: VectorArithmetic {
    static let slotCount = 30
    private(set) var components: [Double]

    init(components: [Double]) {
        precondition(components.count == Self.slotCount * 4)
        self.components = components
    }

    init(scheme: WakeUpColorScheme, dark: Bool, increasedContrast: Bool) {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: increasedContrast ? .high : .normal)
        ])
        let space = CGColorSpace(name: CGColorSpace.extendedSRGB)!
        self.init(components: Self.slots(of: scheme).flatMap { color -> [Double] in
            let ui = UIColor(color).resolvedColor(with: traits)
            if let converted = ui.cgColor.converted(to: space, intent: .relativeColorimetric, options: nil),
               let rgba = converted.components, rgba.count == 4 {
                return rgba.map { Double($0) }
            }
            // 现有角色均是 RGB/灰度色；保留 UIKit 桥接兜底，透明度不丢失。
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
            ui.getRed(&r, green: &g, blue: &b, alpha: &a)
            return [Double(r), Double(g), Double(b), Double(a)]
        })
    }

    static func slots(of s: WakeUpColorScheme) -> [Color] {
        [s.primary, s.onPrimary, s.primaryContainer, s.onPrimaryContainer,
         s.secondary, s.onSecondary, s.secondaryContainer, s.onSecondaryContainer,
         s.tertiary, s.onTertiary, s.tertiaryContainer, s.onTertiaryContainer,
         s.background, s.onBackground, s.surface, s.onSurface, s.surfaceVariant, s.onSurfaceVariant,
         s.surfaceContainerLowest, s.surfaceContainerLow, s.surfaceContainer,
         s.surfaceContainerHigh, s.surfaceContainerHighest, s.outline, s.outlineVariant, s.scrim,
         s.error, s.onError, s.errorContainer, s.onErrorContainer]
    }

    var scheme: WakeUpColorScheme {
        func c(_ slot: Int) -> Color {
            let i = slot * 4
            return Color(.sRGB, red: components[i], green: components[i + 1],
                         blue: components[i + 2], opacity: components[i + 3])
        }
        return WakeUpColorScheme(
            primary: c(0), onPrimary: c(1), primaryContainer: c(2), onPrimaryContainer: c(3),
            secondary: c(4), onSecondary: c(5), secondaryContainer: c(6), onSecondaryContainer: c(7),
            tertiary: c(8), onTertiary: c(9), tertiaryContainer: c(10), onTertiaryContainer: c(11),
            background: c(12), onBackground: c(13), surface: c(14), onSurface: c(15),
            surfaceVariant: c(16), onSurfaceVariant: c(17), surfaceContainerLowest: c(18),
            surfaceContainerLow: c(19), surfaceContainer: c(20), surfaceContainerHigh: c(21),
            surfaceContainerHighest: c(22), outline: c(23), outlineVariant: c(24), scrim: c(25),
            error: c(26), onError: c(27), errorContainer: c(28), onErrorContainer: c(29))
    }

    static var zero: Self { Self(components: Array(repeating: 0, count: slotCount * 4)) }
    static func + (lhs: Self, rhs: Self) -> Self {
        Self(components: zip(lhs.components, rhs.components).map { $0 + $1 })
    }
    static func - (lhs: Self, rhs: Self) -> Self {
        Self(components: zip(lhs.components, rhs.components).map { $0 - $1 })
    }
    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    mutating func scale(by rhs: Double) { components = components.map { $0 * rhs } }
    var magnitudeSquared: Double { components.reduce(0) { $0 + $1 * $1 } }
}

/// 一棵内容树，SwiftUI 从当前 presentation vector 接续到新目标。
struct InterpolatedThemeColors: AnimatableModifier {
    var vector: ThemeColorVector
    var reduceMotion = false

    var animatableData: ThemeColorVector {
        get { reduceMotion ? .zero : vector }
        set { if !reduceMotion { vector = newValue } }
    }

    func body(content: Content) -> some View {
        content.environment(\.localWakeUpColors, vector.scheme)
    }
}

/// 根布局不能读自己注入的 environment；下沉消费者以取得每帧插值色。
struct ThemeRoleFill: View {
    @Environment(\.localWakeUpColors) private var colors
    let role: KeyPath<WakeUpColorScheme, Color>
    var body: some View { colors[keyPath: role] }
}

struct ThemePrimaryTint: ViewModifier {
    @Environment(\.localWakeUpColors) private var colors
    func body(content: Content) -> some View { content.tint(colors.primary) }
}
#endif
