// WidgetBackgroundCompat.swift — containerBackground API 兼容封装
//
// iOS 17 起(Xcode 15+ SDK 构建时强制)WidgetKit 要求 widget 顶层视图用
// containerBackground(for: .widget) 声明背景,供 StandBy / 锁屏 / 智能堆栈等
// 场景剥离背景。仍用旧 .background() 的 widget 在 iOS 17+ 上会被系统直接渲染成
// 「Please adopt containerBackground API」错误占位。
//
// 部署目标 15.6,故 iOS 16 及以下回退旧 .background()。全部 5 个 widget 的
// EntryView 顶层背景统一走 sleepyWidgetBackground { ... }。

import SwiftUI
import WidgetKit

extension View {
    /// widget 顶层背景: iOS 17+ 用 containerBackground, 更早回退 .background()。
    /// (本文件 App/Extension 双 target 共编, 闸门用 iOS 而非 iOSApplicationExtension)
    @ViewBuilder
    func sleepyWidgetBackground<BG: View>(@ViewBuilder backgroundView: () -> BG) -> some View {
        if #available(iOS 17.0, *) {
            containerBackground(for: .widget, content: backgroundView)
        } else {
            background(backgroundView())
        }
    }
}

// contentMarginsDisabled() 本身 iOS 15.0+ 即可直接调用 — SDK 里它内嵌
// iOS 17 版本闸门(iOS 16 及以下返回 self), 无需再包一层。

// MARK: - iOS 26 「透明/着色」小组件样式 (Liquid Glass) 渲染模式探测
//
// 用户 2026-10-28 报告「小部件在透明的主题下 很多字/图标无法正常显示」:
// iOS 26 起 显示与亮度 → Liquid Glass 选「透明(clear)/着色(tinted)」后, 系统将
// 每个 widget 以 WidgetRenderingMode.accented/vibrant 渲染 (Apple: "Optimizing
// your widget for accented rendering mode and Liquid Glass"):背景移除换玻璃、
// **所有不透明内容整组染成纯白、只保留 alpha**。本 app 课程卡/胶囊/文字全是
// 不透明主题色 → 染色后同白、层级消失。原版本 无此机制 (对齐审计不覆盖)。
// 修法: 渲染期读模式, glass 态把配色整体换成「白 @ alpha 阶梯」
// (resolveWidgetScheme(isGlass:) → glassWidgetScheme)。
// widgetRenderingMode 环境键 iOS 16+ (玻璃样式 iOS 26 才有, 16~25 恒 fullColor);
// 部署目标 15.6 → 属性包装不可 #available 门控, 收敛在本探测子视图内。

struct WidgetGlassModeContent<Content: View>: View {
    let build: (Bool) -> Content
    init(@ViewBuilder build: @escaping (Bool) -> Content) { self.build = build }

    @available(iOS 16.0, *)
    private struct Reader: View {
        @Environment(\.widgetRenderingMode) private var mode
        let build: (Bool) -> Content
        var body: some View {
            build(mode == .accented || mode == .vibrant)
        }
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            Reader(build: build)
        } else {
            build(false)
        }
    }
}
