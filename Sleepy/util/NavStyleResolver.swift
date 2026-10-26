// NavStyleResolver.swift — 底栏形态决策单点
//
// ★ 2026-10-26 Kerry 定稿(两项制): 设置页只有「贴底 / 悬浮」两个选项, 默认悬浮。
//   没有「自动」档 —— 设备/系统差异全部折叠进「悬浮」一项内部:
//   - 悬浮 + 系统原生 TabBar 可用(iOS 26+ Liquid Glass)→ native(原生玻璃悬浮)
//   - 悬浮 + 原生不可用(iOS 15~25)                      → floating(自绘悬浮药丸)
//   - 贴底                                                  → docked(自绘贴底, 恒自绘)
//   prefs 键从未写入(老装/新装未动过设置)= 悬浮(缺省 true)。
//
// 优先级链(高→低):
//   1. UITest 钉死自绘(-SLEEPY_FORCE_PILL_NAV, 全量 UITests 依赖 pill_* 标识)
//   2. 用户选择(贴底 → docked 恒定; 悬浮 → native 可用则原生)
//
// ★ "未设置" ≠ "设置了贴底": isNavDocked() 对未写入返回 false 是缺省值而非
//   用户意志; 存在性判定走 AppPrefs.hasExplicitNavStyle(), 未写入按悬浮缺省。

import SwiftUI

enum NavBarRenderMode: Equatable {
    case native                       // iOS 26+ 系统 TabBar(Liquid Glass)
    case floating                     // 自绘悬浮药丸(原生不可用时的悬浮兜底)
    case docked                       // 自绘贴底
}

enum NavStyleResolver {

    /// UITests 钉死自绘的启动参数(全量套件按 pill_<id> 导航, 原生 TabBar 无此标识)。
    static let forcePillArg = "-SLEEPY_FORCE_PILL_NAV"

    // MARK: - 纯逻辑(单测直打)

    /// floating=true(悬浮) / false(贴底) → 渲染形态。
    /// forcedPill: UITest 钉死 → 悬浮语义降级为自绘 floating(永不 native)。
    static func effectiveMode(floating: Bool,
                              supportsNative: Bool,
                              forcedPill: Bool) -> NavBarRenderMode {
        if !floating { return .docked }
        if forcedPill { return .floating }
        return supportsNative ? .native : .floating
    }

    // MARK: - 运行时判定(生产入口)

    static func effectiveMode() -> NavBarRenderMode {
        effectiveMode(floating: isFloatingRequested(),
                      supportsNative: supportsNativeTabBar,
                      forcedPill: ProcessInfo.processInfo.arguments.contains(forcePillArg))
    }

    /// 用户意图 = 悬浮? 未写入键 → true(缺省悬浮, Kerry 2026-10-26 定)。
    static func isFloatingRequested() -> Bool {
        let prefs = AppPrefs.shared
        return prefs.hasExplicitNavStyle() ? prefs.isNavDocked() : true
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

    // MARK: - 能力探测

    /// 系统原生 TabBar 可用作底栏(iOS 26 起 SwiftUI TabView = Liquid Glass 悬浮玻璃;
    /// 部署目标 15.6 下 iOS 15~25 返回 false → 自绘兜底)。
    static var supportsNativeTabBar: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}
