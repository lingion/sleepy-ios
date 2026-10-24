// ColorStyleSheetConsistencyTests.swift — 设计令牌一致性守卫
// (v1.0.56 起挂账的 TODO 补齐, v1.0.61 交付)
//
// 钉死三类内容, 任何一项被误改(手滑/merge 冲突/重建丢失)即刻红:
//   1. 字体令牌 — SleepyTypography(M3 type scale 11 档)+ SleepyTextStyle(扩展 4 档)
//      逐档钉 size+weight(Font: Equatable, 两参数都在相等判定内)。
//   2. 形状/alpha 令牌 — SleepyShapes 5 档 + SleepyTheme.Alpha 4 档 + fieldShape 联动。
//   3. 色彩结构不变量 — surface container 层级明度单调、on*/base 对比差、
//      outline 对深浅方向、背景表面同值。规则对 lightScheme/darkScheme 与
//      ThemePresets.all 全部预设的 light/dark 成对生效(样式表全表一致性)。
//
// 不钉具体色值(预设色由 CustomThemeTests/ThemeAndPinyinTests 抽查),
// 本文件守的是"结构关系"— 色值合理但层级倒挂(容器比表面深/浅错位)同样红。

import XCTest
import SwiftUI
@testable import Sleepy

final class ColorStyleSheetConsistencyTests: XCTestCase {

    // MARK: - 亮度工具(WCAG 相对亮度, sRGB 线性化后加权和)

