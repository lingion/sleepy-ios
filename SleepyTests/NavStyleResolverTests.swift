// NavStyleResolverTests.swift — 底栏形态决策单点测试(2026-10-26 设备自适应改造)
//
// 契约(优先级链 高→低, 见 NavStyleResolver.swift 头注):
//   1. UITest 钉死自绘(forcePill) — 全量 UITests 按 pill_* 标识导航, 必须永远自绘
//   2. 用户显式选择(hasExplicit) — 设置页选过贴底/悬浮即永久优先, 不再自适应
//   3. 系统能力(supportsNative) — iOS 26+ 原生 TabBar 本身就是悬浮玻璃
//   4. 设备形态(homeIndicator) — 全面屏→悬浮 / Home 键老设备→贴底
//
// 关键语义锚: 「未设置」≠「设置了贴底」。isNavDocked() 未写入返回的 false 是
// 缺省值不是用户意志, 存在性判定走 hasExplicitNavStyle()(object(forKey:) != nil)。

import XCTest
@testable import Sleepy

final class NavStyleResolverTests: XCTestCase {

    // MARK: - 纯逻辑优先级(全参注入, 直打 effectiveMode 六边形)

    func testForcePillOverridesEverything() {
        // 测试钉死: 即使 iOS26 原生可用 + 未显式设置, forcedPill 也走自绘
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(hasExplicit: false, explicitFloating: false,
                                           homeIndicator: true, supportsNative: true,
                                           forcedPill: true),
            .floating,
            "forcePill + 未存键 → 自绘悬浮(全量 UITests 历史默认几何)")
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(hasExplicit: true, explicitFloating: false,
                                           homeIndicator: true, supportsNative: true,
                                           forcedPill: true),
            .docked,
            "forcePill 仍跟随显式 docked(专测贴底几何的用例预存 false 键)")
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(hasExplicit: true, explicitFloating: true,
                                           homeIndicator: false, supportsNative: true,
                                           forcedPill: true),
            .floating,
            "forcePill 下显式悬浮仍悬浮(pill 语义保留)")
    }

    func testExplicitChoiceBeatsNativeAndDevice() {
        // 用户显式贴底 → iOS26 也不给原生(设置优先 ← Android b0f8280 语义)
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(hasExplicit: true, explicitFloating: false,
                                           homeIndicator: true, supportsNative: true,
                                           forcedPill: false),
            .docked)
        // 用户显式悬浮 → 无 Home 指示条也悬浮
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(hasExplicit: true, explicitFloating: true,
                                           homeIndicator: false, supportsNative: false,
                                           forcedPill: false),
            .floating)
    }

    func testAutoNativeBeforeDeviceProbe() {
        // 未显式设置 + iOS26 → 原生(设备形态不参与)
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(hasExplicit: false, explicitFloating: false,
                                           homeIndicator: false, supportsNative: true,
                                           forcedPill: false),
            .native,
            "iOS26+ 未设置必须走原生 — 老用户升级即免配置")
    }

    func testAutoDeviceSplitOnLegacyOS() {
        // 未显式设置 + iOS<26 → 按设备形态分档
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(hasExplicit: false, explicitFloating: false,
                                           homeIndicator: true, supportsNative: false,
                                           forcedPill: false),
            .floating, "全面屏(SE2 以下不存在此类)→ 悬浮")
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(hasExplicit: false, explicitFloating: false,
                                           homeIndicator: false, supportsNative: false,
                                           forcedPill: false),
            .docked, "Home 键设备(SE/8)→ 贴底")
    }

    // MARK: - prefs 层存在性语义(「未设置」≠「贴底」回归锚)

    func testPrefsExplicitSemantics() {
        let suiteName = "NavStyleResolverTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }
        let prefs = AppPrefs(defaults: suite)

        // 初始: 未写入 → 缺省 false 但非用户意志
        XCTAssertFalse(prefs.isNavDocked(), "未写入缺省 false")
        XCTAssertFalse(prefs.hasExplicitNavStyle(), "未写入不得算显式")

        // 显式贴底: 值同缺省, 但存在性翻转 — 这是整个自适应改造的支点
        prefs.setNavDocked(false)
        XCTAssertFalse(prefs.isNavDocked())
        XCTAssertTrue(prefs.hasExplicitNavStyle(), "存 false = 用户显式选贴底")

        // 显式悬浮
        prefs.setNavDocked(true)
        XCTAssertTrue(prefs.isNavDocked())
        XCTAssertTrue(prefs.hasExplicitNavStyle())

        // 清盘回自动
        prefs.clearNavStyle()
        XCTAssertFalse(prefs.isNavDocked(), "清盘后回到缺省")
        XCTAssertFalse(prefs.hasExplicitNavStyle(), "清盘 = 撤销显式 → 自适应")
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
