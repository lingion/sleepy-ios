// WidgetThemeModeTests.swift — 小组件深色跟随修复(2026 dark-mode bug)的纯逻辑链:
// themeMode 快照 → effectiveWidgetIsDark(渲染期环境色域覆盖) → resolveWidgetScheme。

import XCTest
@testable import Sleepy

final class WidgetThemeModeTests: XCTestCase {

    func testAppAndExtensionDomainsShareExistingAndUpdatedWidgetRenderingPreferences() throws {
        let names = (0..<3).map { _ in "widget-process-prefs-\(UUID().uuidString)" }
        let application = try XCTUnwrap(UserDefaults(suiteName: names[0]))
        let extensionLocal = try XCTUnwrap(UserDefaults(suiteName: names[1]))
        let shared = try XCTUnwrap(UserDefaults(suiteName: names[2]))
        defer { for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) } }
        application.set(true, forKey: AppPrefs.KEY_WIDGET_COLORLESS)
        application.set("theme-before-upgrade", forKey: AppPrefs.KEY_THEME)
        application.set(true, forKey: AppPrefs.KEY_WIDGET_USE_ALIAS)
        application.set("three_line", forKey: AppPrefs.KEY_PERIOD_HEADER_LAYOUT)
        application.set("private-account-data", forKey: "unrelated_private_value")
        extensionLocal.set(false, forKey: AppPrefs.KEY_WIDGET_COLORLESS)
        let app = AppPrefs(defaults: application, widgetSharedDefaults: shared, role: .application)
        let widget = AppPrefs(defaults: extensionLocal,
            widgetSharedDefaults: try XCTUnwrap(UserDefaults(suiteName: names[2])), role: .widgetExtension)
        XCTAssertTrue(widget.isWidgetColorless(), "An upgrade must publish the saved value without another toggle")
        XCTAssertEqual(widget.getThemeKey(), "theme-before-upgrade")
        XCTAssertTrue(widget.isWidgetUseAlias())
        XCTAssertEqual(widget.getPeriodHeaderLayout(), "three_line")
        XCTAssertNil(shared.object(forKey: "unrelated_private_value"))
        app.setWidgetColorless(false)
        app.setWidgetUseAlias(false)
        app.setThemeKey("default")
        app.setPeriodHeaderLayout("legacy")
        app.setPeriodHeaderHideTime(true)
        app.setPeriodHeaderTimeAlignment("center")
        app.setShowDate(false)
        app.setVisibleDays([2, 4])
        app.setGridShowSeparators(true)
        app.setGridLongBreakSpacing(true)
        XCTAssertFalse(widget.isWidgetColorless())
        XCTAssertFalse(widget.isWidgetUseAlias())
        XCTAssertEqual(widget.getThemeKey(), "default")
        XCTAssertEqual(widget.getPeriodHeaderLayout(), "legacy")
        XCTAssertTrue(widget.isPeriodHeaderHideTime())
        XCTAssertEqual(widget.getPeriodHeaderTimeAlignment(), "center")
        XCTAssertFalse(widget.isShowDate())
        XCTAssertEqual(widget.getVisibleDays(), [2, 4])
        XCTAssertTrue(widget.isGridShowSeparators())
        XCTAssertTrue(widget.isGridLongBreakSpacing())
        XCTAssertEqual(extensionLocal.object(forKey: AppPrefs.KEY_THEME) as? String, nil)
        widget.syncWidgetPreferences(replacingMissing: true)
        XCTAssertTrue(shared.bool(forKey: AppPrefs.KEY_PERIOD_HEADER_HIDE_TIME),
                      "The extension must never publish its unrelated local defaults over the app's settings")
    }

    func testMissingAppGroupKeepsLocalFallbackAndDoesNotEraseValidSharedValues() throws {
        let names = (0..<2).map { _ in "widget-fallback-prefs-\(UUID().uuidString)" }
        let local = try XCTUnwrap(UserDefaults(suiteName: names[0]))
        let shared = try XCTUnwrap(UserDefaults(suiteName: names[1]))
        defer { for name in names { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) } }
        shared.set(true, forKey: AppPrefs.KEY_WIDGET_COLORLESS)
        _ = AppPrefs(defaults: local, widgetSharedDefaults: shared)
        XCTAssertTrue(shared.bool(forKey: AppPrefs.KEY_WIDGET_COLORLESS))
        let fallback = AppPrefs(defaults: local, role: .widgetExtension)
        fallback.setWidgetColorless(true)
        XCTAssertTrue(fallback.isWidgetColorless())
        local.removeObject(forKey: AppPrefs.KEY_WIDGET_COLORLESS)
        let publisher = AppPrefs(defaults: local, widgetSharedDefaults: shared)
        publisher.syncWidgetPreferences(replacingMissing: true)
        XCTAssertNil(shared.object(forKey: AppPrefs.KEY_WIDGET_COLORLESS))
    }

    // system 模式 → 用渲染期环境色域(WidgetKit \.colorScheme), 不信快照
    func testSystemModeFollowsEnvironmentNotSnapshot() {
        XCTAssertTrue(effectiveWidgetIsDark(themeMode: AppPrefs.THEME_MODE_SYSTEM,
                                            snapshotIsDark: false, envScheme: .dark))
        XCTAssertFalse(effectiveWidgetIsDark(themeMode: AppPrefs.THEME_MODE_SYSTEM,
                                             snapshotIsDark: false, envScheme: .light))
        // 环境优先: 即便快照 isDark=true, system 模式下浅色环境仍应渲染浅色
        XCTAssertFalse(effectiveWidgetIsDark(themeMode: AppPrefs.THEME_MODE_SYSTEM,
                                             snapshotIsDark: true, envScheme: .light))
    }

    // 锁定 light/dark → 信快照 isDark(与系统外观无关)
    func testLockedModesTrustSnapshot() {
        XCTAssertFalse(effectiveWidgetIsDark(themeMode: AppPrefs.THEME_MODE_LIGHT,
                                             snapshotIsDark: false, envScheme: .dark))
        XCTAssertTrue(effectiveWidgetIsDark(themeMode: AppPrefs.THEME_MODE_DARK,
                                            snapshotIsDark: true, envScheme: .light))
    }

    // 旧快照(无 themeMode 字段=nil)→ 沿用快照 isDark, 不改变历史行为
    func testLegacySnapshotWithoutThemeModeKeepsOldBehavior() {
        XCTAssertEqual(effectiveWidgetIsDark(themeMode: nil,
                                             snapshotIsDark: false, envScheme: .dark), false)
        XCTAssertEqual(effectiveWidgetIsDark(themeMode: nil,
                                             snapshotIsDark: true, envScheme: .light), true)
    }

    // 默认主题模式=system; 快照应携带 themeMode 供渲染端判别
    func testDefaultThemeModePrefIsSystem() {
        let suite = UserDefaults(suiteName: "WidgetThemeModeTests")!
        suite.removeObject(forKey: AppPrefs.KEY_THEME_MODE)
        let prefs = AppPrefs(defaults: suite)
        XCTAssertEqual(prefs.getThemeMode(), AppPrefs.THEME_MODE_SYSTEM)
        suite.removePersistentDomain(forName: "WidgetThemeModeTests")
    }

    // resolver: 同一主题键, isDark 翻转必须给出不同 surfaceContainer(此前 bug 的直接表征)
    func testResolverDarkLightProduceDistinctSurfaces() {
        let light = resolveWidgetScheme(themeKey: ThemePresets.KEY_DEFAULT, isDark: false)
        let dark = resolveWidgetScheme(themeKey: ThemePresets.KEY_DEFAULT, isDark: true)
        XCTAssertNotEqual(light.surfaceContainer, dark.surfaceContainer)
        XCTAssertNotEqual(light.bg, dark.bg)
    }

    // system 主题键走 dynamicSystemScheme(dark:)
    func testSystemKeyFollowsDarkFlag() {
        let light = SleepyThemeProvider.dynamicSystemScheme(dark: false)
        let dark = SleepyThemeProvider.dynamicSystemScheme(dark: true)
        XCTAssertNotEqual(light.surfaceContainer, dark.surfaceContainer)
    }
}
