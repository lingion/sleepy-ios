// NavStyleResolverTests.swift — 底栏形态决策单点测试
//
// ★ 2026-10-26 Kerry 定稿两项制契约(设置页只有「贴底 / 悬浮」, 默认悬浮):
//   - 贴底(false) → docked(恒自绘, 任何系统/设备下不变)
//   - 悬浮(true)  → 原生 TabBar 可用(iOS26+) → native; 不可用 → floating(自绘兜底)
//   - prefs 未写入 = 缺省悬浮(isFloatingRequested()=true)
//   - UITest 钉死(forcePill): 悬浮语义降级自绘 floating, 永不 native; 贴底仍 docked
//
// 关键语义锚: 「未设置」≠「设置了贴底」。isNavDocked() 未写入返回的 false 是
// 缺省值不是用户意志, 缺省悬浮判定走 NavStyleResolver.isFloatingRequested()。

import XCTest
@testable import Sleepy

final class NavStyleResolverTests: XCTestCase {

    // MARK: - 纯逻辑(全参注入, 直打 effectiveMode 六边形)

    func testDockedIsAlwaysSelfDrawn() {
        // 贴底: 原生可用与否都 docked(用户要贴底就给贴底, 不玩自适应)
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: false, supportsNative: true,
                                           forcedPill: false),
            .docked)
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: false, supportsNative: false,
                                           forcedPill: false),
            .docked)
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: false, supportsNative: true,
                                           forcedPill: true),
            .docked, "forcePill 下贴底仍贴底")
    }

    func testFloatingPrefersNativeThenFallsBack() {
        // 悬浮 + iOS26 原生可用 → native(用户令: 能原生就原生)
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: true, supportsNative: true,
                                           forcedPill: false),
            .native)
        // 悬浮 + 原生不可用(iOS15~25) → 自绘药丸兜底
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: true, supportsNative: false,
                                           forcedPill: false),
            .floating)
    }

    func testForcePillNeverGoesNative() {
        // UITests 钉死自绘: 悬浮语义 → floating(全量套件按 pill_* 标识导航)
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: true, supportsNative: true,
                                           forcedPill: true),
            .floating,
            "forcePill + 悬浮 → 自绘药丸(永不原生)")
    }

    // MARK: - prefs 层缺省语义(「未设置」= 悬浮回归锚)

    func testPrefsDefaultIsFloating() {
        let suiteName = "NavStyleResolverTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let prefs = AppPrefs(defaults: suite)

        // 初始: 未写入 → 缺省值 false 但非用户意志 → 意图=悬浮
        XCTAssertFalse(prefs.isNavDocked(), "未写入缺省 false")
        XCTAssertFalse(prefs.hasExplicitNavStyle(), "未写入不得算显式")

        // 显式贴底: 值同缺省, 但存在性翻转 → 意图=贴底
        prefs.setNavDocked(false)
        XCTAssertTrue(prefs.hasExplicitNavStyle(), "存 false = 用户显式选贴底")

        // 显式悬浮
        prefs.setNavDocked(true)
        XCTAssertTrue(prefs.isNavDocked())
        XCTAssertTrue(prefs.hasExplicitNavStyle())
    }

    // MARK: - effectiveFloating 口径(native 归悬浮语义)

    func testModeToFloatingMapping() {
        // AppRoot 旧口径兼容: docked=false, 其余(floating/native)=true
        XCTAssertFalse(NavStyleResolver.floating(for: .docked))
        XCTAssertTrue(NavStyleResolver.floating(for: .floating))
        XCTAssertTrue(NavStyleResolver.floating(for: .native),
                      "原生 TabBar = 悬浮语义(内容直通屏底)")
    }
}
