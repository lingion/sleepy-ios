import Foundation
import UIKit
import XCTest
@testable import Sleepy

final class OSCapabilityGatingTests: XCTestCase {
    func testEffectiveStyleFallsBackToClassicBelowOS26WithoutLaunchArg() {
        XCTAssertEqual(
            SleepyUIStyle.effectiveStyle(
                for: "liquid_glass",
                supportsLiquidGlass: false,
                allowLaunchArgumentOverride: false
            ),
            .classic
        )
        XCTAssertEqual(
            SleepyUIStyle.effectiveStyle(
                for: "classic",
                supportsLiquidGlass: false,
                allowLaunchArgumentOverride: false
            ),
            .classic
        )
        XCTAssertEqual(
            SleepyUIStyle.effectiveStyle(
                for: "unexpected",
                supportsLiquidGlass: false,
                allowLaunchArgumentOverride: false
            ),
            .classic
        )
    }

    func testEffectiveStyleAllowsLiquidGlassWhenSupportedOrExplicitOverride() {
        XCTAssertEqual(
            SleepyUIStyle.effectiveStyle(
                for: "liquid_glass",
                supportsLiquidGlass: true,
                allowLaunchArgumentOverride: false
            ),
            .liquidGlass
        )
        XCTAssertEqual(
            SleepyUIStyle.effectiveStyle(
                for: "liquid_glass",
                supportsLiquidGlass: false,
                allowLaunchArgumentOverride: true
            ),
            .liquidGlass
        )
        XCTAssertEqual(
            SleepyUIStyle.effectiveStyle(
                for: "classic",
                supportsLiquidGlass: true,
                allowLaunchArgumentOverride: true
            ),
            .classic
        )
    }

    func testStoredLiquidGlassPreferenceInDefaultsStaysClassicWhenUnsupported() {
        let suiteName = "OSCapabilityGatingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let prefs = AppPrefs(defaults: defaults)
        prefs.setUiStyle("liquid_glass")
        XCTAssertEqual(prefs.getUiStyle(), "liquid_glass")
        XCTAssertEqual(
            SleepyUIStyle.effectiveStyle(
                for: prefs.getUiStyle(),
                supportsLiquidGlass: false,
                allowLaunchArgumentOverride: false
            ),
            .classic
        )
    }

    func testRuntimeCapabilitiesMatchOperatingSystemMajorVersion() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let supportsOS26 = major >= 26
        let supportsWatch10 = major >= 17 && UIDevice.current.userInterfaceIdiom != .pad
        XCTAssertEqual(SleepyUIStyle.supportsLiquidGlass, supportsOS26)
        XCTAssertEqual(NavStyleResolver.supportsNativeTabBar, supportsOS26)
        XCTAssertEqual(ClassDayActivityCore.supportsScheduledActivities, supportsOS26)
        XCTAssertEqual(WidgetSettingsScreen.supportsWatchTimeStrip, supportsWatch10)
    }
}
