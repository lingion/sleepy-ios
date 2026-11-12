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

    // Diagnostic timing is opt-in; correctness tests above run by default.
    // Fixed iteration counts; no absolute timing assertion in correctness CI.
    // Report 7 independent batches after a 32-call warmup, retaining every result via checksum.
    private func benchmark(_ label: String, iterations: Int = 1_000,
                           _ operation: (Int) -> Color) {
        var checksum = 0
        for index in 0..<32 { checksum = checksum &+ operation(index).hashValue }
        var samples: [Double] = []
        for _ in 0..<7 {
            let start = DispatchTime.now().uptimeNanoseconds
            for index in 0..<iterations { checksum = checksum &+ operation(index).hashValue }
            let end = DispatchTime.now().uptimeNanoseconds
            samples.append(Double(end - start) / Double(iterations) / 1_000)
        }
        let sorted = samples.sorted()
        print("THEME_BENCH \(label) us_per_operation=\(samples) median=\(sorted[3]) max=\(sorted[6]) checksum=\(checksum)")
    }

    func testBenchmarkSystemWarmSingleEndpoint() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1")
        let input = snapshot(0)
        benchmark("system_warm_single") { _ in
            SystemColorScheme.resolve(snapshot: input, dark: false, increasedContrast: false).primary
        }
    }

    func testBenchmarkSystemFourAppearanceEndpoints() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1")
        let input = snapshot(0)
        benchmark("system_appearance_4") { index in
            SystemColorScheme.resolve(snapshot: input, dark: index % 2 == 1,
                increasedContrast: index % 4 >= 2).primary
        }
    }

    func testBenchmarkSystemChurnBeyondCacheCapacity() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1")
        let inputs = (0..<64).map { snapshot($0) }
        benchmark("system_churn_64") { index in
            SystemColorScheme.resolve(snapshot: inputs[index % inputs.count], dark: false,
                increasedContrast: false).primary
        }
    }

    func testBenchmarkProviderSystemAndPresetResolution() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1")
        let input = snapshot(0)
        for key in [ThemePresets.KEY_SYSTEM, ThemePresets.KEY_OCEAN] {
            benchmark("provider_\(key)") { _ in
                SleepyThemeProvider.resolve(themeKey: key, dark: false, snapshot: input,
                    increasedContrast: false).primary
            }
        }
    }

    func testBenchmarkUncachedVectorConversionContext() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1")
        let scheme = lightScheme
        benchmark("vector_constructor_context") { _ in
            ThemeColorVector(scheme: scheme, dark: false, increasedContrast: false).scheme.primary
        }
    }

    func testBenchmarkProviderTerminalVectorAgainstConstructorPath() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1")
        let input = snapshot(0)
        for key in [ThemePresets.KEY_SYSTEM, ThemePresets.KEY_OCEAN] {
            // Both paths use the current scheme resolver. This comparison isolates
            // terminal-vector reuse; the recorded pre-change binary measures total gain.
            benchmark("provider_vector_constructor_\(key)") { _ in
                let scheme = SleepyThemeProvider.resolve(themeKey: key, dark: false,
                    snapshot: input, increasedContrast: false)
                return ThemeColorVector(scheme: scheme, dark: false, increasedContrast: false).scheme.primary
            }
            benchmark("provider_vector_terminal_\(key)") { _ in
                SleepyThemeProvider.terminalVector(themeKey: key, dark: false,
                    snapshot: input, increasedContrast: false).scheme.primary
            }
        }
    }

    func testBenchmarkCustomProviderAgainstOriginalDerivationPath() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SLEEPY_RUN_PERFORMANCE_TESTS"] == "1")
        let defaults = CustomThemeStore.defaults
        let documentKey = CustomThemeCore.KEY_THEMES
        let originalDocument = defaults.object(forKey: documentKey)
        defer {
            if let originalDocument { defaults.set(originalDocument, forKey: documentKey) }
            else { defaults.removeObject(forKey: documentKey) }
        }
        let theme = SleepyThemeProvider.defaultSeedTheme.copy(id: "theme-cache-benchmark", name: "Probe")
        defaults.set(CustomThemeCore.toJson([theme]), forKey: documentKey)
        let key = ThemePresets.CUSTOM_KEY_PREFIX + theme.id
        let input = snapshot(0)
        // This is the exact former custom-provider path: fresh document decode,
        // fresh derivation, then the ordinary vector constructor.
        benchmark("provider_vector_custom_original") { _ in
            let seed = CustomThemeStore.getById(theme.id) ?? SleepyThemeProvider.defaultSeedTheme
            let scheme = CustomSchemeDeriver.derive(theme: seed, isDark: false)
            return ThemeColorVector(scheme: scheme, dark: false, increasedContrast: false).scheme.primary
        }
        benchmark("provider_vector_custom_terminal") { _ in
            SleepyThemeProvider.terminalVector(themeKey: key, dark: false,
                snapshot: input, increasedContrast: false).scheme.primary
        }
    }
}
