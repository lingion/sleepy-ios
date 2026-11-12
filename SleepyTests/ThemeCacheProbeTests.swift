// Terminal theme correctness and diagnostic timing workloads.
import XCTest
import SwiftUI
import UIKit
@testable import Sleepy

@MainActor
final class ThemeCacheProbeTests: XCTestCase {
    private let roles: [KeyPath<WakeUpColorScheme, Color>] = [
        \.primary, \.onPrimary, \.primaryContainer, \.onPrimaryContainer,
        \.secondary, \.onSecondary, \.secondaryContainer, \.onSecondaryContainer,
        \.tertiary, \.onTertiary, \.tertiaryContainer, \.onTertiaryContainer,
        \.background, \.onBackground, \.surface, \.onSurface, \.surfaceVariant, \.onSurfaceVariant,
        \.surfaceContainerLowest, \.surfaceContainerLow, \.surfaceContainer,
        \.surfaceContainerHigh, \.surfaceContainerHighest, \.outline, \.outlineVariant, \.scrim,
        \.error, \.onError, \.errorContainer, \.onErrorContainer
    ]

    private func snapshot(_ index: Int, dark: Bool = false, high: Bool = false) -> SystemColorSnapshot {
        .init(seed: .init(red: UInt8((index * 73 + 17) % 256),
                          green: UInt8((index * 37 + 91) % 256),
                          blue: UInt8((index * 113 + 53) % 256)),
              systemDark: dark, increasedContrast: high, windowID: "probe-\(index)")
    }

    private func rgba(_ scheme: WakeUpColorScheme) -> [Double] {
        let space = CGColorSpace(name: CGColorSpace.extendedSRGB)!
        return roles.flatMap { key in
            let color = UIColor(scheme[keyPath: key]).cgColor
            guard let components = color.converted(to: space, intent: .relativeColorimetric,
                                                    options: nil)?.components,
                  components.count == 4 else {
                XCTFail("Every terminal role must resolve to RGBA")
                return [Double](repeating: .nan, count: 4)
            }
            return components.map(Double.init)
        }
    }

    private func assertSame(_ a: WakeUpColorScheme, _ b: WakeUpColorScheme,
                            file: StaticString = #filePath, line: UInt = #line) {
        for (actual, expected) in zip(rgba(a), rgba(b)) {
            XCTAssertEqual(actual, expected, accuracy: 0.000001, file: file, line: line)
        }
    }

    func testSystemWorkingSetDoesNotBleedAcrossSeedAppearanceOrWindow() {
        // Save expected endpoints before interleaving the same inputs in reverse order.
        let inputs = (0..<9).flatMap { index in
            [false, true].flatMap { dark in
                [false, true].map { high in (snapshot(index, dark: dark, high: high), dark, high) }
            }
        }
        let expected = inputs.map { SystemColorScheme.resolve(snapshot: $0.0, dark: $0.1,
                                                               increasedContrast: $0.2) }
        for index in inputs.indices.reversed() {
            let input = inputs[index]
            assertSame(SystemColorScheme.resolve(snapshot: input.0, dark: input.1,
                                                  increasedContrast: input.2), expected[index])
        }
        let green = snapshot(2)
        let sameSeedOtherWindow = SystemColorSnapshot(seed: green.seed, systemDark: true,
            increasedContrast: true, windowID: "other-window")
        assertSame(SystemColorScheme.resolve(snapshot: green, dark: false, increasedContrast: false),
                   SystemColorScheme.resolve(snapshot: sameSeedOtherWindow, dark: false,
                                             increasedContrast: false))
    }

