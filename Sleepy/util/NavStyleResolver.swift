// NavStyleResolver.swift — 底栏形态决策单点(2026-10-26 设备自适应改造)
//
// 背景: 贴底 docked 原本是为非全面屏(Home 键)设备准备的形态, 悬浮药丸是全面屏
// 形态。Android 侧碎片化只能把选择权交给用户(v1.0.45 b0f8280), iOS 设备形态
// 只有两类且系统能力可知, 故未显式设置时按设备自适应:
//   - 有 Home 指示条(safeAreaInsets.bottom > 0)→ 悬浮
//   - 无(Home 键老设备)→ 贴底
// 且 iOS 26+ 系统 TabBar(Liquid Glass)本身即原生悬浮胶囊 → 能原生就原生。
//
// 优先级链(高→低):
//   1. UITest 钉死自绘(-SLEEPY_FORCE_PILL_NAV, 全量 UITests 依赖 pill_* 标识)
//   2. 用户显式选择(设置页选过贴底/悬浮; ← Android「设置优先」语义)
//   3. 系统能力(iOS 26+ → 原生 TabBar)
//   4. 设备形态(全面屏 → 悬浮 / 非全面屏 → 贴底)
//
// ★ "未设置" ≠ "设置了贴底": isNavDocked() 对未写入返回 false 是缺省值而非
//   用户意志, 存在性判定必须走 AppPrefs.hasExplicitNavStyle()。

import SwiftUI

enum NavBarRenderMode: Equatable {
    case native                       // iOS 26+ 系统 TabBar(Liquid Glass)
    case floating                     // 自绘悬浮药丸(全面屏)
    case docked                       // 自绘贴底(非全面屏/Home 键设备)
}

enum NavStyleResolver {

    /// UITests 钉死自绘的启动参数(全量套件按 pill_<id> 导航, 原生 TabBar 无此标识)。
    static let forcePillArg = "-SLEEPY_FORCE_PILL_NAV"

    // MARK: - 纯逻辑(单测直打)

    static func effectiveMode(hasExplicit: Bool,
                              explicitFloating: Bool,
                              homeIndicator: Bool,
                              supportsNative: Bool,
                              forcedPill: Bool) -> NavBarRenderMode {
        if forcedPill {
            // 钉死自绘分支: 无显式选择 → 悬浮(与历史 UITests 默认几何一致,
            // iOS15~25 上 prefs 未写入时 navFloating 缺省 true);
            // 有显式选择 → 跟随显式(专测 docked 几何的用例可预存 false 键)。
            if hasExplicit { return explicitFloating ? .floating : .docked }
            return .floating
        }
        if hasExplicit { return explicitFloating ? .floating : .docked }
        if supportsNative { return .native }
        return homeIndicator ? .floating : .docked
    }

    // MARK: - 运行时判定(生产入口)

    static func effectiveMode() -> NavBarRenderMode {
        // 冷启极早期 keyWindow 可能尚未就绪(nil): 保守按悬浮 — 与悬浮几何
        // (DockSpec.bottomFloat 悬于手势条上方)一致性优先, 且 AppRoot 会在
        // onAppear/scenePhase.active 再判一次纠偏(仅"未显式设置"路径受影响)。
        effectiveMode(hasExplicit: AppPrefs.shared.hasExplicitNavStyle(),
                      explicitFloating: AppPrefs.shared.isNavDocked(),
                      homeIndicator: hasHomeIndicator ?? true,
                      supportsNative: supportsNativeTabBar,
                      forcedPill: ProcessInfo.processInfo.arguments.contains(forcePillArg))
    }

    /// 悬浮语义布尔(AppRootViewModel.navFloating 兼容旧口径)。
    /// native 归 true — 原生同样是悬浮语义(内容直通屏底)。
    static func effectiveFloating() -> Bool {
        floating(for: effectiveMode())
    }

    /// 形态 → 内容布局口径(纯函数, 单测直打): docked=false, floating/native=true。
    /// native 归悬浮语义 — 原生 TabBar 玻璃悬浮, 内容同样直通屏底。
    static func floating(for mode: NavBarRenderMode) -> Bool {
        switch mode {
        case .native, .floating: return true
        case .docked: return false
        }
    }

    /// 当前生效形态的可读名 — 设置页「自动」档 subtitle 展示(5 语言齐)。
    static func currentModeLabel() -> String {
        switch effectiveMode() {
        case .native: return L10n.t("settings_nav_style_native")
        case .floating: return L10n.t("settings_nav_style_floating")
        case .docked: return L10n.t("settings_nav_style_docked")
        }
    }

    // MARK: - 设备形态

    /// 是否有 Home 指示条(全面屏)。bottom inset: 全面屏 21~34pt, Home 键设备 0。
    /// nil = keyWindow 尚未就绪(冷启极早期) — 调用方决定保守默认。
    static var hasHomeIndicator: Bool? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
            .map { $0.safeAreaInsets.bottom > 0 }
    }

    // MARK: - 能力探测

    /// 系统原生 TabBar 可用作底栏(iOS 26 起 SwiftUI TabView = Liquid Glass 悬浮玻璃;
    /// 部署目标 15.6 下 iOS 15~25 返回 false → 自绘兜底)。
    static var supportsNativeTabBar: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}
