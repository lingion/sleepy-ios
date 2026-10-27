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
//   0. 宽屏横屏双闸(可用宽 ≥600pt 且 横屏几何 → rail 左侧栏 + Master-Detail 双栏;
//      ← Android 版本 SleepyNavHost issue#45 ③ `!isCompact && !portrait` — PR#114
//      master-detail 重写 + PR#235 横屏几何闸。竖屏判据 = 逐帧真实几何(宽<高),
//      不用 orientation 枚举(分屏/自由窗口下枚举不可靠, ← PR#235 根因)。
//      UITest forcePill 除外。宽屏竖屏回落手机形态分支链 = Android 同语义:
//      navDock 仅在 Compact/竖屏分支参与分流, 用户两项选择在双栏下不生效)
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
    case rail                         // 宽屏横屏左侧栏 + Master-Detail 双栏
                                       //   (iPad 横屏/Split View 宽侧/Stage Manager
                                       //   可用宽 ≥600pt 且 宽≥高 ← Android 版本
                                       //   WindowWidthSizeClass !Compact 加 PR#235
                                       //   横屏几何闸; 宽屏竖屏回落手机形态)
}

enum NavStyleResolver {

    /// UITests 钉死自绘的启动参数(全量套件按 pill_<id> 导航, 原生 TabBar 无此标识)。
    static let forcePillArg = "-SLEEPY_FORCE_PILL_NAV"

    /// 宽度档闸阈值 ← Android 版本 Material3 WindowWidthSizeClass.Compact 上界
    /// (<600dp): 可用宽度 ≥600pt 过第一闸。双栏 = 此闸 && 横屏几何闸(见
    /// isLandscapeGeometry, ← PR#235): iPad 横屏(1024+)/Split View 宽侧/Stage
    /// Manager 命中; iPad 竖屏(768/820)过宽度闸但竖屏 → 回落手机形态;
    /// iPhone 恒竖屏(≤430pt)两闸皆不触发。
    static let railWidthThreshold: CGFloat = 600

    /// 横屏几何闸(← Android 版本 PR#235 `portrait = screenWidthDp < screenHeightDp`
    /// 取反): 逐帧真实几何判横屏, 不用 orientation 枚举(分屏/自由窗口下枚举不可靠)。
    /// 宽 ≥ 高(正方形窗口/分屏)放行双栏 = Android `!portrait` 同语义;
    /// 尺寸缺失(nil/零)= 保守 false 按手机形态。
    static func isLandscapeGeometry(width: CGFloat?, height: CGFloat?) -> Bool {
        guard let width = width, let height = height, width > 0, height > 0 else {
            return false
        }
        return width >= height
    }

    // MARK: - 纯逻辑(单测直打)

    /// floating=true(悬浮) / false(贴底) → 渲染形态。
    /// forcedPill: UITest 钉死 → 悬浮语义降级为自绘 floating(永不 native)。
    /// isWide: 宽度档闸(可用宽 ≥ railWidthThreshold)。
    /// isPortrait: 竖屏几何(高>宽, ← Android 版本 PR#235 portrait 判据取反口径:
    ///   双栏要求 !portrait 即宽≥高)。isWide && !isPortrait && !forcedPill → rail
    ///   双栏(先于用户两项选择; 底部药丸/贴底是手机形态语义, 平板横屏下不适用;
    ///   平板竖屏同语义回落手机分支链)。forcePill 不降级 rail,
    ///   全量 UITests 的 pill_* 标识链路保持。
    static func effectiveMode(floating: Bool,
                              supportsNative: Bool,
                              forcedPill: Bool,
                              isWide: Bool = false,
                              isPortrait: Bool = false) -> NavBarRenderMode {
        if isWide && !isPortrait && !forcedPill { return .rail }
        if !floating { return .docked }
        if forcedPill { return .floating }
        return supportsNative ? .native : .floating
    }

    // MARK: - 运行时判定(生产入口)

    /// 生产入口。windowSize = AppRoot 实时上报(优先级高, 旋转/分屏即时覆盖);
    /// nil 时回退 keyWindow 实测(冷启/scenePhase 路径)。
    static func effectiveMode(windowSize: CGSize? = nil) -> NavBarRenderMode {
        effectiveMode(floating: isFloatingRequested(),
                      supportsNative: supportsNativeTabBar,
                      forcedPill: ProcessInfo.processInfo.arguments.contains(forcePillArg),
                      isWide: isWideLayout(windowSize: windowSize),
                      isPortrait: isPortraitLayout(windowSize: windowSize))
    }

    /// 宽度档闸实测 = 可用宽度 ≥ 断点(竖/横/分屏/Stage Manager 缩放皆覆盖;
    /// 双栏还须再过 isLandscapeGeometry 横屏几何闸)。
    /// 两值皆 nil(冷启极早期)= 保守 false 按手机形态; AppRoot 的尺寸回调
    /// (onPreferenceChange)与 scenePhase.active 会在窗口就位后重判纠偏。
    static func isWideLayout(windowSize: CGSize? = nil) -> Bool {
        let size = windowSize ?? connectedKeyWindowSize()
        return (size?.width ?? 0) >= railWidthThreshold
    }

    /// 竖屏几何实测(高>宽)=true。← Android 版本 PR#235
    /// `portrait = screenWidthDp < screenHeightDp` 同款逐帧几何口径。
    /// 尺寸未就绪 = false(保守)但配合宽度 0 过不了宽度闸, 整体仍按手机形态。
    static func isPortraitLayout(windowSize: CGSize? = nil) -> Bool {
        let size = windowSize ?? connectedKeyWindowSize()
        guard let size = size, size.width > 0, size.height > 0 else { return false }
        return size.height > size.width
    }

    private static func connectedKeyWindowSize() -> CGSize? {
        UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow })?
            .bounds.size
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

    /// 形态 → 内容布局口径(纯函数, 单测直打): docked/rail=false, floating/native=true。
    /// native 归悬浮语义 — 原生 TabBar 玻璃悬浮, 内容同样直通屏底。
    /// rail 归 false — 侧栏水平占位, 底部零遮挡, 不需要直通屏底/滚动余量。
    static func floating(for mode: NavBarRenderMode) -> Bool {
        switch mode {
        case .native, .floating: return true
        case .docked, .rail: return false
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