    func testInvalidSnapshotUsesExistingFallbackBeforeResolvingContrast() throws {
        let valid = snapshot(4, dark: true, high: true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any])
        json["algorithmVersion"] = 999
        let invalid = try JSONDecoder().decode(SystemColorSnapshot.self,
            from: JSONSerialization.data(withJSONObject: json))
        let fallback = SystemColorSnapshot.fallback(.invalidSnapshot)
        for dark in [false, true] {
            assertSame(SystemColorScheme.resolve(snapshot: invalid, dark: dark),
                       SystemColorScheme.resolve(snapshot: fallback, dark: dark))
            for high in [false, true] {
                assertSame(SystemColorScheme.resolve(snapshot: invalid, dark: dark, increasedContrast: high),
                           SystemColorScheme.resolve(snapshot: fallback, dark: dark, increasedContrast: high))
            }
        }
    }

    func testPresetIgnoresSystemSignalsAndUnknownThemeKeepsExistingFallback() {
        for key in [ThemePresets.KEY_DEFAULT, ThemePresets.KEY_SPRING, ThemePresets.KEY_OCEAN,
                    ThemePresets.KEY_PEACH, ThemePresets.KEY_SLATE, "unknown-cache-probe"] {
            for dark in [false, true] {
                let first = SleepyThemeProvider.resolve(themeKey: key, dark: dark,
                    snapshot: snapshot(0), increasedContrast: false)
                let second = SleepyThemeProvider.resolve(themeKey: key, dark: dark,
                    snapshot: snapshot(1, high: true), increasedContrast: true)
                assertSame(first, second)
            }
        }
    }

    func testSameIDCustomEditDeletionAndDirectRestoreRemainFresh() {
        let defaults = CustomThemeStore.defaults
        let key = CustomThemeCore.KEY_THEMES
        let originalDocument = defaults.object(forKey: key)
        defer {
            if let originalDocument { defaults.set(originalDocument, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        let red = CustomTheme(id: "theme-cache-probe", name: "Probe", primary: "#FF0000",
            secondary: "#00FF00", tertiary: "#0000FF", surfaceHue: 0, surfaceChroma: 8, createdAt: 1)
        let blue = red.copy(primary: "#0000FF", surfaceHue: 240)
        let themeKey = "custom:theme-cache-probe"
        func resolve() -> WakeUpColorScheme {
            SleepyThemeProvider.resolve(themeKey: themeKey, dark: false,
                snapshot: snapshot(0), increasedContrast: false)
        }
        func assertVector(_ theme: CustomTheme, file: StaticString = #filePath, line: UInt = #line) {
            let expected = ThemeColorVector(scheme: CustomSchemeDeriver.derive(theme: theme, isDark: false),
                                            dark: false, increasedContrast: false)
            let actual = SleepyThemeProvider.terminalVector(themeKey: themeKey, dark: false,
                snapshot: snapshot(0), increasedContrast: false)
            XCTAssertEqual(actual.components, expected.components, file: file, line: line)
        }
        // Direct defaults writes cover backup/import paths that bypass a store callback.
        defaults.set(CustomThemeCore.toJson([red]), forKey: key)
        let redEndpoint = resolve()
        assertSame(redEndpoint, CustomSchemeDeriver.derive(theme: red, isDark: false))
        assertVector(red)
        defaults.set(CustomThemeCore.toJson([blue]), forKey: key)
        let blueEndpoint = resolve()
        assertSame(blueEndpoint, CustomSchemeDeriver.derive(theme: blue, isDark: false))
        assertVector(blue)
        XCTAssertNotEqual(rgba(redEndpoint), rgba(blueEndpoint))
        let otherRoles = blue.copy(secondary: "#FF00FF", tertiary: "#00FFFF", surfaceChroma: 12)
        defaults.set(CustomThemeCore.toJson([otherRoles]), forKey: key)
        assertSame(resolve(), CustomSchemeDeriver.derive(theme: otherRoles, isDark: false))
        assertVector(otherRoles)
        defaults.set("[]", forKey: key)
        assertSame(resolve(), CustomSchemeDeriver.derive(theme: SleepyThemeProvider.defaultSeedTheme,
                                                         isDark: false))
        assertVector(SleepyThemeProvider.defaultSeedTheme)
        defaults.set(CustomThemeCore.toJson([red]), forKey: key)
        assertSame(resolve(), redEndpoint)
        assertVector(red)
        defaults.set("invalid-json", forKey: key)
        assertSame(resolve(), CustomSchemeDeriver.derive(theme: SleepyThemeProvider.defaultSeedTheme,
                                                         isDark: false))
        assertVector(SleepyThemeProvider.defaultSeedTheme)
    }

    func testProviderTerminalVectorsKeepAllRolesFreshAcrossAppearanceAndWindowInputs() {
        let keys = [ThemePresets.KEY_SYSTEM, ThemePresets.KEY_OCEAN, ThemePresets.KEY_PEACH]
        for key in keys {
            let inputs = (0..<9).flatMap { index in
                [false, true].flatMap { dark in
                    [false, true].map { high in (snapshot(index, dark: dark, high: high), dark, high) }
                }
            }
            let expected = inputs.map {
                ThemeColorVector(scheme: SleepyThemeProvider.resolve(themeKey: key, dark: $0.1,
                    snapshot: $0.0, increasedContrast: $0.2), dark: $0.1, increasedContrast: $0.2)
            }
            for index in inputs.indices.reversed() {
                let input = inputs[index]
                let actual = SleepyThemeProvider.terminalVector(themeKey: key, dark: input.1,
                    snapshot: input.0, increasedContrast: input.2)
                XCTAssertEqual(actual.components, expected[index].components)
            }
        }
    }

    func testBoundedCacheRetainsRecentlyUsedInputsAndRecomputesEvictedInput() {
        let cache = ThemeValueCache<String, Int>(capacity: 2)
        var computations = 0
        func read(_ key: String) -> Int {
            cache.value(for: key) { computations += 1; return computations }
        }
        XCTAssertEqual(read("a"), 1)
        XCTAssertEqual(read("b"), 2)
        XCTAssertEqual(read("a"), 1)
        XCTAssertEqual(read("c"), 3)
        XCTAssertEqual(read("a"), 1)
        XCTAssertEqual(read("b"), 4)
        XCTAssertEqual(computations, 4)
    }

}
