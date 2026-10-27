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

    // MARK: - 宽屏横屏 rail(← Android 版本 issue#45 ③ !isCompact→NavigationRail,
    //        PR#114 master-detail 终态 + PR#235 横屏几何闸 !portrait)

    func testWideLandscapeAlwaysRailRegardlessOfUserChoice() {
        // 宽屏横屏双闸先于用户两项选择(悬浮/贴底/原生可用与否全被覆盖)
        for floating in [true, false] {
            for native in [true, false] {
                XCTAssertEqual(
                    NavStyleResolver.effectiveMode(floating: floating, supportsNative: native,
                                                   forcedPill: false,
                                                   isWide: true, isPortrait: false),
                    .rail, "宽屏横屏悬浮/贴底 × 原生可用/不可 → 一律 rail 双栏")
            }
        }
    }

    func testPortraitWideFallsBackToPhoneChain() {
        // ← PR#235 契约(平板竖屏 800dp 也过宽度闸 → 被强分双栏, 比例不适):
        // 双栏加横屏几何闸, 竖屏宽屏设备回落既有手机形态分支链, 零新分支。
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: true, supportsNative: true,
                                           forcedPill: false, isWide: true, isPortrait: true),
            .native, "竖屏宽屏 + 悬浮 + 原生可用 → native(手机链)")
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: true, supportsNative: false,
                                           forcedPill: false, isWide: true, isPortrait: true),
            .floating, "竖屏宽屏 + 悬浮 + 原生不可用 → 自绘药丸(手机链)")
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: false, supportsNative: true,
                                           forcedPill: false, isWide: true, isPortrait: true),
            .docked, "竖屏宽屏 + 贴底 → docked(手机链)")
    }

    func testForcePillBlocksRail() {
        // UITest 钉死手机几何: forcePill + 宽屏横屏 → 不降级 rail, 走原 forcePill 分支
        XCTAssertEqual(
            NavStyleResolver.effectiveMode(floating: true, supportsNative: true,
                                           forcedPill: true, isWide: true, isPortrait: false),
            .floating, "forcePill 宽屏仍自绘 pill(pill_* 标识链路保持)")
    }

    func testCompactNeverRail() {
        // 宽度闸不过(isWide=false)→ 手机三态原语义(rail 只在宽屏横屏出现);
        // 竖屏几何同样永不 rail
        XCTAssertNotEqual(
            NavStyleResolver.effectiveMode(floating: true, supportsNative: true,
                                           forcedPill: false, isWide: false, isPortrait: false),
            .rail)
        XCTAssertNotEqual(
            NavStyleResolver.effectiveMode(floating: true, supportsNative: true,
                                           forcedPill: false, isWide: false, isPortrait: true),
            .rail)
    }

    func testRailIsNotFloatingSemantics() {
        // rail 水平占位、底部零遮挡 → floating(for:)=false(无直通屏底/滚动余量)
        XCTAssertFalse(NavStyleResolver.floating(for: .rail))
        XCTAssertTrue(NavStyleResolver.floating(for: .native))
        XCTAssertTrue(NavStyleResolver.floating(for: .floating))
        XCTAssertFalse(NavStyleResolver.floating(for: .docked))
    }

    func testWideLayoutBreakpoint() {
        // 宽度档闸实测: ≥600pt 宽(含 1024×768 横屏 iPad / 820×1180 竖屏 iPad 的
        // 宽度分量)= true; <600pt(430×932 iPhone Max 竖屏 / Split View 窄侧)= false;
        // nil = 保守 false。双栏还须过横屏几何闸(见下 isLandscapeGeometry 测)。
        let b = NavStyleResolver.railWidthThreshold
        XCTAssertTrue(NavStyleResolver.isWideLayout(windowSize: CGSize(width: b, height: 500)))
        XCTAssertTrue(NavStyleResolver.isWideLayout(windowSize: CGSize(width: 1024, height: 768)))
        XCTAssertTrue(NavStyleResolver.isWideLayout(windowSize: CGSize(width: 820, height: 1180)),
                      "竖屏 iPad 也过宽度闸(PR#235 根因), 由几何闸拦回手机形态")
        XCTAssertFalse(NavStyleResolver.isWideLayout(windowSize: CGSize(width: b - 1, height: 500)))
        XCTAssertFalse(NavStyleResolver.isWideLayout(windowSize: CGSize(width: 430, height: 932)))
        // 显式零尺寸 = 保守 false。注意: windowSize=nil 是运行时回退 keyWindow
        // 实测的冷启纠偏入口(结果取决于宿主设备几何), 不在此做静态断言。
        XCTAssertFalse(NavStyleResolver.isWideLayout(windowSize: .zero))
    }

    func testLandscapeGeometryGate() {
        // ← PR#235 portrait = screenWidthDp < screenHeightDp 取反口径: 宽≥高 放行;
        // 正方形窗口(Stage Manager 默认卡 1087×945 缩放/分屏方窗)= !portrait 放行,
        // 与 Android 同语义。缺尺寸 = 保守 false(按手机形态)。
        XCTAssertTrue(NavStyleResolver.isLandscapeGeometry(width: 1024, height: 768))
        XCTAssertTrue(NavStyleResolver.isLandscapeGeometry(width: 600, height: 600))
        XCTAssertFalse(NavStyleResolver.isLandscapeGeometry(width: 820, height: 1180))
        XCTAssertFalse(NavStyleResolver.isLandscapeGeometry(width: 393, height: 852))
        XCTAssertFalse(NavStyleResolver.isLandscapeGeometry(width: nil, height: nil))
        XCTAssertFalse(NavStyleResolver.isLandscapeGeometry(width: 0, height: 800))
        // isPortraitLayout = Android portrait 同款逐帧口径
        XCTAssertTrue(NavStyleResolver.isPortraitLayout(windowSize: CGSize(width: 820, height: 1180)))
        XCTAssertFalse(NavStyleResolver.isPortraitLayout(windowSize: CGSize(width: 1024, height: 768)))
        XCTAssertFalse(NavStyleResolver.isPortraitLayout(windowSize: CGSize(width: 600, height: 600)))
        // 尺寸未就绪(显式 .zero)保守 false; 真 nil 走 keyWindow 回退(冷启纠偏
        // 语义), 结果取决于宿主几何, 不做静态断言。
        XCTAssertFalse(NavStyleResolver.isPortraitLayout(windowSize: .zero),
                       "零尺寸保守 false(配合宽度闸 0 值整体落手机形态)")
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
