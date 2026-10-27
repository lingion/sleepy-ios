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