    private func relativeLuminance(_ color: Color) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else {
            XCTFail("颜色无法解析为 RGBA")
            return -1
        }
        XCTAssertEqual(a, 1, accuracy: 0.001, "守卫只针对不透明令牌色")
        func linearize(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    // MARK: - 1. 字体令牌(← M3 type scale, Android 1.0.51 官方字号)

    func testM3TypeScaleFontTokens() {
        XCTAssertEqual(SleepyTypography.displaySmall, Font.system(size: 36))
        XCTAssertEqual(SleepyTypography.headlineMedium, Font.system(size: 28))
        XCTAssertEqual(SleepyTypography.titleLarge, Font.system(size: 22))
        XCTAssertEqual(SleepyTypography.titleMedium, Font.system(size: 16, weight: .medium))
        XCTAssertEqual(SleepyTypography.titleSmall, Font.system(size: 14, weight: .medium))
        XCTAssertEqual(SleepyTypography.bodyLarge, Font.system(size: 16))
        XCTAssertEqual(SleepyTypography.bodyMedium, Font.system(size: 14))
        XCTAssertEqual(SleepyTypography.bodySmall, Font.system(size: 12))
        XCTAssertEqual(SleepyTypography.labelLarge, Font.system(size: 14, weight: .medium))
        XCTAssertEqual(SleepyTypography.labelMedium, Font.system(size: 12, weight: .medium))
        XCTAssertEqual(SleepyTypography.labelSmall, Font.system(size: 11, weight: .medium))
    }

    func testExtendedTextStyleFontTokens() {
        // ← switchable.html 额外尺寸 9/10/13/15
        XCTAssertEqual(SleepyTextStyle.micro(), Font.system(size: 9))
        XCTAssertEqual(SleepyTextStyle.smallMeta(), Font.system(size: 10))
        XCTAssertEqual(SleepyTextStyle.dayLabel(), Font.system(size: 13, weight: .semibold))
        XCTAssertEqual(SleepyTextStyle.sectionHead(), Font.system(size: 15, weight: .medium))
    }

    // MARK: - 2. 形状与 alpha 令牌

    func testShapeTokens() {
        XCTAssertEqual(SleepyShapes.extraSmall, 4)
        XCTAssertEqual(SleepyShapes.small, 8)
        XCTAssertEqual(SleepyShapes.medium, 12)
        XCTAssertEqual(SleepyShapes.large, 16)
        XCTAssertEqual(SleepyShapes.extraLarge, 28)
        // 统一输入框形状 = medium 联动(改 medium 不忘查这里)
        XCTAssertEqual(SleepyTheme.fieldShape, SleepyShapes.medium)
    }

    func testAlphaTokens() {
        XCTAssertEqual(SleepyTheme.Alpha.highContent, 0.8, accuracy: 0.0001)
        XCTAssertEqual(SleepyTheme.Alpha.hairline, 0.3, accuracy: 0.0001)
        XCTAssertEqual(SleepyTheme.Alpha.tinted, 0.12, accuracy: 0.0001)
        XCTAssertEqual(SleepyTheme.Alpha.inactive, 0.6, accuracy: 0.0001)
        // 档位序关系: tinted < hairline < inactive < highContent(误换值时双保险)
        XCTAssertLessThan(SleepyTheme.Alpha.tinted, SleepyTheme.Alpha.hairline)
        XCTAssertLessThan(SleepyTheme.Alpha.hairline, SleepyTheme.Alpha.inactive)
        XCTAssertLessThan(SleepyTheme.Alpha.inactive, SleepyTheme.Alpha.highContent)
    }

    // MARK: - 3. 色彩结构不变量(全表: 基础双 scheme + 5 预设成对)

    /// container 层级明度单调: lowest < low < container < high < highest
    /// (浅色主题=越高层越"浮起"偏白? M3 规范浅色高层更暗 — 按现值方向钉:
    ///  light:  lowest(白)最亮 → highest 最暗;  dark:  lowest 最暗 → highest 最亮。
    ///  共同不变量 = 严格单调, 方向按 scheme 亮度族区分, 倒挂即红)
    private func assertContainerMonotonic(_ scheme: WakeUpColorScheme, dark: Bool, label: String) {
        let l0 = relativeLuminance(scheme.surfaceContainerLowest)
        let l1 = relativeLuminance(scheme.surfaceContainerLow)
        let l2 = relativeLuminance(scheme.surfaceContainer)
        let l3 = relativeLuminance(scheme.surfaceContainerHigh)
        let l4 = relativeLuminance(scheme.surfaceContainerHighest)
        let steps = [l0, l1, l2, l3, l4]
        for i in 1..<steps.count {
            if dark {
                XCTAssertGreaterThan(steps[i], steps[i - 1],
                                     "\(label): container 层级应自 lowest 向上递增(深色族)")
            } else {
                XCTAssertLessThan(steps[i], steps[i - 1],
                                  "\(label): container 层级应自 lowest 向上递减(浅色族)")
            }
        }
    }

    /// on*/base 对比差: 每对前景/底色相对亮度差 > 0.25(Material on* 角色即强对比设计)
    private func assertOnColorContrast(_ scheme: WakeUpColorScheme, label: String) {
        let pairs: [(String, Color, Color)] = [
            ("primary", scheme.primary, scheme.onPrimary),
            ("secondary", scheme.secondary, scheme.onSecondary),
            ("tertiary", scheme.tertiary, scheme.onTertiary),
            ("error", scheme.error, scheme.onError),
            ("background", scheme.background, scheme.onBackground),
            ("surface", scheme.surface, scheme.onSurface),
            ("surfaceVariant", scheme.surfaceVariant, scheme.onSurfaceVariant),
            ("primaryContainer", scheme.primaryContainer, scheme.onPrimaryContainer),
            ("secondaryContainer", scheme.secondaryContainer, scheme.onSecondaryContainer),
            ("tertiaryContainer", scheme.tertiaryContainer, scheme.onTertiaryContainer),
            ("errorContainer", scheme.errorContainer, scheme.onErrorContainer),
        ]
        for (name, base, on) in pairs {
            let diff = abs(relativeLuminance(base) - relativeLuminance(on))
            XCTAssertGreaterThan(diff, 0.25,
                                 "\(label): \(name) 与其 on* 前景亮度差 \(diff) 过小, 前景几乎不可读")
        }
    }

    /// 全表通用结构: background==surface、scrim 纯黑、outline 族方向按深浅族区分
    private func assertStructuralInvariants(_ scheme: WakeUpColorScheme, dark: Bool, label: String) {
        XCTAssertEqual(relativeLuminance(scheme.background),
                       relativeLuminance(scheme.surface),
                       accuracy: 0.0001, "\(label): background 应与 surface 同值(M3 基线)")
        XCTAssertLessThan(relativeLuminance(scheme.scrim), 0.01, "\(label): scrim 应为近黑")
        // 整族亮度定位: 深色族 surface 亮度 < 0.2 < 浅色族 surface 亮度
        let surfaceL = relativeLuminance(scheme.surface)
        if dark {
            XCTAssertLessThan(surfaceL, 0.2, "\(label): 深色族 surface 应近黑")
            XCTAssertGreaterThan(relativeLuminance(scheme.outline),
                                 relativeLuminance(scheme.outlineVariant),
                                 "\(label): 深色族 outline(较亮线)应亮于 outlineVariant")
        } else {
            XCTAssertGreaterThan(surfaceL, 0.8, "\(label): 浅色族 surface 应近白")
            XCTAssertLessThan(relativeLuminance(scheme.outline),
                              relativeLuminance(scheme.outlineVariant),
                              "\(label): 浅色族 outline(较暗线)应暗于 outlineVariant")
        }
    }

    private func check(scheme: WakeUpColorScheme, dark: Bool, label: String) {
        assertContainerMonotonic(scheme, dark: dark, label: label)
        assertOnColorContrast(scheme, label: label)
        assertStructuralInvariants(scheme, dark: dark, label: label)
    }

    func testBaseLightAndDarkSchemeConsistency() {
        check(scheme: lightScheme, dark: false, label: "lightScheme")
        check(scheme: darkScheme, dark: true, label: "darkScheme")
        // 深浅族整体分离: dark.surface 必须比 light.surface 暗(两族没互换)
        XCTAssertLessThan(relativeLuminance(darkScheme.surface),
                          relativeLuminance(lightScheme.surface))
    }

    func testAllPresetsLightDarkConsistency() {
        // 每个预设的 light/dark 成对 scheme 都须满足同一组结构不变量 —
        // "颜色样式表全表一致性"的正题: 新增预设(如 v1.0.56 custom)不得漏配。
        for preset in ThemePresets.all {
            check(scheme: preset.light, dark: false, label: "preset \(preset.key) light")
            check(scheme: preset.dark, dark: true, label: "preset \(preset.key) dark")
            XCTAssertLessThan(relativeLuminance(preset.dark.surface),
                              relativeLuminance(preset.light.surface),
                              "preset \(preset.key): dark/light 整体明度应分离")
        }
    }
}
