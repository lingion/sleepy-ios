import XCTest
import SwiftUI
import UIKit
@testable import Sleepy

final class SystemColorTests: XCTestCase {
    func testSnapshotRoundTripDeduplicatesAndRejectsFutureAlgorithm() throws {
        let name = "SystemColorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(SystemColorSeedStore.read(from: defaults).fallbackReason, .missingSnapshot)
        let value = SystemColorSnapshot(seed: SystemSeedRGB(red: 80, green: 80, blue: 80),
            systemDark: true, increasedContrast: true, windowID: "window-A")
        XCTAssertTrue(SystemColorSeedStore.write(value, to: defaults))
        XCTAssertFalse(SystemColorSeedStore.write(value, to: defaults))
        XCTAssertEqual(SystemColorSeedStore.read(from: defaults), value)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        json["algorithmVersion"] = 999
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: SystemColorSeedStore.key)
        XCTAssertEqual(SystemColorSeedStore.read(from: defaults).fallbackReason, .invalidSnapshot)
        json["algorithmVersion"] = 1
        json["source"] = "homeScreenTint"
        defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: SystemColorSeedStore.key)
        XCTAssertEqual(SystemColorSeedStore.read(from: defaults).source, .fallback)
    }

    func testSeedRejectsNonfiniteAndTranslucentButKeepsNeutral() {
        XCTAssertNil(SystemSeedRGB(red: .nan, green: 0, blue: 0, alpha: 1))
        XCTAssertNil(SystemSeedRGB(red: 1, green: 0, blue: 0, alpha: 0.5))
        XCTAssertEqual(SystemSeedRGB(red: 0.5, green: 0.5, blue: 0.5, alpha: 1),
                       SystemSeedRGB(red: 128, green: 128, blue: 128))
    }

    func testMalformedSnapshotNeverMasqueradesAsWindowTint() throws {
        let name = "InvalidSystemColor.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("broken".utf8), forKey: SystemColorSeedStore.key)
        XCTAssertEqual(SystemColorSeedStore.read(from: defaults).fallbackReason, .invalidSnapshot)
        let valid = SystemColorSnapshot(seed: .init(red: 10, green: 20, blue: 30),
            systemDark: false, increasedContrast: false, windowID: "window")
        let base = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        for (key, value) in [("schemaVersion", 999 as Any), ("windowID", "" as Any),
                             ("fallbackReason", "invalidColor" as Any)] {
            var json = base
            json[key] = value
            defaults.set(try JSONSerialization.data(withJSONObject: json), forKey: SystemColorSeedStore.key)
            XCTAssertEqual(SystemColorSeedStore.read(from: defaults).source, .fallback)
        }
    }

    func testAppWidgetAndCourseAnchorShareTheSameSnapshot() throws {
        let name = "SystemColorConsumers.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = AppPrefs(defaults: defaults)
        prefs.setThemeKey(ThemePresets.KEY_SYSTEM)
        prefs.setThemeMode(AppPrefs.THEME_MODE_SYSTEM)
        for dark in [false, true] {
            for high in [false, true] {
                let snapshot = SystemColorSnapshot(seed: .init(red: 20, green: 180, blue: 90),
                    systemDark: dark, increasedContrast: high, windowID: "window")
                let app = SleepyThemeProvider.resolve(themeKey: ThemePresets.KEY_SYSTEM, dark: dark,
                    snapshot: snapshot, increasedContrast: high)
                let widget = resolveWidgetScheme(themeKey: ThemePresets.KEY_SYSTEM, isDark: dark,
                    renderingMode: .fullColor, snapshot: snapshot, increasedContrast: high)
                XCTAssertEqual(app.primary, widget.primary)
                XCTAssertEqual(app.surface, widget.surface)
                XCTAssertEqual(app.onSurface, widget.onSurface)
                let anchor = try XCTUnwrap(CourseColorWriteGlue.resolveAnchor(
                    mode: AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME, prefs: prefs, systemSnapshot: snapshot))
                let rgb = CustomSchemeDeriver.rgb(of: app.primary)
                let roundedHue = CustomSchemeDeriver.hueOf(
                    r: (rgb.r * 255).rounded() / 255, g: (rgb.g * 255).rounded() / 255,
                    b: (rgb.b * 255).rounded() / 255)
                XCTAssertEqual(anchor, try XCTUnwrap(roundedHue), accuracy: 0.05)
            }
        }
        prefs.setThemeMode(AppPrefs.THEME_MODE_LIGHT)
        let darkSnapshot = SystemColorSnapshot(seed: .init(red: 200, green: 40, blue: 120),
            systemDark: true, increasedContrast: false, windowID: "window")
        let locked = try XCTUnwrap(CourseColorWriteGlue.resolveAnchor(
            mode: AppPrefs.COURSE_COLOR_MODE_FOLLOW_THEME, prefs: prefs, systemSnapshot: darkSnapshot))
        let light = SystemColorScheme.resolve(snapshot: darkSnapshot, dark: false)
        XCTAssertEqual(locked, CourseColorUtil.hueOf(SystemColorScheme.argb(light.primary)), accuracy: 0.01)
    }

    func testRenderingModesRemainDistinctAndDoNotProduceSeeds() {
        let a = SystemColorSnapshot(seed: .init(red: 255, green: 0, blue: 0),
            systemDark: false, increasedContrast: false, windowID: "a")
        let b = SystemColorSnapshot(seed: .init(red: 0, green: 0, blue: 255),
            systemDark: true, increasedContrast: true, windowID: "b")
        for mode in [SleepyWidgetRenderingMode.accented, .vibrant] {
            let first = resolveWidgetScheme(themeKey: "system", isDark: false, renderingMode: mode, snapshot: a)
            let second = resolveWidgetScheme(themeKey: "system", isDark: true, renderingMode: mode, snapshot: b)
            XCTAssertEqual(first.renderingMode, mode)
            XCTAssertEqual(first.primary, second.primary, "宿主渲染模式不应反向生成颜色种子")
            XCTAssertTrue(first.isGlass, "保留禁止课程色覆盖的兼容契约")
        }
        XCTAssertNotEqual(glassWidgetScheme().primaryContainer, vibrantWidgetScheme().primaryContainer)
        if #available(iOS 16.0, *) {
            XCTAssertEqual(SleepyWidgetRenderingMode(.accented), .accented)
            XCTAssertEqual(SleepyWidgetRenderingMode(.vibrant), .vibrant)
            XCTAssertEqual(SleepyWidgetRenderingMode(.fullColor), .fullColor)
        }
    }

    func testSystemSignalDoesNotOverridePresetOrCustomTheme() {
        let red = SystemColorSnapshot(seed: .init(red: 255, green: 0, blue: 0),
            systemDark: false, increasedContrast: false, windowID: "a")
        let blue = SystemColorSnapshot(seed: .init(red: 0, green: 0, blue: 255),
            systemDark: false, increasedContrast: false, windowID: "a")
        for key in [ThemePresets.KEY_OCEAN, "custom:missing-system-color-test"] {
            let before = SleepyThemeProvider.resolve(themeKey: key, dark: false, snapshot: red, increasedContrast: false)
            let after = SleepyThemeProvider.resolve(themeKey: key, dark: false, snapshot: blue, increasedContrast: false)
            XCTAssertEqual(before.primary, after.primary)
            XCTAssertEqual(before.surface, after.surface)
        }
        let before = SleepyThemeProvider.resolve(themeKey: "system", dark: false, snapshot: red, increasedContrast: false)
        let after = SleepyThemeProvider.resolve(themeKey: "system", dark: false, snapshot: blue, increasedContrast: false)
        XCTAssertNotEqual(before.primary, after.primary)
    }

    func testSeedPublicationOnlyTouchesItsOwnKeyAndDoesNotChangeThemeSelection() throws {
        let name = "SystemColorIsolation.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("ocean", forKey: AppPrefs.KEY_THEME)
        defaults.set(Data([1, 2, 3]), forKey: "unrelated_payload")
        let before = defaults.persistentDomain(forName: name) ?? [:]
        SystemColorSeedStore.write(.init(seed: .init(red: 80, green: 80, blue: 80),
            systemDark: true, increasedContrast: true, windowID: "window"), to: defaults)
        var after = defaults.persistentDomain(forName: name) ?? [:]
        after.removeValue(forKey: SystemColorSeedStore.key)
        XCTAssertEqual(NSDictionary(dictionary: before), NSDictionary(dictionary: after))
    }

    func testSystemSchemesHaveRequiredContrastForChromaticAndNeutralSeeds() {
        let seeds: [SystemSeedRGB] = [
            .init(red: 255, green: 0, blue: 0), .init(red: 0, green: 255, blue: 0),
            .init(red: 0, green: 0, blue: 255), .init(red: 255, green: 255, blue: 0),
            .init(red: 0, green: 255, blue: 255), .init(red: 255, green: 0, blue: 255),
            .init(red: 0, green: 0, blue: 0), .init(red: 128, green: 128, blue: 128),
            .init(red: 255, green: 255, blue: 255)
        ]
        for seed in seeds {
            for dark in [false, true] {
                for increased in [false, true] {
                    let snapshot = SystemColorSnapshot(seed: seed, systemDark: dark,
                        increasedContrast: increased, windowID: "test")
                    let s = SystemColorScheme.resolve(snapshot: snapshot, dark: dark)
                    let pairs: [(Color, Color)] = [
                        (s.onPrimary, s.primary), (s.onPrimaryContainer, s.primaryContainer),
                        (s.onSecondary, s.secondary), (s.onSecondaryContainer, s.secondaryContainer),
                        (s.onTertiary, s.tertiary), (s.onTertiaryContainer, s.tertiaryContainer),
                        (s.onBackground, s.background), (s.onSurface, s.surface),
                        (s.onSurfaceVariant, s.surfaceVariant), (s.onError, s.error),
                        (s.onErrorContainer, s.errorContainer),
                        (s.onSurface, s.surfaceContainerLowest), (s.onSurface, s.surfaceContainerLow),
                        (s.onSurface, s.surfaceContainer), (s.onSurface, s.surfaceContainerHigh),
                        (s.onSurface, s.surfaceContainerHighest)
                    ]
                    for (foreground, background) in pairs {
                        // 独立 oracle，不调用生产 contrast 方法。
                        XCTAssertGreaterThanOrEqual(contrast(foreground, background), increased ? 6.99 : 4.49,
                            "seed=\(seed), dark=\(dark), increased=\(increased)")
                    }
                    if seed.red == seed.green && seed.green == seed.blue {
                        for color in [s.primary, s.secondary, s.tertiary, s.surface] {
                            let rgb = CustomSchemeDeriver.rgb(of: color)
                            XCTAssertEqual(rgb.r, rgb.g, accuracy: 1 / 255)
                            XCTAssertEqual(rgb.g, rgb.b, accuracy: 1 / 255)
                        }
                    }
                }
            }
        }
    }

    private func contrast(_ a: Color, _ b: Color) -> Double {
        func luminance(_ color: Color) -> Double {
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            guard let c = UIColor(color).cgColor.converted(to: space, intent: .relativeColorimetric,
                                                          options: nil)?.components, c.count == 4 else {
                XCTFail("系统角色应可解析为 sRGB"); return 0
            }
            XCTAssertEqual(Double(c[3]), 1, accuracy: 0.0001)
            func linear(_ x: CGFloat) -> Double {
                let v = Double(x)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2])
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
